extends Action
## Fire Blast: the character 大 made of fire, like in the games and the anime. It forms in
## front of the user while it winds up, opening from the crossing outward, and then flies
## at the rival standing across its way (facing whoever threw it, not the camera). Big and
## slow, with a hit as big as it looks ("radius"), and it barely follows the rival (85
## accuracy in the games). Where it strikes it breaks up into embers; landing near, on the
## ground or a wall, it still burns all round ("blast_radius"). It can burn. If it is broken
## or runs out of reach it only breaks up. It can be broken, never sent back: a blaze that
## size is not batted away.

const FIRE := Color(1.0, 0.5, 0.12)
const SIZE := 4.0              # metres across: what you see
const LIFT := 1.8              # height of its center over the ground
const DEPTH := 0.13            # how thick the character is (two of its pixels: not a block)

var _forming: MeshInstance3D
var _embers := 0.0


## Where it stands while it forms and where it flies from: just in front of the mouth, so
## a rival right up close is already inside its hit as it leaves.
func _forming_at() -> Vector3:
	var at: Vector3 = l.global_position + l.forward() * (l.data.radius + 0.6)
	at.y = l.main.ground_y + LIFT
	return at


func _facing(way: Vector3) -> Basis:
	var flat := Vector3(way.x, 0.0, way.z)
	return Basis.looking_at(flat.normalized() if flat.length() > 0.01 else l.forward(), Vector3.UP)


func on_start() -> void:
	turn_mult = 2.0
	_forming = l.main.vfx.flat_sprite("res://fx/tex/custom/daimonji_open.png", 3, SIZE, _forming_at(), _facing(l.forward()),
		startup_len() + 0.1, Color.WHITE, 0.0, Callable(), DEPTH)
	_forming.scale = Vector3.ONE * 0.2
	l.main.vfx.cobble("fireblast_actor1", mouth(), null, l.data.height)
	play_sound("charge", -10.0)


func in_startup(delta: float) -> void:
	var k := clampf(t / maxf(startup_len(), 0.01), 0.0, 1.0)
	tint_col = FIRE
	tint_k = 0.1 + 0.3 * k
	if is_instance_valid(_forming):
		_forming.global_position = _forming_at()
		_forming.global_basis = _facing(l.forward())
		_forming.scale = Vector3.ONE * snappedf(lerpf(0.2, 1.0, k), 0.1)
	# Fire breathed into it.
	_embers -= delta
	if _embers <= 0.0:
		_embers = 0.05
		var to := _forming_at()
		l.main.vfx.burst("fire_fx", mouth(), (to - mouth()).normalized(), Color(0, 0, 0, 0), 0.5)
		l.main.vfx.burst("embers", to + Vector3(randf_range(-1.6, 1.6), randf_range(-1.4, 1.4), 0.0), Vector3.UP, Color(0, 0, 0, 0), 0.4)


