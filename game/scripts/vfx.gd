class_name Vfx
extends Node3D
## Battle visual effects. Kept apart from the logic: nothing here deals damage.
## Each effect stacks layers instead of a single recolored particle:
##   impact     flash with rays + short light + particles of the
##              type's material + Cobblemon's pixel impact for the type
##   burst      GPU particles per material (sparks with trails, Cobblemon's animated
##              fire, smoke, dust, drops, frost, debris, leaves, shadow...)
##   bolt       jagged lightning rebuilt every few frames
##   beam       a continuous stream or beam with moving noise
##   ribbon     trail of claws and tails
##   wave       ring that spreads across the ground
##   mark       a burn, crack or frost on the ground that fades out
##   afterimage silhouette of the Pokémon in its current pose (dodges)
## Emitters, lights and texts are reused (not created on every hit).

const TEX := "res://fx/tex/generic/"
const BY_TYPE := {
	"electric": ["sparks", "stars"], "fire": ["fire_fx", "embers"], "water": ["water_fx", "steam"],
	"ice": ["ice_fx", "steam"], "grass": ["leaves"], "ground": ["debris", "dust"], "rock": ["debris", "dust"],
	"steel": ["sparks_metal", "stars"], "ghost": ["shadow"], "poison": ["shadow"], "dark": ["shadow"],
	"dragon": ["sparks_dragon", "shadow"], "psychic": ["stars"], "fairy": ["stars"],
	"flying": ["wind"], "normal": ["dust", "stars"], "fighting": ["dust", "stars"], "bug": ["leaves"],
}

var main: Node
var _pools := {}
var _lights: Array = []
## Floating texts and damage numbers. The HUD draws them in the pixel font with
## Cobblemon's one-pixel shadow (Hud._floating): {pos, s, col, t, dur, v, big}.
var texts: Array = []
var _noise: NoiseTexture2D
var _shaders := {}
var _living: Array = []        # effects with their own life: {node, t, dur, step: Callable}
var reduced := false         # accessibility option: less shaking


func _ready() -> void:
	_noise = NoiseTexture2D.new()
	_noise.width = 128
	_noise.height = 128
	_noise.seamless = true
	var fn := FastNoiseLite.new()
	fn.frequency = 0.04
	fn.fractal_octaves = 3
	_noise.noise = fn
	for i in 8:
		var o := OmniLight3D.new()
		o.visible = false
		o.shadow_enabled = false
		o.omni_range = 4.0
		add_child(o)
		_lights.append({"light": o, "t": 0.0, "dur": 0.0, "e": 0.0})


func shader(key: String, source: String) -> Shader:
	if not _shaders.has(key):
		var s := Shader.new()
		s.code = source
		_shaders[key] = s
	return _shaders[key]


