class_name NightStadium
extends Arena
## Night stadium, drawn by script in the game's style: smooth low-poly shapes, 16 px per
## meter pixel textures, hard edges. Its proportions come from measuring a real stadium
## from the games (cross-section, plan and palette) and scaling it ×0.273 so its field
## lines match ours (36 × 22). No mesh or texture from any game is here.
##
## Stands profile (outward distance from the wall, height):
##   2.2 m wall · three tiers of rows with landings up to 8.8 m · an 8 m concourse ·
##   an upper tier over the concourse · a strip of pink LED glass up to 24.5 m ·
##   a chevron facade outside. A Camp Nou style roof with a ring of floodlights at its
##   edge leaves the field open to the sky.
## The crowd and its director live in crowd.gd; the battle feeds them through on_hit(),
## on_dodge(), on_ko() and on_rematch().
## Fighters stay inside the cyan neon line drawn on the ground; projectiles fly on until
## the real wall.

const WALL_A := 22.6          # X half-side of the wall's oval (lines + 4.6 m)
const WALL_B := 16.7          # Z half-side (lines + 5.7 m)
const WALL_R := 12.0          # corner radius: almost an oval
const WALL_H := 2.2
const ROW_D := 0.82
const ROW_H := 0.55
const ROWS_PER_TIER := 4
const LANDING := 0.9
const CONCOURSE := 8.0
const GLASS_TOP := 24.5
const LIMIT := 1.5            # the neon line: this far outside the field lines

# Measured palette, in flat tones.
const C_STRUCTURE := Color("2b5a66")
const C_FLOOR := Color("2e3236")
const C_CONCRETE := Color("5c666c")
const C_PINK := Color("e0609e")
const C_CYAN := Color("7cf2f2")
const C_BLUE := Color("4a8cf0")               # the right side on the strip and the scoreboards
const C_GRASS_A := Color("468a2c")
const C_GRASS_B := Color("55a034")
const C_LINE := Color("d8dad6")

var crowd: Crowd
var strip: ShaderMaterial
var glass: ShaderMaterial
var scoreboards: Array = []
var board: Scoreboard
var _portrait_tex: Array = [null, null]
var _board_set := false
var _share := 0.5               # the left side's share of the HP left (the strip's edge)
var _win_t := -1.0              # seconds since the final blow (-1: battle on)
var _share_to := 0.5
var _moving_spots: Array = []
var _battle_t := 0.0
## The night sky's material and the environment, for stages built on this one
## (FloatingStadium) to retune.
var night_sky: ShaderMaterial
var night_env: Environment


func build() -> void:
	_night_environment()
	_night_field()
	_limits()
	_wall()
	_stands()
	_concourse()
	_upper_tier()
	_glass_wall()
	_facade()
	_roof_ring()
	_floodlight_ring()
	_fog()
	_night_scoreboards()
	_camera_shell()
	_flags()
	_moving_spotlights()
	crowd = Crowd.new()
	add_child(crowd)
	crowd.build(self)


func _process(delta: float) -> void:
	_t += delta
	_battle_t += delta
	_move_spots()
	if main and main.fighters.size() == 2:
		var hp := [1.0, 1.0]
		for f in main.fighters:
			if is_instance_valid(f):
				hp[_side(f)] = clampf(f.hp / f.hp_max, 0.0, 1.0)
		crowd.set_hp(hp[0], hp[1])
		if board and not _board_set:
			_board_set = true
			for k in 2:
				var f: Fighter = main.fighters[k]
				board.portraits[_side(f)] = _portrait_tex[k]
				board.names[_side(f)] = tr(f.data.display_name)
			board.refresh()
	# The strip's edge goes slowly toward whoever is losing.
	if strip:
		_share = move_toward(_share, _share_to, delta * 0.12)
		strip.set_shader_parameter("edge", (_share - 0.5) * 2.0 * WALL_A)
		if _win_t >= 0.0:
			_win_t += delta
			strip.set_shader_parameter("win_t", _win_t)


func _end_winner() -> void:
	_win_t = -1.0
	if strip:
		strip.set_shader_parameter("win_t", -1.0)


## "WINNER " drawn once in the HUD's pixel font and cropped to its lit rows, for the strip
## to repeat after a KO, centered in the nine rows inside its frame.
func _winner_word() -> void:
	var font: Font = load("res://gui/font/pixel.fnt")
	var text := "WINNER  "
	var w := int(ceilf(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x))
	var vp := SubViewport.new()
	vp.size = Vector2i(w, 12)
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var lb := Label.new()
	lb.text = text
	lb.add_theme_font_override("font", font)
	lb.add_theme_font_size_override("font_size", 12)
	lb.add_theme_color_override("font_color", Color.WHITE)
	lb.position = Vector2(0, -1)
	vp.add_child(lb)
	add_child(vp)
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	var used := img.get_used_rect()
	if used.size.y <= 0:
		return
	var word := img.get_region(Rect2i(0, used.position.y, w, used.size.y))
	strip.set_shader_parameter("word", ImageTexture.create_from_image(word))
	strip.set_shader_parameter("word_px", Vector2(w, used.size.y))
	strip.set_shader_parameter("word_top", floorf((9.0 - used.size.y) * 0.5))


## Each battle: the portraits for the scoreboards (placed by side once the fighters are in).
func screens(tex_a: Texture2D, tex_b: Texture2D, _col_a: Color, _col_b: Color) -> void:
	_portrait_tex = [tex_a, tex_b]
	_board_set = false
	_share = 0.5
	_share_to = 0.5
	_end_winner()
	if board:
		board.hp = [1.0, 1.0]


# ---------------------------------------------------------------- battle events

## 0 = pink (left half of the stands, x < 0), 1 = cyan: the side of the fighter's spawn.
func _side(f: Fighter) -> int:
	return 0 if f.start_pos.x < 0.0 else 1


func on_hit(attacker: Fighter, target: Fighter, damage: float) -> void:
	if attacker and is_instance_valid(attacker) and target.hp_max > 0.0:
		crowd.hit(_side(attacker), damage / target.hp_max)


func on_dodge(f: Fighter) -> void:
	crowd.close_dodge(_side(f))


func on_ko(winner: Fighter) -> void:
	crowd.finish(_side(winner), _battle_t)
	if strip:
		strip.set_shader_parameter("win_col", C_PINK if _side(winner) == 0 else C_BLUE)
		_win_t = 0.0


