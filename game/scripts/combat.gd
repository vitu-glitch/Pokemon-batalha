class_name Combat
extends Node
## Resolves hits: tests every active volume against each target's body, applies damage
## with the type chart, knockback, stun and hitstop, and notifies effects, sound and
## rumble. Projectiles move here with a swept test (they never pass through anything,
## however fast) and collide with walls. The logic does not depend on the visual
## effects.

const WORLD_LAYER := 1

var main: Node
var hits: Array = []
var projectiles: Array = []
var targets: Array = []        # fighters and decoys (anything that can be hit)
var clock := 0.0


func add_hit(g: Hit) -> Hit:
	g.born = clock
	hits.append(g)
	return g


func remove(g: Hit) -> void:
	if g:
		g.active = false


## When a battle ends nothing must be left active.
func clear() -> void:
	for p in projectiles:
		if is_instance_valid(p.node):
			p.node.queue_free()
	hits.clear()
	projectiles.clear()


func remove_from(user: Node) -> void:
	for g in hits:
		if g.user == user:
			g.active = false


# ---------------------------------------------------------------- projectiles

## p: {user, pos, velocity, radius, lifetime, gravity, hit (a Hit in the world), node
## (visual that moves with it), on_impact (Callable(pos, against)), pierces, target, homing,
## track}
## Every projectile follows its target (by default whatever its user aims at, a decoy
## included): "track" is how fast it can turn horizontally (rad/s, from the move's accuracy
## in the games unless set), so stepping aside at mid range does not shake it off; only up
## close, where it cannot turn fast enough, or jumping at the right time. A dodge breaks the
## lock for good, like a step in Gundam Versus: from then on it flies straight. It also
## stops following once it has gone past the target (no U-turns). "homing" is a stronger
## pull in 3D (Aura Sphere), with the same rules.
func projectile(p: Dictionary) -> Dictionary:
	p.merge({"radius": 0.3, "lifetime": 2.0, "gravity": 0.0, "pierces": false, "age_t": 0.0, "alive": true,
		"homing": 0.0, "target": null, "track": -1.0}, false)
	if p.target == null and p.user is Fighter and is_instance_valid(p.user):
		p.target = p.user.aim_target()
	if p.track < 0.0:
		p.track = track_for(p.hit.move_id)
		# Sand Veil: in a sandstorm, projectiles follow it worse (its evasion in the games).
		if p.target is Fighter and p.target.data.passive.id == "sandveil" and main.weather and main.weather.is_on("sand"):
			p.track *= 0.8
	p.hit.local = false
	p.hit.shape = "sphere"
	p.hit.radius = p.radius
	# Its number among its user's shots: both copies count the same, so online a deflect
	# can say which one it was.
	if p.user is Fighter and is_instance_valid(p.user):
		p.user.shots += 1
		p.seq = p.user.shots
		p.shooter = p.user               # stays, even if it is sent back
	projectiles.append(p)
	return p


## Clashing projectiles (special against special, like in the anime): two shots from
## different sides that meet compare their strength, the move's power (what this shot is
## worth of it) by its type's effectiveness against the other's type. Clearly stronger
## (by more than CLASH_TIE) goes on with what the other took off it; otherwise both burst in
## the middle. Status shots count as CLASH_STATUS power. Online the host referees and tells
## the guest (Net event "clash"), so both screens see the same.
const CLASH_TIE := 0.15
const CLASH_STATUS := 20.0


func _clashes(delta: float) -> void:
	if main.net and not main.net.host:
		return
	for i in projectiles.size():
		var a: Dictionary = projectiles[i]
		for j in range(i + 1, projectiles.size()):
			var b: Dictionary = projectiles[j]
			if not a.alive or not b.alive or a.get("clashed", false) or b.get("clashed", false) or a.user == b.user:
				continue
			var a0: Vector3 = a.pos - a.velocity * delta
			var b0: Vector3 = b.pos - b.velocity * delta
			if dist_seg_seg(a0, a.pos, b0, b.pos) >= a.radius + b.radius:
				continue
			if main.net:
				var mine: Dictionary = a if a.get("shooter") == main.net.local else b
				var theirs: Dictionary = b if mine == a else a
				main.net.send_event({"t": "clash", "h": mine.get("seq", -1), "g": theirs.get("seq", -1)})
			clash(a, b)


