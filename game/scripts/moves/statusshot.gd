extends Action
## Status moves fired at the rival (Will-O-Wisp, Thunder Wave, Hypnosis, Yawn): no
## damage or stun, only the status ("inflicts") if they touch (Fighter._status_move). How
## well they follow comes from their accuracy (Combat.track_for) and a dodge breaks the
## lock, as with every projectile. Each one looks its own way:
##   willowisp    three blue flames appear around the user, hover while it winds up and
##                drift at the rival in a fan: one is enough
##   thunderwave  a fast ring of sparks
##   hypnosis     a slow beam of rings, like in the games: rings laid across its way one
##                after another from the user to a spinning spiral at the front, widening
##                as it comes; it follows badly (60% accuracy)
##   yawn         a big slow bubble that never stops following (it never misses there)

## Pixel strip, frames, size, frames per second (fx/tex/custom, tools/status_sprites.py).
const LOOK := {
	"willowisp": ["willowisp", 6, 0.55, 12.0],
	"hypnosis": ["hypnosis_rings", 6, 1.1, 8.0],
	"yawn": ["yawn_bubble", 4, 0.95, 5.0],
}
const WISP_COLOR := Color(0.45, 0.55, 1.0)
## Hypnosis's rings, in turn.
const PSY := [Color(1.0, 0.5, 0.88), Color(0.72, 0.5, 1.0), Color(1.0, 0.78, 0.95)]

var _wisps: Array = []


func on_start() -> void:
	turn_mult = 3.0
	if id == "willowisp":
		for i in 3:
			_wisps.append(_ball())
		l.main.vfx.cobble("willowisp_actorappear", l.center(), null, l.data.height)


func in_startup(_delta: float) -> void:
	tint_col = Status.COLOR.get(d.inflicts, Color.WHITE) if d.inflicts != "drowsy" else Color(0.8, 0.9, 1.0)
	tint_k = 0.25
	# The flames circle it while it winds up, bobbing in steps.
	for i in _wisps.size():
		var a := total * 4.0 + i * TAU / 3.0
		var bob := snappedf(0.15 * sin(total * 9.0 + i), 0.05)
		_wisps[i].global_position = l.center() + Vector3(cos(a) * 0.9, 0.35 + bob, sin(a) * 0.9)


func on_active() -> void:
	tint_k = 0.0
	var dir := aim(0.7)
	var g := Hit.new()
	g.user = l
	g.move_id = id
	g.type = d.type
	g.cat = "status"
	g.damage = 0.0
	g.stun = 0.0
	g.hitstop = 0.0
	g.contact = false
	g.strength = 0
	var track := -1.0
	play_sound(id, -2.0)
	if id == "willowisp":
		# A fan of three: the first one that touches burns and the others go out.
		var shots: Array = []
		g.on_strike = func(_o, _res):
			for p in shots:
				p.age_t = p.lifetime
		for i in _wisps.size():
			var w: Node3D = _wisps[i]
			shots.append(_fire(w.global_position, dir.rotated(Vector3.UP, (i - 1) * 0.28), g, w, track))
		_wisps.clear()
		return
	if id == "thunderwave":
		var node := Node3D.new()
		l.main.vfx.add_child(node)
		l.main.vfx.cobble("thunderwave_launch1", mouth(), mouth() + dir * 3.0, l.data.height)
		_fire(mouth(), dir, g, node, track)
		return
	_fire(mouth(), dir, g, _ball(), track)


func on_end(interrupted: bool) -> void:
	# Cut while winding up: the flames go out.
	for w in _wisps:
		if is_instance_valid(w):
			l.main.vfx.burst("shadow", w.global_position, Vector3.UP, WISP_COLOR, 0.3)
			w.queue_free()
	_wisps.clear()
	super(interrupted)


func _ball() -> Node3D:
	if id == "hypnosis":
		# The front of the beam: Cobblemon's spiral, across its way (the projectile turns
		# the root along it, so the spiral faces back at the user and the camera).
		var root := Node3D.new()
		l.main.vfx.add_child(root)
		var sp: MeshInstance3D = l.main.vfx.flat_sprite("res://fx/tex/generic/psychic/psyspiral.png", 8, d.radius * 2.6, Vector3.ZERO,
			Basis.IDENTITY, d.reach / d.speed + 0.1, Color.WHITE, 14.0)
		sp.reparent(root, false)
		sp.transform = Transform3D.IDENTITY
		l.main.vfx.live(root, d.reach / d.speed + 0.1)
		root.global_position = mouth()
		return root
	var lk: Array = LOOK[id]
	var col: Color = WISP_COLOR if id == "willowisp" else Status.COLOR.get(d.inflicts, Color(0.8, 0.9, 1.0))
	var n: Node3D = l.main.vfx.pixel_ball(lk[0], lk[1], lk[2], col, lk[3], id != "yawn")
	n.global_position = l.center()
	return n


