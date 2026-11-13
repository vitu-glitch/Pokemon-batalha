extends EnergyStream
## Solar Beam: a long, very visible charge. A beam of light comes down from the sky onto
## the flower, a sun forms in it and the ground marks the line the beam will follow (it
## turns slowly with the aim while charging). Then a huge golden beam pours out of the
## flower for as long as the button is held (EnergyStream: aimed, several hits, energy
## drain), lumpy and with coils of light like Dragon Pulse's, never a plain tube, leaves
## swirling off it. Quicker to charge in the sun.

const GOLD := Color(1.0, 0.85, 0.4)
const PALETTE := {"edge": Color(0.45, 0.55, 0.12), "mid": Color(0.95, 0.8, 0.25), "glow": Color(1.0, 0.95, 0.55), "core": Color(1.0, 1.0, 0.92)}

var _pillar: MeshInstance3D
var _sun: Node3D
var _line: MeshInstance3D
var _line_mat: StandardMaterial3D
var _beams: Array[MeshInstance3D] = []
var _spark := 0.0
var _leaf := 0.0


func on_start() -> void:
	turn_mult = d.charge_turn
	# In harsh sunlight it barely needs to charge, as in the games.
	if l.main.weather.is_on("sun"):
		startup_mult = 0.25
	play_sound("solarbeam_charge", -2.0)
	var vfx: Vfx = l.main.vfx
	_pillar = vfx.beam(Color(1.0, 0.92, 0.55), 0.35, Color(1.0, 1.0, 0.9), 2.0)
	_sun = vfx.pixel_ball("sun_ball", 6, 0.75, Color(1.0, 0.72, 0.2), 8.0)
	# Line on the ground: where the beam will go. Pulses slowly (under 2 times per second).
	_line = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1, 1)
	_line.mesh = pm
	_line_mat = StandardMaterial3D.new()
	_line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_line_mat.albedo_color = Color(1.0, 0.92, 0.5, 0.0)
	_line.material_override = _line_mat
	_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	vfx.add_child(_line)


func _flower() -> Vector3:
	return l.point("locator_special") + Vector3.UP * 0.35


func origin() -> Vector3:
	return _flower() + l.forward() * 0.5


func in_startup(delta: float) -> void:
	# On the frame it is released the charge has already been removed.
	if phase != "startup" or not is_instance_valid(_line):
		return
	var k: float = clampf(t / startup_len(), 0.0, 1.0)
	tint_col = Color(1.0, 0.9, 0.5)
	tint_k = 0.4 * k
	var flower := _flower()
	var vfx: Vfx = l.main.vfx
	if is_instance_valid(_pillar):
		vfx.place_beam(_pillar, flower + Vector3.UP * 30.0, flower, 0.3 + 1.2 * k)
	if is_instance_valid(_sun):
		_sun.global_position = flower
		_sun.scale = Vector3.ONE * (0.5 + 1.3 * k)
	# Ground line the beam will follow.
	var dir := _dir()
	dir = Vector3(dir.x, 0.0, dir.z).normalized()
	var length := _reach(flower, dir)
	var center: Vector3 = l.global_position + dir * (l.data.radius + length * 0.5)
	center.y = l.main.ground_y + 0.05
	_line.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP) * Basis.from_scale(Vector3(d.radius * 2.0, 1.0, length)), center)
	_line_mat.albedo_color.a = (0.12 + 0.2 * k) * (0.75 + 0.25 * sin(t * TAU * 1.5))
	# Light gathers in the flower.
	_spark -= delta
	if _spark <= 0.0:
		_spark = 0.05
		var from_pos := flower + Vector3(randf_range(-1, 1), randf_range(0.2, 1.2), randf_range(-1, 1)).normalized() * randf_range(1.5, 2.5)
		vfx.burst("stars", from_pos, (flower - from_pos).normalized(), Color(0, 0, 0, 0), 0.25)
		if randf() < 0.3:
			vfx.burst("leaves", l.global_position, Vector3.UP, Color(0, 0, 0, 0), 0.3)


func _beam_on(o: Vector3, dir: Vector3) -> void:
	_remove_charge()
	var vfx: Vfx = l.main.vfx
	_beams = vfx.dragon_beam(d.radius * 0.75, 24.0, PALETTE)
	for b in _beams:
		vfx.place_beam(b, o, o + dir * 0.5, 1.0)
	_sun = vfx.pixel_ball("sun_ball", 6, 1.6, GOLD, 14.0)
	_sun.global_position = o
	vfx.light(o + dir * 2.0, GOLD, 6.0, 10.0, 0.4)
	vfx.cobble("leafstorm_actorwind", o, o + dir * 8.0, l.data.height)
	l.velocity -= dir * 1.0
	play_sound("solarbeam", 2.0)


func _beam_at(o: Vector3, dir: Vector3, length: float, _full: float) -> void:
	var vfx: Vfx = l.main.vfx
	var front := o + dir * length
	for b in _beams:
		if is_instance_valid(b):
			vfx.place_beam(b, o, front, 1.0 + 0.12 * sin(total * 50.0))
	if is_instance_valid(_sun):
		_sun.global_position = o
		_sun.scale = Vector3.ONE * (1.0 + 0.15 * sin(total * 40.0))
	_leaf -= l.get_physics_process_delta_time()
	if _leaf <= 0.0:
		_leaf = 0.07
		var side := dir.cross(Vector3.UP).normalized()
		vfx.burst("leaves", o + dir * randf_range(1.0, length) + side * randf_range(-0.8, 0.8), Vector3.UP, Color(0, 0, 0, 0), 0.4)


func _beam_off(dur: float) -> void:
	_remove_charge()
	for b in _beams:
		l.main.vfx.stop_beam(b, dur)
	_beams.clear()


func _remove_charge() -> void:
	if is_instance_valid(_pillar):
		l.main.vfx.stop_beam(_pillar, 0.2)
	_pillar = null
	if is_instance_valid(_sun):
		_sun.queue_free()
	_sun = null
	if is_instance_valid(_line):
		_line.queue_free()
	_line = null


func pose() -> Dictionary:
	match phase:
		"startup":
			var k: float = t / startup_len()
			return {"tilt": -0.2 * k, "stretch": 0.94 - 0.04 * k}
		"active":
			return {"tilt": -0.1 + 0.03 * sin(total * 40.0), "stretch": 1.06}
	return {"tilt": 0.1 * (1.0 - t / d.recovery), "stretch": 0.97}