func mat(key: String, source: String, params := {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader(key, source)
	for k in params:
		m.set_shader_parameter(k, params[k])
	if source == VfxShaders.BEAM:
		m.set_shader_parameter("noise", _noise)
	return m


# ---------------------------------------------------------------- particles

## Data for each particle material.
func _preset(key: String) -> Dictionary:
	match key:
		"sparks":
			return {"n": 26, "lifetime": 0.42, "streak": Vector2(0.05, 0.42), "v": [6.0, 15.0], "spread": 80.0, "g": -8.0, "damp": 3.0, "e": 4.0, "color": Color(1.0, 0.92, 0.45)}
		"sparks_metal":
			return {"n": 22, "lifetime": 0.38, "streak": Vector2(0.04, 0.35), "v": [7.0, 16.0], "spread": 75.0, "g": -14.0, "damp": 2.0, "e": 3.5, "color": Color(1.0, 0.95, 0.85)}
		"sparks_dragon":
			return {"n": 22, "lifetime": 0.5, "streak": Vector2(0.06, 0.4), "v": [5.0, 12.0], "spread": 80.0, "g": -3.0, "damp": 3.0, "e": 3.5, "color": Color(0.65, 0.45, 1.0)}
		"embers":
			return {"n": 18, "lifetime": 0.9, "streak": Vector2(0.04, 0.16), "v": [2.0, 6.0], "spread": 60.0, "g": 3.0, "damp": 1.5, "e": 1.8, "color": Color(1.0, 0.5, 0.12)}
		"water_fx":
			# Water drops: they do not glow (normal blend), like the water stream.
			return {"n": 26, "lifetime": 0.55, "streak": Vector2(0.07, 0.3), "add": false, "v": [4.0, 10.0], "spread": 70.0, "g": -18.0, "damp": 0.5, "e": 1.0, "color": Color(0.35, 0.65, 0.95)}
		"wind":
			return {"n": 16, "lifetime": 0.35, "streak": Vector2(0.05, 0.9), "v": [8.0, 14.0], "spread": 60.0, "g": 0.0, "damp": 6.0, "e": 1.4, "color": Color(0.9, 0.95, 1.0, 0.7)}
		"fire_fx":
			return {"n": 16, "lifetime": 0.6, "tex": "fire/cloudyfire_white.png", "frames": Vector2i(10, 1), "add": false, "v": [1.0, 3.5],
				"spread": 50.0, "g": 3.0, "damp": 2.0, "e": 1.5, "dims": [0.5, 1.0],
				"ramp": [Color(1.0, 0.86, 0.35), Color(1.0, 0.5, 0.1), Color(0.75, 0.16, 0.04, 0.9), Color(0.25, 0.08, 0.05, 0.0)]}
		"smoke":
			return {"n": 10, "lifetime": 1.2, "tex": "smoke/smoke.png", "frames": Vector2i(1, 6), "add": false, "v": [0.5, 1.6],
				"spread": 60.0, "g": 1.0, "damp": 1.5, "e": 1.0, "dims": [0.8, 1.6],
				"ramp": [Color(0.35, 0.33, 0.32, 0.8), Color(0.25, 0.24, 0.24, 0.0)]}
		"dust":
			return {"n": 12, "lifetime": 0.7, "tex": "smoke/smoke.png", "frames": Vector2i(1, 6), "add": false, "v": [1.5, 4.0],
				"spread": 85.0, "g": 0.5, "damp": 4.0, "e": 1.0, "dims": [0.4, 0.9],
				"ramp": [Color(0.86, 0.8, 0.7, 0.75), Color(0.8, 0.75, 0.66, 0.0)]}
		"steam":
			return {"n": 10, "lifetime": 0.8, "tex": "smoke/smoke.png", "frames": Vector2i(1, 6), "add": false, "v": [1.0, 3.0],
				"spread": 80.0, "g": 1.0, "damp": 3.0, "e": 1.0, "dims": [0.5, 1.1],
				"ramp": [Color(0.8, 0.95, 1.0, 0.6), Color(0.6, 0.85, 1.0, 0.0)]}
		"ice_fx":
			return {"n": 14, "lifetime": 0.7, "tex": "ice/iceshard.png", "frames": Vector2i(3, 1), "add": true, "v": [4.0, 9.0],
				"spread": 75.0, "g": -12.0, "damp": 1.0, "e": 2.0, "dims": [0.25, 0.45], "turn": 360.0,
				"ramp": [Color(0.9, 1.0, 1.0), Color(0.6, 0.9, 1.0, 0.0)]}
		"leaves":
			return {"n": 12, "lifetime": 0.9, "tex": "grass/leaf.png", "frames": Vector2i(1, 4), "add": false, "v": [3.0, 7.0],
				"spread": 80.0, "g": -4.0, "damp": 2.5, "e": 1.0, "dims": [0.25, 0.4], "turn": 540.0,
				"ramp": [Color(0.75, 1.0, 0.6), Color(0.5, 0.85, 0.4, 0.0)]}
		"shadow":
			# Dark, matte smoke (ghost, poison, dark): it does not glow.
			return {"n": 12, "lifetime": 0.8, "tex": "smoke/smoke.png", "frames": Vector2i(1, 6), "add": false, "v": [1.0, 3.0],
				"spread": 80.0, "g": 1.5, "damp": 2.0, "e": 1.0, "dims": [0.5, 1.0],
				"ramp": [Color(0.32, 0.14, 0.45, 0.85), Color(0.12, 0.04, 0.2, 0.0)]}
		"stars":
			return {"n": 8, "lifetime": 0.5, "tex": "sparkle/glowingsparkle.png", "frames": Vector2i(1, 4), "add": true, "v": [3.0, 7.0],
				"spread": 80.0, "g": -6.0, "damp": 2.0, "e": 2.5, "dims": [0.18, 0.32],
				"ramp": [Color(1, 1, 1), Color(1, 1, 0.8, 0.0)]}
		"debris":
			return {"n": 14, "lifetime": 0.9, "cubes": true, "v": [4.0, 9.0], "spread": 55.0, "g": -22.0, "damp": 0.3, "dims": [0.08, 0.2], "turn": 720.0,
				"color": Color(0.55, 0.45, 0.35)}
	return {}


func _create_emitter(key: String) -> GPUParticles3D:
	var p: Dictionary = _preset(key)
	var e := GPUParticles3D.new()
	e.amount = p.n
	e.lifetime = p.lifetime
	e.one_shot = true
	e.explosiveness = 0.95
	e.local_coords = false
	e.emitting = false
	e.visibility_aabb = AABB(Vector3(-20, -20, -20), Vector3(40, 40, 40))
	e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 0, -1)
	pm.spread = p.spread
	pm.initial_velocity_min = p.v[0]
	pm.initial_velocity_max = p.v[1]
	pm.gravity = Vector3(0, p.g, 0)
	pm.damping_min = p.damp
	pm.damping_max = p.damp * 1.3
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.15
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.6))
	curve.add_point(Vector2(0.25, 1.0))
	curve.add_point(Vector2(1, 0.15))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	if p.has("ramp"):
		var gr := Gradient.new()
		gr.colors = PackedColorArray(p.ramp)
		var offs := PackedFloat32Array()
		for i in p.ramp.size():
			offs.append(float(i) / (p.ramp.size() - 1))
		gr.offsets = offs
		var gt := GradientTexture1D.new()
		gt.gradient = gr
		pm.color_ramp = gt
	elif p.has("color"):
		pm.color = p.color
	if p.has("turn"):
		pm.angle_min = 0.0
		pm.angle_max = 360.0
		pm.angular_velocity_min = -p.turn
		pm.angular_velocity_max = p.turn
	if p.has("streak"):
		pm.particle_flag_align_y = true
		var q := QuadMesh.new()
		q.size = p.streak
		var add_s: bool = p.get("add", true)
		q.material = mat("streak_add" if add_s else "streak_mix", VfxShaders.STREAK % ["blend_add" if add_s else "blend_mix"], {"energy": p.e})
		e.draw_pass_1 = q
		pm.scale_min = 0.7
		pm.scale_max = 1.3
		var gr2 := Gradient.new()
		gr2.colors = PackedColorArray([p.color, Color(p.color.r, p.color.g, p.color.b, 0.0)])
		var gt2 := GradientTexture1D.new()
		gt2.gradient = gr2
		pm.color_ramp = gt2
	elif p.get("cubes", false):
		var bx := BoxMesh.new()
		bx.size = Vector3.ONE
		var sm := StandardMaterial3D.new()
		sm.albedo_color = p.color
		sm.roughness = 1.0
		sm.vertex_color_use_as_albedo = false
		bx.material = sm
		e.draw_pass_1 = bx
		pm.scale_min = p.dims[0]
		pm.scale_max = p.dims[1]
		e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	else:
		var q := QuadMesh.new()
		q.size = Vector2.ONE
		var add: bool = p.get("add", true)
		var code: String = VfxShaders.PARTICLE % ["blend_add" if add else "blend_mix", "filter_nearest"]
		q.material = mat("particle_" + ("add" if add else "mix"), code,
			{"tex": load(TEX + p.tex), "energy": p.e, "h_frames": p.frames.x, "v_frames": p.frames.y})
		e.draw_pass_1 = q
		pm.scale_min = p.dims[0]
		pm.scale_max = p.dims[1]
		pm.anim_speed_min = 1.0
		pm.anim_speed_max = 1.0
	e.process_material = pm
	add_child(e)
	return e


