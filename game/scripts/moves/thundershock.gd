extends Action
## Thunder Shock: a straight discharge from the cheeks. A fast projectile (36 m/s):
## avoided by positioning or with a dodge. The cheeks spark first.

var _cheek := 0.0


func on_start() -> void:
	turn_mult = 3.0
	play_sound("charge", -14.0)


func in_startup(delta: float) -> void:
	tint_col = Roster.TYPE_COLOR.electric
	tint_k = 0.25 + 0.25 * sin(total * 60.0)
	_cheek -= delta
	if _cheek <= 0.0:
		_cheek = 0.05
		var m := l.point("cheek_active_right")
		l.main.vfx.bolt(m, m + Vector3(randf_range(-0.3, 0.3), randf_range(0.0, 0.3), randf_range(-0.3, 0.3)), Roster.TYPE_COLOR.electric, 0.05, 0.06, 0)


func on_active() -> void:
	var from_pos := l.point("cheek_active_right")
	var dir := aim(0.7)
	var g := Hit.new()
	g.user = l
	g.move_id = id
	g.type = "electric"
	g.cat = "special"
	g.damage = d.damage
	g.stun = d.stun
	g.hitstop = d.hitstop
	g.contact = false
	g.strength = 1
	var node: Node3D = l.main.vfx.pixel_ball("electroball", 6, 0.36, Roster.TYPE_COLOR.electric, 18.0)
	var tail := {"prev": from_pos}
	l.main.combat.projectile({"user": l, "pos": from_pos, "velocity": dir * d.speed, "radius": 0.28, "lifetime": d.reach / d.speed,
		"hit": g, "node": node, "on_impact": func(pos: Vector3, against: String):
			l.main.vfx.bolt(pos + Vector3.UP * 0.2, pos + Vector3(randf_range(-0.6, 0.6), -0.3, randf_range(-0.6, 0.6)), Roster.TYPE_COLOR.electric, 0.1, 0.12, 1)
			if against == "world":
				l.main.vfx.burst("sparks", pos, -dir)
				l.main.vfx.mark(pos, "burned", 0.4, 2.0)
			l.main.audio.play_sound("thundershock_hit", pos, -4.0)})
	# The visible bolt: a zigzag from the cheek to the head of the projectile, redrawn as it flies.
	var proj: Dictionary = l.main.combat.projectiles.back()
	node.set_meta("proj", proj)
	var vfx: Vfx = l.main.vfx
	vfx.live(node, d.reach / d.speed + 0.05, func(_k):
		if proj.alive:
			vfx.bolt(tail.prev, proj.pos, Roster.TYPE_COLOR.electric, 0.06, 0.16, 1)
			tail.prev = proj.pos)
	l.main.vfx.burst("sparks", from_pos, dir)
	l.main.vfx.light(from_pos, Roster.TYPE_COLOR.electric, 4.0, 4.0, 0.12)
	play_sound("thundershock", -2.0)
	l.velocity -= dir * 1.5


func pose() -> Dictionary:
	match phase:
		"startup":
			return {"tilt": -0.15, "stretch": 0.92, "anim": "special", "reset": t < 0.02}
		"active":
			return {"tilt": 0.15, "stretch": 1.1}
	return {}
