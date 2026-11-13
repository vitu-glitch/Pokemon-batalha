class_name FloatingStadium
extends NightStadium
## A stadium whose battle platform floats over a deep pit, in the spirit of the stadium
## stages of platform fighters. Drawn by script in the game's style (16 px per meter
## pixels, hard edges). No mesh or texture from any game is here.
##
## What gives it its look:
##   · the platform floats high over a deep, dark pit, on top of a pillar that goes down
##     to the water at the bottom;
##   · the stands start far away and below the platform: between them, the void;
##   · under the deck, stacked layers of white and grey plating with red panels;
##   · the floodlights hang on a truss band at the platform's height and ONLY light the
##     platform and the battle (they do not see the pit or the stands): everything else
##     stays dark;
##   · behind, a dark block with the giant screen, a city and mountains.
## The battle ground is still y = 0 and the field is 36 × 22. There are no walls: the
## platform's edge is the limit and falling off is a KO (Arena.void_y).

const PLAT_X := 24.0          # half-sides of the platform: field + trainer zones
const PLAT_Z := 13.5
const PLAT_R := 6.0           # corner chamfer (octagon)
const PILLAR_R := 5.5
const WATER_Y := -31.0        # bottom of the pit
const BOWL_A := 50.0          # oval of the pit wall, where the stands start
const BOWL_B := 38.0
const BOWL_R := 16.0
const FIRST_ROW := -20.0      # the stands start 20 m below the platform
const ROWS_PER_SECTION := 10
const BOWL_ROW_DEPTH := 0.9
const BOWL_ROW_RISE := 0.85
const AISLE := 3.0
const OUTSIDE_Y := -22.0      # ground outside the stadium
const TRAINER_X := PLAT_X + 7.0     # each trainer's own small platform, apart from the deck
const VOID_Y := -28.0         # below this, a fighter that fell off is out: low, so flyers
                              # (Charizard, Gengar) have time to fly back up
## Visual layers: the platform's floodlights see neither of them, so the pit, the stands
## and the city stay in the dark (fighters, effects and the platform are on layer 1).
const LAYER_DARK := 8
const LAYER_SCREEN := 16      # the giant screen's block, lit only by its own two lights

var _jumbo_mat: ShaderMaterial
var _tv_cam: Camera3D
var _fireworks: Array = []
var _firework_i := 0
var _fireworks_t := 0.0


func build() -> void:
	void_y = VOID_Y
	_night_environment()
	_tune_environment()
	_platform()
	_pillar()
	_platform_collider()
	_trainer_platforms()
	var start := get_child_count()
	_pit()
	_bowl_stands()
	_floodlight_band()
	_background()
	_prepare_fireworks()
	crowd = Crowd.new()
	add_child(crowd)
	crowd.build(self)
	for i in range(start, get_child_count()):
		_set_layers(get_child(i), LAYER_DARK)
	# The screen goes on its own layer.
	start = get_child_count()
	_giant_screen()
	for i in range(start, get_child_count()):
		_set_layers(get_child(i), LAYER_SCREEN)


func _set_layers(n: Node, layers: int) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).layers = layers
	for c in n.get_children():
		_set_layers(c, layers)


func _process(delta: float) -> void:
	super(delta)
	# The TV camera sweeps slowly from side to side.
	if _tv_cam:
		_tv_cam.position = Vector3(sin(_t * 0.12) * 14.0, 10.0, 40.0)
		_tv_cam.look_at(Vector3(sin(_t * 0.12) * 4.0, 0.0, 0.0))


## Inside the platform's octagon (with "margin" to spare).
func inside(p: Vector3, margin := 0.0) -> bool:
	var q := Vector2(absf(p.x), absf(p.z))
	return q.x < PLAT_X - margin and q.y < PLAT_Z - margin and q.x + q.y < PLAT_X + PLAT_Z - PLAT_R - margin * 1.414


## A green-blue night, without the purple band on the horizon, and reflections on the
## pit's water.
func _tune_environment() -> void:
	night_sky.set_shader_parameter("top", Color(0.006, 0.028, 0.04))
	night_sky.set_shader_parameter("mid", Color(0.012, 0.05, 0.068))
	night_sky.set_shader_parameter("low", Color(0.03, 0.075, 0.09))
	night_sky.set_shader_parameter("horizon", Color(0.05, 0.1, 0.12))
	night_env.ssr_enabled = true
	night_env.ssr_max_steps = 48
	night_env.volumetric_fog_albedo = Color(0.55, 0.7, 0.75)
	night_env.volumetric_fog_density = 0.004


# ---------------------------------------------------------------- crowd hooks

func crowd_oval() -> Vector3:
	return Vector3(BOWL_A, BOWL_B, BOWL_R)


func crowd_rows() -> Array:
	var out: Array = []
	var d := 0.6
	var y := FIRST_ROW
	for section in 2:
		for k in ROWS_PER_SECTION:
			y += BOWL_ROW_RISE
			out.append([d + BOWL_ROW_DEPTH * 0.5, y, section])
			d += BOWL_ROW_DEPTH
		if section == 0:
			d += AISLE
			y += 1.5
	return out


