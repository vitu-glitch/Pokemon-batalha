class_name EnergyStream
extends Action
## Held energy beams (Hyper Beam, Dragon Pulse, Solar Beam), aimed like Flamethrower and
## Hydro Pump: while the button is held (up to "max") the beam pours out of origin(), hitting
## every "interval" seconds whoever is in it ("split" shares the move's damage among the
## ticks), turning slowly toward where it is aimed ("emit_turn"; with the stick,
## "manual_turn") and draining energy ("drain" per second); out of energy, it stops. Its front
## runs out at "beam_speed" and stops at walls (or where a stronger stream cuts it). The
## user is pushed back a little while firing. Each move draws its own beam through
## _beam_on, _beam_at and _beam_off.

var _g: Hit
var _len := 0.5
var _sound_t := 0.0


## Where the beam comes out (the mouth, unless the move says otherwise).
func origin() -> Vector3:
	return mouth() + l.forward() * 0.4


func _dir() -> Vector3:
	return aim_stream(origin())


## How far the beam reaches: the nearest wall along its line, or where a stronger stream
## cuts it (Combat).
func _reach(from_pos: Vector3, dir: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(from_pos, from_pos + dir * d.length, 1)
	var r: Dictionary = l.main.get_world_3d().direct_space_state.intersect_ray(q)
	var reach: float = from_pos.distance_to(r.position) if not r.is_empty() else float(d.length)
	if _g and _g.cut > 0.0:
		reach = minf(reach, _g.cut)
	return reach


func on_active() -> void:
	tint_k = 0.0
	turn_mult = d.emit_turn
	var o := origin()
	var dir := _dir()
	_len = 0.5
	_g = hit({"shape": "capsule", "local": false, "a": o, "b": o + dir * _len, "radius": d.radius, "interval": d.interval})
	_beam_on(o, dir)
	l.velocity -= dir * 2.0
	l.main.shake_camera(0.25, o)


func in_active(delta: float) -> void:
	l.energy -= d.drain * delta
	if l.energy <= 0.0:
		l.energy = 0.0
		_go_to("recovery")
		return
	var o := origin()
	var dir := _dir()
	var full := _reach(o, dir)
	_len = minf(full, _len + float(d.beam_speed) * delta)
	if _g:
		_g.a = o
		_g.b = o + dir * _len
	_beam_at(o, dir, _len, full)
	# Recoil: pushed back a little while it pours out.
	l.velocity.x = -dir.x * 0.6
	l.velocity.z = -dir.z * 0.6
	_sound_t -= delta
	if _sound_t <= 0.0:
		_sound_t = 0.45
		l.main.shake_camera(0.07, o)


func on_recovery() -> void:
	tint_k = 0.0
	_beam_off(0.2)


func on_end(_interrupted: bool) -> void:
	_beam_off(0.1)


func _beam_on(_o: Vector3, _dir_: Vector3) -> void:
	pass


func _beam_at(_o: Vector3, _dir_: Vector3, _length: float, _full: float) -> void:
	pass


func _beam_off(_dur: float) -> void:
	pass