## A burst of one material at a point, in a direction (or upward).
func burst(key: String, pos: Vector3, dir := Vector3.UP, color := Color(0, 0, 0, 0), size_mult := 1.0) -> void:
	if not _pools.has(key):
		_pools[key] = []
	var free: GPUParticles3D = null
	for e in _pools[key]:
		if not e.emitting:
			free = e
			break
	if free == null:
		if _pools[key].size() >= 8:
			free = _pools[key][0]
			_pools[key].push_back(_pools[key].pop_front())
		else:
			free = _create_emitter(key)
			_pools[key].append(free)
	free.global_position = pos
	var d := dir.normalized() if dir.length() > 0.01 else Vector3.UP
	free.global_basis = Basis.looking_at(d, Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT)
	free.speed_scale = 1.0
	free.scale = Vector3.ONE * size_mult
	if color.a > 0.0:
		(free.process_material as ParticleProcessMaterial).color = color
	free.restart()
	free.emitting = true


func sparks(pos: Vector3, color: Color, n := 1) -> void:
	for i in maxi(1, n / 20):
		burst("sparks", pos, Vector3(randf_range(-1, 1), 1, randf_range(-1, 1)), color)


func dust(pos: Vector3, dims := 1.0) -> void:
	burst("dust", pos + Vector3.UP * 0.1, Vector3.UP, Color(0, 0, 0, 0), clampf(dims, 0.5, 2.5))


# ---------------------------------------------------------------- impacts

## Launches a Cobblemon particle piece (game/fx/particles). `facing` is the point it
## faces, like the target in a Cobblemon battle.
func cobble(id: String, pos: Vector3, facing = null, height := 1.0) -> Dictionary:
	if main.fx == null:
		return {}
	return main.fx.play(id, pos, facing, {"height": height, "width": height * 0.8})


func impact(pos: Vector3, type: String, strength: int, contact := true) -> void:
	var col: Color = Roster.TYPE_COLOR.get(type, Color.WHITE)
	var dims := 1.0 + 0.7 * strength
	_flash(pos, col, dims * (0.75 if contact else 0.65), 0.12 + 0.04 * strength)
	light(pos, col, 1.5 + 2.0 * strength, 3.0 + strength * 2.0, 0.1 + 0.05 * strength)
	for pr in BY_TYPE.get(type, ["dust"]):
		burst(pr, pos, Vector3(randf_range(-0.5, 0.5), 1.0, randf_range(-0.5, 0.5)), Color(0, 0, 0, 0), 0.7 + 0.3 * strength)
	sprite_anim(TEX + "impact/impact_%s.png" % type, pos, 0.55 + 0.2 * strength, Vector2i(1, 7), 0.24, col.lerp(Color.WHITE, 0.3))


func _flash(pos: Vector3, col: Color, dims: float, dur: float) -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	mi.mesh = q
	var m := mat("flash_col", VfxShaders.FLASH, {"color": col, "energy": 2.0, "seed": randf() * 6.0, "bolts": float(randi_range(6, 10))})
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * dims
	live(mi, dur, func(k: float): m.set_shader_parameter("t", k); mi.scale = Vector3.ONE * dims * (0.8 + k * 0.6))


func light(pos: Vector3, col: Color, energy: float, reach: float, dur: float) -> void:
	var l: Dictionary = _lights[0]
	for c in _lights:
		if c.t >= c.dur:
			l = c
			break
	l.light.global_position = pos
	l.light.light_color = col
	l.light.omni_range = reach
	l.light.visible = true
	l.t = 0.0
	l.dur = dur
	l.e = energy


## One-shot pixel animation (Cobblemon's impacts).
func sprite_anim(file_path: String, pos: Vector3, dims: float, frames: Vector2i, dur: float, col := Color.WHITE) -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	mi.mesh = q
	var m := mat("sprite", VfxShaders.SPRITE, {"tex": load(file_path), "energy": 1.5, "h_frames": frames.x, "v_frames": frames.y, "color": col})
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * dims
	var total := frames.x * frames.y
	live(mi, dur, func(k: float): m.set_shader_parameter("frame", mini(int(k * total), total - 1)))


func armor(l: Node) -> void:
	var c: Vector3 = l.center()
	_flash(c, Color(1.0, 0.65, 0.2), l.data.height * 1.3, 0.14)
	burst("sparks_metal", c, Vector3.UP, Color(1.0, 0.7, 0.3))
	main.audio.play_sound("armor", c, -2.0)


# ---------------------------------------------------------------- texts

func text(pos: Vector3, s: String, col: Color, dims := 0.75) -> void:
	_text(pos + Vector3.UP * 0.5, s, col, 0.9, dims, Vector3(randf_range(-0.2, 0.2), 1.2, 0))


## The damage dealt, colored by how effective it was (Roster.tier): orange and big when
## super effective, yellow when effective, grey when not very, dark grey when barely.
func number(pos: Vector3, damage: float, affinity: float) -> void:
	var col := Color(1, 1, 1)
	var big := damage > 90
	match Roster.tier(affinity):
		"super":
			col = Color("ff8a3a")
			big = true
		"effective":
			col = Color("ffd93a")
		"not_very":
			col = Color("a9adb8")
		"barely":
			col = Color("7c808c")
	_text(pos + Vector3(randf_range(-0.3, 0.3), 0.3, 0), str(int(round(damage))), col, 0.7, 1.15 if big else 0.9,
		Vector3(randf_range(-0.6, 0.6), 2.2, 0))