func on_rematch() -> void:
	crowd.reset()
	_battle_t = 0.0
	_share = 0.5
	_share_to = 0.5
	_end_winner()
	if board:
		board.hp = [1.0, 1.0]
		board.refresh()


# ---------------------------------------------------------------- environment

const SH_SKY := """
shader_type sky;
// Night in three hard bands (no gradient) with pixel stars that twinkle slowly.
uniform vec3 top : source_color = vec3(0.008, 0.012, 0.045);
uniform vec3 mid : source_color = vec3(0.02, 0.03, 0.09);
uniform vec3 low : source_color = vec3(0.05, 0.05, 0.14);
uniform vec3 horizon : source_color = vec3(0.12, 0.1, 0.3);
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	vec3 c = h > 0.32 ? top : (h > 0.1 ? mid : low);
	// Stars: cells in spherical coordinates, a few of them lit.
	vec2 sph = vec2(atan(d.x, d.z), asin(clamp(d.y, -1.0, 1.0)));
	vec2 cell = floor(sph * 220.0);
	float s = hash(cell);
	float twinkle = 0.6 + 0.4 * step(0.5, fract(TIME * 0.35 + s * 7.0));
	if (h > 0.08 && s > 0.9965) c += vec3(0.85, 0.9, 1.0) * twinkle;
	// The stadium's glow on the horizon: a low, hard band.
	if (h < 0.05 && h > -0.02) c = mix(c, horizon, 0.6);
	COLOR = c;
}
"""


func _night_environment() -> void:
	var sky := Sky.new()
	night_sky = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SH_SKY
	night_sky.shader = sh
	sky.sky_material = night_sky
	night_env = Environment.new()
	night_env.background_mode = Environment.BG_SKY
	night_env.sky = sky
	night_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	night_env.ambient_light_color = Color(0.25, 0.32, 0.7)
	night_env.ambient_light_energy = 0.02
	night_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	night_env.tonemap_exposure = 1.05
	night_env.glow_enabled = true
	night_env.glow_intensity = 0.55
	night_env.glow_strength = 1.0
	night_env.glow_bloom = 0.0
	night_env.glow_hdr_threshold = 1.1
	night_env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	night_env.set_glow_level(1, 0.5)
	night_env.set_glow_level(2, 0.8)
	night_env.set_glow_level(3, 0.5)
	night_env.set_glow_level(4, 0.2)
	night_env.set_glow_level(5, 0.0)
	night_env.ssao_enabled = true
	night_env.ssao_radius = 1.6
	night_env.ssao_intensity = 1.6
	# Very thin volumetric fog: the floodlights show in the air without hiding anything.
	night_env.volumetric_fog_enabled = true
	night_env.volumetric_fog_density = 0.005
	night_env.volumetric_fog_albedo = Color(0.5, 0.56, 0.8)
	night_env.volumetric_fog_anisotropy = 0.65
	night_env.volumetric_fog_length = 120.0
	night_env.volumetric_fog_ambient_inject = 0.0
	# Light bounces: the pink glass, the screens and the lamps tint what is around them.
	night_env.sdfgi_enabled = true
	night_env.sdfgi_use_occlusion = true
	night_env.sdfgi_cascades = 4
	night_env.sdfgi_min_cell_size = 0.4
	night_env.sdfgi_bounce_feedback = 0.5
	night_env.sdfgi_energy = 0.55
	night_env.adjustment_enabled = true
	night_env.adjustment_saturation = 1.12
	night_env.adjustment_contrast = 1.06
	var we := WorldEnvironment.new()
	we.environment = night_env
	add_child(we)
	# A cold, soft moon with shadows: it lights the roof and the outside; the stands stay in
	# the roof's shade.
	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-80, 140, 0)
	moon.light_energy = 0.14
	moon.light_color = Color(0.55, 0.65, 1.0)
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 220.0
	add_child(moon)