func on_active() -> void:
	tint_k = 0.0
	if is_instance_valid(_forming):
		_forming.queue_free()
	var dir := aim(0.8)
	dir = Vector3(dir.x, 0.0, dir.z).normalized()
	var g := Hit.new()
	g.user = l
	g.move_id = id
	g.type = "fire"
	g.cat = "special"
	g.damage = d.damage
	g.lift = d.lift
	g.stun = d.stun
	g.strength = 2
	g.hitstop = 0.1
	g.contact = false
	var vfx: Vfx = l.main.vfx
	var life: float = d.reach / d.speed
	# The flying character: the projectile turns the root along its way, so the quad (its
	# face to +Z) shows its face back at the user. Extruded like a Minecraft item, so from
	# the side it is a solid character, not a sheet.
	var root := Node3D.new()
	vfx.add_child(root)
	var kanji := vfx.flat_sprite("res://fx/tex/custom/daimonji_fly.png", 4, SIZE, Vector3.ZERO, Basis.IDENTITY, life + 0.1,
		Color.WHITE, 10.0, Callable(), DEPTH)
	kanji.reparent(root, false)
	kanji.transform = Transform3D(Basis.IDENTITY, Vector3(0, 0, DEPTH * 0.5))
	vfx.live(root, life + 0.1)
	var from_pos := _forming_at()
	root.global_position = from_pos
	var p: Dictionary = l.main.combat.projectile({"user": l, "pos": from_pos, "velocity": dir * d.speed, "radius": d.radius,
		"lifetime": life, "hit": g, "node": root, "target": l.rival,
		"on_impact": func(pos: Vector3, against: String): _end(pos, dir, against)})
	# Flames and embers shed from its strokes as it goes.
	var clock := {"t": 0.0}
	vfx.live(Node3D.new(), life, func(_k: float):
		clock.t += l.get_process_delta_time()
		if p.alive and clock.t > 0.05:
			clock.t = 0.0
			# On the strokes (the bar, and the two legs splaying down), rising off them.
			var side := Vector3(-p.velocity.z, 0.0, p.velocity.x).normalized()
			for n in 3:
				var k := randf()
				var off: Vector2
				match n:
					0: off = Vector2(lerpf(-1.5, 1.5, k), 0.25)
					1: off = Vector2(lerpf(0.0, -1.6, k), lerpf(0.3, -1.9, k))
					_: off = Vector2(lerpf(0.0, 1.6, k), lerpf(0.0, -1.9, k))
				var at: Vector3 = p.pos + side * off.x + Vector3.UP * off.y
				vfx.burst("fire_fx", at, Vector3.UP - p.velocity.normalized() * 0.5, Color(0, 0, 0, 0), 0.45)
			vfx.burst("embers", p.pos + side * randf_range(-1.5, 1.5), Vector3.UP, Color(0, 0, 0, 0), 0.4))
	l.main.vfx.cobble("fireblast_actorshoot", mouth(), from_pos, l.data.height)
	play_sound(id, 0.0)


## It breaks up where it ends. On a body the projectile already struck (and froze the
## user with it, so a hit added now would expire unused); on the ground or a wall it burns
## all round; out of reach or broken it only breaks up.
func _end(pos: Vector3, dir: Vector3, against: String) -> void:
	var vfx: Vfx = l.main.vfx
	var ground: float = l.main.ground_y
	var floor_at := Vector3(pos.x, ground, pos.z)
	var mid := Vector3(pos.x, maxf(pos.y, ground + LIFT), pos.z)
	vfx.flat_sprite("res://fx/tex/custom/daimonji_end.png", 4, SIZE, mid, _facing(dir), 0.55, Color.WHITE, 0.0, Callable(), DEPTH)
	vfx.burst("embers", mid, Vector3.UP, Color(0, 0, 0, 0), 1.4)
	if against == "":
		return
	if against != "body":
		var g := Hit.new()
		g.user = l
		g.move_id = id
		g.local = false
		g.shape = "sphere"
		g.center = pos
		g.radius = d.blast_radius
		g.type = "fire"
		g.cat = "special"
		g.damage = d.damage
		g.lift = d.lift
		g.stun = d.stun
		g.strength = 2
		g.hitstop = 0.1
		g.contact = false
		g.lifetime = 0.08
		l.main.combat.add_hit(g)
	for piece in ["daimonji1", "daimonji2", "daimonji3", "daimonji4"]:
		vfx.cobble(piece, mid, l.center(), 1.6)
	vfx.impact(pos, "fire", 2, false)
	vfx.wave(floor_at, d.blast_radius * 1.2, 0.35, FIRE, 0.1)
	vfx.light(mid, FIRE, 7.0, d.blast_radius * 3.5, 0.8)
	vfx.mark(floor_at, "burned", d.blast_radius * 0.9, 4.0)
	l.main.audio.play_sound(id + "_hit", pos, 0.0)
	l.main.shake_camera(0.4, pos)


func on_end(_interrupted: bool) -> void:
	if is_instance_valid(_forming):
		_forming.queue_free()


## It draws back while the character forms and thrusts forward as it sends it.
func pose() -> Dictionary:
	match phase:
		"startup":
			return {"tilt": -0.22, "stretch": 0.9, "anim": "special", "reset": t < 0.02}
		"active":
			return {"tilt": 0.3, "stretch": 1.12}
	return {"tilt": 0.3 * (1.0 - t / maxf(float(d.recovery), 0.01))}
