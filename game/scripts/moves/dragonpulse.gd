extends EnergyStream
## Dragon Pulse, held like a kamehameha: it gathers dragon energy into a ball in front of
## its mouth (sparks and rings drawn in, the ball swelling), turning slowly toward the
## rival, then pours it out as a beam for as long as the button is held (EnergyStream: aimed,
## several hits, energy drain). The ball stays lit at the mouth and a smaller one rides the
## beam's front; it bursts where the beam strikes. The beam is not a tube: see DRAGON_BEAM.
## Energy, not a thing: it cannot be batted back.

const VIOLET := Color(0.5, 0.36, 1.0)
const CYAN := Color(0.45, 0.86, 1.0)

var _ball: Node3D
var _head: Node3D
var _beams: Array[MeshInstance3D] = []
var _gather := 0.0
var _trail := 0.0
var _burst := 0.0


func _hold() -> Vector3:
	return mouth() + l.forward() * 0.8


func on_start() -> void:
	turn_mult = d.charge_turn
	_ball = l.main.vfx.pixel_ball("dragonpulse_ball", 6, 1.8, VIOLET, 14.0)
	_ball.scale = Vector3.ONE * 0.15
	l.main.vfx.cobble("dracometeor_actorpulseaura", l.center(), null, l.data.height)
	play_sound("dragonpulse_charge", -6.0)


func in_startup(delta: float) -> void:
	var k := clampf(t / maxf(startup_len(), 0.01), 0.0, 1.0)
	tint_col = VIOLET
	tint_k = 0.1 + 0.12 * k
	var c := _hold()
	if is_instance_valid(_ball):
		_ball.global_position = c
		_ball.scale = Vector3.ONE * lerpf(0.15, 1.0, k * k)
	# Energy drawn into the ball: sparks from all round, and a ring closing on it now and
	# then (faced along its aim, so it reads as a ring from behind).
	_gather -= delta
	if _gather <= 0.0:
		_gather = 0.04
		var from_pos: Vector3 = c + Vector3(randf_range(-1, 1), randf_range(-0.7, 1), randf_range(-1, 1)).normalized() * randf_range(1.4, 2.4)
		l.main.vfx.burst("sparks", from_pos, (c - from_pos).normalized(), CYAN if randf() < 0.5 else VIOLET, 0.35)
		if randf() < 0.25:
			l.main.vfx.flat_sprite("res://fx/tex/custom/psy_ring.png", 1, 2.6, c, Basis.looking_at(l.forward(), Vector3.UP), 0.2,
				CYAN, 0.0, func(n: MeshInstance3D, rk: float):
					if is_instance_valid(l):
						n.global_position = _hold()
					n.scale = Vector3.ONE * maxf(0.05, snappedf(1.0 - rk, 0.2)), 0.05)


func origin() -> Vector3:
	return _hold()


func _beam_on(o: Vector3, dir: Vector3) -> void:
	var vfx: Vfx = l.main.vfx
	_beams = vfx.dragon_beam(d.radius * 0.55)
	for b in _beams:
		vfx.place_beam(b, o, o + dir * 0.5)
	_head = vfx.pixel_ball("dragonpulse_ball", 6, 1.5, CYAN, 18.0, false)
	_head.global_position = o
	if is_instance_valid(_ball):
		_ball.scale = Vector3.ONE * 1.25
	vfx.light(o, VIOLET, 5.0, 8.0, 0.4)
	vfx.cobble("dragonrage_actorring", o, o + dir * 5.0, 1.5)
	# Each tick that strikes bursts on the body (not more than a few a second).
	_g.on_strike = func(target, _r):
		if is_instance_valid(target) and _burst <= 0.0:
			_burst = 0.3
			var oc: Vector3 = target.center() if target.has_method("center") else target.global_position
			_impact(oc, dir)
	play_sound(id, 0.0)


func _beam_at(o: Vector3, dir: Vector3, length: float, full: float) -> void:
	var vfx: Vfx = l.main.vfx
	var front := o + dir * length
	for b in _beams:
		if is_instance_valid(b):
			vfx.place_beam(b, o, front, 1.0 + 0.12 * sin(total * 45.0))
	if is_instance_valid(_head):
		_head.global_position = front
		_head.scale = Vector3.ONE * (1.0 + 0.15 * sin(total * 40.0))
	if is_instance_valid(_ball):
		_ball.global_position = o
		_ball.scale = Vector3.ONE * (1.25 + 0.1 * sin(total * 50.0))
	var dt := l.get_physics_process_delta_time()
	_burst -= dt
	# Against a wall it bursts there now and then.
	if length >= full - 0.05 and full < float(d.length) and _burst <= 0.0:
		_burst = 0.35
		_impact(front, dir)
	_trail -= dt
	if _trail <= 0.0:
		_trail = 0.06
		var at := o + dir * randf_range(0.5, length)
		var side := dir.cross(Vector3.UP).normalized()
		vfx.burst("sparks", at + side * randf_range(-0.6, 0.6) + Vector3.UP * randf_range(-0.4, 0.4), dir, CYAN, 0.25)


func _beam_off(dur: float) -> void:
	for b in _beams:
		l.main.vfx.stop_beam(b, dur)
	_beams.clear()
	for n in [_ball, _head]:
		if is_instance_valid(n):
			n.queue_free()
	_ball = null
	_head = null


func _impact(at: Vector3, dir: Vector3) -> void:
	var vfx: Vfx = l.main.vfx
	vfx.cobble("dragonrage_target", at, l.center(), 1.6)
	vfx.light(at, CYAN, 6.0, 6.0, 0.35)
	vfx.wave(Vector3(at.x, l.main.ground_y, at.z), 2.4, 0.3, VIOLET, 0.1)
	for i in 2:
		vfx.flat_sprite("res://fx/tex/custom/psy_ring.png", 1, 0.9, at, Basis.looking_at(dir, Vector3.UP), 0.25 + i * 0.07,
			CYAN if i == 0 else VIOLET, 0.0, func(n: MeshInstance3D, rk: float):
				n.scale = Vector3.ONE * snappedf(1.0 + rk * (1.4 + i), 0.25), 0.04)
	l.main.audio.play_sound("dragonpulse_hit", at, 0.0)


func on_end(interrupted: bool) -> void:
	super(interrupted)
	_beam_off(0.1)


## Held like a kamehameha: leaning back as the ball grows, pushing forward as it fires.
func pose() -> Dictionary:
	match phase:
		"startup":
			var k: float = clampf(t / maxf(startup_len(), 0.01), 0.0, 1.0)
			return {"tilt": -0.22 * k, "stretch": 0.95, "anim": "special", "reset": t < 0.02}
		"active":
			return {"tilt": 0.18 + 0.03 * sin(total * 40.0), "stretch": 1.07}
	return {"tilt": 0.1 * (1.0 - t / d.recovery), "stretch": 0.98}
