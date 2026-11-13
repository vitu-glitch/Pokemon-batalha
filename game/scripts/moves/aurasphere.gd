extends Action
## Aura Sphere and Shadow Ball (same script, different data): energy gathers between the
## hands and a sphere flies out, homing on the rival ("homing" in the data: Aura Sphere
## homes a lot, Shadow Ball a little). Walls stop it.
## Aura Sphere looks like in Smash Ultimate: a navy core, a cyan rim with sparks and
## translucent aura flames; energy is absorbed toward the hands while charging, it flies
## without smoke (leaving translucent echoes of itself) and bursts into a dark circle
## with a cyan ring, bolts and a white star.

var _ball: Node3D
var _spark := 0.0
var _full := false


## Data value according to the charge: "field" uncharged and "field_max" fully charged
## (Shadow Ball is not chargeable: always the first).
func _v(field: String) -> float:
	return lerpf(float(d[field]), float(d.get(field + "_max", d[field])), charge)


func _color() -> Color:
	return Color(0.4, 0.62, 1.0) if d.type == "fighting" else Color(0.45, 0.2, 0.6)


func _hand() -> Vector3:
	return (l.point("locator_hand_primary") + l.point("locator_hand_secondary")) * 0.5 + l.forward() * 0.35


## Pixel ball: blue with a swirl (Aura) or seething purple (Shadow).
func _new_ball() -> Node3D:
	if d.type == "fighting":
		return l.main.vfx.pixel_ball("aurasphere_ball", 8, 0.9, _color(), 12.0)
	return l.main.vfx.pixel_ball("shadowball", 6, 0.85, _color(), 10.0)


func on_start() -> void:
	turn_mult = 2.5
	_ball = _new_ball()
	play_sound("charge", -12.0)


func in_startup(delta: float) -> void:
	tint_col = _color()
	tint_k = 0.25 * clampf(t / d.startup, 0.0, 1.0) + 0.2 * charge
	if is_instance_valid(_ball):
		_ball.global_position = _hand() + l.forward() * 0.25 * charge
		# Grows until it is released and, if charged, keeps growing.
		_ball.scale = Vector3.ONE * (0.4 + 0.6 * clampf(t / d.startup, 0.0, 1.0) + 0.9 * charge)
	# Full charge: a flash (like the eye gleam in Smash).
	if charge >= 1.0 and not _full:
		_full = true
		l.main.fx.anim("generic/sparkle/bigsparkle.png", _hand(), 1.2, 6, 0.3)
		l.main.vfx.light(_hand(), _color(), 4.0, 4.0, 0.25)
	_spark -= delta
	if _spark <= 0.0:
		_spark = 0.05
		# Energy is absorbed toward the hands (the absorb effect while charging in Smash).
		var from_pos := _hand() + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized() * 0.9
		l.main.vfx.burst("stars" if d.type == "fighting" else "shadow", from_pos, (_hand() - from_pos).normalized(), _color(), 0.2)
		if d.type == "fighting" and randf() < 0.5:
			l.main.fx.anim("generic/sparkle/glowingsparkle_cyan.png", _hand() + Vector3(randf_range(-0.35, 0.35), randf_range(-0.35, 0.35), randf_range(-0.35, 0.35)),
				0.28, 4, 0.25)


func on_active() -> void:
	var from_pos := _hand()
	var dir := aim(0.8)
	var g := Hit.new()
	g.user = l
	g.move_id = id
	g.type = d.type
	g.cat = "special"
	g.damage = _v("damage")
	g.stun = _v("stun")
	g.strength = roundi(_v("strength"))
	g.contact = false
	var ball := _ball
	_ball = null
	if not is_instance_valid(ball):
		ball = _new_ball()
	var ball_size := 1.0 + 0.9 * charge
	ball.scale = Vector3.ONE * ball_size * (1.2 if d.type != "fighting" else 1.0)
	var speed := _v("speed")
	var vfx: Vfx = l.main.vfx
	var col := _color()
	var aura: bool = d.type == "fighting"
	var fx: Fx = l.main.fx
	var p: Dictionary = l.main.combat.projectile({"user": l, "pos": from_pos, "velocity": dir * speed, "radius": _v("radius"),
		"lifetime": d.reach / speed, "hit": g, "node": ball, "homing": _v("homing"), "target": l.rival,
		"on_impact": func(pos: Vector3, _c: String):
			if aura:
				fx.anim("custom/aurasphere_burst.png", pos, 2.4 * ball_size, 8, 0.42, Color.WHITE, 0.0, true)
				vfx.light(pos, Color(0.35, 0.6, 1.0), 4.0, 5.0, 0.3)
			else:
				vfx.burst("shadow", pos, Vector3.UP, col, 1.0)
				vfx.wave(Vector3(pos.x, l.main.ground_y, pos.z), 1.6, 0.3, col, 0.06)
			l.main.audio.play_sound(id + "_hit", pos, -2.0)})
	# While flying: Aura Sphere leaves translucent echoes of itself (no smoke, like in
	# Smash); Shadow Ball leaves wisps.
	var clock := {"t": 0.0}
	vfx.live(Node3D.new(), d.reach / speed, func(_k: float):
		clock.t += l.get_process_delta_time()
		if not p.alive:
			return
		if aura:
			if clock.t > 0.05:
				clock.t = 0.0
				fx.anim("custom/aurasphere_ball.png", p.pos, 0.75 * ball_size, 8, 0.16, Color(1, 1, 1, 0.45), 0.0, true)
		elif randf() < 0.5:
			vfx.burst("shadow", p.pos, -p.velocity.normalized(), col, 0.2))
	play_sound(id, 0.0)


func on_end(_i: bool) -> void:
	if is_instance_valid(_ball):
		_ball.queue_free()


func pose() -> Dictionary:
	match phase:
		"startup":
			return {"tilt": -0.15, "stretch": 0.95, "anim": "special"}
		"active":
			return {"tilt": 0.2, "stretch": 1.06}
	return {}
