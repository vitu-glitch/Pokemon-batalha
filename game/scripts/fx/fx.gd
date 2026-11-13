class_name Fx
extends Node3D
## Interpreter for Cobblemon's move particles (Bedrock / Snowstorm format, converted by
## tools/convert_particles.py into game/fx/).
## It supports what those effects use: instant, continuous and looping emitters; point,
## sphere, disc and box shapes; speed, drag, spin; parametric motion; ground collision;
## animation strips; gradient colors; events that launch other pieces; and move
## sequences.
## All particles with the same texture and material are drawn with ONE MultiMesh (one
## draw call), with the browser in mind.
##
## Axes: Bedrock has X flipped compared to Godot (as in the models). The emitter faces
## its target (its Godot -Z), and target_deltax/y/z are the target in that frame as
## Cobblemon computes them.

const DIR := "res://fx/particles/"
const SEQUENCES := "res://fx/sequences/"
const MAX_EMITTERS := 120
## Budget of live particles (each one evaluates its Molang in GDScript: about 25 µs).
## Past the cap, new effects spawn with fewer particles. Low-priority ones ("low") give
## way before the player's.
const BUDGET := 320
const BUDGET_LOW := 160

static var _defs := {}
static var _sequences := {}
static var _shaders := {}

var main: Node
var ctx := FxCtx.new()
var _emitters: Array = []
var _buckets := {}
var _pending: Array = []      # sequence steps waiting for their moment: [time, callable]
var _t := 0.0
var _alive := 0
var _sprites: Array = []      # sprites for this frame (projectiles): [tex, pos, size, uv, color]
var _anims: Array = []        # one-shot animations (slashes): see anim()
static var _tex_cache := {}


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


# ---------------------------------------------------------------- loading

static func load_def(id: String) -> Dictionary:
	if _defs.has(id):
		return _defs[id]
	var file_path := DIR + id + ".json"
	if not FileAccess.file_exists(file_path):
		_defs[id] = {}
		return {}
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(file_path))
	d.curves = _compile(d.curves)
	d.comp = _compile(d.comp)
	d.tex_res = load(d.tex) if d.tex != "" and ResourceLoader.exists(d.tex) else null
	_defs[id] = d
	return d


static func _compile(x):
	if x is Dictionary:
		if x.size() == 1 and x.has("e"):
			var ex := Expression.new()
			if ex.parse(x.e) != OK:
				push_warning("Untranslated Molang: " + x.e)
				return 0.0
			return ex
		var out := {}
		for k in x:
			out[k] = _compile(x[k])
		return out
	if x is Array:
		var a := []
		for v in x:
			a.append(_compile(v))
		return a
	return x


static func sequence(seq_id: String) -> Array:
	if _sequences.has(seq_id):
		return _sequences[seq_id]
	var file_path := SEQUENCES + seq_id + ".json"
	_sequences[seq_id] = JSON.parse_string(FileAccess.get_file_as_string(file_path)) if FileAccess.file_exists(file_path) else []
	return _sequences[seq_id]


# ---------------------------------------------------------------- API

func clear() -> void:
	_emitters.clear()
	_pending.clear()
	_anims.clear()
	_alive = 0