## Streams (Flamethrower, Hydro Pump: hits that repeat) against shots and against each
## other, without a tug of war. A shot that flies into a stream at least as strong is put
## out; a stronger one goes through, weaker. Two streams that touch: the weaker is cut where
## they meet (its hit and its look stop there) and the stronger goes on weaker while they
## touch; even ones are both cut. Strength is power by type against type, as in clash().
## Every copy works it out itself: online, whoever is hit decides with what it sees.
func _streams() -> void:
	var list: Array = []
	for g in hits:
		if g.active and g.interval > 0.0 and g.user is Fighter and is_instance_valid(g.user) and g.shape in ["capsule", "cone"]:
			g.cut = 0.0
			g.bonus = 1.0
			list.append(g)
	for g in list:
		for p in projectiles:
			if not p.alive or p.user == g.user or p.get("cut_by") == g or not _touches_point(g, p.pos, p.radius):
				continue
			var sg := _power(g.move_id, g.hit_share()) * Roster.affinity(g.type, [p.hit.type])
			var sp := clash_strength(p, {"hit": g})
			p.cut_by = g
			main.vfx.impact(p.pos, g.type, 1, false)
			if sg >= sp * (1.0 - CLASH_TIE):
				p.age_t = p.lifetime
			else:
				var h: Hit = p.hit.copy()
				h.bonus *= 1.0 - sg / sp
				p.hit = h
	for i in list.size():
		for j in range(i + 1, list.size()):
			var a: Hit = list[i]
			var b: Hit = list[j]
			if a.user == b.user:
				continue
			var at = _stream_contact(a, b)
			if at == null:
				continue
			var sa := _power(a.move_id, 1.0) * Roster.affinity(a.type, [b.type])
			var sb := _power(b.move_id, 1.0) * Roster.affinity(b.type, [a.type])
			var even := absf(sa - sb) <= CLASH_TIE * maxf(sa, sb)
			if even or sa < sb:
				_cut(a, at)
			if even or sb < sa:
				_cut(b, at)
			if not even:
				var win: Hit = a if sa > sb else b
				win.bonus = 1.0 - minf(sa, sb) / maxf(sa, sb)
			_contact_fx(at, a.type, b.type)


## Stops stream g at point "at" now (its script keeps it there from the next frame on).
func _cut(g: Hit, at: Vector3) -> void:
	var s := _seg(g)
	g.cut = maxf(s[0].distance_to(at), 0.3)
	if g.shape == "capsule":
		g.b = g.a + (g.b - g.a).normalized() * g.cut
	else:
		g.length = g.cut


## A move's power for these comparisons (status moves and unset power: CLASH_STATUS).
func _power(move_id: String, share: float) -> float:
	var d: Dictionary = Moves.DATA.get(move_id, {})
	var power: float = d.get("power", 0)
	return (power if power > 0.0 else CLASH_STATUS) * share


## The stream's line (origin, end) and thickness.
func _seg(g: Hit) -> Array:
	if g.shape == "capsule":
		return [g.a, g.b, g.radius]
	return [g.center, g.center + g.dir.normalized() * g.length, g.length * tan(g.angle) * 0.6]


## Where two streams meet (the middle of their closest points), or null.
func _stream_contact(a: Hit, b: Hit):
	var sa := _seg(a)
	var sb := _seg(b)
	var best := INF
	var at := Vector3.ZERO
	for k in 13:
		var pa: Vector3 = sa[0].lerp(sa[1], k / 12.0)
		var pb := closest_on_seg(pa, sb[0], sb[1])
		var dist := pa.distance_to(pb)
		if dist < best:
			best = dist
			at = (pa + pb) * 0.5
	return at if best < float(sa[2]) + float(sb[2]) else null


var _contact_t := 0.0