func _glowing(col: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col * 0.3
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	return m


## Adds a "grid" grain (the concourse's floor plates) to the stages' pixel grains.
func _grain(kind: String) -> ImageTexture:
	if kind != "grid":
		return super(kind)
	if _grains.has(kind):
		return _grains[kind]
	var img := Image.create(32, 32, true, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	for y in 32:
		for x in 32:
			var v := 0.55 if (x % 8 == 0 or y % 8 == 0) else (0.95 if rng.randf() < 0.2 else 1.0)
			img.set_pixel(x, y, Color(v * 0.92, v * 0.92, v * 0.92))
	img.generate_mipmaps()
	_grains[kind] = ImageTexture.create_from_image(img)
	return _grains[kind]


# ---------------------------------------------------------------- geometry around the wall's oval

func _ring_path(a: float, b: float, r: float, seg := 12) -> Array:
	var pts: Array = []
	var centers := [Vector2(a - r, b - r), Vector2(-(a - r), b - r), Vector2(-(a - r), -(b - r)), Vector2(a - r, -(b - r))]
	for k in 4:
		for i in seg + 1:
			var ang := (k + float(i) / seg) * PI * 0.5
			var n := Vector3(cos(ang), 0.0, sin(ang))
			var c: Vector2 = centers[k]
			pts.append([Vector3(c.x, 0.0, c.y) + n * r, n])
	return pts


## Points along a rounded rectangle every "step" meters (or exactly "count" of them):
## [position, outward normal, distance along, total length].
func spots(a: float, b: float, r: float, step: float, count := 0) -> Array:
	var dense := _ring_path(a, b, r, 24)
	var lengths: Array[float] = [0.0]
	for i in dense.size():
		var p0: Vector3 = dense[i][0]
		var p1: Vector3 = dense[(i + 1) % dense.size()][0]
		lengths.append(lengths[-1] + p0.distance_to(p1))
	var total: float = lengths[-1]
	var n := count if count > 0 else int(total / step)
	var out: Array = []
	var j := 0
	for k in n:
		var s := k * total / n
		while lengths[j + 1] < s:
			j += 1
		var p0: Vector3 = dense[j][0]
		var p1: Vector3 = dense[(j + 1) % dense.size()][0]
		var f := (s - lengths[j]) / maxf(lengths[j + 1] - lengths[j], 0.0001)
		var nn: Vector3 = dense[j][1].lerp(dense[(j + 1) % dense.size()][1], f).normalized()
		out.append([p0.lerp(p1, f), nn, s, total])
	return out


## Extrudes a profile [(d, y)] around the wall's oval (or "oval": half-sides and corner
## radius): d outward, y upward.
func _ring(profile: PackedVector2Array, mat: Material, shadow := true, oval := Vector3.ZERO) -> MeshInstance3D:
	var o := oval if oval != Vector3.ZERO else crowd_oval()
	var path := _ring_path(o.x, o.y, o.z, 36)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var u: Array[float] = [0.0]
	for i in range(1, path.size() + 1):
		var p0: Vector3 = path[i - 1][0]
		var p1: Vector3 = path[i % path.size()][0]
		u.append(u[-1] + p0.distance_to(p1))
	var v: Array[float] = [0.0]
	for j in range(1, profile.size()):
		v.append(v[-1] + profile[j - 1].distance_to(profile[j]))
	for i in path.size():
		var i2 := (i + 1) % path.size()
		var pa: Vector3 = path[i][0]
		var na: Vector3 = path[i][1]
		var pb: Vector3 = path[i2][0]
		var nb: Vector3 = path[i2][1]
		for j in profile.size() - 1:
			var q0 := profile[j]
			var q1 := profile[j + 1]
			var t := (q1 - q0).normalized()
			var n2 := Vector2(-t.y, t.x)
			var v00 := pa + na * q0.x + Vector3.UP * q0.y
			var v01 := pa + na * q1.x + Vector3.UP * q1.y
			var v10 := pb + nb * q0.x + Vector3.UP * q0.y
			var v11 := pb + nb * q1.x + Vector3.UP * q1.y
			var n_a := (na * n2.x + Vector3.UP * n2.y).normalized()
			var n_b := (nb * n2.x + Vector3.UP * n2.y).normalized()
			var quad := [[v00, n_a, Vector2(u[i], v[j])], [v10, n_b, Vector2(u[i + 1], v[j])], [v11, n_b, Vector2(u[i + 1], v[j + 1])], [v01, n_a, Vector2(u[i], v[j + 1])]]
			for tri in [[0, 1, 2], [0, 2, 3]]:
				var A: Vector3 = quad[tri[0]][0]
				var B: Vector3 = quad[tri[1]][0]
				var C: Vector3 = quad[tri[2]][0]
				var order: Array = tri
				if (B - A).cross(C - A).dot(n_a) > 0.0:
					order = [tri[0], tri[2], tri[1]]
				for k in order:
					st.set_normal(quad[k][1])
					st.set_uv(quad[k][2])
					st.add_vertex(quad[k][0])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _box(dims: Vector3, pos: Vector3, mat: Material, basis := Basis()) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = dims
	mi.mesh = bm
	mi.material_override = mat
	mi.transform = Transform3D(basis, pos)
	add_child(mi)
	return mi


## Truss bars: each bar [a, b] is a 1 m box stretched inside a MultiMesh, so hundreds of
## bars go in a single draw call.
func _bars(bars: Array, thickness: float, mat: Material) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = BoxMesh.new()
	mm.instance_count = bars.size()
	for k in bars.size():
		var a: Vector3 = bars[k][0]
		var b: Vector3 = bars[k][1]
		var d := (b - a).normalized()
		var up := Vector3.UP if absf(d.y) < 0.99 else Vector3.RIGHT
		var basis := Basis.looking_at(d, up) * Basis.from_scale(Vector3(thickness, thickness, a.distance_to(b) + thickness))
		mm.set_instance_transform(k, Transform3D(basis, (a + b) * 0.5))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	add_child(mi)


## A square tube all the way round the oval at distance d and height y.
func _tube(d: float, y: float, g: float, mat: Material) -> void:
	_ring(PackedVector2Array([Vector2(d - g, y - g), Vector2(d - g, y + g), Vector2(d + g, y + g), Vector2(d + g, y - g), Vector2(d - g, y - g)]), mat)


# ---------------------------------------------------------------- field

const SH_NIGHT_FIELD := """
shader_type spatial;
render_mode cull_back;
// Night grass in pixels (16 per meter): diagonal mown stripes, white markings, the center
// rings and our own emblem. Outside the lines, the dark track up to the wall, with the
// cyan neon line that marks the battle limit.
uniform float field_len;
uniform float field_wid;
uniform float limit = 1.5;
uniform float px = 16.0;
uniform vec3 grass_a : source_color;
uniform vec3 grass_b : source_color;
uniform vec3 line_col : source_color;
uniform vec3 track : source_color;
uniform vec3 pink : source_color;
uniform vec3 cyan : source_color;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float stroke(float d, float w) { return step(abs(d), w * 0.5); }
float box(vec2 p, vec2 h, float r) {
	vec2 q = abs(p) - h + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}
float grain(vec2 cell) {
	float h = hash(cell);
	return h < 0.14 ? 0.86 : (h > 0.9 ? 1.1 : 1.0);
}
void fragment() {
	vec2 cell = floor(wp.xz * px);
	vec2 p = (cell + 0.5) / px;
	float hl = field_len * 0.5, hw = field_wid * 0.5, W = 0.125;
	float g = grain(cell);
	// Diagonal 2 m stripes.
	float band = step(0.5, fract((p.x + p.y) / 4.0));
	vec3 c = mix(grass_a, grass_b, band) * g;
	c = mix(c, c * 1.1, step(0.94, hash(vec2(cell.x, floor(cell.y / 2.0)))));
	float r = length(p);
	// Markings: rectangle, halfway line, three rings and the center spot.
	float l = stroke(box(p, vec2(hl, hw), 0.0), W);
	l = max(l, stroke(p.x, W) * step(abs(p.y), hw));
	l = max(l, stroke(r - 6.0, W));
	l = max(l, stroke(r - 3.6, W));
	l = max(l, stroke(r - 1.4, W));
	l = max(l, step(r, 0.25));
	l *= step(0.08, hash(cell + 3.1));
	c = mix(c, line_col * mix(1.0, g, 0.5), l);
	// Track up to the wall: dark rubber tiles with a seam, and the cyan limit line.
	float outside = step(0.0, box(p, vec2(hl + limit, hw + limit), limit));
	vec2 seam = step(fract(p), vec2(1.0 / px));
	vec3 ap = track * grain(cell + 9.0) * (1.0 - 0.2 * max(seam.x, seam.y));
	float edge = stroke(box(p, vec2(hl + limit, hw + limit), limit), 0.125);
	c = mix(c, ap, outside);
	c = mix(c, cyan * 0.8, edge);
	// Each trainer's area: outside the rectangle, against the end line like a goal box,
	// plain in its side's color with a stripe in the middle and a white outline.
	float marks = l;
	for (float s = -1.0; s <= 1.0; s += 2.0) {
		vec2 q = p - vec2(s * (hl + 1.6), 0.0);
		float dz = box(q, vec2(1.6, 2.8), 0.0);
		if (dz < 0.0) {
			c = mix(ap, (s < 0.0 ? pink : cyan) * 0.5 * mix(1.0, grain(cell + 5.0), 0.4), 0.75);
			edge = 0.0;   // the track's line does not cross the area
		}
		float lz = max(stroke(dz, W), stroke(q.x, W) * step(abs(q.y), 2.8));
		lz *= step(0.08, hash(cell + 3.1));
		c = mix(c, line_col * mix(1.0, g, 0.5), lz);
		marks = max(marks, lz);
	}
	ALBEDO = c;
	EMISSION = cyan * edge * 1.5 + line_col * marks * 0.45;
	ROUGHNESS = mix(0.9, 0.55, outside);
	SPECULAR = mix(0.2, 0.5, outside);
}
"""


func _night_field() -> void:
	_box_collider(Vector3(0, -0.5, 0), Vector3(LENGTH + 60, 1.0, WIDTH + 60))
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(WALL_A * 2.0 + 2.0, WALL_B * 2.0 + 2.0)
	pm.subdivide_width = 8
	pm.subdivide_depth = 8
	mi.mesh = pm
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SH_NIGHT_FIELD
	sm.shader = sh
	sm.set_shader_parameter("field_len", LENGTH)
	sm.set_shader_parameter("field_wid", WIDTH)
	sm.set_shader_parameter("limit", LIMIT)
	sm.set_shader_parameter("grass_a", C_GRASS_A)
	sm.set_shader_parameter("grass_b", C_GRASS_B)
	sm.set_shader_parameter("line_col", C_LINE)
	sm.set_shader_parameter("track", C_FLOOR)
	sm.set_shader_parameter("pink", C_PINK)
	sm.set_shader_parameter("cyan", C_CYAN)
	mi.material_override = sm
	add_child(mi)


## In their side's trainer area, behind the invisible wall: out of the fighters' reach.
func trainer_spot(side: float) -> Vector3:
	return Vector3(side * (LENGTH * 0.5 + 2.6), 0.0, 0.0)


## The battle limit: an invisible wall (layer 3, fighters only) on the cyan neon line, and
## the real wall's collision (layer 1) for projectiles and the camera, as boxes around the
## oval.
func _limits() -> void:
	var a := LENGTH * 0.5 + LIMIT
	var b := WIDTH * 0.5 + LIMIT
	for s in [-1.0, 1.0]:
		_box_collider(Vector3(0, 15, s * (b + 0.25)), Vector3(LENGTH + 2.0 * LIMIT + 1.0, 30, 0.5), 4)
		_box_collider(Vector3(s * (a + 0.25), 15, 0), Vector3(0.5, 30, WIDTH + 2.0 * LIMIT + 1.0), 4)
	var path := _ring_path(WALL_A, WALL_B, WALL_R, 8)
	for i in path.size():
		var p0: Vector3 = path[i][0]
		var p1: Vector3 = path[(i + 1) % path.size()][0]
		var length := p0.distance_to(p1)
		if length < 0.05:
			continue
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(0.6, WALL_H, length + 0.3)
		cs.shape = bs
		body.add_child(cs)
		var mid := (p0 + p1) * 0.5
		var n: Vector3 = (path[i][1] + path[(i + 1) % path.size()][1]).normalized()
		body.transform = Transform3D(Basis.looking_at((p1 - p0).normalized(), Vector3.UP), mid + n * 0.3 + Vector3.UP * WALL_H * 0.5)
		add_child(body)


# ---------------------------------------------------------------- wall and LED strip

const SH_STRIP := """
shader_type spatial;
render_mode unshaded, cull_back;
// LED strip with the battle's balance: pink (the left side's Pokémon) from the left end up
// to "edge" (world x), cyan beyond it. NightStadium moves the edge slowly toward whoever
// is losing; nothing else moves, so turning the camera never makes it swim. A white LED
// column marks the edge; "hype" only brightens it.
// After the final blow ("win_t" seconds ago) the winner's color sweeps out from the edge
// all the way round and WINNER WINNER WINNER... slides slowly along it ("word", one LED per
// pixel of the word drawn in the HUD's font).
uniform vec3 pink : source_color;
uniform vec3 blue : source_color;
uniform float edge = 0.0;
uniform float hype = 0.0;
uniform float win_t = -1.0;
uniform vec3 win_col : source_color;
uniform sampler2D word : filter_nearest, repeat_enable;
uniform vec2 word_px = vec2(48.0, 8.0);
uniform float word_top = 1.0;      // first lit row from the top inside the frame
varying vec3 world;
void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	float cell = 1.0 / 16.0;
	float x = (floor(world.x / cell) + 0.5) * cell;
	vec3 c = x < edge ? pink : blue;
	c = abs(x - edge) < cell * 1.5 ? vec3(1.0) : c;
	if (win_t >= 0.0 && abs(x - edge) < win_t * 40.0) {
		c = win_col;
		float u = floor(UV.x * 16.0) - floor(win_t * 12.0);
		// Rows 1-9 are inside the darker frame; the word is centered in them.
		float v = 9.0 - floor(UV.y * 16.0) - word_top;
		if (v >= 0.0 && v < word_px.y) {
			float a = texture(word, vec2((u + 0.5) / word_px.x, (v + 0.5) / word_px.y)).a;
			c = mix(c, vec3(1.0), step(0.5, a));
		}
	}
	// Darker top and bottom rows frame it.
	float row = floor(UV.y * 16.0);
	c *= (row < 1.0 || row > 9.0) ? 0.45 : 1.0;
	vec2 gg = fract(UV * 16.0);
	c *= 1.0 - 0.45 * step(0.82, max(gg.x, gg.y)) * (1.0 - clamp(fwidth(UV.x) * 24.0, 0.0, 1.0));
	ALBEDO = c * (0.9 + hype * 0.5);
}
"""


func _wall() -> void:
	var dark := _material(Color("1a1e24"), 0.6, 0.3, "metal")
	_ring(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.0, 0.9)]), dark)
	strip = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SH_STRIP
	strip.shader = sh
	strip.set_shader_parameter("pink", C_PINK)
	strip.set_shader_parameter("blue", C_BLUE)
	_ring(PackedVector2Array([Vector2(0.0, 0.9), Vector2(0.0, 1.6)]), strip, false)
	_winner_word()
	_ring(PackedVector2Array([Vector2(0.0, 1.6), Vector2(0.0, WALL_H), Vector2(0.3, WALL_H)]), dark)
	# Cyan neon edge on top of the wall.
	_ring(PackedVector2Array([Vector2(-0.02, WALL_H + 0.02), Vector2(0.32, WALL_H + 0.02)]), _glowing(C_CYAN, 1.2), false)