## Launches a piece. `target` is the point it "looks at" (if any).
func play(id: String, pos: Vector3, target = null, opts := {}) -> Dictionary:
	var d := load_def(id)
	if d.is_empty() or _emitters.size() >= MAX_EMITTERS:
		return {}
	var basis: Basis = opts.get("basis", Basis.IDENTITY)
	var vars := {"emitter_age": 0.0, "emitter_lifetime": 1.0, "entity_height": opts.get("height", 1.0),
		"entity_width": opts.get("width", 0.8), "entity_radius": opts.get("width", 0.8) * 0.5,
		"entity_scale": 1.0, "entity_size": opts.get("height", 1.0), "scale": 1.0,
		"target_deltax": 0.0, "target_deltay": 0.0, "target_deltaz": 0.0, "target_distance": 0.0}
	for i in 4:
		vars["emitter_random_%d" % (i + 1)] = randf()
	if target != null:
		var to: Vector3 = target - pos
		if not opts.has("basis") and Vector2(to.x, to.z).length() > 0.01:
			basis = Basis.looking_at(Vector3(to.x, 0, to.z).normalized(), Vector3.UP)
		var local: Vector3 = basis.inverse() * to
		vars.target_deltax = local.x
		vars.target_deltay = local.y
		vars.target_deltaz = -local.z
		vars.target_distance = to.length()
	var em := {"d": d, "pos": pos, "basis": basis, "age": 0.0, "vars": vars, "parts": [], "acc": 0.0,
		"fired": {}, "active": true, "dur": opts.get("dur", 3.0), "loops": 0, "low": opts.get("low", false),
		"ground": main.ground_at(pos, pos.y + 1.0) if main else 0.0}
	ctx.e = vars
	ctx.p = {}
	ctx.curves = d.curves
	var c: Dictionary = d.comp
	if c.has("emitter_initialization"):
		_run_statements(c.emitter_initialization.get("creation_expression", []), vars)
	em.life = _lifetime(em)
	vars.emitter_lifetime = em.life
	_emitter_event(em, "creation_event")
	if c.has("emitter_rate_instant"):
		_spawn_n(em, int(ctx.ev(c.emitter_rate_instant.get("num_particles", 1.0))))
	_emitters.append(em)
	return em


## A piece that goes from `from_pos` to `to_pos` (beams between enemies, from attacker to
## target). Cobblemon pieces with "lookat_direction" are drawn centered on the emitter
## and measure 2 × target_distance, so they are launched from the midpoint.
func line(id: String, from_pos: Vector3, to_pos: Vector3) -> Dictionary:
	var middle := (from_pos + to_pos) * 0.5
	return play(id, middle, to_pos, {"basis": Basis.looking_at((to_pos - from_pos).normalized() if (to_pos - from_pos).length() > 0.01 else Vector3.FORWARD, Vector3.UP)})


## Draws a pixelated sprite this frame (projectile balls, for example).
## `frames` in a horizontal or vertical strip depending on the texture's shape.
func sprite(tex_path: String, pos: Vector3, size: float, frame: int, frames: int, color := Color.WHITE) -> void:
	_sprites.append([tex_path, pos, size, frame, frames, color])


## One-shot animation: runs through the frames of a strip and disappears.
## `translucent`: keeps the strip's stepped alpha (custom sprites with half-opaque
## halos); otherwise alpha is cut at one half like in Cobblemon.
func anim(tex_path: String, pos: Vector3, size: float, frames: int, dur: float, color := Color.WHITE, turn := 0.0, translucent := false) -> void:
	_anims.append({"tex": tex_path, "pos": pos, "size": size, "frames": frames, "dur": dur, "t": 0.0, "color": color, "turn": turn,
		"mat": "particles_blend" if translucent else "particles_alpha"})


static func _tex(path: String) -> Texture2D:
	if not _tex_cache.has(path):
		var full := path if path.begins_with("res://") else "res://fx/tex/" + path
		_tex_cache[path] = load(full) if ResourceLoader.exists(full) else null
	return _tex_cache[path]


func _draw_sprite(tex_path: String, pos: Vector3, size: float, frame: int, frames: int, color: Color, turn: float, cam: Camera3D, material := "particles_alpha") -> void:
	var tex := _tex(tex_path)
	if tex == null:
		return
	var b = _bucket_tex(tex_path, tex, material)
	var w := float(tex.get_width())
	var h := float(tex.get_height())
	var uvr := Color(0, 0, 1, 1)
	if frames > 1:
		if w >= h:
			uvr = Color(float(frame) / frames, 0, 1.0 / frames, 1)
		else:
			uvr = Color(0, float(frame) / frames, 1, 1.0 / frames)
	var cb := cam.global_basis
	var x := cb.x
	var y := cb.y
	if turn != 0.0:
		var nx := x * cos(turn) + y * sin(turn)
		y = y * cos(turn) - x * sin(turn)
		x = nx
	_put(b, Transform3D(Basis(x * size, y * size, cb.z), pos), color, uvr)