func _text(pos: Vector3, s: String, col: Color, dur: float, dims: float, v: Vector3) -> void:
	if texts.size() >= 32:
		texts.pop_front()
	texts.append({"pos": pos, "s": s, "col": col, "t": 0.0, "dur": dur, "v": v, "big": dims >= 1.1})


# ---------------------------------------------------------------- lasting shapes

## Removes everything in progress (when going back to the menu: many effects follow a
## Pokémon that stops existing).
func clear() -> void:
	for v in _living:
		if is_instance_valid(v.node):
			v.node.queue_free()
	_living.clear()
	texts.clear()
	if main.fx:
		main.fx.clear()


## Registers a node that lives "dur" seconds; "step" receives the progress from 0 to 1.
func live(node: Node3D, dur: float, step := Callable()) -> void:
	_living.append({"node": node, "t": 0.0, "dur": dur, "step": step})


func _process(delta: float) -> void:
	var i := 0
	while i < _living.size():
		var v: Dictionary = _living[i]
		v.t += delta
		if not is_instance_valid(v.node):
			_living.remove_at(i)
			continue
		var k := clampf(v.t / maxf(v.dur, 0.001), 0.0, 1.0)
		if v.step.is_valid():
			v.step.call(k)
		if v.t >= v.dur:
			v.node.queue_free()
			_living.remove_at(i)
		else:
			i += 1
	for l in _lights:
		if l.t < l.dur:
			l.t += delta
			var k: float = clampf(l.t / l.dur, 0.0, 1.0)
			l.light.light_energy = l.e * (1.0 - k) * (1.0 - k)
			if l.t >= l.dur:
				l.light.visible = false
	var ti := 0
	while ti < texts.size():
		var c: Dictionary = texts[ti]
		c.t += delta
		c.pos += c.v * delta
		c.v.y -= 4.0 * delta
		if c.t >= c.dur:
			texts.remove_at(ti)
		else:
			ti += 1


## Jagged lightning between two points. Rebuilt every 0.07 s while it lasts (in jumps,
## like a frame strip, not smoothly).
## "outline" (alpha above 0) draws a flat darker band under it, like a drawn bolt.
func bolt(a: Vector3, b: Vector3, col: Color, dur := 0.15, width := 0.18, branches := 2, outline := Color(0, 0, 0, 0)) -> void:
	var mi := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	mi.mesh = im
	mi.material_override = mat("lightning", VfxShaders.LIGHTNING, {"color": col, "energy": 5.0, "outline": outline})
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var state := {"t": 0.0}
	var lined := outline.a > 0.0
	_draw_bolt(im, a, b, width, branches, 1.0, lined)
	live(mi, dur, func(k: float):
		state.t += get_process_delta_time()
		if state.t > 0.07:
			state.t = 0.0
			_draw_bolt(im, a, b, width * (1.0 - k * 0.5), branches, 1.0 - k, lined))


func _draw_bolt(im: ImmediateMesh, a: Vector3, b: Vector3, width: float, branches: int, opacity: float, lined := false) -> void:
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var cam := get_viewport().get_camera_3d()
	var points := _zigzag(a, b, maxi(6, int(a.distance_to(b) * 2.5)), a.distance_to(b) * 0.09)
	var lines: Array = [[points, width, opacity]]
	for r in branches:
		var i0 := randi_range(1, points.size() - 2)
		var p0: Vector3 = points[i0]
		var end_pos := p0 + (b - a).normalized().rotated(Vector3.UP, randf_range(-0.9, 0.9)) * a.distance_to(b) * randf_range(0.15, 0.3) \
			+ Vector3(0, randf_range(-0.5, 0.5), 0)
		lines.append([_zigzag(p0, end_pos, 4, p0.distance_to(end_pos) * 0.15), width * 0.5, opacity * 0.8])
	# Every outline first, so no band covers another bolt's core.
	if lined:
		for line in lines:
			_ribbon(im, line[0], line[1] * 1.9, line[2], cam, 0.0)
	for line in lines:
		_ribbon(im, line[0], line[1], line[2], cam)
	im.surface_end()


## Short arcs crawling over a body for "dur" seconds ("center" returns where it is now,
## or null once it is gone). For a Pokémon struck by lightning.
func crackle(center: Callable, radius: float, dur: float, col: Color, outline: Color) -> void:
	var holder := Node3D.new()
	add_child(holder)
	var state := {"t": 0.0}
	live(holder, dur, func(k: float):
		state.t -= get_process_delta_time()
		if state.t > 0.0:
			return
		state.t = lerpf(0.04, 0.09, k)
		var c = center.call()
		if c == null:
			return
		var n := Vector3(randf_range(-1, 1), randf_range(-0.7, 1), randf_range(-1, 1)).normalized()
		var axis := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
		var m := n.rotated(axis, randf_range(0.6, 1.2))
		bolt(c + n * radius, c + m * radius, col, 0.07, lerpf(0.11, 0.05, k), 1, outline))


func _zigzag(a: Vector3, b: Vector3, n: int, deviation: float) -> Array:
	var out := [a]
	var dir := (b - a).normalized()
	var side := dir.cross(Vector3.UP).normalized()
	if side.length() < 0.1:
		side = Vector3.RIGHT
	var up := side.cross(dir)
	for i in range(1, n):
		var k := float(i) / n
		var amp := deviation * sin(k * PI)
		out.append(a.lerp(b, k) + side * randf_range(-amp, amp) + up * randf_range(-amp, amp))
	out.append(b)
	return out


