extends Action
## Thunderbolt: the body charges, crackling more and more, while a ring at the rival's feet
## follows it. A moment before firing ("lock" seconds) the ring stops and turns white; then
## the bolt leaps from the cheeks to that spot at once. Avoided by dodging (or moving off
## the ring) right when it turns white: lightning gives no time once it is out. Not a
## projectile, so it cannot be sent back. Reach "reach" metres.
##
## The look is the series' one: drawn bolts (yellow, white core, amber outline) bursting
## from the whole body, a thick one to the rival with strands around it, sparks running
## over whoever it hits and a star of bolts on the ground where it lands.

const OUTLINE := Color(0.85, 0.42, 0.05)
const CORE := Color(1.0, 0.93, 0.35)

var _ring: MeshInstance3D
var _glow: OmniLight3D
var _at := Vector3.ZERO
var _locked := false
var _crackle := 0.0
var _cheeks := 0.0
var _ground := 0.0


func on_start() -> void:
	turn_mult = 2.5
	_locked = false
	_at = _target_spot()
	_ring = l.main.vfx.telegraph(_at, d.radius + 0.3, startup_len() + 0.05, Roster.TYPE_COLOR.electric)
	_ring.material_override = _ring.material_override.duplicate()     # its own, to turn it white
	l.main.vfx.cobble("thunderbolt_actorsparks", l.center(), null, l.data.height)
	l.main.vfx.cobble("thunderbolt_actorbolts", l.center(), null, l.data.height)
	# Its own light, which grows steadily while charging (no flicker).
	_glow = OmniLight3D.new()
	_glow.light_color = CORE
	_glow.omni_range = 3.0 + l.data.height * 2.0
	_glow.light_energy = 0.0
	_glow.shadow_enabled = false
	l.add_child(_glow)
	_glow.position = Vector3(0, l.data.height * 0.6, 0)
	play_sound("charge", -10.0)


## Where the bolt would land now: the rival, or straight ahead as far as it reaches.
func _target_spot() -> Vector3:
	var r: Node3D = l.aim_target()
	var spot: Vector3 = l.global_position + l.forward() * d.reach
	if r and is_instance_valid(r) and not (r is Fighter and r.state == "ko"):
		spot = r.global_position
	var flat := Vector3(spot.x - l.global_position.x, 0, spot.z - l.global_position.z)
	if flat.length() > d.reach:
		spot = l.global_position + flat.normalized() * d.reach
	spot.y = l.main.ground_y
	return spot


func in_startup(delta: float) -> void:
	var k := clampf(t / maxf(startup_len(), 0.01), 0.0, 1.0)
	var vfx: Vfx = l.main.vfx
	tint_col = Roster.TYPE_COLOR.electric
	tint_k = 0.12 + 0.3 * k + (0.25 if _locked else 0.0)
	if is_instance_valid(_glow):
		_glow.light_energy = 0.5 + 2.5 * k
	if not _locked:
		_at = _at.move_toward(_target_spot(), 14.0 * delta)
		if t >= startup_len() - float(d.lock):
			_locked = true
			if is_instance_valid(_ring):
				_ring.material_override.set_shader_parameter("color", Color(1, 1, 1))
			# It gathers: sparks pulled into the body.
			vfx.burst("sparks", l.center(), Vector3.UP, CORE, 0.8)
	if is_instance_valid(_ring):
		_ring.global_position = _at + Vector3.UP * 0.04
		_ring.material_override.set_shader_parameter("k", k)
	var c := l.center()
	var body: float = l.data.height * 0.55
	# Arcs hugging the body, more and thicker as the charge fills.
	_crackle -= delta
	if _crackle <= 0.0:
		_crackle = lerpf(0.09, 0.03, k)
		var n := Vector3(randf_range(-1, 1), randf_range(-0.6, 1), randf_range(-1, 1)).normalized()
		var axis := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
		vfx.bolt(c + n * body, c + n.rotated(axis, randf_range(0.7, 1.4)) * body * randf_range(1.0, 1.3),
			CORE, 0.07, lerpf(0.05, 0.11, k), 0, OUTLINE)
	# The cheeks spit little sparks.
	_cheeks -= delta
	if _cheeks <= 0.0:
		_cheeks = 0.07
		for side in ["cheek_active_left", "cheek_active_right"]:
			var p := l.point(side)
			var out := (p - c).normalized() if p.distance_to(c) > 0.05 else l.forward()
			vfx.bolt(p, p + (out + Vector3(randf_range(-0.6, 0.6), randf_range(-0.3, 0.6), randf_range(-0.6, 0.6))) * 0.35,
				Color(1, 1, 0.8), 0.06, 0.05, 0)
	# Near the end, it reaches the ground around its feet.
	if k > 0.55:
		_ground -= delta
		if _ground <= 0.0:
			_ground = 0.06
			var foot := l.global_position + Vector3.UP * 0.05
			var spread: Vector3 = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * randf_range(0.7, 1.4) * l.data.radius * 2.0
			vfx.bolt(c, foot + spread, CORE, 0.07, 0.07, 0, OUTLINE)