## The crowd gets going: the screen brightens and, when it is really loud, fireworks go
## up, closer together the louder it gets.
func on_hype(hype: float, _hp: Array) -> void:
	_jumbo_mat.set_shader_parameter("hype", hype)
	if hype < 0.45:
		_fireworks_t = 0.0
		return
	_fireworks_t -= get_process_delta_time()
	if _fireworks_t <= 0.0:
		_launch_firework()
		_fireworks_t = lerpf(1.8, 0.4, (hype - 0.45) / 0.55)


# ---------------------------------------------------------------- mesh pieces

## Points of a rounded rectangle's outline at height y. With seg = 1 the corners are
## chamfers (an octagon), like the platform.
func _loop(a: float, b: float, r: float, y: float, seg: int) -> Array:
	var out: Array = []
	for p in _ring_path(a, b, r, seg):
		out.append(p[0] + Vector3.UP * y)
	return out


## A triangle with its normal; the winding is swapped so the face looks toward n.
func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3) -> void:
	if (b - a).cross(c - a).dot(n) > 0.0:
		var t := b
		b = c
		c = t
	for v in [a, b, c]:
		st.set_normal(n)
		st.add_vertex(v)


## Joins two loops with the same number of points with flat faces. "k" says where they
## should face: x outward (radial), y upward.
func _loft(a: Array, b: Array, mat: Material, k := Vector2(1.0, 0.0)) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in a.size():
		var j := (i + 1) % a.size()
		var a0: Vector3 = a[i]
		var a1: Vector3 = a[j]
		var b0: Vector3 = b[i]
		var b1: Vector3 = b[j]
		var center := (a0 + a1 + b0 + b1) * 0.25
		var wanted := Vector3(center.x, 0.0, center.z).normalized() * k.x + Vector3.UP * k.y
		var n := (a1 - a0).cross(b0 - a0)
		if n.length() < 0.0001:
			n = (b1 - b0).cross(b0 - a0)
		n = n.normalized()
		if n.dot(wanted) < 0.0:
			n = -n
		_tri(st, a0, a1, b1, n)
		_tri(st, a0, b1, b0, n)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	add_child(mi)


## Flat cap of a loop (a fan from the center).
func _cap(edge: Array, mat: Material, n: Vector3) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := Vector3(0.0, (edge[0] as Vector3).y, 0.0)
	for i in edge.size():
		_tri(st, c, edge[i], edge[(i + 1) % edge.size()], n)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	add_child(mi)
	return mi


func _multi(mesh: Mesh, transforms: Array, mat: Material) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for k in transforms.size():
		mm.set_instance_transform(k, transforms[k])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	add_child(mi)


# ---------------------------------------------------------------- platform