func _put(b: Dictionary, tr: Transform3D, color: Color, uvr: Color) -> void:
	var mm: MultiMesh = b.mm
	if b.n >= mm.instance_count:
		mm.instance_count = mm.instance_count * 2
	mm.set_instance_transform(b.n, tr)
	mm.set_instance_color(b.n, color)
	mm.set_instance_custom_data(b.n, uvr)
	b.n += 1


## Plays a Cobblemon sequence: which piece comes out, from whom and when.
## actor / target: {"root": pos, "middle": pos, "target": pos, "height": h}
func play_sequence(seq_id: String, actor: Dictionary, target: Dictionary, time_scale := 1.0, skip_fx := []) -> void:
	var t := 0.0
	for step in sequence(seq_id):
		if step.has("pause"):
			t += float(step.pause) / time_scale
			continue
		if step.fx in skip_fx:
			continue
		var subject: Dictionary = actor if step.who == "actor" else target
		var other: Dictionary = target if step.who == "actor" else actor
		var loc: String = step.loc
		var pos: Vector3 = subject.get(loc, subject.root)
		var looks: Vector3 = other.get("middle", other.root)
		var opts := {"height": subject.get("height", 1.0)}
		var id: String = step.fx
		if t <= 0.0:
			play(id, pos, looks, opts)
		else:
			_pending.append([_t + t, play.bind(id, pos, looks, opts)])


func _lifetime(em: Dictionary) -> float:
	var c: Dictionary = em.d.comp
	if c.has("emitter_lifetime_once"):
		return ctx.ev(c.emitter_lifetime_once.get("active_time", 1.0))
	if c.has("emitter_lifetime_looping"):
		return ctx.ev(c.emitter_lifetime_looping.get("active_time", 1.0))
	if c.has("emitter_lifetime_events"):
		return em.dur
	return 1.0


func _run_statements(list: Array, target_point: Dictionary) -> void:
	for st in list:
		target_point[st[0]] = ctx.ev(st[1])


# ---------------------------------------------------------------- events

func _emitter_event(em: Dictionary, which: String) -> void:
	var c: Dictionary = em.d.comp
	if not c.has("emitter_lifetime_events"):
		return
	var ev = c.emitter_lifetime_events.get(which)
	if ev != null:
		_fire(em, ev, em.pos)


func _fire(em: Dictionary, names, pos: Vector3) -> void:
	var list: Array = names if names is Array else [names]
	for n in list:
		var ev: Dictionary = em.d.events.get(n, {})
		_fire_def(em, ev, pos)


func _fire_def(em: Dictionary, ev: Dictionary, pos: Vector3) -> void:
	if ev.has("sequence"):
		for sub in ev.sequence:
			_fire_def(em, sub, pos)
	if ev.has("randomize") and not ev.randomize.is_empty():
		_fire_def(em, ev.randomize[randi() % ev.randomize.size()], pos)
	if ev.has("particle_effect"):
		var id: String = String(ev.particle_effect.effect).split(":")[-1]
		var child := play(id, pos, null, {"basis": em.basis, "low": em.low})
		if not child.is_empty():
			for k in ["target_deltax", "target_deltay", "target_deltaz", "target_distance", "entity_height", "entity_width"]:
				child.vars[k] = em.vars[k]


# ---------------------------------------------------------------- particles

static func _flip(v: Vector3) -> Vector3:
	return Vector3(-v.x, v.y, v.z)


func _vec(a) -> Vector3:
	if a is Array and a.size() >= 3:
		return Vector3(ctx.ev(a[0]), ctx.ev(a[1]), ctx.ev(a[2]))
	return Vector3.ZERO


func _spawn_n(em: Dictionary, n: int) -> void:
	for i in n:
		_spawn(em)