# ---------------------------------------------------------------- stands

## Rows of the three tiers: [d, y, tier] of each tread (where the seat goes).
## The oval the crowd's rows go round (half-sides and corner radius).
func crowd_oval() -> Vector3:
	return Vector3(WALL_A, WALL_B, WALL_R)


## Every row with seats, [distance out from crowd_oval(), height, tier].
func crowd_rows() -> Array:
	return rows() + upper_rows()


## The crowd gets louder (hype 0-1) or the HP changes ([left, right], 0-1): the LED
## strip, the glass and the scoreboards follow.
func on_hype(hype: float, hp: Array) -> void:
	strip.set_shader_parameter("hype", hype)
	glass.set_shader_parameter("hype", hype)
	for m in scoreboards:
		m.set_shader_parameter("hype", hype)
	var total: float = hp[0] + hp[1]
	_share_to = hp[0] / total if total > 0.001 else 0.5
	if board:
		board.set_hp(hp[0], hp[1])


func rows() -> Array:
	var out: Array = []
	var d := 0.3
	var y := WALL_H
	for tier in 3:
		for k in ROWS_PER_TIER:
			y += ROW_H
			out.append([d + ROW_D * 0.5, y, tier])
			d += ROW_D
		if tier < 2:
			d += LANDING
	return out