## Steam where fire meets water, sparks in both colors otherwise, now and then.
func _contact_fx(at: Vector3, ta: String, tb: String) -> void:
	_contact_t -= get_physics_process_delta_time()
	if _contact_t > 0.0:
		return
	_contact_t = 0.06
	if (ta == "fire" and tb == "water") or (ta == "water" and tb == "fire"):
		main.vfx.burst("steam", at, Vector3.UP, Color(0, 0, 0, 0), 1.4)
	else:
		main.vfx.burst("sparks", at, Vector3.UP, Roster.TYPE_COLOR.get(ta, Color.WHITE), 0.8)
		main.vfx.burst("sparks", at, Vector3.UP, Roster.TYPE_COLOR.get(tb, Color.WHITE), 0.8)


## How strong a shot is against another (its power, what share of it this shot carries, its
## damage bonus, by its type against the other's type).
func clash_strength(p: Dictionary, other: Dictionary) -> float:
	var d: Dictionary = Moves.DATA.get(p.hit.move_id, {})
	var power: float = d.get("power", 0)
	if power <= 0.0:
		power = 60.0 if d.get("power_by", "") != "" else CLASH_STATUS
	if d.has("power_at"):
		power *= clampf(p.hit.damage / maxf(float(d.power_at), 0.01), 0.2, 2.0)
	return power * p.hit.bonus * Roster.affinity(p.hit.type, [other.hit.type])


func clash(a: Dictionary, b: Dictionary) -> void:
	a.clashed = true
	b.clashed = true
	var sa := clash_strength(a, b)
	var sb := clash_strength(b, a)
	var mid: Vector3 = (a.pos + b.pos) * 0.5
	main.vfx.impact(mid, a.hit.type, 1, false)
	main.vfx.impact(mid, b.hit.type, 1, false)
	main.shake_camera(0.12, mid)
	if absf(sa - sb) <= CLASH_TIE * maxf(sa, sb):
		main.vfx.text(mid + Vector3.UP * 0.8, main.tr("Clash!"), Color(0.9, 0.92, 1.0))
		a.age_t = a.lifetime
		b.age_t = b.lifetime
		return
	var win: Dictionary = a if sa > sb else b
	var lose: Dictionary = b if win == a else a
	var keep: float = 1.0 - minf(sa, sb) / maxf(sa, sb)
	lose.age_t = lose.lifetime
	var g: Hit = win.hit.copy()
	g.bonus *= keep
	win.hit = g
	win.clashed = false              # it can meet another one
	main.vfx.text(mid + Vector3.UP * 0.8, main.tr("Overpowered!"), Roster.TYPE_COLOR.get(g.type, Color.WHITE))


## Deflecting projectiles, with the move itself: a move with "deflects" in its data (1 breaks
## them, 2 sends them back) whose hit is active where a projectile passes stops it. Each
## projectile says how far it can be deflected ("deflectable", 2 by default: a lobbed bomb or
## a bursting ball only break). Sent back, it flies at whoever threw it DEFLECT_SPEED times as
## fast and hits DEFLECT_BONUS times as hard, still with the thrower's stats; it belongs to
## the deflector from then on and can be sent back again. It takes timing, but fair timing:
## the first DEFLECT_WINDOW seconds of the hit count (a swing too early or too late lets it
## through), the hit stops projectiles a little past its own reach (DEFLECT_REACH), and from
## a wide arc in front (DEFLECT_FRONT, the cosine of the widest angle). A broken projectile is
## gone: it does not burst or hit (a bomb broken in the air does no damage). Online the
## deflector's own copy decides and tells the other one (Net event "deflect" with the
## projectile's number).
const DEFLECT_SPEED := 1.2
const DEFLECT_BONUS := 1.25
const DEFLECT_WINDOW := 0.3
const DEFLECT_REACH := 0.6
const DEFLECT_FRONT := 0.2
## The wind-up's end counts too, like a parry: in the last DEFLECT_EARLY seconds of a
## deflecting move's startup, a ball DEFLECT_GUARD wide just in front of the body stops
## shots (fast ones would otherwise land before the hit comes out).
const DEFLECT_EARLY := 0.12
const DEFLECT_GUARD := 1.4


