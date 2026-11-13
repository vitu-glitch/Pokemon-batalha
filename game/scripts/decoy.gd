class_name Decoy
extends Node3D
## A copy of the Pokémon that combat treats as one more target: Substitute's doll (still,
## in its idle animation) or a Double Team clone ("wander": it runs around the rival with a
## minimal AI, changing direction now and then). The first hit breaks it (a puff of smoke)
## and the attacker feels it as a normal hit. It can be told apart from the real one: it
## has no shadow.

var main: Node
var user: Fighter
var data: Dictionary
var types: Array = []
var _model: PokeModel
var _time_left := 4.0
var kind := "substitute"          # or "clone" (Double Team)
var wander := false
var _goal := Vector3.ZERO
var _goal_t := 0.0
var _vel := Vector3.ZERO


func setup(m: Node, l: Fighter, dur: float) -> void:
	main = m
	user = l
	data = l.data
	types = l.types
	_time_left = dur
	_model = PokeModel.new()
	_model.setup(l.species)
	_model.scale = l.model.scale
	_model.rotation.y = PI
	add_child(_model)
	_model.mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	global_position = l.global_position
	rotation.y = l.face_yaw
	if data.get("levitates", false):
		_model.position.y = 0.38
	_model.play("air_idle" if data.get("levitates", false) and _model.has_anim("air_idle") else "battle_idle", 0.0)


func _process(delta: float) -> void:
	_time_left -= delta
	if _time_left <= 0.0:
		undo()
		return
	if wander:
		_wander(delta)


## Double Team clone: runs to a point around the rival, picks another every 0.5-1.1 s.
func _wander(delta: float) -> void:
	_goal_t -= delta
	var r: Fighter = user.rival if user and is_instance_valid(user) else null
	if _goal_t <= 0.0 or global_position.distance_to(_goal) < 0.8:
		_goal_t = randf_range(0.5, 1.1)
		var around: Vector3 = r.global_position if r and is_instance_valid(r) else global_position
		var a := randf() * TAU
		_goal = around + Vector3(cos(a), 0.0, sin(a)) * randf_range(4.0, 8.0)
		if not main.arena.inside(_goal, 2.0):
			_goal = around * 0.5
		_goal.y = global_position.y
	var to := _goal - global_position
	to.y = 0.0
	var speed: float = float(data.speed) * 0.95
	_vel = _vel.move_toward(to.normalized() * speed if to.length() > 0.3 else Vector3.ZERO, 40.0 * delta)
	global_position += _vel * delta
	if _vel.length() > 0.5:
		rotation.y = lerp_angle(rotation.y, atan2(_vel.x, _vel.z), 1.0 - exp(-12.0 * delta))
		if _model.has_anim("ground_run") and _model.anim != "ground_run":
			_model.play("ground_run", 0.1)
	elif _model.anim == "ground_run":
		_model.play("battle_idle", 0.15)


# ---------------------------------------------------------------- what combat asks

func hittable() -> bool:
	return true


func body() -> Array:
	var r := radius()
	return [global_position + Vector3.UP * r, global_position + Vector3.UP * maxf(r, data.height - r)]


func radius() -> float:
	return data.radius


func center() -> Vector3:
	return global_position + Vector3.UP * data.height * 0.5


func on_floor() -> bool:
	return not data.get("levitates", false)


func receive(_info: Dictionary) -> String:
	undo()
	return "hit"


func undo() -> void:
	if is_queued_for_deletion():
		return
	main.vfx.burst("shadow", center(), Vector3.UP, Color(0, 0, 0, 0), 1.6)
	main.vfx.burst("smoke", center(), Vector3.UP, Color(0, 0, 0, 0), 1.2)
	main.audio.play_sound("dodge", global_position, -4.0, 0.7)
	main.combat.targets.erase(self)
	queue_free()
