extends Action
## Sludge Bomb: lobs a ball of sludge to where the rival is (between "min" and "max"
## distance). The ground marks where it will land from the moment it is thrown. On
## landing it bursts and leaves a poison puddle: whoever steps in it is poisoned (slowly
## loses HP) while inside and for a while afterwards.

const GRAVITY := 22.0


func on_start() -> void:
	turn_mult = 2.0


func in_startup(_delta: float) -> void:
	tint_col = Roster.TYPE_COLOR.poison
	tint_k = 0.25 * (t / d.startup)
	if int(total * 30.0) % 3 == 0:
		l.main.vfx.burst("shadow", l.point("locator_mouth"), Vector3.UP, Color(0, 0, 0, 0), 0.3)


func _target_pos() -> Vector3:
	var p: Vector3 = l.global_position + l.forward() * d.max * 0.6
	if l.rival and is_instance_valid(l.rival) and l.rival.state != "ko":
		# Lobbed: it lands where the rival will be when it comes down.
		p = l.rival.global_position + Vector3(l.rival.velocity.x, 0.0, l.rival.velocity.z) * d.flight_time * l.aim_lead
	var plane := Vector3(p.x - l.global_position.x, 0, p.z - l.global_position.z)
	var dist: float = clampf(plane.length(), d.min, d.max)
	var dir := plane.normalized() if plane.length() > 0.1 else l.forward()
	var dest := l.global_position + dir * dist
	dest.y = l.main.ground_y
	return dest


func on_active() -> void:
	var from_pos := l.point("locator_mouth") + l.forward() * 0.4
	var dest := _target_pos()
	var tv: float = d.flight_time
	var speed := Vector3((dest.x - from_pos.x) / tv, (dest.y - from_pos.y + 0.5 * GRAVITY * tv * tv) / tv, (dest.z - from_pos.z) / tv)
	var g := Hit.new()
	g.user = l
	g.move_id = id
	g.type = "poison"
	g.cat = "special"
	g.damage = d.damage * 0.5
	g.stun = 0.25
	g.contact = false
	var vfx: Vfx = l.main.vfx
	vfx.telegraph(dest, d.blast_radius, tv, Roster.TYPE_COLOR.poison)
	# "track": 0: a lobbed bomb comes down where the ground is marked, it does not follow.
	l.main.combat.projectile({"user": l, "pos": from_pos, "velocity": speed, "radius": 0.35, "lifetime": tv + 0.6, "gravity": GRAVITY, "track": 0.0,
		"hit": g, "node": _ball(), "on_impact": func(pos: Vector3, _c: String): _burst(Vector3(pos.x, l.main.ground_y, pos.z))})
	vfx.cobble("sludgebomb_actorfling", from_pos, dest, l.data.height)
	play_sound("sludgebomb", 0.0)


## Pixel blob of sludge (fx/tex/custom/sludgebomb.png, from tools/move_sprites.py) that
## sheds dark wisps while it flies.
func _ball() -> Node3D:
	var vfx: Vfx = l.main.vfx
	var root: Node3D = vfx.pixel_ball("sludgebomb", 8, 0.8, Roster.TYPE_COLOR.poison, 10.0, false)
	vfx.live(root, d.flight_time + 0.6, func(_k: float):
		if randf() < 0.3:
			vfx.burst("shadow", root.global_position, Vector3.UP, Color(0, 0, 0, 0), 0.2))
	return root


func _burst(pos: Vector3) -> void:
	var g := Hit.new()
	g.user = l
	g.move_id = id
	g.local = false
	g.shape = "sphere"
	g.center = pos + Vector3.UP * 0.5
	g.radius = d.blast_radius
	g.type = "poison"
	g.cat = "special"
	g.damage = d.damage
	g.lift = d.lift
	g.stun = d.stun
	g.strength = d.strength
	g.contact = false
	g.lifetime = 0.08
	l.main.combat.add_hit(g)
	var vfx: Vfx = l.main.vfx
	var col := Roster.TYPE_COLOR.poison
	vfx.wave(pos, d.blast_radius * 1.1, 0.3, col, 0.08)
	vfx.burst("shadow", pos, Vector3.UP, Color(0, 0, 0, 0), 1.6)
	vfx.cobble("sludgebomb_targetdust", pos, null, 1.0)
	l.main.audio.play_sound("sludgebomb_hit", pos, 0.0)
	l.main.shake_camera(0.2, pos)
	_puddle(pos)


## Poison puddle: lasts a few seconds and poisons whoever steps in it.
func _puddle(pos: Vector3) -> void:
	var main: Node = l.main
	var user := l
	var radius: float = d.puddle_radius
	var poison_dur: float = d.poison_dur
	var vfx: Vfx = main.vfx
	vfx.mark(pos, "poison_puddle", radius, d.puddle_dur)
	var zone := Node3D.new()
	vfx.add_child(zone)
	var bubble := {"t": 0.0}
	vfx.live(zone, d.puddle_dur, func(_k: float):
		bubble.t -= vfx.get_process_delta_time()
		if bubble.t <= 0.0:
			bubble.t = 0.25
			var off := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).limit_length(1.0) * radius * 0.8
			vfx.burst("shadow", pos + off, Vector3.UP, Color(0, 0, 0, 0), 0.25)
		for o in main.fighters:
			if o == user or not is_instance_valid(o) or not o.on_floor():
				continue
			var h := Vector2(o.global_position.x - pos.x, o.global_position.z - pos.z).length()
			if h < radius + o.radius() * 0.4:
				o.poison_target(poison_dur))


func pose() -> Dictionary:
	match phase:
		"startup":
			return {"tilt": -0.25, "stretch": 0.94}
		"active":
			return {"tilt": 0.15, "stretch": 1.06}
	return {}