func _stands() -> void:
	var concrete := _material(C_CONCRETE, 0.92, 0.0, "concrete")
	var profile := PackedVector2Array([Vector2(0.3, WALL_H)])
	var d := 0.3
	var y := WALL_H
	for tier in 3:
		for k in ROWS_PER_TIER:
			profile.append(Vector2(d, y + ROW_H))
			y += ROW_H
			d += ROW_D
			profile.append(Vector2(d, y))
		if tier < 2:
			# Landing (its railing goes separately).
			d += LANDING
			profile.append(Vector2(d, y))
	_ring(profile, concrete)
	_railings()


## Glass railings on the landings with a cyan neon edge.
func _railings() -> void:
	var neon := _glowing(C_CYAN, 0.7)
	var d := 0.3
	var y := WALL_H
	for tier in 2:
		d += ROWS_PER_TIER * ROW_D
		y += ROWS_PER_TIER * ROW_H
		_ring(PackedVector2Array([Vector2(d + 0.05, y), Vector2(d + 0.05, y + 0.9)]), _glass_mat(), false)
		_ring(PackedVector2Array([Vector2(d, y + 0.9), Vector2(d + 0.1, y + 0.92)]), neon, false)
		d += LANDING


func _glass_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.5, 0.85, 0.9, 0.18)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.1
	return m


# ---------------------------------------------------------------- upper tier

const UPPER_OVERHANG := 1.0   # the upper tier's front overhangs the concourse by 1 m
const UPPER_CLEAR := 4.5      # height of the front over the concourse
const UPPER_ROWS := 8
const UPPER_D := 0.8
const UPPER_H := 0.75         # steeper than below, like a real upper tier


## Rows of the upper tier, in the same format as rows().
func upper_rows() -> Array:
	var end := _rows_end()
	var d := end.x + UPPER_OVERHANG
	var y := end.y + UPPER_CLEAR
	var out: Array = []
	for k in UPPER_ROWS:
		y += UPPER_H
		out.append([d + UPPER_D * 0.5, y, 3])
		d += UPPER_D
	return out


## Height where the LED strip starts: one meter above the top upper row.
func _strip_y() -> float:
	return _rows_end().y + UPPER_CLEAR + UPPER_ROWS * UPPER_H + 1.0


## Distance of the glass (which leans outward) at height y.
func _glass_d(y: float) -> float:
	var end := _rows_end()
	return end.x + CONCOURSE + 3.8 * (y - end.y) / (GLASS_TOP - end.y)


## Upper tier over the concourse: the back wall of the concourse, a sloped underside, a
## front with an LED strip and glass railing, eight steep rows and a back floor that
## reaches the glass.
func _upper_tier() -> void:
	var end := _rows_end()
	var d := end.x + UPPER_OVERHANG
	var y := end.y + UPPER_CLEAR
	var back := end.x + CONCOURSE
	var profile := PackedVector2Array([Vector2(back, end.y), Vector2(back, end.y + 8.7), Vector2(d, y - 1.0), Vector2(d, y)])
	for k in UPPER_ROWS:
		profile.append(Vector2(d, y + UPPER_H))
		y += UPPER_H
		d += UPPER_D
		profile.append(Vector2(d, y))
	var top := _strip_y()
	profile.append(Vector2(d, top))
	profile.append(Vector2(_glass_d(top), top))
	_ring(profile, _material(C_CONCRETE, 0.92, 0.0, "concrete"))
	# Front: the same chevron strip as the field wall, and a glass railing with a cyan
	# neon edge, like the landings'.
	var d0 := end.x + UPPER_OVERHANG
	var y0 := end.y + UPPER_CLEAR
	_ring(PackedVector2Array([Vector2(d0 - 0.02, y0 - 0.9), Vector2(d0 - 0.02, y0 - 0.2)]), strip, false)
	_ring(PackedVector2Array([Vector2(d0 + 0.05, y0), Vector2(d0 + 0.05, y0 + 0.9)]), _glass_mat(), false)
	_ring(PackedVector2Array([Vector2(d0, y0 + 0.9), Vector2(d0 + 0.1, y0 + 0.92)]), _glowing(C_CYAN, 0.7), false)


# ---------------------------------------------------------------- concourse and glass

func _rows_end() -> Vector2:
	var f: Array = rows()
	return Vector2(f[-1][0] + ROW_D * 0.5, f[-1][1])


