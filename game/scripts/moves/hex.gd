extends Action
## Hex: Gengar points at the rival and a cursed mark appears on the ground under it. The
## mark creeps after the rival ("follow" m/s) while Gengar winds up and stops for the last
## "lock" seconds, then bursts: dodge as it locks, or be quick to leave it. If the rival
## has a status condition (poisoned, burned, chilled, charged), it deals double: it combos
## with Sludge Bomb.

var _point := Vector3.ZERO
var _mark: MeshInstance3D


func on_start() -> void:
	turn_mult = 3.0
	var target := l.global_position + l.forward() * minf(6.0, d.reach)
	if l.rival and is_instance_valid(l.rival) and l.rival.state != "ko":
		target = l.rival.global_position
	var flat := Vector3(target.x - l.global_position.x, 0, target.z - l.global_position.z)
	if flat.length() > d.reach:
		target = l.global_position + flat.normalized() * d.reach
	_point = Vector3(target.x, l.main.ground_y, target.z)
	_mark = l.main.vfx.telegraph(_point, d.radius, startup_len() + 0.05, Roster.TYPE_COLOR.ghost)
	play_sound("charge", -12.0)


func in_startup(delta: float) -> void:
	tint_col = Roster.TYPE_COLOR.ghost
	tint_k = 0.3 * (t / d.startup)
	# The mark creeps after the rival until it locks.
	if t < startup_len() - float(d.lock) and l.rival and is_instance_valid(l.rival) and l.rival.state != "ko":
		var to := Vector3(l.rival.global_position.x, _point.y, l.rival.global_position.z)
		var flat := Vector3(to.x - l.global_position.x, 0, to.z - l.global_position.z)
		if flat.length() > d.reach:
			to = l.global_position + flat.normalized() * d.reach
			to.y = _point.y
		_point = _point.move_toward(to, float(d.follow) * delta)
		if is_instance_valid(_mark):
			_mark.global_position = _point
	if int(total * 30.0) % 3 == 0:
		var off: Vector3 = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).limit_length(1.0) * d.radius
		l.main.vfx.burst("shadow", _point + off, Vector3.UP, Color(0, 0, 0, 0), 0.3)


func on_active() -> void:
	var double: bool = l.rival and is_instance_valid(l.rival) and l.rival.has_status()
	hit({"shape": "sphere", "local": false, "center": _point + Vector3.UP * 0.8, "radius": d.radius,
		"damage": d.damage * (2.0 if double else 1.0), "strength": 2 if double else d.strength, "lifetime": 0.08})
	var vfx: Vfx = l.main.vfx
	var col := Roster.TYPE_COLOR.ghost
	vfx.wave(_point, d.radius * 1.2, 0.3, col, 0.1)
	vfx.burst("shadow", _point + Vector3.UP * 0.5, Vector3.UP, Color(0, 0, 0, 0), 2.0)
	vfx.cobble("nightshade_targetres", _point, l.center(), 1.0)
	if double:
		vfx.text(_point + Vector3.UP * 2.2, l.tr("Double!"), Color(0.8, 0.6, 1.0))
	play_sound("hex", 0.0)


func pose() -> Dictionary:
	match phase:
		"startup":
			return {"tilt": -0.1, "side": 0.2, "stretch": 0.96}
		"active":
			return {"tilt": 0.18, "stretch": 1.06}
	return {}