## "step": where it goes this frame; the whole stretch is checked, not just where it is.
func _try_deflect(p: Dictionary, step: Vector3) -> bool:
	for g in hits:
		if not g.active or not (g.user is Fighter) or not is_instance_valid(g.user) or g.user == p.user or g.user.is_remote:
			continue
		var level: int = int(Moves.DATA.get(g.move_id, {}).get("deflects", 0))
		if level <= 0 or clock - g.born > DEFLECT_WINDOW:
			continue
		var from: Vector3 = p.pos - g.user.center()
		if Vector2(from.x, from.z).normalized().dot(Vector2(g.user.forward().x, g.user.forward().z)) < DEFLECT_FRONT:
			continue
		var touches := false
		for k in 4:
			if _touches_point(g, p.pos + step * (k / 3.0), p.radius + DEFLECT_REACH):
				touches = true
				break
		if not touches:
			continue
		level = mini(level, int(Moves.DATA.get(p.hit.move_id, {}).get("deflectable", 2)))
		if level <= 0:
			continue
		deflect(p, g.user, level)
		if main.net:
			main.net.send_event({"t": "deflect", "seq": p.get("seq", -1), "level": level})
		return true
	# The wind-up's end.
	for f in targets:
		if not (f is Fighter) or not is_instance_valid(f) or f == p.user or f.is_remote:
			continue
		var a: Action = f.action
		if a == null or a.phase != "startup" or a.t < a.startup_len() - DEFLECT_EARLY:
			continue
		var level: int = int(a.d.get("deflects", 0))
		if level <= 0:
			continue
		var guard: Vector3 = f.center() + f.forward() * (float(f.data.radius) + 0.6)
		var from: Vector3 = p.pos - f.center()
		if Vector2(from.x, from.z).normalized().dot(Vector2(f.forward().x, f.forward().z)) < DEFLECT_FRONT:
			continue
		var touches := false
		for k in 4:
			if (p.pos + step * (k / 3.0)).distance_to(guard) < DEFLECT_GUARD + p.radius:
				touches = true
				break
		if not touches:
			continue
		level = mini(level, int(Moves.DATA.get(p.hit.move_id, {}).get("deflectable", 2)))
		if level <= 0:
			continue
		deflect(p, f, level)
		if main.net:
			main.net.send_event({"t": "deflect", "seq": p.get("seq", -1), "level": level})
		return true
	return false


## Breaks the projectile (level 1) or sends it back at whoever threw it (2).
func deflect(p: Dictionary, by: Fighter, level: int) -> void:
	var col: Color = Roster.TYPE_COLOR.get(p.hit.type, Color.WHITE)
	main.vfx.impact(p.pos, p.hit.type, 2, true)
	main.vfx.burst("sparks_metal", p.pos, Vector3.UP, Color(0, 0, 0, 0), 1.2)
	main.vfx.wave(p.pos - Vector3.UP * 0.4, 1.4, 0.25, col, 0.1)
	main.audio.play_sound("armor", p.pos, 2.0, 1.15)
	main.shake_camera(0.18, p.pos)
	by.freeze(0.08)
	var shooter: Node = p.user
	if level < 2 or not (shooter is Fighter) or not is_instance_valid(shooter):
		main.vfx.text(p.pos + Vector3.UP * 0.8, main.tr("Broken!"), Color(0.9, 0.92, 1.0))
		p.age_t = p.lifetime
		p.deflected = true
		p.broken = true
		return
	main.vfx.text(p.pos + Vector3.UP * 0.8, main.tr("Sent back!"), Color("ffd21f"))
	main.session.event("deflect", {"by": by.species, "move": p.hit.move_id})
	var g: Hit = p.hit.copy()
	g.user = by
	if g.source == null:
		g.source = shooter
	g.bonus = minf(g.bonus * DEFLECT_BONUS, 2.0)
	p.hit = g
	p.user = by
	p.target = shooter
	var speed: float = p.velocity.length() * DEFLECT_SPEED
	var to: Vector3 = shooter.center() - p.pos
	p.velocity = to.normalized() * speed
	p.gravity = 0.0
	p.age_t = 0.0
	p.lifetime = maxf(p.lifetime, to.length() / maxf(speed, 0.1) + 0.6)