const SH_PLATFORM := """
shader_type spatial;
render_mode cull_back;
// The platform's deck in pixels (16 px/m): a speckled green field with its lines, a
// split Poké Ball (white and red) in the middle, yellow triangles around it and red ones
// in the corners; outside the field, dark plating in panels with a red trim, the white
// edge and each trainer's zone at the ends.
uniform vec2 field = vec2(18.0, 11.0);
uniform vec3 plat = vec3(24.0, 13.5, 6.0);
uniform vec3 grass : source_color = vec3(0.2, 0.55, 0.22);
uniform vec3 speck : source_color = vec3(0.24, 0.59, 0.25);
uniform vec3 plate : source_color = vec3(0.13, 0.14, 0.16);
uniform vec3 white : source_color = vec3(0.9, 0.91, 0.92);
uniform vec3 red : source_color = vec3(0.86, 0.16, 0.14);
uniform vec3 yellow : source_color = vec3(0.95, 0.85, 0.2);
uniform vec3 black : source_color = vec3(0.06, 0.06, 0.07);
uniform vec3 pink : source_color;
uniform vec3 cyan : source_color;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float sd_box(vec2 p, vec2 h) { vec2 q = abs(p) - h; return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0); }
// Octagon: a rectangle with its corners cut at 45° (chamfer c).
float octo(vec2 p, vec2 h, float c) { vec2 q = abs(p); return max(max(q.x - h.x, q.y - h.y), (q.x + q.y - (h.x + h.y - c)) * 0.7071); }
float stroke(float d, float w) { return step(abs(d), w * 0.5); }
// A triangle pointing along dir (center o, size s).
float tri_mask(vec2 p, vec2 o, vec2 dir, float s) {
	vec2 q = p - o;
	vec2 side_v = vec2(-dir.y, dir.x);
	float a = dot(q, dir);
	float b = abs(dot(q, side_v));
	return step(-s, a) * step(a, s) * step(b, (s - a) * 0.6);
}
void fragment() {
	vec2 cell = floor(wp.xz * 16.0);
	vec2 p = (cell + 0.5) / 16.0;
	float g = hash(cell);
	// Soft grain that fades out where a cell is smaller than a screen pixel (far away), so
	// the deck never turns into static.
	float near = 1.0 - clamp(fwidth(wp.x) * 16.0 - 0.5, 0.0, 1.0);
	float grain = mix(1.0, g < 0.1 ? 0.94 : (g > 0.93 ? 1.04 : 1.0), near);
	vec3 c;
	float glow = 0.0;
	float dc = sd_box(p, field);
	if (dc < 0.0) {
		// Speckled grass, no stripes.
		c = mix(grass, speck, step(0.88, g) * near) * grain;
		float l = max(stroke(dc + 0.1, 0.16), stroke(p.x, 0.16));
		float r = length(p);
		if (r < 4.6) {
			c = (p.x > 0.0 ? red : white) * grain;
			if (abs(p.x) < 0.3 || r > 4.35) c = black;
			if (r < 1.45) c = r < 1.05 ? white * grain : black;
			l = 0.0;
		}
		// Yellow triangles around the Poké Ball, pointing at it.
		for (float i = 0.0; i < 4.0; i += 1.0) {
			float a = i * 1.5708 + 0.7854;
			vec2 d = vec2(cos(a), sin(a));
			c = mix(c, yellow * grain, tri_mask(p, d * 7.2, -d, 0.55));
		}
		// Red triangles in the field's four corners.
		vec2 e = field - vec2(1.2);
		vec2 q = abs(p);
		c = mix(c, red * grain, tri_mask(q, e, normalize(vec2(-1.0, -1.0)), 0.9) * step(0.0, -dc));
		c = mix(c, white * grain, l);
		glow = l;
	} else {
		// Dark plating in 2 m panels, a red trim by the field and the white edge.
		vec2 seam = abs(fract(p / 2.0) - 0.5);
		c = plate * grain * (max(seam.x, seam.y) > 0.46 ? 0.6 : 1.0);
		if (dc < 0.45) c = red * grain;
		if (octo(p, plat.xy, plat.z) > -1.0) c = white * grain;
		for (float s = -1.0; s <= 1.0; s += 2.0) {
			vec2 q = p - vec2(s * (field.x + 3.0), 0.0);
			float dz = sd_box(q, vec2(1.6, 2.8));
			if (dz < 0.0) c = (s < 0.0 ? pink : cyan) * 0.5 * grain;
			float lz = max(stroke(dz, 0.14), stroke(q.x, 0.14) * step(abs(q.y), 2.8));
			c = mix(c, white * grain, lz);
			glow = max(glow, lz);
		}
	}
	ALBEDO = c;
	// Almost matte: the floodlights must not leave shiny patches on it.
	ROUGHNESS = 0.95;
	SPECULAR = 0.15;
	EMISSION = white * glow * 0.3;
}
"""


## The platform: the painted deck and, below it, the white edge, a dark slot, a white
## slab with red panels between posts, another slot, a grey slab and a dark cone down to
## the pillar's collar.
func _platform() -> void:
	var seg := 1
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SH_PLATFORM
	sm.shader = sh
	sm.set_shader_parameter("field", Vector2(LENGTH * 0.5, WIDTH * 0.5))
	sm.set_shader_parameter("plat", Vector3(PLAT_X, PLAT_Z, PLAT_R))
	sm.set_shader_parameter("pink", C_PINK)
	sm.set_shader_parameter("cyan", C_CYAN)
	var edge := _loop(PLAT_X, PLAT_Z, PLAT_R, 0.0, seg)
	_cap(edge, sm, Vector3.UP)
	var white := _material(Color("dfe3e7"), 0.6, 0.2, "metal")
	var grey := _material(Color("8a929b"), 0.5, 0.5, "metal")
	var dark := _material(Color("1c2026"), 0.5, 0.5, "metal")
	# [half-side x, half-side z, top y, bottom y, face material]
	var layers_down := [
		[PLAT_X, PLAT_Z, 0.0, -1.4, white],
		[PLAT_X - 1.6, PLAT_Z - 1.6, -1.4, -2.0, dark],
		[PLAT_X - 0.7, PLAT_Z - 0.7, -2.0, -3.0, white],
		[PLAT_X - 2.6, PLAT_Z - 2.6, -3.0, -3.6, dark],
		[PLAT_X - 1.8, PLAT_Z - 1.8, -3.6, -4.5, grey],
	]
	var prev: Array = []
	for l in layers_down:
		var top := _loop(l[0], l[1], PLAT_R, l[2], seg)
		var bottom := _loop(l[0], l[1], PLAT_R, l[3], seg)
		if not prev.is_empty():
			# Step between one layer and the next: a horizontal face.
			var k := -1.0 if (l[0] as float) < (prev[0][0] as float) else 1.0
			_loft(prev[1], top, dark, Vector2(0.0, k))
		_loft(top, bottom, l[4], Vector2(1.0, 0.0))
		prev = [l, bottom]
	var collar := _loop(9.0, 9.0, 9.0, -7.0, seg + 2)
	var last := _loop(PLAT_X - 1.8, PLAT_Z - 1.8, PLAT_R, -4.5, seg + 2)
	_loft(last, collar, dark, Vector2(1.0, -1.0))
	# White posts and lit red panels on the middle slab, set face by face of the octagon
	# (a post at each vertex and the panels between posts), so on the chamfers they sit
	# flush instead of floating.
	var posts: Array = []
	var panels: Array = []
	var slab := _loop(PLAT_X - 0.7, PLAT_Z - 0.7, PLAT_R, 0.0, seg)
	for i in slab.size():
		var v0: Vector3 = slab[i]
		var v1: Vector3 = slab[(i + 1) % slab.size()]
		var side_len := v0.distance_to(v1)
		var n := (v1 - v0).cross(Vector3.UP).normalized()
		if n.dot(Vector3((v0 + v1).x, 0.0, (v0 + v1).z)) < 0.0:
			n = -n
		var b := Basis.looking_at(-n, Vector3.UP)
		var spans := maxi(1, int(side_len / 6.0))
		for k in spans:
			var t0 := float(k) / spans
			var middle := v0.lerp(v1, (k + 0.5) / spans)
			posts.append(Transform3D(b * Basis.from_scale(Vector3(1.0, 3.4, 0.5)), v0.lerp(v1, t0) + n * 0.2 + Vector3.DOWN * 2.6))
			var w := minf(2.6, side_len / spans - 1.6)
			if w > 0.6:
				panels.append(Transform3D(b * Basis.from_scale(Vector3(w, 0.6, 0.06)), middle + n * 0.03 + Vector3.DOWN * 2.5))
	_boxes(posts, white)
	_boxes(panels, _glowing(Color(1.0, 0.04, 0.04), 1.3))


