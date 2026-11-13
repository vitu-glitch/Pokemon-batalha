extends Action
## Dig: Garchomp sinks into the ground (startup) and moves underground while the button
## is held, up to "max". It cannot be seen, but the ground cracks and kicks up dust where
## it passes: you know where it is. Underground nothing touches it except Earthquake,
## which deals double (resolved by the fighter). On release it bursts out, launching the
## target; the exit is punishable. Steered with the stick; the AI steers toward the rival.

var _dir := Vector3.FORWARD
var _trail := 0.0
var _came_out := false


func on_start() -> void:
	turn_mult = 2.0
	play_sound("dig", -2.0)


func in_startup(_delta: float) -> void:
	tint_col = Roster.TYPE_COLOR.ground
	tint_k = 0.2 * (t / d.startup)
	if int(total * 30.0) % 2 == 0:
		l.main.vfx.burst("dust", l.global_position, Vector3.UP, Color(0, 0, 0, 0), 0.6)
		l.main.vfx.burst("debris", l.global_position, Vector3.UP, Color(0, 0, 0, 0), 0.3)


func on_active() -> void:
	_dir = l.forward()
	faces_rival = false
	no_brake = true
	l.model.visible = false
	l.main.vfx.mark(l.global_position, "crack", 1.4, 3.0)
	l.main.shake_camera(0.1, l.global_position)


func in_active(delta: float) -> void:
	# Underground: untouchable except by Earthquake (see Fighter.receive).
	l.invulnerable = maxf(l.invulnerable, 0.05)
	var wants := Vector3.ZERO
	if l.is_player:
		wants = l._world_dir(l.ctrl.move_input)
	elif l.rival and is_instance_valid(l.rival):
		wants = l.rival.global_position - l.global_position
		wants.y = 0.0
		# The AI comes out when it is right under the rival.
		if wants.length() < 1.2 and t > 0.3:
			_go_to("recovery")
			return
	if wants.length() > 0.1:
		var ang := _dir.signed_angle_to(wants.normalized(), Vector3.UP)
		_dir = _dir.rotated(Vector3.UP, clampf(ang, -d.max_turn * delta, d.max_turn * delta))
	l.velocity.x = _dir.x * d.speed
	l.velocity.z = _dir.z * d.speed
	l.face_yaw = atan2(_dir.x, _dir.z)
	_trail -= delta
	if _trail <= 0.0:
		_trail = 0.12
		var p := l.global_position
		p.y = l.main.ground_y
		l.main.vfx.mark(p, "crack", 0.9, 1.6)
		l.main.vfx.burst("dust", p, Vector3.UP, Color(0, 0, 0, 0), 0.5)
		l.main.vfx.burst("debris", p, Vector3.UP, Color(0, 0, 0, 0), 0.25)


## On release (or at the maximum) it bursts out of the ground striking upward.
func on_recovery() -> void:
	_emerge()


func _emerge() -> void:
	if _came_out:
		return
	_came_out = true
	no_brake = false
	l.invulnerable = 0.0
	l.model.visible = true
	l.velocity = Vector3(l.velocity.x * 0.1, 6.0, l.velocity.z * 0.1)
	hit({"shape": "sphere", "local": false, "center": l.global_position + Vector3.UP * 0.6, "radius": d.exit_radius, "lifetime": 0.1})
	var p := l.global_position
	var vfx: Vfx = l.main.vfx
	vfx.wave(p, 3.0, 0.3, Color(0.85, 0.7, 0.45), 0.1)
	vfx.burst("debris", p, Vector3.UP, Color(0, 0, 0, 0), 1.6)
	vfx.burst("dust", p, Vector3.UP, Color(0, 0, 0, 0), 2.0)
	vfx.mark(p, "crack", 2.2, 4.0)
	vfx.cobble("rockslide_targetdust", p, null, l.data.height)
	l.main.shake_camera(0.35, p)
	l.main.audio.play_sound("dig_emerge", p, 0.0)


func on_end(_i: bool) -> void:
	l.model.visible = true
	if not _came_out and phase == "active":
		# Interrupted underground (Earthquake): it comes out without hitting.
		_came_out = true
		l.main.vfx.burst("debris", l.global_position, Vector3.UP, Color(0, 0, 0, 0), 1.0)


func pose() -> Dictionary:
	match phase:
		"startup":
			return {"tilt": 0.5 * (t / d.startup), "stretch": lerpf(1.0, 0.6, t / d.startup), "height": -l.data.height * 0.4 * (t / d.startup)}
		"active":
			return {"height": -l.data.height}
	return {"tilt": -0.2 * (1.0 - clampf(t / 0.2, 0.0, 1.0)), "stretch": 1.1 - 0.1 * clampf(t / 0.2, 0.0, 1.0), "anim": "physical"}