func _spawn(em: Dictionary) -> void:
	var cap := BUDGET_LOW if em.low else BUDGET
	if _alive > cap and randf() > float(cap) / _alive:
		return
	_alive += 1
	var c: Dictionary = em.d.comp
	var p := {"particle_age": 0.0, "particle_lifetime": 1.0}
	for i in 4:
		p["particle_random_%d" % (i + 1)] = randf()
	ctx.p = p
	ctx.e = em.vars
	ctx.curves = em.d.curves
	var local := Vector3.ZERO
	var dir := Vector3.ZERO
	var shape := {}
	for k in ["emitter_shape_point", "emitter_shape_sphere", "emitter_shape_disc", "emitter_shape_box"]:
		if c.has(k):
			shape = c[k]
			shape["_k"] = k
			break
	if not shape.is_empty():
		var off := _vec(shape.get("offset", [0.0, 0.0, 0.0]))
		var toward := Vector3.ZERO
		match shape._k:
			"emitter_shape_sphere":
				var r := ctx.ev(shape.get("radius", 1.0))
				var u := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
				toward = u
				local = u * (r if shape.get("surface_only", false) else r * pow(randf(), 1.0 / 3.0))
			"emitter_shape_disc":
				var r := ctx.ev(shape.get("radius", 1.0))
				var a := randf() * TAU
				var rr := r if shape.get("surface_only", false) else r * sqrt(randf())
				var nrm := Vector3.UP
				var pn = shape.get("plane_normal", "y")
				if pn is String:
					nrm = {"x": Vector3.RIGHT, "y": Vector3.UP, "z": Vector3.BACK}.get(pn, Vector3.UP)
				elif pn is Array:
					nrm = _vec(pn).normalized()
				var t1 := nrm.cross(Vector3.FORWARD if absf(nrm.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
				var t2 := nrm.cross(t1)
				local = (t1 * cos(a) + t2 * sin(a)) * rr
				toward = local.normalized()
			"emitter_shape_box":
				var hd := _vec(shape.get("half_dimensions", [0.5, 0.5, 0.5]))
				local = Vector3(randf_range(-hd.x, hd.x), randf_range(-hd.y, hd.y), randf_range(-hd.z, hd.z))
				toward = local.normalized()
		var dd = shape.get("direction", "outwards")
		if dd is Array:
			dir = _vec(dd)
		elif dd is String and dd == "inwards":
			dir = -toward
		else:
			dir = toward if shape._k != "emitter_shape_point" else Vector3.ZERO
		local += off
	var basis: Basis = em.basis
	var wpos: Vector3 = em.pos + basis * _flip(local)
	var wdir: Vector3 = basis * _flip(dir)
	if wdir.length() > 0.0001:
		wdir = wdir.normalized()
	var speed := Vector3.ZERO
	var sp = c.get("particle_initial_speed", 0.0)
	if sp is Array:
		speed = basis * _flip(_vec(sp))
	else:
		speed = wdir * ctx.ev(sp)
	p.particle_lifetime = ctx.ev(c.get("particle_lifetime_expression", {}).get("max_lifetime", 1.0))
	var spin: Dictionary = c.get("particle_initial_spin", {})
	p._pos = wpos
	p._vel = speed
	p._dir = wdir
	p._rot = ctx.ev(spin.get("rotation", 0.0))
	p._rrate = ctx.ev(spin.get("rotation_rate", 0.0))
	p._origin = em.pos
	p._fired = {}
	em.parts.append(p)
	_particle_event(em, p, "creation_event")


func _particle_event(em: Dictionary, p: Dictionary, which: String) -> void:
	var c: Dictionary = em.d.comp
	if c.has("particle_lifetime_events"):
		var ev = c.particle_lifetime_events.get(which)
		if ev != null:
			_fire(em, ev, p._pos)


# ---------------------------------------------------------------- loop

var cost_us := 0          # how long the last frame took (for tests)
var particles := 0


func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	global_transform = Transform3D.IDENTITY
	_t += delta
	var i := 0
	while i < _pending.size():
		if _pending[i][0] <= _t:
			var f: Callable = _pending[i][1]
			_pending.remove_at(i)
			f.call()
		else:
			i += 1
	for b in _buckets.values():
		b.n = 0
	_alive = 0
	for em in _emitters:
		_alive += em.parts.size()
	var cam := get_viewport().get_camera_3d()
	var e := 0
	while e < _emitters.size():
		var em: Dictionary = _emitters[e]
		_update_emitter(em, delta, cam)
		if not em.active and em.parts.is_empty():
			_emitters.remove_at(e)
		else:
			e += 1
	if cam != null:
		for s in _sprites:
			_draw_sprite(s[0], s[1], s[2], s[3], s[4], s[5], 0.0, cam)
		var k := 0
		while k < _anims.size():
			var a: Dictionary = _anims[k]
			a.t += delta
			if a.t >= a.dur:
				_anims.remove_at(k)
				continue
			var fr := mini(int(a.t / a.dur * a.frames), a.frames - 1)
			_draw_sprite(a.tex, a.pos, a.size, fr, a.frames, a.color, a.turn, cam, a.mat)
			k += 1
	_sprites.clear()
	particles = 0
	for b in _buckets.values():
		b.mm.visible_instance_count = b.n
		particles += b.n
	cost_us = Time.get_ticks_usec() - t0


func _update_emitter(em: Dictionary, delta: float, cam: Camera3D) -> void:
	var c: Dictionary = em.d.comp
	ctx.e = em.vars
	ctx.p = {}
	ctx.curves = em.d.curves
	em.age += delta
	em.vars.emitter_age = em.age
	if c.has("emitter_initialization"):
		_run_statements(c.emitter_initialization.get("per_update_expression", []), em.vars)
	if em.active:
		# Events timed by the emitter.
		if c.has("emitter_lifetime_events") and c.emitter_lifetime_events.has("timeline"):
			var tl: Dictionary = c.emitter_lifetime_events.timeline
			for k in tl:
				if not em.fired.has(k) and em.age >= float(k):
					em.fired[k] = true
					_fire(em, tl[k], em.pos)
		if c.has("emitter_rate_steady"):
			var rate := ctx.ev(c.emitter_rate_steady.get("spawn_rate", 1.0))
			var cap := ctx.ev(c.emitter_rate_steady.get("max_particles", 50.0))
			em.acc += rate * delta
			while em.acc >= 1.0:
				em.acc -= 1.0
				if em.parts.size() < cap:
					_spawn(em)
				ctx.e = em.vars
				ctx.p = {}
		if em.age >= em.life:
			if c.has("emitter_lifetime_looping") and em.age < em.dur:
				# Looping: starts over (and repeats the instant part) until its duration.
				em.loops += 1
				em.dur -= em.age
				em.age = 0.0
				em.fired = {}
				if c.has("emitter_rate_instant"):
					_spawn_n(em, int(ctx.ev(c.emitter_rate_instant.get("num_particles", 1.0))))
			else:
				em.active = false
				_emitter_event(em, "expiration_event")
	_update_particles(em, delta, cam)


func _update_particles(em: Dictionary, delta: float, cam: Camera3D) -> void:
	var c: Dictionary = em.d.comp
	var dyn: Dictionary = c.get("particle_motion_dynamic", {})
	var parametric: Dictionary = c.get("particle_motion_parametric", {})
	var col: Dictionary = c.get("particle_motion_collision", {})
	var bb: Dictionary = c.get("particle_appearance_billboard", {})
	var tint: Dictionary = c.get("particle_appearance_tinting", {})
	var tl: Dictionary = c.get("particle_lifetime_events", {}).get("timeline", {})
	var bucket = _bucket(em.d)
	var basis: Basis = em.basis
	var i := 0
	while i < em.parts.size():
		var p: Dictionary = em.parts[i]
		ctx.p = p
		p.particle_age += delta
		if p.particle_age >= p.particle_lifetime:
			_particle_event(em, p, "expiration_event")
			em.parts.remove_at(i)
			continue
		for k in tl:
			if not p._fired.has(k) and p.particle_age >= float(k):
				p._fired[k] = true
				_fire(em, tl[k], p._pos)
		if not parametric.is_empty() and parametric.has("relative_position"):
			p._pos = p._origin + basis * _flip(_vec(parametric.relative_position))
			if parametric.has("direction"):
				p._dir = (basis * _flip(_vec(parametric.direction))).normalized()
		else:
			var acc := basis * _flip(_vec(dyn.get("linear_acceleration", [0.0, 0.0, 0.0])))
			var drag := ctx.ev(dyn.get("linear_drag_coefficient", 0.0))
			p._vel += (acc - p._vel * drag) * delta
			p._pos += p._vel * delta
			var racc := ctx.ev(dyn.get("rotation_acceleration", 0.0))
			var rdrag := ctx.ev(dyn.get("rotation_drag_coefficient", 0.0))
			p._rrate += (racc - p._rrate * rdrag) * delta
			p._rot += p._rrate * delta
			if p._vel.length() > 0.001:
				p._dir = p._vel.normalized()
		if not col.is_empty() and col.get("enabled", true):
			var r := ctx.ev(col.get("collision_radius", 0.1))
			if p._pos.y - r < em.ground:
				if col.get("expire_on_contact", false):
					em.parts.remove_at(i)
					continue
				p._pos.y = em.ground + r
				if p._vel.y < 0.0:
					p._vel.y = -p._vel.y * ctx.ev(col.get("coefficient_of_restitution", 0.0))
				var cd := ctx.ev(col.get("collision_drag", 0.0))
				var h := Vector2(p._vel.x, p._vel.z).move_toward(Vector2.ZERO, cd * delta)
				p._vel.x = h.x
				p._vel.z = h.y
		if bucket != null and cam != null:
			_draw(bucket, em, p, bb, tint, cam)
		i += 1


# ---------------------------------------------------------------- drawing

func _bucket(d: Dictionary):
	if d.tex_res == null:
		return null
	return _bucket_tex(d.tex, d.tex_res, d.material)


func _bucket_tex(path: String, tex: Texture2D, material: String):
	var key: String = path + "|" + material
	if _buckets.has(key):
		return _buckets[key]
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE
	var mat := ShaderMaterial.new()
	mat.shader = _shader(material)
	mat.set_shader_parameter("tex", tex)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = 64
	mm.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 1000.0
	add_child(mi)
	var b := {"mm": mm, "n": 0}
	_buckets[key] = b
	return b


static func _shader(material: String) -> Shader:
	if _shaders.has(material):
		return _shaders[material]
	var mode := "blend_mix, depth_draw_never"
	var alpha := "ALPHA = c.a;"
	if material == "particles_add":
		mode = "blend_add, depth_draw_never"
	elif material == "particles_alpha":
		mode = "blend_mix, depth_draw_opaque"
		alpha = "ALPHA = c.a; ALPHA_SCISSOR_THRESHOLD = 0.5;"
	var s := Shader.new()
	s.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, %s;
uniform sampler2D tex : source_color, filter_nearest;
varying vec4 uvr;
void vertex() { uvr = INSTANCE_CUSTOM; }
void fragment() {
	vec4 c = texture(tex, uvr.xy + UV * uvr.zw) * COLOR;
	ALBEDO = c.rgb;
	%s
}
""" % [mode, alpha]
	_shaders[material] = s
	return s


func _draw(b: Dictionary, em: Dictionary, p: Dictionary, bb: Dictionary, tint: Dictionary, cam: Camera3D) -> void:
	var size: Array = bb.get("size", [0.1, 0.1])
	# Like Cobblemon (SnowstormParticle.kt): vertices at ±size / 1.5.
	var w := ctx.ev(size[0]) * 2.0 / 1.5
	var h := ctx.ev(size[1]) * 2.0 / 1.5
	if w <= 0.0 or h <= 0.0:
		return
	var pos: Vector3 = p._pos
	var cb := cam.global_basis
	var x := cb.x
	var y := cb.y
	var z := cb.z
	var mode: String = bb.get("facing", "rotate_xyz")
	match mode:
		"rotate_y", "lookat_y":
			z = cam.global_position - pos if mode == "lookat_y" else cb.z
			z.y = 0.0
			z = z.normalized() if z.length() > 0.001 else Vector3.BACK
			y = Vector3.UP
			x = y.cross(z)
		"lookat_xyz":
			z = (cam.global_position - pos).normalized()
			x = Vector3.UP.cross(z).normalized()
			y = z.cross(x)
		"lookat_direction", "direction_x", "direction_y", "direction_z":
			var d: Vector3 = p._dir if p._dir.length() > 0.001 else em.basis * Vector3.FORWARD
			var tc := (cam.global_position - pos).normalized()
			x = d
			z = (tc - d * d.dot(tc))
			z = z.normalized() if z.length() > 0.001 else cb.z
			y = z.cross(x)
		"emitter_transform_xy":
			x = em.basis.x
			y = em.basis.y
			z = em.basis.z
		"emitter_transform_xz":
			x = em.basis.x
			y = em.basis.z
			z = em.basis.y
		"emitter_transform_yz":
			x = em.basis.z
			y = em.basis.y
			z = em.basis.x
	if p._rot != 0.0 and mode in ["rotate_xyz", "lookat_xyz", "emitter_transform_xy", "emitter_transform_xz", "emitter_transform_yz", "rotate_y", "lookat_y"]:
		var r := deg_to_rad(p._rot)
		var nx := x * cos(r) + y * sin(r)
		var ny := y * cos(r) - x * sin(r)
		x = nx
		y = ny
	var tr := Transform3D(Basis(x * w, y * h, z), pos)
	# Texture coordinates (animation strip or fixed rect).
	var tw: float = bb.get("tw", 1.0)
	var th: float = bb.get("th", 1.0)
	var uvr := Color(0, 0, 1, 1)
	if bb.has("flip"):
		var f: Dictionary = bb.flip
		var maxf_ := maxi(1, int(ctx.ev(f.max)))
		var frame := 0
		if f.stretch:
			frame = int(p.particle_age / maxf(p.particle_lifetime, 0.001) * maxf_)
		else:
			frame = int(p.particle_age * float(f.fps))
		frame = frame % maxf_ if f.loop else mini(frame, maxf_ - 1)
		var base: Array = f.base
		var u := ctx.ev(base[0]) + float(f.step[0]) * frame
		var v := ctx.ev(base[1]) + float(f.step[1]) * frame
		uvr = Color(u / tw, v / th, float(f.size[0]) / tw, float(f.size[1]) / th)
	elif bb.has("uv"):
		uvr = Color(ctx.ev(bb.uv[0]) / tw, ctx.ev(bb.uv[1]) / th, ctx.ev(bb.uv_size[0]) / tw, ctx.ev(bb.uv_size[1]) / th)
	var color := Color.WHITE
	if tint.has("grad"):
		color = _gradient(tint.grad, ctx.ev(tint.interp))
	elif tint.has("hex"):
		color = _hex(tint.hex)
	elif tint.has("rgba"):
		var a: Array = tint.rgba
		color = Color(ctx.ev(a[0]), ctx.ev(a[1]), ctx.ev(a[2]), ctx.ev(a[3]) if a.size() > 3 else 1.0)
	_put(b, tr, color, uvr)


static func _hex(s: String) -> Color:
	# Bedrock: #AARRGGBB
	var h := s.trim_prefix("#")
	if h.length() == 8:
		return Color(("%s%s" % [h.substr(2), h.substr(0, 2)]))
	return Color(h)


static func _gradient(g: Array, t: float) -> Color:
	if g.is_empty():
		return Color.WHITE
	if t <= float(g[0][0]):
		return _hex(g[0][1])
	for i in g.size() - 1:
		var a: Array = g[i]
		var b: Array = g[i + 1]
		if t <= float(b[0]):
			var k := (t - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.0001)
			return _hex(a[1]).lerp(_hex(b[1]), k)
	return _hex(g[-1][1])