## What fighters stand on: the deck's octagon, 1.4 m thick, on the world layer (fighters,
## projectiles and the camera). Nothing else stops them: off the edge is the void.
func _platform_collider() -> void:
	var pts := PackedVector3Array()
	for p in _loop(PLAT_X, PLAT_Z, PLAT_R, 0.0, 1):
		pts.append(p)
		pts.append(p + Vector3.DOWN * 1.4)
	var shape := ConvexPolygonShape3D.new()
	shape.points = pts
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	add_child(body)


## Each trainer's platform: a small white octagon with their side's color on top and a
## glow underneath, 7 m off the deck's end. Nobody can get to it: it has no collision, and
## a tall invisible wall (layer 3, fighters only) round it stops flyers and jumps. It does
## not touch projectiles or the camera.
func trainer_spot(side: float) -> Vector3:
	return Vector3(side * TRAINER_X, 0.0, 0.0)


func _trainer_platforms() -> void:
	var white := _material(Color("dfe3e7"), 0.6, 0.2, "metal")
	var dark := _material(Color("1c2026"), 0.5, 0.5, "metal")
	for side in [-1.0, 1.0]:
		var at := Vector3(side * TRAINER_X, 0.0, 0.0)
		var col: Color = C_PINK if side < 0.0 else C_CYAN
		var parts := [[2.2, 1.7, 0.6, -0.3, white], [2.0, 2.0, 0.06, 0.02, _material(col.darkened(0.25), 0.8)],
			[1.6, 0.9, 0.5, -0.85, dark], [0.8, 0.5, 0.12, -1.16, _glowing(col, 2.5)]]
		for p in parts:
			var mi := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = p[0]
			cm.bottom_radius = p[1]
			cm.height = p[2]
			cm.radial_segments = 8
			cm.rings = 1
			mi.mesh = cm
			mi.material_override = p[4]
			mi.position = at + Vector3.UP * p[3]
			mi.rotation.y = PI / 8.0
			add_child(mi)
		var glow := OmniLight3D.new()
		glow.light_color = col
		glow.light_energy = 1.5
		glow.omni_range = 4.0
		glow.position = at + Vector3.DOWN * 1.6
		add_child(glow)
		_box_collider(at + Vector3.UP * 15.0, Vector3(9.0, 120.0, 9.0), 4)


const SH_PILLAR := """
shader_type spatial;
// White pillar in panels, with two dark zigzag bands.
uniform vec3 grey : source_color = vec3(0.78, 0.8, 0.83);
uniform vec3 dark : source_color = vec3(0.14, 0.16, 0.2);
uniform float band_a = 9.5;
uniform float band_b = -2.0;
varying float y;
void vertex() { y = VERTEX.y; }
void fragment() {
	float u = floor(UV.x * 128.0) / 128.0;
	float v = floor(y * 16.0) / 16.0;
	vec3 c = grey;
	if (fract(u * 16.0) < 0.06) c *= 0.78;
	float zig = abs(fract(u * 24.0) - 0.5) * 1.4;
	if ((v > band_a - 1.0 + zig && v < band_a + zig) || (v > band_b - 1.0 + zig && v < band_b + zig)) c = dark;
	ALBEDO = c;
	ROUGHNESS = 0.6;
	METALLIC = 0.3;
}
"""