func on_active() -> void:
	tint_k = 0.6
	tint_col = Color(1, 1, 0.85)
	var vfx: Vfx = l.main.vfx
	var c := l.center()
	var from_pos := l.point("cheek_active_right")
	var to := _at + Vector3.UP * 0.9
	var g := hit({"shape": "capsule", "local": false, "a": from_pos, "b": to, "radius": d.radius, "lifetime": 0.06, "contact": false})
	# Whoever it strikes keeps crackling for a moment.
	g.on_strike = func(o: Node, _res: String):
		var who := o as Node3D
		var h: float = o.data.height if o is Fighter else 1.0
		vfx.crackle(func(): return who.center() if is_instance_valid(who) and who.has_method("center") else null,
			h * 0.55, 0.55, CORE, OUTLINE)
	# The discharge bursts out of the whole body...
	for i in 7:
		var a := TAU * i / 7.0 + randf_range(-0.3, 0.3)
		var dir := Vector3(cos(a), randf_range(-0.2, 0.9), sin(a)).normalized()
		vfx.bolt(c + dir * l.data.height * 0.4, c + dir * l.data.height * randf_range(1.3, 2.0), CORE, 0.2, 0.12, 1, OUTLINE)
	# ...and one thick bolt leaps to the rival, with a thin strand twisting round it.
	vfx.bolt(from_pos, to, CORE, 0.38, 0.36, 2, OUTLINE)
	var off := Vector3(randf_range(-0.6, 0.6), randf_range(0.2, 0.6), randf_range(-0.6, 0.6))
	vfx.bolt(from_pos, to + off, Roster.TYPE_COLOR.electric, 0.2, 0.1, 0, OUTLINE)
	# Where it lands: a star of bolts along the ground, the flash and a scorch mark.
	var floor_at := _at + Vector3.UP * 0.06
	for i in 6:
		var a := TAU * i / 6.0 + randf_range(-0.4, 0.4)
		vfx.bolt(floor_at, floor_at + Vector3(cos(a), 0.0, sin(a)) * randf_range(1.0, 1.9), CORE, 0.24, 0.14, 1, OUTLINE)
	vfx.light(to, CORE, 7.0, 8.0, 0.3)
	vfx.cobble("thunderbolt_targetimpact", to, from_pos, 1.0)
	vfx.burst("sparks", to, Vector3.UP, CORE, 1.4)
	vfx.mark(_at, "burned", 1.1, 3.5)
	if is_instance_valid(_glow):
		_glow.light_energy = 7.0
	if is_instance_valid(_ring):
		_ring.queue_free()
	l.main.shake_camera(0.14, to)
	play_sound("thunderbolt", 0.0)


func in_recovery(delta: float) -> void:
	var k := clampf(t / maxf(float(d.recovery), 0.01), 0.0, 1.0)
	tint_k = 0.6 * (1.0 - k) * (1.0 - k)
	if is_instance_valid(_glow):
		_glow.light_energy = 7.0 * (1.0 - k) * (1.0 - k)
	# Leftover sparks on the body for the first moments.
	if k < 0.45:
		_crackle -= delta
		if _crackle <= 0.0:
			_crackle = 0.08
			var c := l.center()
			var n := Vector3(randf_range(-1, 1), randf_range(-0.6, 1), randf_range(-1, 1)).normalized()
			l.main.vfx.bolt(c + n * l.data.height * 0.55, c + n.rotated(Vector3.UP, 0.9) * l.data.height * 0.6, CORE, 0.07, 0.06, 0, OUTLINE)


func on_end(_interrupted: bool) -> void:
	if is_instance_valid(_ring):
		_ring.queue_free()
	if is_instance_valid(_glow):
		_glow.queue_free()


func pose() -> Dictionary:
	match phase:
		"startup":
			return {"tilt": -0.12, "stretch": 0.92 + 0.03 * sin(total * 40.0), "anim": "special", "reset": t < 0.02}
		"active":
			return {"tilt": 0.18, "stretch": 1.1}
	return {"tilt": 0.18 * (1.0 - t / maxf(float(d.recovery), 0.01))}
