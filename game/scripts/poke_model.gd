class_name PokeModel
extends Node3D
## Cobblemon model built from game/pokemon/<species>/model.json.gz.
## A single mesh with a skeleton (Skeleton3D) and native Godot animations, in two
## layers like in Cobblemon. The base one (looping: idle, walk, run, fly) moves the
## whole body; the one on top (attacks, hit taken, cry, faint) only writes the bones it
## animates, and the rest keeps the base. If the top ones also moved the rest, it would
## go to the rest pose, which in these models is the T-pose.
##
## Interpolation and blending are done by the engine, not GDScript, and each Pokémon
## costs one draw call. Mesh, skeleton and animations are built once per species and
## shared.

const PX := 1.0 / 16.0
## Reactions: they add to the pose instead of replacing it (see PokeExtras).
const REACTIONS := ["recoil", "air_recoil", "hurt", "cry", "battle_cry"]
const SHADER := preload("res://shaders/pokemon.gdshader")

static var _cache := {}

var species_id := ""
var skel: Skeleton3D
var mesh_instance: MeshInstance3D
var anim_player: AnimationPlayer      # base layer
var layer: AnimationPlayer             # top layer
var extras: PokeExtras
var mat: ShaderMaterial

var anim := ""
var speed := 1.0:
	set(v):
		speed = v
		if anim_player:
			anim_player.speed_scale = v
		# Negative (walking backward) only on the base; the top layer always forward.
		if layer:
			layer.speed_scale = absf(v)
		if extras:
			extras.speed = absf(v)

## Extra rotations (degrees, X axis) and extra scales per bone, on top of the animation.
var extra_rot: Dictionary:
	get:
		return extras.extra_rot
var extra_scale: Dictionary:
	get:
		return extras.extra_scale

var _res: Dictionary


func setup(species: String, shiny := false) -> void:
	species_id = species
	_res = _load(species)
	skel = Skeleton3D.new()
	skel.name = "Skeleton3D"
	for b in _res.bones:
		var i := skel.add_bone(b.name)
		skel.set_bone_rest(i, b.rest)
	for b in _res.bones:
		if b.parent != "":
			skel.set_bone_parent(skel.find_bone(b.name), skel.find_bone(b.parent))
	skel.reset_bone_poses()
	add_child(skel)

	mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = _res.mesh
	mesh_instance.skin = _res.skin
	mat = _res.mat.duplicate()
	if shiny and not ResourceLoader.exists(_res.dir + "texture_shiny.png"):
		shiny = false
	mat.set_shader_parameter("tex", load(_res.dir + ("texture_shiny.png" if shiny else "texture.png")))
	mesh_instance.material_override = mat
	skel.add_child(mesh_instance)
	mesh_instance.skeleton = NodePath("..")

	extras = PokeExtras.new()
	extras.blink = _res.blink
	extras.fps = _res.fps
	skel.add_child(extras)

	anim_player = AnimationPlayer.new()
	add_child(anim_player)
	anim_player.root_node = NodePath("..")
	anim_player.add_animation_library("", _res.library)
	anim_player.speed_scale = speed
	# The top layer is processed after the base (it comes later in the tree).
	layer = AnimationPlayer.new()
	add_child(layer)
	layer.root_node = NodePath("..")
	layer.add_animation_library("", _res.layer_library)
	layer.speed_scale = speed