## A white collar under the platform and the pillar, going down to the pit's water.
func _pillar() -> void:
	var collar := MeshInstance3D.new()
	var cc := CylinderMesh.new()
	cc.top_radius = 8.0
	cc.bottom_radius = 7.0
	cc.height = 1.6
	cc.radial_segments = 16
	collar.mesh = cc
	collar.material_override = _material(Color("dfe3e7"), 0.6, 0.2, "metal")
	collar.position = Vector3(0, -7.6, 0)
	add_child(collar)
	var h := -8.4 - (WATER_Y - 1.0)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = PILLAR_R
	cm.bottom_radius = PILLAR_R
	cm.height = h
	cm.radial_segments = 16
	cm.rings = 1
	mi.mesh = cm
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SH_PILLAR
	sm.shader = sh
	sm.set_shader_parameter("band_a", h * 0.5 - 2.0)
	sm.set_shader_parameter("band_b", h * 0.5 - 12.0)
	mi.material_override = sm
	mi.position = Vector3(0, -8.4 - h * 0.5, 0)
	add_child(mi)


# ---------------------------------------------------------------- pit and stands

const SH_WATER := """
shader_type spatial;
// Dark water at the bottom of the pit: pixel ripples that change once a second. The
// reflections come from the environment (screen-space reflections), not a filter.
uniform vec3 water : source_color = vec3(0.01, 0.03, 0.05);
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void fragment() {
	vec2 cell = floor(wp.xz * 3.0);
	float t = floor(TIME);
	float o = sin(cell.x * 0.7 + cell.y * 0.4 + t * 0.6) + sin(cell.y * 1.1 - t * 0.5);
	vec3 n = normalize(vec3(step(1.2, o) * 0.08 - 0.04, 1.0, step(1.2, -o) * 0.08 - 0.04));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	ALBEDO = water * (0.9 + 0.2 * hash(cell));
	ROUGHNESS = 0.12;
	SPECULAR = 0.6;
}
"""


