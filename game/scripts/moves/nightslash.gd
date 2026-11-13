extends Action
## Night Slash: Greninja vanishes (smoke) and reappears beside the rival, facing it,
## and slashes. The stick picks the side (or it is random); if the rival is farther
## than "reach", it only closes in toward it. An attack from a different angle: the
## smoke as it leaves gives it away.

var _target_pos := Vector3.ZERO


func on_start() -> void:
	turn_mult = 4.0


func in_startup(_delta: float) -> void:
	tint_col = Roster.TYPE_COLOR.dark
	tint_k = 0.35 * (t / d.startup)


func _flank() -> Vector3:
	var r := l.rival
	if r == null or not is_instance_valid(r) or r.state == "ko":
		return l.global_position + l.forward() * 4.0
	var toward := r.global_position - l.global_position
	toward.y = 0.0
	if toward.length() > d.reach:
		return l.global_position + toward.normalized() * (d.reach - 1.5)
	var side := toward.normalized().cross(Vector3.UP)
	var dir_sign := 1.0 if randf() < 0.5 else -1.0
	if l.is_player and absf(l.ctrl.move_input.x) > 0.3:
		dir_sign = -signf(l.ctrl.move_input.x)
	var p: Vector3 = r.global_position + side * dir_sign * (r.radius() + l.data.radius + 0.9) - toward.normalized() * 0.4
	return Vector3(p.x, r.global_position.y, p.z)


func on_active() -> void:
	var vfx: Vfx = l.main.vfx
	vfx.burst("shadow", l.center(), Vector3.UP, Color(0, 0, 0, 0), 1.2)
	vfx.burst("smoke", l.global_position, Vector3.UP, Color(0, 0, 0, 0), 0.8)
	_target_pos = _flank()
	l.global_position = _target_pos
	l.reset_physics_interpolation()
	if l.rival and is_instance_valid(l.rival):
		l.face_now(l.rival.global_position)
	l.velocity = Vector3.ZERO
	vfx.burst("shadow", l.center(), Vector3.UP, Color(0, 0, 0, 0), 1.0)
	hit({"shape": "sphere", "center": Vector3(0, l.data.height * 0.5, l.data.radius + 0.8), "radius": d.radius})
	var col := Roster.TYPE_COLOR.dark.lightened(0.3)
	var clock := {"t": 0.0}
	vfx.ribbon(func():
		clock.t += vfx.get_process_delta_time()
		var k := clampf(clock.t / 0.14, 0.0, 1.0)
		var c := l.center() + Vector3.UP * 0.2
		var dir := l.forward().rotated(Vector3.UP, lerpf(1.2, -1.2, k)) + Vector3.DOWN * (k - 0.5) * 1.2
		return [c + dir * 0.5, c + dir * (l.data.radius + 1.6)], col, 0.14, 0.15)
	play_sound("nightslash", 0.0)


func on_recovery() -> void:
	tint_k = 0.0


func pose() -> Dictionary:
	match phase:
		"startup":
			return {"tilt": -0.2, "stretch": 0.9}
		"active":
			return {"tilt": 0.35, "side": -0.3, "stretch": 1.08, "anim": "physical", "reset": t < 0.02}
	return {"tilt": 0.1 * (1.0 - t / d.recovery)}
