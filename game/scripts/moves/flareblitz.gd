extends Action
## Flare Blitz: wraps itself in flames (very visible) and charges in a straight line.
## It shrugs off light hits while it lasts and takes recoil when it lands. If it misses,
## it is left panting: very punishable.

var _dir := Vector3.FORWARD
var _cap_y := INF
var _fire_fx: GPUParticles3D
var _light: OmniLight3D


func on_start() -> void:
	turn_mult = 2.0
	_fire_fx = l.main.vfx.continuous_emitter("fire_fx", 90, 0.5, Vector2(1.0, 3.0), 70.0, Vector2(0.5, 1.1))
	(_fire_fx.process_material as ParticleProcessMaterial).emission_sphere_radius = l.data.radius
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.5, 0.15)
	_light.omni_range = 6.0
	l.main.vfx.add_child(_light)
	play_sound("charge", -6.0)


func _seguir_fuego() -> void:
	if is_instance_valid(_fire_fx):
		_fire_fx.global_position = l.center()
	if is_instance_valid(_light):
		_light.global_position = l.center()
		_light.light_energy = 4.0 + randf() * 2.0


func in_startup(_delta: float) -> void:
	tint_col = Roster.TYPE_COLOR.fire
	tint_k = 0.5 * (t / d.startup)
	_seguir_fuego()


func on_active() -> void:
	# Toward the target, including its height (if it flies, or if the dash starts in the
	# air). It rises at most to where the target was: if the target dodges, it carries on
	# horizontally at that height instead of shooting into the sky.
	_dir = l.attack_dir()
	if l.is_on_floor() and absf(_dir.y) < 0.2:
		_dir = Vector3(_dir.x, 0.0, _dir.z).normalized()
	_cap_y = l.target_center().y - l.data.height * 0.5 + 0.3 if _dir.y > 0.0 else INF
	faces_rival = false
	no_brake = true
	no_gravity = absf(_dir.y) > 0.01 or not l.is_on_floor()
	var g := hit({"shape": "capsule", "a": Vector3(0, l.data.height * 0.45, -0.3), "b": Vector3(0, l.data.height * 0.45, l.data.radius + 0.6),
		"radius": l.data.radius})
	play_sound("flareblitz", 2.0)


func in_active(_delta: float) -> void:
	if _dir.y > 0.0 and l.global_position.y >= _cap_y:
		_dir = Vector3(_dir.x, 0.0, _dir.z).normalized()
	var v: Vector3 = _dir * d.dist / d.active
	l.velocity = Vector3(v.x, v.y if no_gravity else l.velocity.y, v.z)
	_seguir_fuego()
	tint_k = 0.55
	if int(total * 30.0) % 2 == 0:
		l.main.vfx.burst("fire_fx", l.center() - _dir * 0.8, -_dir, Color(0, 0, 0, 0), 1.2)
	if int(total * 10.0) != int((total - l.get_physics_process_delta_time()) * 10.0):
		l.main.vfx.mark(l.global_position, "burned", 0.7, 2.5)


func on_recovery() -> void:
	no_brake = false
	tint_k = 0.0
	l.velocity.x *= 0.25
	l.velocity.z *= 0.25
	_turn_off()
	l.main.vfx.burst("smoke", l.center(), Vector3.UP)


func on_end(_i: bool) -> void:
	_turn_off()


func _turn_off() -> void:
	l.main.vfx.stop_emitter(_fire_fx)
	_fire_fx = null
	if is_instance_valid(_light):
		_light.queue_free()


func pose() -> Dictionary:
	match phase:
		"startup":
			return {"tilt": -0.3 * (t / d.startup), "stretch": 0.85, "anim": "battle_cry" if l.model.has_anim("battle_cry") else ""}
		"active":
			return {"tilt": 0.7, "stretch": 1.15, "anim": "air_fly" if l.model.has_anim("air_fly") else "", "anim_speed": 2.0}
	return {"tilt": -0.1, "stretch": 0.92 + 0.04 * sin(total * 10.0)}
