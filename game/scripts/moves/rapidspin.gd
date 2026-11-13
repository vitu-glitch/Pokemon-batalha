extends Action
## Rapid Spin: Blastoise withdraws into its shell and spins around the field, hitting
## whatever it touches (several times if it stays on top). Steered with the stick,
## turning gradually; the AI steers it toward the rival. Starting it removes slowness
## (Ice, Static).

var _dir := Vector3.FORWARD
var _spin := 0.0
var _dust := 0.0


func on_start() -> void:
	turn_mult = 3.0
	no_brake = true
	l.slow = 1.0
	play_sound("rapidspin", -2.0)


func in_startup(_delta: float) -> void:
	tint_col = Color(0.85, 0.75, 0.55)
	tint_k = 0.2 * (t / d.startup)


func on_active() -> void:
	_dir = l.forward()
	faces_rival = false
	turn_mult = 0.0
	hit({"shape": "sphere", "center": Vector3(0, l.data.height * 0.35, 0), "radius": d.radius, "interval": d.interval})
	l.main.vfx.dust(l.global_position, 1.4)
	l.main.audio.play_sound("dodge", l.global_position, -4.0, 0.6)


func in_active(delta: float) -> void:
	# Where it wants to go: the player's stick or, for the AI, the rival.
	var wants := Vector3.ZERO
	if l.is_player:
		wants = l._world_dir(l.ctrl.move_input)
	elif l.rival and is_instance_valid(l.rival):
		wants = l.rival.global_position - l.global_position
		wants.y = 0.0
	if wants.length() > 0.1:
		var ang := _dir.signed_angle_to(wants.normalized(), Vector3.UP)
		_dir = _dir.rotated(Vector3.UP, clampf(ang, -d.max_turn * delta, d.max_turn * delta))
	l.velocity.x = _dir.x * d.speed
	l.velocity.z = _dir.z * d.speed
	l.face_yaw = atan2(_dir.x, _dir.z)
	_spin += delta * 22.0
	_dust -= delta
	if _dust <= 0.0:
		_dust = 0.08
		l.main.vfx.burst("dust", l.global_position, Vector3.UP, Color(0, 0, 0, 0), 0.5)
		l.main.vfx.afterimage(l, Color(0.9, 0.8, 0.6))


func on_recovery() -> void:
	no_brake = false
	l.velocity.x *= 0.25
	l.velocity.z *= 0.25
	tint_k = 0.0


func pose() -> Dictionary:
	match phase:
		"startup":
			return {"tilt": 0.1, "stretch": lerpf(1.0, 0.72, t / d.startup)}
		"active":
			# Blastoise's run animation in Cobblemon is exactly this: inside the shell.
			if l.model.has_anim("ground_run"):
				return {"tilt": 0.0, "spin": fmod(_spin, TAU), "anim": "ground_run", "anim_speed": 1.6}
			return {"tilt": 0.12, "stretch": 0.72, "spin": fmod(_spin, TAU)}
	return {"stretch": lerpf(0.72, 1.0, clampf(t / 0.15, 0.0, 1.0)), "tilt": -0.1}