## The pit: dark water at the bottom and a tall, smooth wall up to the first row, with a
## blue band and a white parapet on top. Between the wall and the platform, the void.
func _pit() -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2((BOWL_A + 2.0) * 2.0, (BOWL_B + 2.0) * 2.0)
	mi.mesh = pm
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SH_WATER
	sm.shader = sh
	mi.material_override = sm
	mi.position = Vector3(0, WATER_Y, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var o := crowd_oval()
	_ring(PackedVector2Array([Vector2(0.0, WATER_Y - 1.0), Vector2(0.0, FIRST_ROW)]), _material(Color("5a636c"), 0.9, 0.0, "concrete"), true, o)
	_ring(PackedVector2Array([Vector2(-0.03, FIRST_ROW - 3.2), Vector2(-0.03, FIRST_ROW - 1.6)]), _material(Color("2c4f8a"), 0.6, 0.2, "metal"), false, o)
	_ring(PackedVector2Array([Vector2(-0.04, FIRST_ROW - 0.35), Vector2(-0.04, FIRST_ROW + 0.05)]), _material(Color("dfe3e7"), 0.6, 0.2, "metal"), false, o)


## End of the stands: [d, y] of the top edge, where the truss band goes.
func _stands_top() -> Vector2:
	var f: Array = crowd_rows()[-1]
	return Vector2(f[0] + BOWL_ROW_DEPTH * 0.5, f[1])


## Stands in two sections with an aisle, a dark front on the upper section and a facade
## behind, down to the outside ground.
func _bowl_stands() -> void:
	var o := crowd_oval()
	var profile := PackedVector2Array([Vector2(0.0, FIRST_ROW), Vector2(0.6, FIRST_ROW)])
	var d := 0.6
	var y := FIRST_ROW
	var aisle := Vector2.ZERO
	for section in 2:
		for k in ROWS_PER_SECTION:
			profile.append(Vector2(d, y + BOWL_ROW_RISE))
			y += BOWL_ROW_RISE
			d += BOWL_ROW_DEPTH
			profile.append(Vector2(d, y))
		if section == 0:
			aisle = Vector2(d, y)
			d += AISLE
			profile.append(Vector2(d, y))
			y += 1.5
			profile.append(Vector2(d, y))
	profile.append(Vector2(d, y + 1.2))
	profile.append(Vector2(d + 2.0, y + 1.2))
	profile.append(Vector2(d + 2.0, OUTSIDE_Y))
	_ring(profile, _material(Color("6c747c"), 0.92, 0.0, "concrete"), true, o)
	_ring(PackedVector2Array([Vector2(aisle.x + 0.05, aisle.y), Vector2(aisle.x + 0.05, aisle.y + 1.0)]), _material(Color("dfe3e7"), 0.6, 0.2, "metal"), true, o)
	_ring(PackedVector2Array([Vector2(aisle.x + AISLE - 0.03, aisle.y + 0.2), Vector2(aisle.x + AISLE - 0.03, aisle.y + 1.3)]), _material(Color("23272d"), 0.5, 0.3, "metal"), false, o)


# ---------------------------------------------------------------- floodlights

## A white truss band all the way round above the stands, at the platform's height, with
## four batteries of round floodlights. The floodlights do not see LAYER_DARK: they light
## the platform and the battle and leave the pit and the stands dark. A few weak lights
## wash the stands.
func _floodlight_band() -> void:
	var metal := _material(Color("cfd4da"), 0.45, 0.5, "metal")
	var housing := _material(Color("1a1d22"), 0.4, 0.6, "metal")
	var face := _glowing(Color(0.97, 0.98, 1.0), 9.0)
	var o := crowd_oval()
	var top := _stands_top()
	var dd := top.x + 1.0
	var yb := top.y + 1.2
	var ya := yb + 3.0
	for y in [yb, ya]:
		_ring(PackedVector2Array([Vector2(dd - 0.15, y - 0.15), Vector2(dd - 0.15, y + 0.15), Vector2(dd + 0.15, y + 0.15), Vector2(dd + 0.15, y - 0.15), Vector2(dd - 0.15, y - 0.15)]), metal, true, o)
	var bars: Array = []
	var nodes := spots(o.x + dd, o.y + dd, o.z + dd, 3.0)
	for i in nodes.size():
		var p: Vector3 = nodes[i][0]
		var q: Vector3 = nodes[(i + 1) % nodes.size()][0]
		bars.append([p + Vector3.UP * yb, q + Vector3.UP * ya])
		bars.append([p + Vector3.UP * ya, q + Vector3.UP * yb])
	_bars(bars, 0.16, metal)
	# Four batteries: two on each side of the screen and two opposite.
	var tube := CylinderMesh.new()
	tube.top_radius = 0.6
	tube.bottom_radius = 0.6
	tube.height = 0.6
	tube.radial_segments = 10
	var disc := CylinderMesh.new()
	disc.top_radius = 0.5
	disc.bottom_radius = 0.5
	disc.height = 0.06
	disc.radial_segments = 10
	var axis := Basis(Vector3.RIGHT, PI * 0.5)
	var bodies: Array = []
	var faces: Array = []
	var frames: Array = []
	var battle_mask := 0xFFFFF & ~(LAYER_DARK | LAYER_SCREEN)
	for sz in [-1.0, 1.0]:
		for sx in [-1.0, 1.0]:
			# The band's point on each quarter's diagonal.
			var dir := Vector3(sx * 0.62, 0.0, sz * 0.78).normalized()
			var center := Vector3.ZERO
			for p in nodes:
				var v: Vector3 = p[0]
				if v.normalized().dot(dir) > center.normalized().dot(dir) or center == Vector3.ZERO:
					center = v
			center += Vector3.UP * (ya + 2.4)
			var b := Basis.looking_at((Vector3(sx * 6.0, 0.0, 0.0) - center).normalized(), Vector3.UP)
			var corners := [center - b.x * 8.0 - b.y * 2.2, center + b.x * 8.0 - b.y * 2.2, center + b.x * 8.0 + b.y * 2.2, center - b.x * 8.0 + b.y * 2.2]
			for k in 4:
				frames.append([corners[k], corners[(k + 1) % 4]])
			for s in [-6.0, 6.0]:
				var foot: Vector3 = center + b.x * s - b.y * 2.2
				var support: Vector3 = nodes[0][0]
				for p in nodes:
					var w: Vector3 = p[0]
					if Vector2(w.x - foot.x, w.z - foot.z).length() < Vector2(support.x - foot.x, support.z - foot.z).length():
						support = w
				frames.append([foot, support + Vector3.UP * ya])
			# The battery's spill lights its own frame and the band below.
			var spill := OmniLight3D.new()
			spill.position = center - b.z * 2.5
			spill.omni_range = 11.0
			spill.light_energy = 2.0
			spill.light_color = Color(0.85, 0.9, 1.0)
			spill.light_volumetric_fog_energy = 0.0
			spill.light_cull_mask = LAYER_DARK
			add_child(spill)
			for v in [-1.1, 1.1]:
				for i in 8:
					var pos: Vector3 = center + b.x * (-7.0 + i * 2.0) + b.y * v - b.z * 0.4
					bodies.append(Transform3D(b * axis, pos))
					faces.append(Transform3D(b * axis, pos - b.z * 0.31))
			var targets := [Vector3(sx * 5.0, 0.0, sz * 4.0), Vector3(sx * 17.0, 0.0, sz * 6.0), Vector3(sx * 12.0, 0.0, -sz * 5.0)]
			for i in 3:
				var f := SpotLight3D.new()
				f.position = center + b.x * (-5.0 + i * 5.0) - b.z * 1.0
				add_child(f)
				f.look_at(targets[i], Vector3.UP)
				f.spot_angle = 16.0
				f.spot_angle_attenuation = 0.6
				f.spot_range = 130.0
				f.spot_attenuation = 0.4
				f.light_energy = 4.0
				f.light_color = Color(0.94, 0.96, 1.0)
				f.light_volumetric_fog_energy = 0.35
				f.light_cull_mask = battle_mask
				f.shadow_enabled = i == 0
	_bars(frames, 0.3, metal)
	_multi(tube, bodies, housing)
	_multi(disc, faces, face)
	# Weak lights from the band toward the stands: the people show, but in the half-dark.
	for p in spots(o.x + dd, o.y + dd, o.z + dd, 24.0):
		var l := SpotLight3D.new()
		l.position = p[0] + Vector3.UP * (ya + 0.5) - p[1] * 0.5
		add_child(l)
		l.look_at(p[0] - p[1] * 9.0 + Vector3.UP * (FIRST_ROW + 8.0), Vector3.UP)
		l.spot_angle = 50.0
		l.spot_range = 30.0
		l.light_energy = 1.0
		l.light_color = Color(0.7, 0.8, 1.0)
		l.light_volumetric_fog_energy = 0.0
		l.light_cull_mask = LAYER_DARK


# ---------------------------------------------------------------- giant screen

const SH_JUMBO := """
shader_type spatial;
render_mode unshaded, cull_back;
// Giant screen: the TV camera's picture in fat LEDs (each LED is one pixel of the
// picture, with its dark grid).
uniform sampler2D image : source_color, filter_nearest;
uniform vec2 leds = vec2(192.0, 108.0);
uniform float hype = 0.0;
void fragment() {
	vec2 uvp = (floor(UV * leds) + 0.5) / leds;
	vec3 c = texture(image, uvp).rgb;
	vec2 g = fract(UV * leds);
	c *= 1.0 - 0.45 * step(0.78, max(g.x, g.y));
	ALBEDO = c * (1.0 + hype * 0.4);
}
"""


## A dark block behind the far end of the stands with the giant screen: a frame with
## rounded corners, red arrows above and below, and two side wings with slots and a drum.
## It shows the battle live from a TV camera.
func _giant_screen() -> void:
	var top := _stands_top()
	var z := -(BOWL_B + top.x + 5.0)
	var center := Vector3(0.0, 21.0, z)
	var block := _material(Color("3a4049"), 0.6, 0.3, "metal")
	var frame := _material(Color("23272d"), 0.5, 0.4, "metal")
	var light := _material(Color("9aa2ab"), 0.5, 0.4, "metal")
	var h := center.y + 19.0 - OUTSIDE_Y
	_box(Vector3(64.0, h, 12.0), Vector3(0, OUTSIDE_Y + h * 0.5, z - 6.5), block)
	_box(Vector3(60.0, 34.5, 1.2), center + Vector3(0, 0, -0.4), frame)
	_box(Vector3(58.0, 1.4, 1.4), center + Vector3(0, 17.6, -0.4), frame)
	_box(Vector3(58.0, 1.4, 1.4), center + Vector3(0, -17.6, -0.4), frame)
	for s in [-1.0, 1.0]:
		_box(Vector3(1.4, 33.0, 1.4), center + Vector3(s * 29.6, 0, -0.4), frame)
		# Side wings, lower, with light slots and a drum.
		var wing := Vector3(s * 44.0, OUTSIDE_Y + (h - 12.0) * 0.5, z - 4.0)
		_box(Vector3(18.0, h - 12.0, 10.0), wing, block)
		for k in 5:
			_box(Vector3(0.8, 14.0, 0.3), Vector3(s * (39.0 + k * 2.0), center.y - 6.0, z + 1.05), light)
		var drum := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 2.4
		cm.bottom_radius = 2.4
		cm.height = 7.0
		cm.radial_segments = 12
		drum.mesh = cm
		drum.material_override = frame
		drum.position = Vector3(s * 34.0, center.y - 4.0, z + 0.8)
		add_child(drum)
	var arrows: Array = []
	for y in [17.6, -17.6]:
		for s in [-1.0, 1.0]:
			arrows.append(Transform3D(Basis(Vector3.BACK, PI * 0.25) * Basis.from_scale(Vector3(1.4, 1.4, 0.1)), center + Vector3(s * 10.0, y, 0.4)))
	_boxes(arrows, _glowing(Color(1.0, 0.04, 0.04), 1.5))
	# The TV camera: its own environment, without light bounces or fog (it stays cheap).
	var sv := SubViewport.new()
	sv.size = Vector2i(192, 108)
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(sv)
	_tv_cam = Camera3D.new()
	_tv_cam.fov = 46.0
	_tv_cam.far = 500.0
	_tv_cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # moved in _process
	var env2: Environment = night_env.duplicate()
	env2.sdfgi_enabled = false
	env2.volumetric_fog_enabled = false
	env2.ssr_enabled = false
	_tv_cam.environment = env2
	sv.add_child(_tv_cam)
	_tv_cam.current = true
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(56.0, 31.5)
	q.mesh = qm
	_jumbo_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SH_JUMBO
	_jumbo_mat.shader = sh
	_jumbo_mat.set_shader_parameter("image", sv.get_texture())
	q.material_override = _jumbo_mat
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	q.position = center + Vector3(0, 0, 0.3)
	add_child(q)
	# Two lights from the opposite band that only see the block: it reads dark grey.
	for s in [-1.0, 1.0]:
		var f := SpotLight3D.new()
		f.position = Vector3(s * 30.0, 8.0, BOWL_B + top.x)
		add_child(f)
		f.look_at(Vector3(s * 20.0, center.y, z), Vector3.UP)
		f.spot_angle = 30.0
		f.spot_range = 200.0
		f.spot_attenuation = 0.2
		f.light_energy = 1.6
		f.light_color = Color(0.75, 0.85, 1.0)
		f.light_volumetric_fog_energy = 0.0
		f.light_cull_mask = LAYER_SCREEN


# ---------------------------------------------------------------- background

const SH_BUILDING := """
shader_type spatial;
// A building at night: dark concrete and pixel windows, some lit and some not.
uniform vec3 wall : source_color = vec3(0.05, 0.07, 0.09);
uniform vec3 window_light : source_color = vec3(1.0, 0.88, 0.6);
varying vec3 wp;
varying vec3 wn;
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void fragment() {
	vec2 q = vec2(abs(wn.x) > 0.5 ? wp.z : wp.x, wp.y);
	vec2 cell = floor(q / vec2(2.0, 3.0));
	vec2 f = fract(q / vec2(2.0, 3.0));
	float win = step(0.25, f.x) * step(f.x, 0.75) * step(0.3, f.y) * step(f.y, 0.75);
	if (abs(wn.y) > 0.5) win = 0.0;
	float lit = step(0.6, hash(cell + floor(wp.xz / 40.0)));
	ALBEDO = wall;
	EMISSION = window_light * win * lit * (0.3 + 0.5 * hash(cell * 1.7));
	ROUGHNESS = 0.9;
}
"""


## The outside ground, a tall ridge of mountains in silhouette and a city with lit windows
## that shows above the stands.
func _background() -> void:
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(900.0, 900.0)
	ground.mesh = pm
	ground.material_override = _material(Color("0b1014"), 1.0, 0.0, "concrete")
	ground.position = Vector3(0, OUTSIDE_Y, 0)
	add_child(ground)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 120
	var radius := 460.0
	var crest: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in n:
		var a := TAU * i / n
		var h := 95.0 + 40.0 * sin(a * 3.0 + 1.0) + 20.0 * sin(a * 7.0 + 2.0) + rng.randf() * 14.0
		crest.append(Vector3(cos(a) * radius, OUTSIDE_Y + h, sin(a) * radius))
	for i in n:
		var t0: Vector3 = crest[i]
		var t1: Vector3 = crest[(i + 1) % n]
		var b0 := Vector3(t0.x, OUTSIDE_Y, t0.z)
		var b1 := Vector3(t1.x, OUTSIDE_Y, t1.z)
		var inward := -Vector3((t0 + t1).x, 0.0, (t0 + t1).z).normalized()
		_tri(st, b0, b1, t1, inward)
		_tri(st, b0, t1, t0, inward)
	var ridge := MeshInstance3D.new()
	ridge.mesh = st.commit()
	ridge.material_override = _material(Color("0a161d"), 1.0, 0.0, "plain")
	add_child(ridge)
	var building := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SH_BUILDING
	building.shader = sh
	for i in 110:
		var a := rng.randf_range(0.0, TAU)
		var r := rng.randf_range(230.0, 380.0)
		var dims := Vector3(rng.randf_range(12.0, 26.0), rng.randf_range(24.0, 52.0), rng.randf_range(12.0, 26.0))
		var mi := _box(dims, Vector3(cos(a) * r, OUTSIDE_Y + dims.y * 0.5, sin(a) * r), building)
		mi.rotation.y = -a


# ---------------------------------------------------------------- fireworks

func _prepare_fireworks() -> void:
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(0.7, 0.8))
	curve.add_point(Vector2(1.0, 0.0))
	var scale_tex := CurveTexture.new()
	scale_tex.curve = curve
	for i in 6:
		var p := GPUParticles3D.new()
		p.emitting = false
		p.one_shot = true
		p.amount = 90
		p.lifetime = 2.2
		p.explosiveness = 1.0
		p.visibility_aabb = AABB(Vector3(-20, -20, -20), Vector3(40, 40, 40))
		var pm := ParticleProcessMaterial.new()
		pm.direction = Vector3.UP
		pm.spread = 180.0
		pm.initial_velocity_min = 8.0
		pm.initial_velocity_max = 12.0
		pm.gravity = Vector3(0, -4.0, 0)
		pm.damping_min = 1.5
		pm.damping_max = 2.5
		pm.scale_curve = scale_tex
		p.process_material = pm
		var q := QuadMesh.new()
		q.size = Vector2(0.9, 0.9)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.vertex_color_use_as_albedo = true
		q.material = m
		p.draw_pass_1 = q
		add_child(p)
		_fireworks.append(p)


func _launch_firework() -> void:
	var p: GPUParticles3D = _fireworks[_firework_i % _fireworks.size()]
	_firework_i += 1
	p.position = Vector3(randf_range(-60.0, 60.0), randf_range(45.0, 65.0), randf_range(-90.0, -20.0))
	var col: Color = [C_PINK, C_CYAN, Color(1.0, 0.85, 0.4), Color(0.95, 0.95, 1.0)].pick_random()
	(p.process_material as ParticleProcessMaterial).color = Color(col.r * 4.0, col.g * 4.0, col.b * 4.0)
	p.restart()