## Whether hit "g" covers a ball of radius r at c (sphere, capsule and cone hits).
func _touches_point(g: Hit, c: Vector3, r: float) -> bool:
	var m := g.base()
	match g.shape:
		"sphere":
			return (m * g.center).distance_to(c) < g.radius + r
		"capsule":
			return closest_on_seg(c, m * g.a, m * g.b).distance_to(c) < g.radius + r
		"cone":
			var org := m * g.center
			var v := c - org
			var d := v.length()
			return d - r <= g.length and d > 0.01 and v.angle_to((m.basis * g.dir).normalized()) <= g.angle + atan2(r, d)
	return false


## How fast (rad/s) a move's projectiles turn after their target: 160°/s for 100% accuracy
## in the games, less for less accurate ones (80%: about 90°/s) and 320°/s for those that
## never miss (Aura Sphere). "track" in the move data (degrees/s) overrides it.
static func track_for(move_id: String) -> float:
	var d: Dictionary = Moves.DATA.get(move_id, {})
	if d.has("track"):
		return deg_to_rad(float(d.track))
	if not d.has("accuracy"):
		return 0.0
	var acc: float = d.accuracy
	return deg_to_rad(320.0 if acc <= 0.0 else 160.0 * pow(acc / 100.0, 2.5))


func _physics_process(delta: float) -> void:
	clock += delta
	_streams()
	_move_projectiles(delta)
	var i := 0
	while i < hits.size():
		var g: Hit = hits[i]
		if not g.active or (g.user != null and not is_instance_valid(g.user)):
			hits.remove_at(i)
			continue
		if g.lifetime >= 0.0:
			g.lifetime -= delta
			if g.lifetime < 0.0:
				hits.remove_at(i)
				continue
		if g.user == null or not g.user.frozen():
			for o in targets:
				_try(g, o)
		i += 1


func _move_projectiles(delta: float) -> void:
	var space: PhysicsDirectSpaceState3D = main.get_world_3d().direct_space_state
	var i := 0
	while i < projectiles.size():
		var p: Dictionary = projectiles[i]
		p.age_t += delta
		var tgt: Node3D = p.target if p.target and is_instance_valid(p.target) else null
		if tgt:
			var to: Vector3 = tgt.center() - p.pos
			var flat_v := Vector2(p.velocity.x, p.velocity.z)
			var flat_to := Vector2(to.x, to.z)
			# A dodge breaks the follow, and so does getting clearly behind it; a shot fired
			# off to a side (free aim) keeps following, though it may not turn in time.
			if (tgt is Fighter and tgt.state == "dodge") or flat_to.normalized().dot(flat_v.normalized()) < -0.2:
				p.target = null
			else:
				if p.homing > 0.0:
					var toward: Vector3 = to.normalized() * p.velocity.length()
					p.velocity = p.velocity.lerp(toward, clampf(p.homing * delta, 0.0, 1.0))
				if p.track > 0.0 and flat_v.length() > 0.1:
					var turn := clampf(flat_v.angle_to(flat_to), -p.track * delta, p.track * delta)
					flat_v = flat_v.rotated(turn)
					p.velocity.x = flat_v.x
					p.velocity.z = flat_v.y
		if not p.get("deflected", false):
			_try_deflect(p, p.velocity * delta)
		p.velocity.y -= p.gravity * delta
		var before: Vector3 = p.pos
		var after: Vector3 = before + p.velocity * delta
		var finished: bool = p.age_t >= p.lifetime
		var against := ""
		var where := after
		# Wall or floor in the way.
		var q := PhysicsRayQueryParameters3D.create(before, after + p.velocity.normalized() * p.radius, WORLD_LAYER)
		var hit: Dictionary = space.intersect_ray(q)
		if hit:
			finished = true
			against = "world"
			where = hit.position
		# Bodies in the way (swept as a capsule).
		if not finished or against == "world":
			for o in targets:
				if o == p.user or not o.hittable():
					continue
				var seg: Array = o.body()
				var d := dist_seg_seg(before, where, seg[0], seg[1])
				if d < p.radius + o.radius():
					p.hit.center = closest_on_seg(o.center(), before, where)
					var res := apply(p.hit, o, p.hit.center)
					if res != "" and not p.pierces:
						finished = true
						against = "body"
						where = p.hit.center
						break
		p.pos = where
		if is_instance_valid(p.get("node")):
			p.node.global_position = where
			if p.velocity.length() > 0.1:
				p.node.look_at(where + p.velocity, Vector3.UP if absf(p.velocity.normalized().y) < 0.98 else Vector3.RIGHT)
		if finished:
			p.alive = false
			if p.has("on_impact") and p.on_impact.is_valid() and not p.get("broken", false):
				p.on_impact.call(where, against)
			if is_instance_valid(p.get("node")):
				p.node.queue_free()
			projectiles.remove_at(i)
		else:
			i += 1
	_clashes(delta)


