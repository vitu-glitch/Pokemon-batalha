extends Action
## Volt Tackle, like in the anime: the user crackles, sets off running and wraps itself in
## a ball of electricity (a big see-through plasma globe round its body, bolts leaping off
## it), then rams the rival in a straight line. It shrugs off light hits while it lasts,
## takes recoil when it lands and can paralyze. If it misses it is left open.

const OUTLINE := Color(0.85, 0.42, 0.05)
const CORE := Color(1.0, 0.93, 0.35)

var _dir := Vector3.FORWARD
var _cap_y := INF
var _globe: Node3D
var _light: OmniLight3D
var _spark := 0.0


func on_start() -> void:
	turn_mult = 2.0
	_light = OmniLight3D.new()
	_light.light_color = CORE
	_light.omni_range = 6.0
	_light.light_energy = 0.0
	l.main.vfx.add_child(_light)
	l.main.vfx.cobble("thunderbolt_actorsparks", l.center(), null, l.data.height)
	play_sound("charge", -6.0)


func _follow() -> void:
	var c := l.center()
	if is_instance_valid(_globe):
		_globe.global_position = c
	if is_instance_valid(_light):
		_light.global_position = c


func in_startup(delta: float) -> void:
	var k := clampf(t / maxf(startup_len(), 0.01), 0.0, 1.0)
	tint_col = Roster.TYPE_COLOR.electric
	tint_k = 0.2 + 0.35 * k
	_light.light_energy = 3.0 * k
	_follow()
	_spark -= delta
	if _spark <= 0.0:
		_spark = 0.06
		var c := l.center()
		l.main.vfx.bolt(c, c + Vector3(randf_range(-1, 1), randf_range(-0.6, 1), randf_range(-1, 1)).normalized() * l.data.height * 0.7,
			CORE, 0.08, 0.1, 0, OUTLINE)


func on_active() -> void:
	_dir = l.attack_dir()
	if l.is_on_floor() and absf(_dir.y) < 0.2:
		_dir = Vector3(_dir.x, 0.0, _dir.z).normalized()
	_cap_y = l.target_center().y - l.data.height * 0.5 + 0.3 if _dir.y > 0.0 else INF
	faces_rival = false
	no_brake = true
	no_gravity = absf(_dir.y) > 0.01 or not l.is_on_floor()
	hit({"shape": "capsule", "a": Vector3(0, l.data.height * 0.45, -0.3), "b": Vector3(0, l.data.height * 0.45, l.data.radius + 0.7),
		"radius": l.data.radius + 0.25})
	# The plasma globe round its body (Electro Ball's, much bigger).
	_globe = l.main.vfx.pixel_ball("electroball", 6, l.data.height * 2.6, CORE, 18.0, false)
	_follow()
	l.main.vfx.cobble("thunder_actorring", l.global_position, null, l.data.height)
	play_sound("volttackle", 2.0)


func in_active(delta: float) -> void:
	if _dir.y > 0.0 and l.global_position.y >= _cap_y:
		_dir = Vector3(_dir.x, 0.0, _dir.z).normalized()
	var v: Vector3 = _dir * d.dist / d.active
	l.velocity = Vector3(v.x, v.y if no_gravity else l.velocity.y, v.z)
	_follow()
	tint_k = 0.6
	if is_instance_valid(_light):
		_light.light_energy = 5.0
	var vfx: Vfx = l.main.vfx
	_spark -= delta
	if _spark <= 0.0:
		_spark = 0.04
		var c := l.center()
		var r: float = l.data.height * 1.2
		# Bolts leaping off the globe, and a trail of them on the ground behind.
		var out := Vector3(randf_range(-1, 1), randf_range(-0.5, 1), randf_range(-1, 1)).normalized()
		vfx.bolt(c + out * r * 0.8, c + out * r * 1.4, CORE, 0.1, 0.14, 0, OUTLINE)
		var back := l.global_position - _dir * 0.6
		vfx.bolt(back, back - _dir * randf_range(1.0, 2.0) + Vector3(randf_range(-0.5, 0.5), 0.05, randf_range(-0.5, 0.5)), CORE, 0.15, 0.12, 0, OUTLINE)
	if int(total * 10.0) != int((total - l.get_physics_process_delta_time()) * 10.0):
		vfx.mark(l.global_position, "burned", 0.6, 2.0)


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
	if is_instance_valid(_globe):
		_globe.queue_free()
	_globe = null
	if is_instance_valid(_light):
		_light.queue_free()
	_light = null


func pose() -> Dictionary:
	match phase:
		"startup":
			return {"tilt": -0.3 * clampf(t / maxf(startup_len(), 0.01), 0.0, 1.0), "stretch": 0.85}
		"active":
			return {"tilt": 0.75, "stretch": 1.15, "anim": "run" if l.model.has_anim("run") else "", "anim_speed": 2.5}
	return {"tilt": -0.1, "stretch": 0.92 + 0.04 * sin(total * 10.0)}