func _fire(from_pos: Vector3, dir: Vector3, g: Hit, node: Node3D, track: float) -> Dictionary:
	var vfx: Vfx = l.main.vfx
	var life: float = d.reach / d.speed
	var p: Dictionary = l.main.combat.projectile({"user": l, "pos": from_pos, "velocity": dir * d.speed, "radius": d.radius,
		"lifetime": life, "hit": g, "node": node, "track": track, "on_impact": func(pos: Vector3, against: String):
			_impact(pos, against)})
	var trail := [0.0]
	var mi: Node3D = node.get_child(0) if node.get_child_count() > 0 else null
	vfx.live(node, life + 0.05, func(k: float): _flying(p, k, trail, mi))
	return p


## Every frame while it flies: its trail and how it changes.
func _flying(p: Dictionary, k: float, trail: Array, mi: Node3D) -> void:
	if not p.alive:
		return
	var vfx: Vfx = l.main.vfx
	trail[0] -= vfx.get_process_delta_time()
	match id:
		"willowisp":
			if trail[0] <= 0.0:
				trail[0] = 0.08
				vfx.burst("shadow", p.pos, Vector3.UP, WISP_COLOR, 0.2)
		"thunderwave":
			# A ring of sparks across the way it goes, redrawn as it flies.
			if trail[0] <= 0.0:
				trail[0] = 0.04
				var fwd: Vector3 = p.velocity.normalized()
				var side := fwd.cross(Vector3.UP).normalized()
				var pts: Array = []
				for j in 7:
					var a := TAU * j / 6.0 + k * 9.0
					pts.append(p.pos + (side * cos(a) + Vector3.UP * sin(a)) * d.radius)
				for j in 6:
					vfx.bolt(pts[j], pts[j + 1], Roster.TYPE_COLOR.electric, 0.06, 0.05, 0)
		"hypnosis":
			# The rings widen as they come (and so does what they touch).
			p.radius = d.radius * (1.0 + 0.8 * k)
			if mi:
				mi.scale = Vector3.ONE * snappedf(1.0 + 0.8 * k, 0.2)
			# A ring left behind across its way every few hundredths: together they make
			# the beam. Each one swells a little and fades in steps.
			if trail[0] <= 0.0:
				trail[0] = 0.06
				trail.append(0)
				var col: Color = PSY[trail.size() % PSY.size()]
				var size: float = p.radius * 2.3
				vfx.flat_sprite("res://fx/tex/custom/psy_ring.png", 1, size, p.pos,
					Basis.looking_at(p.velocity.normalized(), Vector3.UP), 0.8, col, 0.0,
					func(n: MeshInstance3D, rk: float):
						n.scale = Vector3.ONE * (1.0 + snappedf(rk * 0.3, 0.1))
						n.material_override.set_shader_parameter("tint", Color(col, 1.0 - snappedf(rk, 0.34))), 0.12)
		"yawn":
			if mi:
				mi.position.y = snappedf(0.12 * sin(k * 14.0), 0.04)


func _impact(pos: Vector3, against: String) -> void:
	var vfx: Vfx = l.main.vfx
	match id:
		"willowisp":
			vfx.burst("shadow", pos, Vector3.UP, WISP_COLOR, 0.5)
		"thunderwave":
			vfx.burst("sparks", pos, Vector3.UP)
		"hypnosis":
			vfx.wave(pos - Vector3.UP * 0.5, 1.2, 0.3, Status.COLOR.slp.lerp(Color(0.85, 0.4, 0.85), 0.7), 0.1)
		"yawn":
			vfx.sprite_anim("res://fx/tex/custom/bubble_pop.png", pos, 0.9, Vector2i(1, 5), 0.25)


func pose() -> Dictionary:
	match phase:
		"startup":
			return {"tilt": -0.1, "stretch": 0.95, "anim": "special", "reset": t < 0.02}
		"active":
			return {"tilt": 0.1, "stretch": 1.06}
	return {}