static func _load(species: String) -> Dictionary:
	if _cache.has(species):
		return _cache[species]
	var dir := "res://pokemon/%s/" % species
	var raw := FileAccess.get_file_as_bytes(dir + "model.json.gz").decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
	var data: Dictionary = JSON.parse_string(raw.get_string_from_utf8())
	var fps := float(data.fps)

	# Bones in parent -> child order, with their rest.
	var by_name := {}
	for b in data.bones:
		by_name[b.name] = b
	var order: Array = []
	var seen := {}
	for b in data.bones:
		_sort(b, by_name, order, seen)
	var bones := []
	var index := {}
	var global_rest := {}
	var rest_pos := {}
	var rest_rot := {}
	for b in order:
		var pos := Vector3(b.pos[0], b.pos[1], b.pos[2])
		var rot := Vector3(b.rot[0], b.rot[1], b.rot[2])
		var rest := Transform3D(euler_zyx(rot), pos * PX)
		index[b.name] = bones.size()
		rest_pos[b.name] = pos
		rest_rot[b.name] = rot
		bones.append({"name": b.name, "parent": b.parent, "rest": rest})
		var g := rest
		if b.parent != "":
			g = global_rest[b.parent] * rest
		global_rest[b.name] = g

	# A single mesh: every vertex bound 100% to its bone.
	var pv := PackedVector3Array()
	var pn := PackedVector3Array()
	var pu := PackedVector2Array()
	var pb := PackedInt32Array()
	var pw := PackedFloat32Array()
	for b in order:
		var v: Array = b.verts
		if v.is_empty():
			continue
		var g: Transform3D = global_rest[b.name]
		var nv: Array = b.normals
		var uv: Array = b.uvs
		var bi: int = index[b.name]
		for i in range(0, v.size(), 3):
			pv.append(g * (Vector3(v[i], v[i + 1], v[i + 2]) * PX))
			pn.append((g.basis * Vector3(nv[i], nv[i + 1], nv[i + 2])).normalized())
			pb.append_array([bi, 0, 0, 0])
			pw.append_array([1.0, 0.0, 0.0, 0.0])
		for i in range(0, uv.size(), 2):
			pu.append(Vector2(uv[i], uv[i + 1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pv
	arrays[Mesh.ARRAY_NORMAL] = pn
	arrays[Mesh.ARRAY_TEX_UV] = pu
	arrays[Mesh.ARRAY_BONES] = pb
	arrays[Mesh.ARRAY_WEIGHTS] = pw
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var skin := Skin.new()
	for b in bones:
		skin.add_named_bind(b.name, (global_rest[b.name] as Transform3D).affine_inverse())

	# Animations: position, rotation and scale tracks per bone.
	var lib := AnimationLibrary.new()
	var layer_lib := AnimationLibrary.new()
	var animated := {}
	for anim_name in data.anims:
		var a: Dictionary = data.anims[anim_name]
		var an := Animation.new()
		an.length = maxf(float(a.len), 1.0 / fps)
		an.loop_mode = Animation.LOOP_LINEAR if a.loop else Animation.LOOP_NONE
		for bone in a.bones:
			if not index.has(bone):
				continue
			animated[bone] = true
			var channels: Dictionary = a.bones[bone]
			var file_path := NodePath("Skeleton3D:" + bone)
			if channels.has("pos"):
				var t := an.add_track(Animation.TYPE_POSITION_3D)
				an.track_set_path(t, file_path)
				var arr: Array = channels.pos
				for i in arr.size() / 3:
					var p := Vector3(arr[i * 3], arr[i * 3 + 1], arr[i * 3 + 2])
					an.position_track_insert_key(t, i / fps, (rest_pos[bone] + p) * PX)
			if channels.has("rot"):
				var t := an.add_track(Animation.TYPE_ROTATION_3D)
				an.track_set_path(t, file_path)
				var arr: Array = channels.rot
				for i in arr.size() / 3:
					var r := Vector3(arr[i * 3], arr[i * 3 + 1], arr[i * 3 + 2])
					an.rotation_track_insert_key(t, i / fps, euler_zyx(rest_rot[bone] + r).get_rotation_quaternion())
			if channels.has("scl"):
				var t := an.add_track(Animation.TYPE_SCALE_3D)
				an.track_set_path(t, file_path)
				var arr: Array = channels.scl
				for i in arr.size() / 3:
					an.scale_track_insert_key(t, i / fps, Vector3(arr[i * 3], arr[i * 3 + 1], arr[i * 3 + 2]))
		lib.add_animation(anim_name, an)
		# Faint stays on its last pose: it goes on the base, which holds it.
		if not a.loop and not anim_name in ["blink", "faint", "sleep_intro"]:
			layer_lib.add_animation(anim_name, an.duplicate(true))
	# On the base layer, each animation also carries the bones it does not move, in the
	# idle pose (the way Cobblemon composes: Snorlax's walk moves the legs and the idle
	# sets the arms). That way the base always writes the whole body and nothing stays
	# frozen in an earlier pose. What not even the idle moves, at rest. Never the bare
	# rest pose: in these models it is the T-pose.
	var channels := {}
	for anim_name in data.anims:
		var bs: Dictionary = data.anims[anim_name].bones
		for bone in bs:
			if index.has(bone):
				if not channels.has(bone):
					channels[bone] = {}
				for c in bs[bone]:
					channels[bone][c] = true
	# Idle pose: the first frame of ground_idle, completed with battle_idle.
	# The normal one first: the battle one may be in a guard stance (Lucario turns its
	# body 32°) and walking or running would inherit that turn.
	var waits := {}
	for ref in ["ground_idle", "battle_idle"]:
		if not lib.has_animation(ref):
			continue
		var ra: Animation = lib.get_animation(ref)
		for k in ra.get_track_count():
			var key := "%s|%d" % [ra.track_get_path(k), ra.track_get_type(k)]
			if waits.has(key):
				continue
			match ra.track_get_type(k):
				Animation.TYPE_POSITION_3D:
					waits[key] = ra.position_track_interpolate(k, 0.0)
				Animation.TYPE_ROTATION_3D:
					waits[key] = ra.rotation_track_interpolate(k, 0.0)
				Animation.TYPE_SCALE_3D:
					waits[key] = ra.scale_track_interpolate(k, 0.0)
	for anim_name in data.anims:
		if anim_name == "blink" or layer_lib.has_animation(anim_name):
			continue
		var an: Animation = lib.get_animation(anim_name)
		var own: Dictionary = data.anims[anim_name].bones
		for bone in channels:
			var file_path := NodePath("Skeleton3D:" + bone)
			var has: Dictionary = own.get(bone, {})
			if channels[bone].has("pos") and not has.has("pos"):
				var t := an.add_track(Animation.TYPE_POSITION_3D)
				an.track_set_path(t, file_path)
				an.position_track_insert_key(t, 0.0, waits.get("%s|%d" % [file_path, Animation.TYPE_POSITION_3D], rest_pos[bone] * PX))
			if channels[bone].has("rot") and not has.has("rot"):
				var t := an.add_track(Animation.TYPE_ROTATION_3D)
				an.track_set_path(t, file_path)
				an.rotation_track_insert_key(t, 0.0, waits.get("%s|%d" % [file_path, Animation.TYPE_ROTATION_3D], euler_zyx(rest_rot[bone]).get_rotation_quaternion()))
			if channels[bone].has("scl") and not has.has("scl"):
				var t := an.add_track(Animation.TYPE_SCALE_3D)
				an.track_set_path(t, file_path)
				an.scale_track_insert_key(t, 0.0, waits.get("%s|%d" % [file_path, Animation.TYPE_SCALE_3D], Vector3.ONE))
	# RESET: the rest of every animated bone, so blending goes back to it.
	var reset := Animation.new()
	reset.length = 0.001
	for bone in animated:
		var file_path := NodePath("Skeleton3D:" + bone)
		var t := reset.add_track(Animation.TYPE_POSITION_3D)
		reset.track_set_path(t, file_path)
		reset.position_track_insert_key(t, 0.0, rest_pos[bone] * PX)
		t = reset.add_track(Animation.TYPE_ROTATION_3D)
		reset.track_set_path(t, file_path)
		reset.rotation_track_insert_key(t, 0.0, euler_zyx(rest_rot[bone]).get_rotation_quaternion())
		t = reset.add_track(Animation.TYPE_SCALE_3D)
		reset.track_set_path(t, file_path)
		reset.scale_track_insert_key(t, 0.0, Vector3.ONE)
	lib.add_animation("RESET", reset)

	# Blinking goes separately, as an additive layer (applied by PokeExtras).
	var blink := {}
	if data.anims.has("blink"):
		var bl: Dictionary = data.anims.blink
		for bone in bl.bones:
			var c := {}
			for channel in bl.bones[bone]:
				c[channel] = PackedFloat32Array(bl.bones[bone][channel])
			blink[bone] = c
		blink["_len"] = float(bl.len)

	var m := ShaderMaterial.new()
	m.shader = SHADER
	if ResourceLoader.exists(dir + "texture_emissive.png"):
		m.set_shader_parameter("emis", load(dir + "texture_emissive.png"))
		m.set_shader_parameter("has_emis", true)
	if ResourceLoader.exists(dir + "texture_flame.png"):
		m.set_shader_parameter("flame_tex", load(dir + "texture_flame.png"))
		m.set_shader_parameter("has_flame", true)
	var res := {"dir": dir, "bones": bones, "mesh": mesh, "skin": skin, "library": lib,
		"blink": blink, "fps": fps, "mat": m, "anims": data.anims.keys(), "layer_library": layer_lib}
	_cache[species] = res
	return res


static func _sort(b: Dictionary, by_name: Dictionary, order: Array, seen: Dictionary) -> void:
	if seen.has(b.name):
		return
	if b.parent != "" and by_name.has(b.parent):
		_sort(by_name[b.parent], by_name, order, seen)
	elif b.parent != "":
		b.parent = ""
	seen[b.name] = true
	order.append(b)


static func euler_zyx(d: Vector3) -> Basis:
	var r := d * (PI / 180.0)
	return Basis(Vector3.BACK, r.z) * Basis(Vector3.UP, r.y) * Basis(Vector3.RIGHT, r.x)


func has_anim(anim_name: String) -> bool:
	return anim_player.has_animation(anim_name)


func play(anim_name: String, fade := 0.15, reset := false) -> void:
	if not anim_player.has_animation(anim_name):
		return
	if anim_name in REACTIONS and layer.has_animation(anim_name):
		anim = anim_name
		extras.react(layer.get_animation(anim_name))
		return
	if layer.has_animation(anim_name):
		# On top of the base, which keeps what it had.
		if anim_name == anim and layer.is_playing() and not reset:
			return
		anim = anim_name
		if reset:
			layer.stop(true)
		layer.play(anim_name, fade)
		return
	if layer.is_playing():
		layer.stop(true)
	if anim_name == anim and not reset:
		return
	anim = anim_name
	if anim_name == anim_player.current_animation and not reset:
		return
	anim_player.play(anim_name, fade)


## Starts the current animation at a random point (so they are not all in sync).
func randomize_phase() -> void:
	if anim_player.current_animation != "":
		anim_player.seek(randf() * anim_player.current_animation_length, true)


func finished() -> bool:
	if anim in REACTIONS:
		return not extras.reacting()
	if layer.has_animation(anim):
		return not layer.is_playing()
	return not anim_player.is_playing()


func set_param(anim_name: String, value) -> void:
	mat.set_shader_parameter(anim_name, value)


func bone_world(anim_name: String) -> Vector3:
	var i := skel.find_bone(anim_name)
	if i < 0:
		return global_position
	return skel.global_transform * skel.get_bone_global_pose(i).origin