func _concourse() -> void:
	var end := _rows_end()
	_ring(PackedVector2Array([end, Vector2(end.x + CONCOURSE, end.y)]), _material(C_STRUCTURE.darkened(0.25), 0.8, 0.1, "grid"))
	# Concourse fence: a teal bar with cyan LEDs below.
	var fence := _material(C_STRUCTURE, 0.5, 0.3, "metal")
	_ring(PackedVector2Array([Vector2(end.x + 0.1, end.y), Vector2(end.x + 0.1, end.y + 1.1), Vector2(end.x + 0.3, end.y + 1.1)]), fence)
	_ring(PackedVector2Array([Vector2(end.x + 0.05, end.y + 0.15), Vector2(end.x + 0.05, end.y + 0.25)]), _glowing(C_CYAN, 0.8), false)


const SH_GLASS := """
shader_type spatial;
render_mode cull_disabled;
// Pink glass wall as an LED lattice: 1 m tiles with a frame, pink inside and still
// chevrons. With "hype" it glows brighter, in a slow soft swell (never on and off).
uniform vec3 pink : source_color;
uniform vec3 frame_col : source_color;
uniform float hype = 0.0;
void fragment() {
	vec2 uvp = (floor(UV * 8.0) + 0.5) / 8.0;
	vec2 lo = fract(UV);
	float border = step(0.9, max(lo.x, lo.y)) + step(max(1.0 - lo.x, 1.0 - lo.y), 0.1);
	float ch = fract(uvp.y * 0.25 + abs(fract(uvp.x / 6.0) - 0.5) * 0.6);
	float band = step(ch, 0.22);
	float swell = 0.5 + 0.5 * sin(TIME * 6.28 * 0.5);
	vec3 c = pink * (0.35 + 0.65 * band);
	c *= 1.0 + hype * (0.35 + 0.25 * swell);
	c = mix(c, frame_col, min(border, 1.0));
	ALBEDO = vec3(0.02, 0.02, 0.03);
	EMISSION = c * 0.38;
	ROUGHNESS = 0.2;
}
"""


func _glass_wall() -> void:
	var end := _rows_end()
	# Leaning outward (3.8 m over its height), only the strip above the upper tier.
	var base := Vector2(_glass_d(_strip_y()), _strip_y())
	var top := Vector2(end.x + CONCOURSE + 3.8, GLASS_TOP)
	glass = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SH_GLASS
	glass.shader = sh
	glass.set_shader_parameter("pink", C_PINK)
	glass.set_shader_parameter("frame_col", Color("1c2a33"))
	_ring(PackedVector2Array([base, top]), glass, false)
	# Crown: a white beam with a cyan top.
	var white := _material(Color("dfe4ea"), 0.6, 0.2, "metal")
	_ring(PackedVector2Array([top, top + Vector2(0.0, 0.9), top + Vector2(1.6, 0.9), top + Vector2(1.6, 0.0)]), white)
	_ring(PackedVector2Array([top + Vector2(-0.05, 0.92), top + Vector2(1.65, 0.92)]), _glowing(C_CYAN, 1.4), false)


## Chevron facade outside, peeking out behind the glass.
func _facade() -> void:
	var end := _rows_end()
	var x0 := end.x + CONCOURSE
	_ring(PackedVector2Array([Vector2(x0 + 14.0, end.y - 1.2), Vector2(x0 + 7.0, 17.6), Vector2(x0 + 11.0, GLASS_TOP + 0.4)]), _material(Color("cfd3d8"), 0.7, 0.1, "metal"))


# ---------------------------------------------------------------- roof and floodlight ring

const RING_D := -1.2     # inner edge of the roof: 1.2 m inside the wall
const RING_Y := 29.0     # underside of the roof at that edge
const NODES := 48        # nodes of the ring; every other one, a radial truss and a floodlight


## Height of the roof's underside at distance d from the wall.
func _roof_y(d: float) -> float:
	var out := _rows_end().x + CONCOURSE + 5.4
	return lerpf(RING_Y, GLASS_TOP + 0.9, clampf((d - RING_D) / (out - RING_D), 0.0, 1.0))


func _node(p: Array, d: float, y: float) -> Vector3:
	return p[0] + p[1] * d + Vector3.UP * y


## Camp Nou style roof: it covers the stands and the concourse, rises a little inward and
## leaves the field open to the sky. Underneath, radial lattice trusses and purlins that go
## all the way round, all exposed.
func _roof_ring() -> void:
	var out := _rows_end().x + CONCOURSE + 5.4
	var sheet := _material(Color("1e2633"), 0.55, 0.4, "metal")
	var metal := _material(Color("6a7684"), 0.45, 0.6, "metal")
	# Light sheet on top (as seen from the air), dark underneath.
	_ring(PackedVector2Array([Vector2(RING_D, RING_Y + 0.6), Vector2(out, GLASS_TOP + 1.7)]), _material(Color("aeb6bf"), 0.7, 0.2, "metal"))
	_ring(PackedVector2Array([Vector2(out, GLASS_TOP + 1.7), Vector2(out, GLASS_TOP + 0.9), Vector2(RING_D, RING_Y), Vector2(RING_D, RING_Y + 0.6)]), sheet)
	# White edge of the inner rim: the opening's silhouette against the sky.
	_ring(PackedVector2Array([Vector2(RING_D - 0.03, RING_Y - 0.1), Vector2(RING_D - 0.03, RING_Y + 0.7)]), _material(Color("d6dce2"), 0.6, 0.2, "metal"))
	# Purlins: tubes going round right under the sheet.
	for d in [6.0, 12.0, 18.0, out - 2.0]:
		_tube(d, _roof_y(d) - 0.2, 0.15, metal)
	# Radial trusses: top chord under the sheet, a bottom chord that thins outward,
	# posts and alternating diagonals.
	var bars: Array = []
	var d0 := RING_D + 2.2
	var spans := 8
	var nodes := spots(WALL_A, WALL_B, WALL_R, 0.0, NODES)
	for k in range(0, NODES, 2):
		var p: Array = nodes[k]
		var pts_a: Array = []
		var pts_b: Array = []
		for t in spans + 1:
			var d := lerpf(d0, out - 1.0, float(t) / spans)
			var ya := _roof_y(d) - 0.2
			pts_a.append(_node(p, d, ya))
			pts_b.append(_node(p, d, ya - lerpf(2.2, 0.7, float(t) / spans)))
		for t in spans + 1:
			bars.append([pts_a[t], pts_b[t]])
			if t < spans:
				bars.append([pts_a[t], pts_a[t + 1]])
				bars.append([pts_b[t], pts_b[t + 1]])
				bars.append([pts_b[t], pts_a[t + 1]] if t % 2 == 0 else [pts_a[t], pts_b[t + 1]])
	_bars(bars, 0.22, metal)