# ---------------------------------------------------------------- tests

func _try(g: Hit, o: Node) -> void:
	if o == g.user or not o.hittable():
		return
	var id := o.get_instance_id()
	if g.hit_list.has(id) and (g.interval <= 0.0 or clock - g.hit_list[id] < g.interval):
		return
	var point = _touches(g, o)
	if point == null:
		return
	apply(g, o, point)


## Returns the contact point, or null if there is no contact.
func _touches(g: Hit, o: Node):
	var m := g.base()
	var seg: Array = o.body()
	var r: float = o.radius()
	match g.shape:
		"sphere":
			var c := m * g.center
			var p := closest_on_seg(c, seg[0], seg[1])
			if c.distance_to(p) < g.radius + r:
				return p.lerp(c, 0.5)
		"capsule":
			var a := m * g.a
			var b := m * g.b
			if dist_seg_seg(a, b, seg[0], seg[1]) < g.radius + r:
				return closest_on_seg(o.center(), a, b)
		"cone":
			var org := m * g.center
			var dir := (m.basis * g.dir).normalized()
			for k in 5:
				var s: Vector3 = seg[0].lerp(seg[1], k / 4.0)
				var v := s - org
				var d := v.length()
				if d - r > g.length or d < 0.01:
					continue
				var ang := v.angle_to(dir)
				if ang <= g.angle + atan2(r, d):
					return s
		"ring":
			var c := m * g.center
			if g.ground_only and not o.on_floor():
				return null
			var h := Vector2(o.global_position.x - c.x, o.global_position.z - c.z).length()
			if h >= g.r_in - r and h <= g.r_out + r and absf(o.global_position.y - c.y) < 1.5:
				return o.global_position + Vector3.UP * 0.2
	return null


## Applies a hit to a target. Returns the result ("hit", "armor", "dodged",
## "detect"...) or "" if nothing happened.
func apply(g: Hit, o: Node, point: Vector3) -> String:
	# Streams (hits that repeat): from the second impact on it counts as "flow".
	var flow := g.interval > 0.0 and g.hit_list.has(o.get_instance_id())
	g.hit_list[o.get_instance_id()] = clock
	var attacker: Node = g.user
	var mult := Roster.affinity(g.type, o.types)
	var info := {"hit": g, "attacker": attacker, "point": point, "affinity": mult, "flow": flow}
	# Online, on the rival's copy: damage is decided by the receiver. Here we only
	# predict the feel of the hit so it responds instantly.
	if o is Fighter and o.is_remote:
		return _predicted_hit(g, o, point, mult, flow)
	var hp_before: float = o.hp if o is Fighter else 0.0
	var res: String = o.receive(info)
	# Online, if the attacker is the rival's copy, the hit is confirmed to it.
	if attacker is Fighter and attacker.is_remote and res != "" and main.net:
		main.net.send_event({"t": "hit", "res": res, "damage": hp_before - (o.hp if o is Fighter else 0.0),
			"affinity": mult, "point": point, "move": g.move_id})
	if res == "":
		return ""
	if g.on_strike.is_valid():
		g.on_strike.call(o, res)
	if res in ["hit", "armor"]:
		var strength := g.strength
		if attacker and is_instance_valid(attacker):
			attacker.on_strike(o, g, res)
			attacker.freeze(g.hitstop)
		main.vfx.impact(point, g.type, strength, g.contact)
		var now := Time.get_ticks_msec()
		if now - int(g.get_meta("fx_ms", -100000)) > 280:
			g.set_meta("fx_ms", now)
			var looks = attacker.center() if attacker and is_instance_valid(attacker) else null
			for piece in Moves.DATA.get(g.move_id, {}).get("fx_hit", []):
				main.vfx.cobble(piece, point, looks, o.data.height)
		main.audio.impact(g.type, strength, point)
		main.shake_camera(0.08 + 0.12 * strength, point)
		for l in [attacker, o]:
			if l and is_instance_valid(l) and l.has_method("rumble_pad"):
				l.rumble_pad(0.2 + 0.25 * strength, 0.35 + 0.3 * strength, 0.08 + 0.06 * strength)
		if g.quiet:
			pass
		else:
			match Roster.tier(mult):
				"super":
					main.vfx.text(point + Vector3.UP * 0.8, main.tr("Super effective!"), Color("ff8a3a"), 1.15)
					main.hud.log_entry(main.tr("It's extremely effective!"))
				"effective":
					main.vfx.text(point + Vector3.UP * 0.8, main.tr("Effective!"), Color("ffd93a"))
					main.hud.log_entry(main.tr("It's super effective!"))
				"barely":
					main.vfx.text(point + Vector3.UP * 0.8, main.tr("Barely effective"), Color("8e93a3"))
					main.hud.log_entry(main.tr("It barely affects it..."))
				"not_very":
					main.vfx.text(point + Vector3.UP * 0.8, main.tr("Not very effective"), Color("b8bcc8"))
					main.hud.log_entry(main.tr("It's not very effective..."))
	return res


