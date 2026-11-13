class_name PokeExtras
extends SkeletonModifier3D
## Layers on top of the animation: blinking, the head following the reticle, the
## puffing cheeks and the reactions (hit taken, cry). Reactions are ADDED to the pose,
## like in Cobblemon: every frame adds how far the animation moves away from the rest
## pose. A bone the reaction leaves at 0 stays as the idle has it (replacing instead
## would send it to the T-pose).

var extra_rot := {}     # bone -> Vector3 (degrees; X is used)
var extra_scale := {}   # bone -> Vector3
var blink := {}         # bone -> {"pos"/"scl": PackedFloat32Array}, "_len"
var fps := 30.0

var speed := 1.0
var _reaction: Animation
var _reac_t := 0.0
var _react_tracks: Array = []   # [bone, type, track]

var _blink_t := -1.0
var _next_blink := 2.0


func _ready() -> void:
	_next_blink = randf_range(1.0, 4.0)


func react(an: Animation) -> void:
	var sk := get_skeleton()
	_reaction = an
	_reac_t = 0.0
	_react_tracks.clear()
	for k in an.get_track_count():
		var i := sk.find_bone(str(an.track_get_path(k)).get_slice(":", 1))
		if i >= 0:
			_react_tracks.append([i, an.track_get_type(k), k])


func reacting() -> bool:
	return _reaction != null


func _process_modification_with_delta(delta: float) -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	if _reaction:
		_reac_t += delta * speed
		var length := minf(_reaction.length, 0.9)
		if _reac_t >= length:
			_reaction = null
		else:
			# Fades in and out quickly so it does not jerk.
			var w := clampf(_reac_t / 0.06, 0.0, 1.0) * clampf((length - _reac_t) / 0.12, 0.0, 1.0)
			for p in _react_tracks:
				var i: int = p[0]
				var rest := sk.get_bone_rest(i)
				match p[1]:
					Animation.TYPE_ROTATION_3D:
						var q := _reaction.rotation_track_interpolate(p[2], _reac_t)
						var dq := rest.basis.get_rotation_quaternion().inverse() * q
						sk.set_bone_pose_rotation(i, sk.get_bone_pose_rotation(i) * Quaternion.IDENTITY.slerp(dq, w))
					Animation.TYPE_POSITION_3D:
						var v := _reaction.position_track_interpolate(p[2], _reac_t)
						sk.set_bone_pose_position(i, sk.get_bone_pose_position(i) + (v - rest.origin) * w)
					Animation.TYPE_SCALE_3D:
						var s := _reaction.scale_track_interpolate(p[2], _reac_t)
						sk.set_bone_pose_scale(i, sk.get_bone_pose_scale(i) * Vector3.ONE.lerp(s, w))
	if not blink.is_empty():
		_next_blink -= delta
		if _next_blink <= 0.0:
			_blink_t = 0.0
			_next_blink = randf_range(2.0, 5.0)
		if _blink_t >= 0.0:
			_blink_t += delta
			if _blink_t > blink._len:
				_blink_t = -1.0
			else:
				for bone in blink:
					if bone == "_len":
						continue
					var i := sk.find_bone(bone)
					if i < 0:
						continue
					var c: Dictionary = blink[bone]
					if c.has("pos"):
						sk.set_bone_pose_position(i, sk.get_bone_pose_position(i) + _sample(c.pos) / 16.0)
					if c.has("scl"):
						sk.set_bone_pose_scale(i, sk.get_bone_pose_scale(i) * _sample(c.scl))
	for bone in extra_rot:
		var i := sk.find_bone(bone)
		var r: Vector3 = extra_rot[bone]
		if i >= 0 and r != Vector3.ZERO:
			sk.set_bone_pose_rotation(i, sk.get_bone_pose_rotation(i) * Quaternion(Vector3.RIGHT, deg_to_rad(r.x)))
	for bone in extra_scale:
		var i := sk.find_bone(bone)
		var s: Vector3 = extra_scale[bone]
		if i >= 0 and s != Vector3.ONE:
			sk.set_bone_pose_scale(i, sk.get_bone_pose_scale(i) * s)


func _sample(arr: PackedFloat32Array) -> Vector3:
	var n := arr.size() / 3
	if n == 1:
		return Vector3(arr[0], arr[1], arr[2])
	var f := _blink_t * fps
	var i := mini(int(f), n - 2)
	var fr := clampf(f - i, 0.0, 1.0)
	var j := i * 3
	return Vector3(arr[j], arr[j + 1], arr[j + 2]).lerp(Vector3(arr[j + 3], arr[j + 4], arr[j + 5]), fr)