## Where each floodlight lands: the field point closest to it, inside a rectangle a little
## smaller than the field. Each one lights its piece and together they cover all of it.
func _spot_target(pos: Vector3) -> Vector3:
	return Vector3(clampf(pos.x, -LENGTH * 0.4, LENGTH * 0.4), 0.0, clampf(pos.z, -WIDTH * 0.32, WIDTH * 0.32))


## Square-section lattice ring hung from the roof's edge, with banks of floodlights below:
## three projectors per node, all alike. They light the field (a SpotLight3D every other
## node); the odd nodes get a small upward light that washes the roof's underside.
func _floodlight_ring() -> void:
	var metal := _material(Color("8c97a6"), 0.45, 0.6, "metal")
	var housing := _material(Color("1a1d22"), 0.4, 0.6, "metal")
	var face := _glowing(Color(0.95, 0.97, 1.0), 8.0)
	var di := RING_D + 0.15
	var de := RING_D + 2.2
	var yb := RING_Y - 2.4
	var ya := RING_Y - 0.15
	for d in [di, de]:
		for y in [yb, ya]:
			_tube(d, y, 0.16, metal)
	var nodes := spots(WALL_A, WALL_B, WALL_R, 0.0, NODES)
	var bars: Array = []
	var bodies: Array = []
	var faces: Array = []
	for k in NODES:
		var p: Array = nodes[k]
		var q: Array = nodes[(k + 1) % NODES]
		var odd_up := k % 2 == 1
		for d in [di, de]:
			bars.append([_node(p, d, yb), _node(p, d, ya)])
			bars.append([_node(p, d, ya if odd_up else yb), _node(q, d, yb if odd_up else ya)])
		bars.append([_node(p, di, yb), _node(p, de, yb)])
		bars.append([_node(p, di, ya), _node(p, de, ya)])
		bars.append([_node(p, di, yb), _node(q, de, yb)])
		# Bank: a hanger and three projectors in a row, facing their piece of field.
		var center := _node(p, di + 0.4, yb - 0.75)
		bars.append([_node(p, di + 0.4, yb), center + Vector3.UP * 0.3])
		var target := _spot_target(center)
		var tangent := Vector3(-p[1].z, 0.0, p[1].x)
		for s in [-0.75, 0.0, 0.75]:
			var pos: Vector3 = center + tangent * s
			var b := Basis.looking_at((target - pos).normalized(), Vector3.UP)
			bodies.append(Transform3D(b * Basis.from_scale(Vector3(0.62, 0.48, 0.5)), pos))
			faces.append(Transform3D(b * Basis.from_scale(Vector3(0.52, 0.38, 0.04)), pos + b * Vector3(0, 0, -0.27)))
		if k % 2 == 0:
			var f := SpotLight3D.new()
			f.position = center - Vector3.UP * 0.4
			add_child(f)
			f.look_at(target, Vector3.UP)
			f.spot_angle = 26.0
			f.spot_angle_attenuation = 0.5
			f.spot_range = 55.0
			f.spot_attenuation = 0.6
			f.light_energy = 1.7
			f.light_color = Color(0.92, 0.95, 1.0)
			f.light_volumetric_fog_energy = 0.25
			f.shadow_enabled = k % 8 == 0
		else:
			var u := SpotLight3D.new()
			u.position = _node(p, de + 0.3, yb - 0.3)
			add_child(u)
			u.look_at(_node(p, 9.0, _roof_y(9.0)), Vector3.UP)
			u.spot_angle = 55.0
			u.spot_angle_attenuation = 1.5
			u.spot_range = 26.0
			u.light_energy = 2.2
			u.light_color = Color(0.75, 0.82, 1.0)
			u.light_volumetric_fog_energy = 0.0
	_bars(bars, 0.2, metal)
	_boxes(bodies, housing)
	_boxes(faces, face)
	# A narrower light on each trainer's area, from the same ring.
	for side in [-1.0, 1.0]:
		var z := SpotLight3D.new()
		z.position = Vector3(side * (WALL_A + di), yb - 1.2, 0.0)
		add_child(z)
		z.look_at(Vector3(side * (LENGTH * 0.5 + 1.6), 0.0, 0.0), Vector3.UP)
		z.spot_angle = 9.0
		z.spot_range = 40.0
		z.light_energy = 4.0
		z.light_color = Color(0.9, 0.94, 1.0)
		z.light_volumetric_fog_energy = 0.3
		z.shadow_enabled = true


func _boxes(transforms: Array, mat: Material) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = BoxMesh.new()
	mm.instance_count = transforms.size()
	for k in transforms.size():
		mm.set_instance_transform(k, transforms[k])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	add_child(mi)


## Colored fog by zones (FogVolume): pink floating by the glass, cold blue up under the
## roof and a low haze over the field that catches the floodlights.
func _fog() -> void:
	var x_glass := _glass_d(22.4) - 0.6
	for p in spots(WALL_A + x_glass, WALL_B + x_glass, WALL_R + x_glass, 9.0):
		_fog_volume(p[0] + Vector3.UP * 22.4, Vector3(10.0, 5.0, 10.0), Color(0.95, 0.4, 0.7), 0.06, 0.08, RenderingServer.FOG_VOLUME_SHAPE_ELLIPSOID)
	_fog_volume(Vector3(0, 30.0, 0), Vector3(110.0, 16.0, 90.0), Color(0.35, 0.5, 1.0), 0.012, 0.02, RenderingServer.FOG_VOLUME_SHAPE_BOX)
	_fog_volume(Vector3(0, 0.8, 0), Vector3(LENGTH + 6.0, 2.2, WIDTH + 6.0), Color(0.75, 0.82, 1.0), 0.03, 0.0, RenderingServer.FOG_VOLUME_SHAPE_BOX)


func _fog_volume(pos: Vector3, dims: Vector3, col: Color, density: float, glow: float, shape: int) -> void:
	var fv := FogVolume.new()
	fv.shape = shape
	fv.size = dims
	fv.position = pos
	var fm := FogMaterial.new()
	fm.density = density
	fm.albedo = col
	fm.emission = col * glow
	fm.edge_fade = 0.6
	fv.material = fm
	add_child(fv)


# ---------------------------------------------------------------- scoreboards and flags