func _ribbon(im: ImmediateMesh, pts: Array, width: float, opacity: float, cam: Camera3D, red := 1.0) -> void:
	var eye := cam.global_position if cam else Vector3(0, 10, 10)
	for i in pts.size() - 1:
		var p0: Vector3 = pts[i]
		var p1: Vector3 = pts[i + 1]
		var d := (p1 - p0).normalized()
		var side := d.cross((eye - p0).normalized()).normalized() * width * 0.5
		var c := Color(red, 1, 1, opacity)
		for v in [[p0 - side, Vector2(0, 0)], [p0 + side, Vector2(0, 1)], [p1 + side, Vector2(1, 1)],
				[p0 - side, Vector2(0, 0)], [p1 + side, Vector2(1, 1)], [p1 - side, Vector2(1, 0)]]:
			im.surface_set_color(c)
			im.surface_set_uv(v[1])
			im.surface_add_vertex(v[0])


## Continuous beam (water stream, ice beam...). Returns the node to move it every step
## with "place_beam"; it is turned off with "stop_beam".
func beam(col: Color, radius: float, core := Color.WHITE, flow_speed := 5.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = 1.0
	cyl.radial_segments = 16
	cyl.rings = 1
	mi.mesh = cyl
	mi.material_override = mat("beam", VfxShaders.BEAM, {"color": col, "core": core, "energy": 3.0, "flow_speed": flow_speed})
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


## Ice beam: like beam(), with the pixel ice shader. Move it with place_beam() and turn
## it off with stop_beam().
func ice_beam(radius: float, flow_speed := 14.0) -> MeshInstance3D:
	var mi := water_stream(radius, flow_speed)
	mi.material_override = mat("ice", VfxShaders.ICE, {"flow_speed": flow_speed})
	return mi


## Water stream (Hydro Pump): like beam(), with the pixel water shader. Move it with
## place_beam() and turn it off with stop_beam().
func water_stream(radius: float, flow_speed := 9.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = 1.0
	cyl.radial_segments = 16
	cyl.rings = 48              # the shader bends it into lumps along its length
	cyl.cap_top = false
	cyl.cap_bottom = false
	mi.mesh = cyl
	mi.material_override = mat("water", VfxShaders.WATER, {"flow_speed": flow_speed})
	mi.extra_cull_margin = radius * 2.0
	mi.set_meta("radius", radius)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


## Dragon Pulse's beam: a see-through sheath and a solid core inside it, both lumpy (see
## DRAGON_BEAM). Move each with place_beam() and fade each with stop_beam().
## "palette": {edge, mid, glow, core} to color it otherwise (Hyper Beam's orange).
func dragon_beam(radius: float, flow_speed := 18.0, palette := {}) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for shell in [1.0, 0.0]:
		var mi := water_stream(radius * (1.7 if shell > 0.5 else 1.0), flow_speed)
		(mi.mesh as CylinderMesh).radial_segments = 24
		var params := {"flow_speed": flow_speed, "shell": shell}
		params.merge(palette)
		var m := mat("dragon_beam", VfxShaders.DRAGON_BEAM, params)
		# The core is drawn over the sheath, so it shows through it.
		m.render_priority = 0 if shell > 0.5 else 1
		mi.material_override = m
		out.append(mi)
	return out


## A hemisphere of radius 1 standing on the ground, with the DOME shader: scale it to grow
## it and keep its "radius" (meters) and "t" parameters up to date.
func dome() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 1.0
	sm.is_hemisphere = true
	sm.radial_segments = 48
	sm.rings = 16
	mi.mesh = sm
	mi.material_override = mat("dome", VfxShaders.DOME)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func place_beam(mi: MeshInstance3D, from_pos: Vector3, to_pos: Vector3, thickness := 1.0) -> void:
	var d := to_pos - from_pos
	var length := maxf(d.length(), 0.01)
	var b := Basis.looking_at(d.normalized(), Vector3.UP if absf(d.normalized().y) < 0.95 else Vector3.RIGHT)
	# The cylinder runs along Y: it is rotated so Y points toward "to".
	b = b * Basis(Vector3.RIGHT, -PI * 0.5)
	# Scale along the cylinder's own axes (scaled() would scale along the world's).
	mi.global_transform = Transform3D(b * Basis.from_scale(Vector3(thickness, length, thickness)), from_pos + d * 0.5)
	# The shaders measure their pixels on the real beam, not on the stretched mesh.
	var m := mi.material_override as ShaderMaterial
	if m:
		m.set_shader_parameter("stream_len", length)
		m.set_shader_parameter("girth", TAU * float(mi.get_meta("radius", 0.3)) * thickness)


func stop_beam(mi: MeshInstance3D, dur := 0.15) -> void:
	if not is_instance_valid(mi):
		return
	var m: ShaderMaterial = mi.material_override
	live(mi, dur, func(k: float): m.set_shader_parameter("faded", k))


## Trail following a body point (claw, tail): "points" returns [base, tip] in the world
## every frame.
func ribbon(points: Callable, col: Color, dur: float, point_life := 0.14) -> void:
	var mi := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	mi.mesh = im
	mi.material_override = mat("ribbon", VfxShaders.RIBBON, {"color": col, "energy": 1.7})
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var samples: Array = []
	var clock := {"t": 0.0}
	live(mi, dur + point_life, func(_k: float):
		var dt := get_process_delta_time()
		clock.t += dt
		for s in samples:
			s.age_t += dt
		while not samples.is_empty() and samples[0].age_t > point_life:
			samples.pop_front()
		if clock.t <= dur:
			var p: Array = points.call()
			samples.append({"a": p[0], "b": p[1], "age_t": 0.0})
		im.clear_surfaces()
		if samples.size() < 2:
			return
		im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in samples.size() - 1:
			var s0: Dictionary = samples[i]
			var s1: Dictionary = samples[i + 1]
			var a0: float = 1.0 - s0.age_t / point_life
			var a1: float = 1.0 - s1.age_t / point_life
			for v in [[s0.a, 0.0, a0], [s0.b, 1.0, a0], [s1.b, 1.0, a1], [s0.a, 0.0, a0], [s1.b, 1.0, a1], [s1.a, 0.0, a1]]:
				im.surface_set_color(Color(1, 1, 1, v[2]))
				im.surface_set_uv(Vector2(0, v[1]))
				im.surface_add_vertex(v[0])
		im.surface_end())


## Ring that spreads across the ground up to "radius" in "dur" seconds.
func wave(center: Vector3, radius: float, dur: float, col: Color, thickness := 0.08) -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(2, 2)
	mi.mesh = pm
	var m := mat("ring", VfxShaders.RING, {"color": col, "energy": 2.2, "thickness": thickness,
		"cells": clampf(roundf(radius * 32.0), 16.0, 192.0)})
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = center + Vector3.UP * 0.05
	live(mi, dur, func(k: float):
		var r := maxf(0.05, radius * (1.0 - pow(1.0 - k, 2.0)))
		mi.scale = Vector3(r, 1.0, r)
		m.set_shader_parameter("t", maxf(0.0, (k - 0.6) / 0.4)))


## Mark on the ground (burn, crack, frost, poison puddle) that fades out.
func mark(pos: Vector3, kind: String, radius: float, dur := 4.0) -> void:
	var d := Decal.new()
	d.texture_albedo = _mark_tex(kind, radius)
	d.size = Vector3(radius * 2.0, 1.0, radius * 2.0)
	d.albedo_mix = 1.0
	d.upper_fade = 0.3
	d.lower_fade = 0.3
	add_child(d)
	d.global_position = pos
	d.rotation.y = randf() * TAU
	live(d, dur, func(k: float): d.modulate.a = 1.0 - smoothstep(0.6, 1.0, k))


var _marks := {}
## The only alpha levels marks use (like the move sprites): no gradients.
const MARK_ALPHA := [0.95, 0.75, 0.47, 0.24]


## Mark texture at 16 px per meter (the density of Cobblemon's models), whatever its size.
## Drawn here in flat color bands and stepped alpha; two variants per size so repeated
## marks do not look stamped.
func _mark_tex(kind: String, radius: float) -> Texture2D:
	var side := clampi(int(roundf(radius * 32.0)), 16, 192)
	var key := "%s_%d_%d" % [kind, side, randi() % 2]
	if _marks.has(key):
		return _marks[key]
	var img := Image.create(side, side, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 6.0 / side
	match kind:
		"crack":
			_paint_crack(img, side, rng)
		"burned":
			_paint_blotch(img, side, noise, rng, [Color(0.07, 0.05, 0.04), Color(0.13, 0.09, 0.07), Color(0.2, 0.14, 0.1)], Color(1.0, 0.45, 0.15), 0.01)
		"frost":
			_paint_blotch(img, side, noise, rng, [Color(0.55, 0.78, 0.95), Color(0.72, 0.9, 1.0), Color(0.92, 0.98, 1.0)], Color(1, 1, 1), 0.03)
		"poison_puddle":
			_paint_puddle(img, side, noise, rng)
		"wet":
			_paint_blotch(img, side, noise, rng, [Color(0.06, 0.14, 0.2), Color(0.1, 0.22, 0.3), Color(0.2, 0.38, 0.5)], Color(0.7, 0.9, 1.0), 0.02)
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_marks[key] = t
	return t


## Cracks: a small crater in the middle and jagged lines out to the edge, with branches,
## a dark core and a light rim pixel on one side (raised dust), plus loose debris.
func _paint_crack(img: Image, side: int, rng: RandomNumberGenerator) -> void:
	var c := Vector2(side, side) * 0.5
	var dark := Color(0.09, 0.07, 0.06, MARK_ALPHA[0])
	var rim := Color(0.62, 0.56, 0.48, MARK_ALPHA[2])
	var crater := maxf(1.5, side * 0.06)
	for y in side:
		for x in side:
			var dd := Vector2(x + 0.5, y + 0.5).distance_to(c)
			if dd < crater:
				img.set_pixel(x, y, dark)
			elif dd < crater + 1.0:
				img.set_pixel(x, y, Color(0.2, 0.16, 0.13, MARK_ALPHA[1]))
	var arms := rng.randi_range(5, 7)
	for i in arms:
		var ang := TAU * i / arms + rng.randf_range(-0.3, 0.3)
		_crack_line(img, side, c, ang, side * rng.randf_range(0.38, 0.48), 2 if side >= 48 else 1, rng, dark, rim, 2)
	for i in side / 6:
		var p := c + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(crater + 2.0, side * 0.45)
		_px(img, side, p, Color(0.3, 0.25, 0.2, MARK_ALPHA[1]))


func _crack_line(img: Image, side: int, from: Vector2, ang: float, length: float, width: int,
		rng: RandomNumberGenerator, dark: Color, rim: Color, depth: int) -> void:
	var p := from
	var travelled := 0.0
	var dir := Vector2.from_angle(ang)
	while travelled < length:
		# A kink every few pixels: the line zigzags instead of running straight.
		dir = dir.rotated(rng.randf_range(-0.55, 0.55)).lerp(Vector2.from_angle(ang), 0.5).normalized()
		var step := rng.randf_range(2.0, 4.0)
		for s in int(step):
			p += dir
			for w in width:
				_px(img, side, p + dir.orthogonal() * w, dark)
			_px(img, side, p + dir.orthogonal() * width, rim)
		travelled += step
		if depth > 0 and travelled > length * 0.3 and rng.randf() < 0.18:
			_crack_line(img, side, p, ang + rng.randf_range(0.5, 0.9) * (1 if rng.randf() < 0.5 else -1),
				(length - travelled) * 0.6, 1, rng, dark, rim, depth - 1)


## A blotch with a ragged edge in three color bands (darker toward the middle), each band
## one alpha level, plus a few accent pixels (embers, ice glints).
func _paint_blotch(img: Image, side: int, noise: FastNoiseLite, rng: RandomNumberGenerator,
		bands: Array, accent: Color, accent_rate: float) -> void:
	var c := Vector2(side, side) * 0.5
	for y in side:
		for x in side:
			var r := Vector2(x + 0.5, y + 0.5).distance_to(c) / (side * 0.5)
			var v := 1.0 - r + noise.get_noise_2d(x, y) * 0.35
			if v < 0.12:
				continue
			var band := 2 if v < 0.3 else (1 if v < 0.55 else 0)
			var col: Color = bands[band]
			col.a = MARK_ALPHA[band + 1]
			if band == 0 and rng.randf() < accent_rate:
				col = Color(accent, MARK_ALPHA[0])
			img.set_pixel(x, y, col)


## Poison puddle: a ragged blob with a dark rim, a mid body, a light patch toward the top
## left (the same light as the sprites) and bubble rings.
func _paint_puddle(img: Image, side: int, noise: FastNoiseLite, rng: RandomNumberGenerator) -> void:
	var c := Vector2(side, side) * 0.5
	var light := c + Vector2(-0.25, -0.3) * side * 0.5
	for y in side:
		for x in side:
			var p := Vector2(x + 0.5, y + 0.5)
			var r := p.distance_to(c) / (side * 0.5)
			var edge := 0.86 + noise.get_noise_2d(x, y) * 0.22
			if r > edge:
				continue
			var col := Color(0.42, 0.2, 0.55, MARK_ALPHA[0])
			if r > edge - 0.07:
				col = Color(0.24, 0.09, 0.33, MARK_ALPHA[0])
			elif p.distance_to(light) < side * 0.16:
				col = Color(0.6, 0.36, 0.74, MARK_ALPHA[0])
			img.set_pixel(x, y, col)
	for i in maxi(2, side / 14):
		var b := c + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, side * 0.3)
		var br := rng.randf_range(1.0, maxf(1.5, side * 0.05))
		for a in 24:
			_px(img, side, b + Vector2.from_angle(TAU * a / 24.0) * br, Color(0.8, 0.6, 0.92, MARK_ALPHA[0]))


func _px(img: Image, side: int, p: Vector2, col: Color) -> void:
	var x := int(p.x)
	var y := int(p.y)
	if x >= 0 and y >= 0 and x < side and y < side:
		img.set_pixel(x, y, col)


## Silhouette of the fighter in its current pose (dodges, speed).
func afterimage(l: Node, col := Color(0.6, 0.8, 1.0)) -> void:
	var skel: Skeleton3D = l.model.skel
	var copy: Node3D = skel.duplicate(0)
	for h in copy.get_children():
		if h is SkeletonModifier3D:
			h.queue_free()
	var m := mat("fantasma", VfxShaders.GHOST, {"color": col})
	for h in copy.get_children():
		if h is MeshInstance3D:
			h.material_override = m
			h.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(copy)
	copy.global_transform = skel.global_transform
	live(copy, 0.28, func(k: float): m.set_shader_parameter("t", k))


## A band of light round a fighter's body for "dur" seconds (see OUTLINE): its meshes get
## the outline as their overlay, which follows its animation, and lose it at the end.
func outline(f: Node, col: Color, dur: float, width := 0.14) -> void:
	if not (f is Fighter) or not is_instance_valid(f):
		return
	var m := mat("outline", VfxShaders.OUTLINE, {"color": col, "width": width})
	var meshes: Array[MeshInstance3D] = []
	for h in f.model.skel.get_children():
		if h is MeshInstance3D:
			h.material_overlay = m
			meshes.append(h)
	live(Node3D.new(), dur, func(k: float): m.set_shader_parameter("t", k * dur))
	get_tree().create_timer(dur, false).timeout.connect(func():
		for h in meshes:
			if is_instance_valid(h) and h.material_overlay == m:
				h.material_overlay = null)


## Pixel energy ball (fx/tex/custom/*.png, from tools/move_sprites.py): a quad that
## faces the camera and runs through its strip, with a soft light of its color. It lasts
## until its creator removes it. glow = false for matter that is not energy (sludge, rock):
## no bloom and no light of its own.
func pixel_ball(key: String, frames: int, dims: float, col: Color, fps := 14.0, glow := true) -> Node3D:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE * dims
	mi.mesh = q
	var m := mat("pixel_ball", VfxShaders.PIXEL_BALL, {"strip": load("res://fx/tex/custom/%s.png" % key),
		"frames": float(frames), "brightness": 1.15 if glow else 0.85})
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	if glow:
		var o := OmniLight3D.new()
		o.light_color = col
		o.light_energy = 1.6
		o.omni_range = dims * 4.0
		root.add_child(o)
	add_child(root)
	var clock := {"t": randf() * 10.0}
	live(root, 3600.0, func(_k: float):
		clock.t += get_process_delta_time()
		m.set_shader_parameter("frame", float(int(clock.t * fps) % frames)))
	return root


## A pixel strip on a flat quad with its own orientation (the quad faces its +Z, so
## Basis.looking_at(dir) shows its face to whoever is behind, looking along "dir"). It
## plays its frames once over "dur", or loops at "fps" when given; "step" (node, k) can
## move, turn or fade it (set "tint" on its material) while it lives.
## "depth" (m) extrudes it like Minecraft's items in hand: the front and back keep the
## animated strip and every opaque edge pixel gets side faces in its own color (shaded by
## the way they face), so from the side it has body instead of being a sheet.
func flat_sprite(tex_path: String, frames: int, size: float, pos: Vector3, basis: Basis, dur: float,
		tint := Color.WHITE, fps := 0.0, step := Callable(), depth := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE * size
	mi.mesh = q
	var m := mat("pixel_flat", VfxShaders.PIXEL_FLAT, {"strip": load(tex_path), "frames": float(frames), "tint": tint})
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = pos
	mi.global_basis = basis
	var sides: MeshInstance3D = null
	if depth > 0.0:
		# Front and back faces at either side of the depth, the side faces between them.
		var back := MeshInstance3D.new()
		back.mesh = q
		back.material_override = m
		back.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.add_child(back)
		back.position = Vector3(0, 0, -depth)
		sides = MeshInstance3D.new()
		sides.material_override = _side_material(tint)
		sides.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.add_child(sides)
		sides.mesh = _extrusion(tex_path, frames, 0, size, depth)
	var clock := {"t": 0.0, "f": 0}
	live(mi, dur, func(k: float):
		clock.t += get_process_delta_time()
		var f := int(clock.t * fps) % frames if fps > 0.0 else mini(int(k * frames), frames - 1)
		m.set_shader_parameter("frame", float(f))
		if sides and f != clock.f:
			sides.mesh = _extrusion(tex_path, frames, f, size, depth)
		clock.f = f
		if step.is_valid():
			step.call(mi, k))
	return mi


## A pixel sprite that pops in and out: it grows from nothing to "size" and shrinks back
## over "dur", in steps (one frame of a strip; "down" when its frames go down the image).
func pop(tex_path: String, frames: int, frame: int, pos: Vector3, size: float, dur: float, tint := Color.WHITE, down := false) -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	mi.mesh = q
	mi.material_override = mat("pixel_pop", VfxShaders.PIXEL_POP, {"strip": load(tex_path), "frames": float(frames),
		"frame": float(frame), "down": down, "tint": tint})
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * 0.01
	live(mi, dur, func(k: float):
		mi.scale = Vector3.ONE * maxf(0.01, snappedf(size * sin(k * PI), size * 0.2)))


var _extrusions := {}


func _side_material(tint: Color) -> StandardMaterial3D:
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.vertex_color_use_as_albedo = true
	sm.albedo_color = Color(tint, 1.0)
	sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	return sm


## The side faces of one frame of a strip, from z 0 back to z -depth: for every opaque pixel,
## a face on each edge with nothing opaque beyond, in the pixel's color (top lighter, bottom
## darker). Built once per strip, frame, size and depth.
func _extrusion(tex_path: String, frames: int, frame: int, size: float, depth: float) -> ArrayMesh:
	var key := "%s|%d|%.3f|%.3f" % [tex_path, frame, size, depth]
	if _extrusions.has(key):
		return _extrusions[key]
	var img: Image = (load(tex_path) as Texture2D).get_image()
	if img.is_compressed():
		img.decompress()
	var fw := img.get_width() / frames
	var fh := img.get_height()
	var x0 := fw * frame
	var solid := func(x: int, y: int) -> bool:
		return x >= 0 and y >= 0 and x < fw and y < fh and img.get_pixel(x0 + x, y).a > 0.7
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var px := size / float(fw)
	var py := size / float(fh)
	for y in fh:
		for x in fw:
			if not solid.call(x, y):
				continue
			var c := img.get_pixel(x0 + x, y)
			var l := (x / float(fw) - 0.5) * size
			var r := l + px
			var t := (0.5 - y / float(fh)) * size
			var b := t - py
			# [neighbour dx, dy, shade, corner a, corner b] for each edge.
			for e in [[0, -1, 1.0, Vector2(l, t), Vector2(r, t)], [0, 1, 0.62, Vector2(r, b), Vector2(l, b)],
					[-1, 0, 0.8, Vector2(l, b), Vector2(l, t)], [1, 0, 0.8, Vector2(r, t), Vector2(r, b)]]:
				if solid.call(x + e[0], y + e[1]):
					continue
				var col := Color(c.r * e[2], c.g * e[2], c.b * e[2])
				var a: Vector2 = e[3]
				var bb: Vector2 = e[4]
				for v in [Vector3(a.x, a.y, 0.0), Vector3(bb.x, bb.y, 0.0), Vector3(bb.x, bb.y, -depth),
						Vector3(a.x, a.y, 0.0), Vector3(bb.x, bb.y, -depth), Vector3(a.x, a.y, -depth)]:
					st.set_color(col)
					st.add_vertex(v)
	var mesh := st.commit()
	_extrusions[key] = mesh
	return mesh


## Continuous emitter (fire or water stream, sparks while charging). Its creator moves
## and stops it; once stopped it is removed when its particles are done.
func continuous_emitter(key: String, amount: int, hp: float, v: Vector2, spread: float, dims: Vector2, parent_n: Node3D = null) -> GPUParticles3D:
	var e := _create_emitter(key)
	e.one_shot = false
	e.explosiveness = 0.0
	e.amount = amount
	e.lifetime = hp
	var pm: ParticleProcessMaterial = e.process_material
	pm.initial_velocity_min = v.x
	pm.initial_velocity_max = v.y
	pm.spread = spread
	pm.scale_min = dims.x
	pm.scale_max = dims.y
	if parent_n:
		e.reparent(parent_n, false)
	e.emitting = true
	return e


func stop_emitter(e: GPUParticles3D) -> void:
	if not is_instance_valid(e):
		return
	e.emitting = false
	var t := get_tree().create_timer(e.lifetime + 0.1)
	t.timeout.connect(func(): if is_instance_valid(e): e.queue_free())


## Warning circle on the ground that fills up in "dur" seconds (where something will land).
func telegraph(center: Vector3, radius: float, dur: float, col := Color(1.0, 0.45, 0.2)) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(2, 2)
	mi.mesh = pm
	var m := mat("telegraph", VfxShaders.WARNING, {"color": col, "cells": clampf(roundf(radius * 32.0), 16.0, 192.0)})
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = center + Vector3.UP * 0.04
	mi.scale = Vector3(radius, 1.0, radius)
	live(mi, dur, func(k: float): m.set_shader_parameter("k", k))
	return mi
