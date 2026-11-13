extends Action
## Flamethrower: hold for a cone of fire from the mouth. While firing it turns slowly
## (you can circle around it) and drains energy; it ends on release or when energy runs
## out. Hits several times in a row with little push.

var _g: Hit
var _fire_fx: GPUParticles3D
var _embers: GPUParticles3D
var _light: OmniLight3D
var _sound_t := 0.0
var _heat := 0.0


func on_start() -> void:
	turn_mult = 1.5
	play_sound("charge", -14.0)


func in_startup(_delta: float) -> void:
	tint_col = Roster.TYPE_COLOR.fire
	tint_k = 0.25 * (t / d.startup)
	if int(total * 30.0) % 3 == 0:
		l.main.vfx.burst("embers", l.point("locator_mouth"), l.forward(), Color(0, 0, 0, 0), 0.6)


func _dir() -> Vector3:
	return aim_stream(l.point("locator_mouth"))


func on_active() -> void:
	turn_mult = d.emit_turn
	var mouth := l.point("locator_mouth")
	_g = hit({"shape": "cone", "local": false, "center": mouth, "dir": _dir(), "length": d.length, "angle": d.angle,
		"interval": d.interval})
	var vfx: Vfx = l.main.vfx
	# Narrow and long ("angle", "length"): faster, tighter flames.
	_fire_fx = vfx.continuous_emitter("fire_fx", 320, 0.6, Vector2(17.5, 22.0), 8.5, Vector2(0.45, 0.9))
	var pm: ParticleProcessMaterial = _fire_fx.process_material
	var width_curve := Curve.new()
	width_curve.add_point(Vector2(0, 0.25))
	width_curve.add_point(Vector2(0.5, 1.2))
	width_curve.add_point(Vector2(1, 1.7))
	var ct := CurveTexture.new()
	ct.curve = width_curve
	pm.scale_curve = ct
	pm.damping_min = 6.0
	pm.damping_max = 9.0
	pm.gravity = Vector3(0, 2.5, 0)
	_embers = vfx.continuous_emitter("embers", 30, 0.75, Vector2(12.0, 18.0), 12.0, Vector2(0.7, 1.2))
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.55, 0.2)
	_light.omni_range = 7.0
	l.main.vfx.add_child(_light)
	play_sound("flamethrower", 0.0)


func in_active(delta: float) -> void:
	l.energy -= d.drain * delta
	if l.energy <= 0.0:
		l.energy = 0.0
		_go_to("recovery")
		return
	var mouth := l.point("locator_mouth")
	var dir := _dir()
	_g.center = mouth
	_g.dir = dir
	# Cut short by a stronger stream (Combat._streams): the hit and the flames stop there.
	var reach: float = _g.cut if _g.cut > 0.0 else float(d.length)
	_g.length = reach
	if is_instance_valid(_fire_fx):
		var want := 0.6 * clampf(reach / float(d.length), 0.15, 1.0)
		if absf(_fire_fx.lifetime - want) > 0.08:
			_fire_fx.lifetime = want
	var b := Basis.looking_at(dir, Vector3.UP)
	for e in [_fire_fx, _embers]:
		if is_instance_valid(e):
			e.global_transform = Transform3D(b, mouth)
	_light.global_position = mouth + dir * 2.5
	_light.light_energy = 5.0 + randf() * 3.0
	_sound_t -= delta
	if _sound_t <= 0.0:
		_sound_t = 0.45
		play_sound("flamethrower", -3.0)
	_heat -= delta
	if _heat <= 0.0:
		_heat = 0.18
		if randf() < 0.4:
			var p: Vector3 = mouth + dir * d.length
			p.y = l.main.ground_y
			if p.distance_to(l.global_position) < d.length + 1.0:
				l.main.vfx.mark(p, "burned", 0.7, 2.5)
	tint_k = 0.18


func on_recovery() -> void:
	_turn_off()
	tint_k = 0.0
	turn_mult = 0.6


func on_end(_i: bool) -> void:
	_turn_off()


func _turn_off() -> void:
	l.main.vfx.stop_emitter(_fire_fx)
	l.main.vfx.stop_emitter(_embers)
	_fire_fx = null
	_embers = null
	if is_instance_valid(_light):
		_light.queue_free()


func pose() -> Dictionary:
	match phase:
		"startup":
			return {"tilt": -0.25 * (t / d.startup), "stretch": 1.0 + 0.06 * (t / d.startup), "anim": "special"}
		"active":
			return {"tilt": 0.18 + 0.03 * sin(total * 30.0), "stretch": 1.04}
	return {"tilt": 0.05}
