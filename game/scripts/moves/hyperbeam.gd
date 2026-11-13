extends EnergyStream
## Hyper Beam: energy gathers at the mouth in rings that close in (long, readable wind-up),
## then a huge orange beam (Dragon Pulse's: lumpy, a see-through sheath with coils round a
## thin hot core, never a plain tube) pours from a flare at the mouth for as long as the
## button is held (EnergyStream: aimed, several hits, energy drain), with rings of shock at
## its start and explosions where it ends. Afterwards it must recharge, as in the games: not
## rooted, but very slow for "tired" seconds.

const COL := Color(1.0, 0.62, 0.25)
const PALETTE := {"edge": Color(0.55, 0.18, 0.04), "mid": Color(1.0, 0.5, 0.12), "glow": Color(1.0, 0.85, 0.35), "core": Color(1.0, 0.98, 0.88)}
var _beams: Array[MeshInstance3D] = []
var _flare: Node3D
var _ring := 0.0
var _boom := 0.0


func on_start() -> void:
	turn_mult = 1.6
	play_sound("hyperbeam_charge", -4.0)


func in_startup(delta: float) -> void:
	tint_col = COL
	tint_k = 0.4 * clampf(t / startup_len(), 0.0, 1.0)
	_ring -= delta
	if _ring <= 0.0:
		_ring = 0.12
		# Rings closing in on the mouth, and sparks drawn in.
		var m := mouth()
		l.main.vfx.wave(m, lerpf(1.6, 0.5, t / startup_len()), 0.12, COL, 0.05)
		l.main.vfx.burst("stars", m + Vector3(randf_range(-1, 1), randf_range(-0.5, 1), randf_range(-1, 1)), Vector3.UP, COL, 0.3)


func _beam_on(o: Vector3, dir: Vector3) -> void:
	var vfx: Vfx = l.main.vfx
	_beams = vfx.dragon_beam(d.radius * 0.8, 26.0, PALETTE)
	for b in _beams:
		vfx.place_beam(b, o, o + dir * 0.5, 1.0)
	_flare = vfx.pixel_ball("sun_ball", 6, 2.6, COL, 18.0)
	_flare.global_position = o
	var face := Basis.looking_at(dir, Vector3.UP)
	for i in 3:
		var at := o + dir * (0.6 + i * 1.6)
		vfx.flat_sprite("res://fx/tex/custom/psy_ring.png", 1, 1.6 + i * 0.5, at, face, 0.3 + 0.06 * i, COL.lerp(Color.WHITE, 0.35), 0.0,
			func(n: MeshInstance3D, k: float):
				n.scale = Vector3.ONE * snappedf(1.0 + k * 1.8, 0.2)
				n.material_override.set_shader_parameter("tint", Color(COL.lerp(Color.WHITE, 0.35), 1.0 - snappedf(k, 0.25))), 0.06)
	for k in 8:
		vfx.burst("sparks", o, (-dir + Vector3(randf_range(-0.6, 0.6), randf_range(-0.3, 0.6), randf_range(-0.6, 0.6))).normalized(), COL, 0.5)
	vfx.light(o, COL, 6.0, 9.0, 0.4)
	play_sound("hyperbeam", 2.0)


func _beam_at(o: Vector3, dir: Vector3, length: float, full: float) -> void:
	var vfx: Vfx = l.main.vfx
	var front := o + dir * length
	var k := 1.0 + 0.14 * sin(total * 55.0)
	for b in _beams:
		if is_instance_valid(b):
			vfx.place_beam(b, o, front, k)
	if is_instance_valid(_flare):
		_flare.global_position = o
		_flare.scale = Vector3.ONE * (1.0 + 0.2 * sin(total * 40.0))
	# Explosions where it ends, now and then (the wall or the end of its reach).
	_boom -= l.get_physics_process_delta_time()
	if length >= full - 0.05 and _boom <= 0.0:
		_boom = 0.3
		vfx.cobble("explosion_burst_flash", front, null, 1.0)
		vfx.burst("debris", front, -dir, Color(0, 0, 0, 0), 0.6)
		vfx.light(front, COL, 4.0, 6.0, 0.2)
		if front.y < l.main.ground_y + 0.6:
			vfx.mark(Vector3(front.x, l.main.ground_y, front.z), "burned", 1.2, 3.0)


func _beam_off(dur: float) -> void:
	for b in _beams:
		l.main.vfx.stop_beam(b, dur)
	_beams.clear()
	if is_instance_valid(_flare):
		_flare.queue_free()
	_flare = null


func on_recovery() -> void:
	super()
	# The recharge: very slow for a while.
	l.slow_down(float(d.tired_slow), float(d.tired))
	l.main.vfx.text(l.center() + Vector3.UP * 1.0, l.tr("Must recharge!"), Color(1.0, 0.75, 0.45))


func pose() -> Dictionary:
	match phase:
		"startup":
			return {"tilt": -0.25 * clampf(t / startup_len(), 0.0, 1.0), "stretch": 0.94, "anim": "special"}
		"active":
			return {"tilt": -0.1 + 0.03 * sin(total * 50.0), "stretch": 1.02}
	# Recharging: slumped, breathing hard.
	return {"tilt": 0.25 * (1.0 - t / d.recovery), "stretch": 0.95 + 0.03 * sin(total * 6.0)}