## Own hit on the rival's copy online: effects, hitstop, landing (for combos) and
## energy right away. No damage: the rival confirms that.
func _predicted_hit(g: Hit, o: Fighter, point: Vector3, mult: float, flow: bool) -> String:
	if o.invulnerable > 0.0 or o.state == "ko":
		return ""
	if g.cat == "status":
		# The rival decides whether it takes (Fighter._status_move); nothing to predict.
		if g.on_strike.is_valid():
			g.on_strike.call(o, "status")
		return "status"
	var attacker: Node = g.user
	var strength := g.strength
	if attacker is Fighter and is_instance_valid(attacker):
		attacker.on_strike(o, g, "hit")
		attacker.energy = minf(Fighter.ENERGY_MAX, attacker.energy + 3.0)
		if attacker.boosted_hits > 0 and g.cat == "physical":
			attacker.boosted_hits -= 1
		if not flow:
			attacker.freeze(g.hitstop)
			o.freeze(g.hitstop)
	if not flow or randf() < 0.4:
		main.vfx.impact(point, g.type, strength, g.contact)
		main.audio.impact(g.type, strength, point)
		main.shake_camera(0.08 + 0.12 * strength, point)
		if attacker is Fighter and attacker.has_method("rumble_pad"):
			attacker.rumble_pad(0.2 + 0.25 * strength, 0.35 + 0.3 * strength, 0.08 + 0.06 * strength)
	if g.on_strike.is_valid():
		g.on_strike.call(o, "hit")
	return "hit"


# ---------------------------------------------------------------- geometry

static func closest_on_seg(p: Vector3, a: Vector3, b: Vector3) -> Vector3:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.000001), 0.0, 1.0)
	return a + ab * t


## Minimum distance between two segments (for capsules and sweeps).
static func dist_seg_seg(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3) -> float:
	var d1 := q1 - p1
	var d2 := q2 - p2
	var r := p1 - p2
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var f := d2.dot(r)
	var s := 0.0
	var t := 0.0
	if a <= 0.000001 and e <= 0.000001:
		return p1.distance_to(p2)
	if a <= 0.000001:
		t = clampf(f / e, 0.0, 1.0)
	else:
		var c := d1.dot(r)
		if e <= 0.000001:
			s = clampf(-c / a, 0.0, 1.0)
		else:
			var bb := d1.dot(d2)
			var den := a * e - bb * bb
			s = clampf((bb * f - c * e) / den, 0.0, 1.0) if den > 0.000001 else 0.0
			t = (bb * s + f) / e
			if t < 0.0:
				t = 0.0
				s = clampf(-c / a, 0.0, 1.0)
			elif t > 1.0:
				t = 1.0
				s = clampf((bb - c) / a, 0.0, 1.0)
	return (p1 + d1 * s).distance_to(p2 + d2 * t)