const SH_BOARD := """
shader_type spatial;
render_mode unshaded, cull_back;
// The scoreboard's canvas (Scoreboard) as chunky LEDs: one LED per canvas pixel with a dark
// gap around it. "hype" only brightens it.
uniform sampler2D board : source_color, filter_nearest;
uniform float hype = 0.0;
void fragment() {
	vec2 n = vec2(192.0, 84.0);
	vec3 c = texture(board, UV).rgb;
	vec2 gg = fract(UV * n);
	c *= 1.0 - 0.35 * step(0.8, max(gg.x, gg.y)) * (1.0 - clamp(fwidth(UV.x) * n.x * 0.6, 0.0, 1.0));
	ALBEDO = c * (1.25 + hype * 0.4);
}
"""


func _night_scoreboards() -> void:
	# One small canvas for both screens (Scoreboard), shown as LEDs.
	var vp := SubViewport.new()
	vp.size = Scoreboard.SIZE
	vp.transparent_bg = false
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	board = Scoreboard.new()
	board.colors = [C_PINK, C_BLUE]
	vp.add_child(board)
	add_child(vp)
	var frame := _material(Color("15181f"), 0.4, 0.3, "metal")
	for s in [-1.0, 1.0]:
		var root := Node3D.new()
		root.position = Vector3(s * (WALL_A + 9.5), 21.0, 0)
		root.rotation.y = -s * PI * 0.5
		add_child(root)
		var case_mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(13.0, 6.0, 0.6)
		case_mi.mesh = bm
		case_mi.material_override = frame
		case_mi.position.z = -0.32
		root.add_child(case_mi)
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(12.4, 5.4)
		q.mesh = qm
		var sm := ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = SH_BOARD
		sm.shader = sh
		sm.set_shader_parameter("board", vp.get_texture())
		q.material_override = sm
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(q)
		scoreboards.append(sm)
		# Hung from the roof by two ties.
		for z in [-5.0, 5.0]:
			_box(Vector3(0.12, 3.6, 0.12), root.position + Vector3(0, 4.8, z), frame)


## The stands as solid steps that only the camera sees (CAMERA_LAYER): it moves in instead
## of going into the seats at the corners. Fighters and projectiles never touch this layer.
func _camera_shell() -> void:
	var path := _ring_path(WALL_A, WALL_B, WALL_R, 8)
	var d := 0.3
	var y := WALL_H
	for tier in 3:
		var d0 := d
		for k in ROWS_PER_TIER:
			y += ROW_H
			d += ROW_D
		if tier < 2:
			d += LANDING
		var mid_d := (d0 + d) * 0.5
		for i in path.size():
			var p0: Vector3 = path[i][0]
			var p1: Vector3 = path[(i + 1) % path.size()][0]
			var length := p0.distance_to(p1)
			if length < 0.05:
				continue
			var n: Vector3 = (path[i][1] + path[(i + 1) % path.size()][1]).normalized()
			var body := StaticBody3D.new()
			body.collision_layer = CAMERA_LAYER
			body.collision_mask = 0
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			# Out at the corners the arc is longer: the boxes grow so they overlap.
			bs.size = Vector3(d - d0, y, length * (1.0 + mid_d / WALL_R) + 0.4)
			cs.shape = bs
			body.add_child(cs)
			body.transform = Transform3D(Basis.looking_at((p1 - p0).normalized(), Vector3.UP), (p0 + p1) * 0.5 + n * mid_d + Vector3.UP * y * 0.5)
			add_child(body)


const SH_FLAG := """
shader_type spatial;
render_mode cull_disabled;
// A flag waving (vertices) in three hard stripes.
uniform vec3 a : source_color = vec3(0.71, 0.85, 0.92);
uniform vec3 b : source_color = vec3(0.6, 0.24, 0.4);
uniform vec3 c : source_color = vec3(0.2, 0.25, 0.45);
uniform float phase = 0.0;
void vertex() {
	VERTEX.z += sin(TIME * 3.0 + VERTEX.x * 2.2 + phase) * 0.18 * (VERTEX.x + 0.9);
}
void fragment() {
	float v = floor(UV.y * 3.0);
	ALBEDO = v < 0.5 ? a : (v < 1.5 ? b : c);
	ROUGHNESS = 0.9;
}
"""


func _flags() -> void:
	var x0 := _rows_end().x + CONCOURSE + 3.8
	var pole := _material(Color("cfd3d8"), 0.5, 0.5, "metal")
	var sh := Shader.new()
	sh.code = SH_FLAG
	var pts := spots(WALL_A + x0, WALL_B + x0, WALL_R + x0, 9.0)
	for i in pts.size():
		var p: Vector3 = pts[i][0] + Vector3.UP * (GLASS_TOP + 0.9)
		_box(Vector3(0.12, 3.2, 0.12), p + Vector3.UP * 1.6, pole)
		var f := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(1.8, 1.1)
		pm.subdivide_width = 6
		pm.orientation = PlaneMesh.FACE_Z
		f.mesh = pm
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("phase", float(i) * 1.7)
		f.material_override = m
		f.position = p + Vector3.UP * 2.6
		f.rotation.y = randf() * TAU
		f.position += f.basis.x * 0.9
		add_child(f)


# ---------------------------------------------------------------- moving spotlights

func _moving_spotlights() -> void:
	var end := _rows_end()
	var body := _material(Color("22262d"), 0.5, 0.5, "metal")
	var sites := spots(WALL_A + end.x + 0.6, WALL_B + end.x + 0.6, WALL_R + end.x + 0.6, 14.0)
	for i in sites.size():
		var p: Vector3 = sites[i][0] + Vector3.UP * (end.y + 1.3)
		_box(Vector3(0.6, 0.6, 0.9), p, body)
		var col := C_PINK if i % 2 == 0 else C_CYAN
		if i % 5 == 0:
			col = Color(1.0, 0.96, 0.9)
		var spot := SpotLight3D.new()
		spot.position = p
		spot.light_color = col
		spot.light_energy = 1.6
		spot.spot_angle = 7.0
		spot.spot_range = 45.0
		spot.light_volumetric_fog_energy = 0.35
		spot.shadow_enabled = false
		add_child(spot)
		_moving_spots.append({"light": spot, "base": p, "phase": randf() * TAU, "speed": randf_range(0.25, 0.5)})


var sweep := 1.0     # 0 = still, pointing at the center; 1 = sweeping the field


func _move_spots() -> void:
	for f in _moving_spots:
		var ang: float = _t * f.speed + f.phase
		var target := Vector3(sin(ang) * 14.0 * sweep, 0.0, cos(ang * 1.3) * 8.0 * sweep)
		var spot: SpotLight3D = f.light
		spot.look_at(target, Vector3.UP)
