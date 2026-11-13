class_name LeagueStadium
extends NightStadium
## The League stadium, a coliseum after the anime's Unova League (Vertress Conference): a
## round field of pale stone slabs with its white lines, a ring of grey-green paving round
## it where the trainers stand in their boxes, a wall of grey bricks, stone stands split
## into sections by pillars with the tunnels people come in through, and a wall all round
## behind them; the scoreboard on a tower of its own behind the far side. Moss, vines and
## grime on the stone. A cool, dim day with drifting clouds (the moves' light stands out).
##
## The field closes in by phases (PHASES): a few seconds before each one, the next ring is
## marked on the floor and the log says so; then a low curtain of light closes in to it. It
## is a wall: nobody gets out past it, and as it closes it pushes whoever is in its way
## inward (each copy online moves its own Pokémon). Its clock runs only while the battle is
## on: it stops at the final blow and in the menus. The AI keeps inside it (inside()).

const FIELD_R := 16.0          # the sand; the fighters' limit is just past it
const LIMIT_R := 16.3
const STONE_R := 20.0          # the green stone ring ends at the wall
const L_WALL_H := 3.2
const L_ROWS := 11
const L_ROW_D := 0.85
const L_ROW_H := 0.5
const SECTIONS := 14           # stands sections, split by pillars (and tunnels every other one)
const TRAINER_R := 18.2
## [second of the battle when it starts closing, radius it closes to]. 5 s to close, the
## next ring shown WARN seconds before.
const PHASES := [[30.0, 12.5], [55.0, 9.5], [80.0, 7.0], [105.0, 5.0]]
const CLOSE_T := 5.0
const WARN := 4.0
const C_SAND := Color("c9ac86")        # the field: big slabs of pale warm stone
const C_SAND_DARK := Color("b39572")
const C_JADE := Color("727d72")        # the ring round the field: grey-green paving
const C_JADE_LIGHT := Color("8a958a")
const C_STONE := Color("8f948d")       # grey brick, a touch of green
const C_STONE_DARK := Color("6f756d")
const C_BRONZE := Color("4f6a5c")
const C_RED := Color("c23a32")
const C_BLUE_FLAG := Color("2f5fb0")

var zone_r := FIELD_R
var _zone_mat: ShaderMaterial
var _ground_mat: ShaderMaterial
var _zone_mesh: MeshInstance3D
var _warned := -1
var zone_t := 0.0              # the closing field's clock: only while the battle is on
var _push_fx := {}             # fighter -> seconds since its last push effect
var _banners: Array = []       # pennants that sway: [mesh, phase, base yaw]
var _sky_mat: ShaderMaterial


func build() -> void:
	process_physics_priority = 50          # after the fighters move: the wall puts them back
	_day_environment()
	_league_field()
	_league_limits()
	_league_wall()
	_league_stands()
	_sections()
	_perimeter_wall()
	_scoreboard_tower()
	_zone()
	crowd = Crowd.new()
	add_child(crowd)
	crowd.build(self)


# ---------------------------------------------------------------- shape

func crowd_oval() -> Vector3:
	return Vector3(STONE_R, STONE_R, STONE_R)


func crowd_rows() -> Array:
	var out: Array = []
	for k in L_ROWS:
		out.append([0.3 + L_ROW_D * (k + 0.5), L_WALL_H + L_ROW_H * (k + 1), 0])
	return out


## The crowd in the sun: plain, muted clothes, a few scarves in each side's color, not quite
## full, a little darker than lit (they sit under the light, not in it).
func crowd_look() -> Dictionary:
	return {"clothes": [Color("7a5c48"), Color("4a5a6e"), Color("c9bfa8"), Color("3c3a38"), Color("8c6a3a"),
			Color("5e6b4a"), Color("8a8478"), Color("6e4a52"), Color("a0603c"), Color("6a7f86"), Color("d8d2c2")],
		"sides": [C_RED.darkened(0.1), C_BLUE_FLAG], "glow_a": C_RED, "glow_b": C_BLUE_FLAG,
		"full": 0.78, "brightness": 0.78, "seat": Color("5b605a")}


## Seats leave room for the monument, the aisles between sections and the tunnels.
func seat_free(p: Vector3) -> bool:
	var a := fposmod(atan2(p.z, p.x), TAU / SECTIONS)
	var r := Vector2(p.x, p.z).length()
	var gap := 1.0 / r                       # radians of a 1 m aisle
	if a < gap or a > TAU / SECTIONS - gap:
		return false
	# The tunnels open in the middle of every other section, in the lower rows.
	var mid := absf(a - TAU / SECTIONS * 0.5) * r
	var sec := int(floor(atan2(p.z, p.x) / (TAU / SECTIONS)))
	if sec % 2 == 0 and mid < 1.4 and p.y < L_WALL_H + L_ROW_H * 5.5:
		return false
	return true


func trainer_spot(side: float) -> Vector3:
	return Vector3(side * TRAINER_R, 0.0, 0.0)


## Inside the field as it is now (the AI keeps in).
func inside(p: Vector3, margin := 0.0) -> bool:
	return Vector2(p.x, p.z).length() < zone_r - margin


func on_hype(hype: float, hp: Array) -> void:
	var total: float = hp[0] + hp[1]
	_share_to = hp[0] / total if total > 0.001 else 0.5
	if board:
		board.set_hp(hp[0], hp[1])
	for m in scoreboards:
		m.set_shader_parameter("hype", hype)


func on_rematch() -> void:
	super()
	zone_r = FIELD_R
	_warned = -1
	zone_t = 0.0
	_push_fx.clear()


# ---------------------------------------------------------------- the closing field

## The field's radius at second "t" of the battle.
static func radius_at(t: float) -> float:
	var r := FIELD_R
	for p in PHASES:
		var start: float = p[0]
		if t <= start:
			break
		r = lerpf(r, p[1], clampf((t - start) / CLOSE_T, 0.0, 1.0))
	return r


func _process(delta: float) -> void:
	super(delta)
	if main and main.fighters.size() == 2 and main.intro_t <= 0.0 and _win_t < 0.0:
		zone_t += delta
	zone_r = radius_at(zone_t)
	# The next ring, a few seconds before it closes: marked on the sand, and said.
	var next := -1.0
	for i in PHASES.size():
		var start: float = PHASES[i][0]
		if zone_t >= start - WARN and zone_t < start + CLOSE_T:
			next = PHASES[i][1]
			if _warned < i and zone_t < start:
				_warned = i
				if main and main.hud:
					main.hud.log_entry(tr("The field closes in!"))
				if main and main.audio:
					main.audio.play_sound("charge", Vector3.ZERO, -4.0)
			break
	if _zone_mesh:
		_zone_mesh.visible = zone_r < FIELD_R - 0.01
		_zone_mesh.scale = Vector3(zone_r, 1.0, zone_r)
		_zone_mat.set_shader_parameter("t", _t)
	if _ground_mat:
		_ground_mat.set_shader_parameter("r", zone_r)
		_ground_mat.set_shader_parameter("next_r", next)
		_ground_mat.set_shader_parameter("t", _t)
	# The banners sway in steps.
	for f in _banners:
		var mi: MeshInstance3D = f[0]
		mi.rotation.y = f[2] + 0.2 * sin(floorf(_t * 8.0) / 8.0 * 1.7 + f[1])


## The wall: after the fighters have moved (this runs later, process_physics_priority), a
## Pokémon past the ring is put back on it and loses its speed outward; a puff of light
## where it pushes, now and then.
func _physics_process(delta: float) -> void:
	if main == null or main.fighters.size() < 2:
		return
	for f in main.fighters:
		if not is_instance_valid(f) or f.is_remote or f.state == "ko":
			continue
		var p := Vector2(f.global_position.x, f.global_position.z)
		var lim: float = zone_r - float(f.data.radius) * 0.6
		_push_fx[f] = _push_fx.get(f, 9.0) + delta
		if p.length() <= lim:
			continue
		var n := p.normalized()
		f.global_position.x = n.x * lim
		f.global_position.z = n.y * lim
		var v := Vector2(f.velocity.x, f.velocity.z)
		var out := v.dot(n)
		if out > 0.0:
			v -= n * out
			f.velocity.x = v.x
			f.velocity.z = v.y
		if _push_fx[f] > 0.4:
			_push_fx[f] = 0.0
			var at := Vector3(n.x * zone_r, f.global_position.y + 0.6, n.y * zone_r)
			main.vfx.burst("sparks", at, Vector3(-n.x, 0.3, -n.y), Color(0.45, 1.0, 0.7), 0.5)


# ---------------------------------------------------------------- environment

## A cool, dim day: a pale sun low from one side behind thin haze (soft long shadows),
## cool ambient light and a sky of pixel clouds drifting by (SH_DAY_SKY). Kept dim so the
## moves' light and effects stand out.
func _day_environment() -> void:
	var sky := Sky.new()
	_sky_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SH_DAY_SKY
	_sky_mat.shader = sh
	sky.sky_material = _sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	# The ambient light from a fixed color: the moving clouds do not make it flicker.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("9fb0c8")
	env.ambient_light_energy = 0.34
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.92
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_hdr_threshold = 1.15
	env.ssao_enabled = true
	env.ssao_radius = 1.8
	env.ssao_intensity = 2.0
	env.fog_enabled = true
	env.fog_light_color = Color("aeb8c6")
	env.fog_density = 0.002
	env.fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.9
	env.adjustment_contrast = 1.08
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-30, -60, 0)
	sun.light_energy = 1.05
	sun.light_color = Color(0.92, 0.94, 1.0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	add_child(sun)


const SH_DAY_SKY := """
shader_type sky;
// A cool, hazy day sky in pixels: muted blue overhead, grey toward the horizon, a pale sun, and clouds that drift: noise projected on a high plane, cut into a few flat tones
// (lit on the sun's side, shaded on the other, a darker belly), thinning toward the
// horizon. Far hills in haze on the horizon all round.
uniform vec3 top : source_color = vec3(0.2, 0.33, 0.55);
uniform vec3 mid : source_color = vec3(0.42, 0.53, 0.68);
uniform vec3 horizon : source_color = vec3(0.7, 0.72, 0.74);
uniform vec3 hills : source_color = vec3(0.55, 0.6, 0.66);
uniform vec3 cloud_lit : source_color = vec3(0.88, 0.9, 0.94);
uniform vec3 cloud_mid : source_color = vec3(0.72, 0.75, 0.8);
uniform vec3 cloud_shade : source_color = vec3(0.5, 0.53, 0.6);
uniform float coverage = 0.42;
uniform float speed = 0.012;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	float a = hash(i), b = hash(i + vec2(1, 0)), c = hash(i + vec2(0, 1)), d = hash(i + vec2(1, 1));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0, a = 0.5;
	for (int i = 0; i < 5; i++) { v += a * vnoise(p); p = p * 2.03 + 17.1; a *= 0.5; }
	return v;
}
void sky() {
	vec3 d = EYEDIR;
	float y = d.y;
	vec3 c = mix(horizon, mid, smoothstep(0.0, 0.25, y));
	c = mix(c, top, smoothstep(0.25, 0.8, y));
	vec3 sun_dir = LIGHT0_ENABLED ? LIGHT0_DIRECTION : vec3(0.0, 0.5, 0.86);
	float s = dot(d, sun_dir);
	c += vec3(0.85, 0.88, 0.95) * pow(max(s, 0.0), 24.0) * 0.3;
	if (s > 0.9993) c = vec3(1.1, 1.12, 1.15);
	// Clouds on a plane above.
	if (y > 0.0) {
		vec2 p = d.xz / (y + 0.12) * 0.9;
		p = floor(p * 48.0) / 48.0;
		vec2 drift = vec2(TIME * speed, TIME * speed * 0.35);
		float n = fbm(p + drift);
		float dens = smoothstep(coverage, coverage + 0.18, n);
		dens = floor(dens * 4.0) / 4.0;
		// Light: is the cloud thicker toward the sun (shaded) or away from it (lit)?
		float toward = fbm(p + drift + sun_dir.xz * 0.12);
		float light = clamp((n - toward) * 6.0 + 0.55, 0.0, 1.0);
		vec3 cc = light > 0.66 ? cloud_lit : (light > 0.33 ? cloud_mid : cloud_shade);
		if (n > coverage + 0.3) cc = mix(cc, cloud_shade, 0.35);
		cc = mix(cc, horizon, 1.0 - smoothstep(0.02, 0.25, y));
		dens *= smoothstep(0.0, 0.08, y);
		c = mix(c, cc, dens);
	}
	// Far hills in haze.
	float az = atan(d.x, d.z);
	float hh = 0.025 + 0.03 * vnoise(vec2(az * 3.0, 1.0)) + 0.015 * vnoise(vec2(az * 9.0, 4.0));
	if (y < hh && y > -0.05) c = mix(hills, horizon, 0.35);
	if (y <= -0.05) c = mix(hills, vec3(0.45, 0.42, 0.36), 0.5);
	COLOR = c;
}
"""


# ---------------------------------------------------------------- field

const SH_LEAGUE_FIELD := """
shader_type spatial;
render_mode cull_back;
// The League field in pixels (16 per meter): slabs of pale warm stone, 2 x 1 m in running
// bond, with faint joints and barely different shades (calm, so the
// Pokémon and the moves stand out), worn a little in places, its white lines (border, halfway,
// center rings), and round it the ring of grey-green paving in courses, with lighter
// stripes running out to the wall and each trainer's box.
uniform float field_r = 16.0;
uniform float stone_r = 20.0;
uniform float trainer_r = 18.2;
uniform vec3 sand : source_color;
uniform vec3 sand_dark : source_color;
uniform vec3 jade : source_color;
uniform vec3 jade_light : source_color;
uniform vec3 line_col : source_color;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	float a = hash(i), b = hash(i + vec2(1, 0)), c = hash(i + vec2(0, 1)), d = hash(i + vec2(1, 1));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}
float stroke(float d, float w) { return step(abs(d), w * 0.5); }
void fragment() {
	vec2 cell = floor(wp.xz * 16.0);
	vec2 p = (cell + 0.5) / 16.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float W = 0.14;
	float h = hash(cell);
	// Slabs: all 2 x 1 m, in running bond (each course shifted half a slab), a faint joint,
	// barely varied in shade.
	float wear = noise(p * 0.22) * 0.7 + noise(p * 0.9) * 0.3;
	float course = floor(p.y / 1.0);
	float along = p.x / 2.0 + mod(course, 2.0) * 0.5;
	vec2 slab = vec2(floor(along), course);
	vec3 c = mix(sand, sand_dark, hash(slab) * 0.3);
	c = mix(c, sand_dark, step(0.66, wear) * 0.25);
	c *= h < 0.14 ? 0.96 : (h > 0.93 ? 1.03 : 1.0);
	if (fract(along) < 0.03 || fract(p.y) < 0.06) c *= 0.86;
	// Lines: worn too, a few cells missing.
	float l = stroke(r - (field_r - 0.6), W);
	l = max(l, stroke(p.x, W) * step(r, field_r - 0.6));
	l = max(l, stroke(r - 3.0, W));
	l = max(l, step(r, 0.35));
	l *= step(0.1, hash(cell + 3.1)) * (1.0 - 0.35 * step(0.66, wear));
	c = mix(c, line_col, l * 0.92);
	// The stone ring: courses of tiles, each a slightly different green, dark seams, and
	// lighter stripes running out to the wall every 30 degrees.
	if (r >= field_r) {
		float course = floor((r - field_r) / 1.0);
		float along = a * r / 1.3 + course * 0.5;
		float tile = floor(along);
		float tint = 0.88 + 0.16 * hash(vec2(tile, course));
		vec3 base = jade;
		float spoke = abs(fract(a / (3.14159265 / 6.0) + 0.5) - 0.5) * (3.14159265 / 6.0) * r;
		if (spoke < 0.75) base = jade_light;
		vec3 t = base * tint * (h < 0.15 ? 0.94 : 1.0);
		float seam = max(step(fract(along), 0.05), step(fract((r - field_r) / 1.0), 0.07));
		c = mix(t, base * 0.55, seam);
		// A curb where it meets the slabs.
		if (r < field_r + 0.3) c = jade * 0.62;
		// Each trainer's box: a white outline on the stone.
		for (float s = -1.0; s <= 1.0; s += 2.0) {
			vec2 q = abs(p - vec2(s * trainer_r, 0.0)) - vec2(1.0, 1.4);
			float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
			c = mix(c, line_col, stroke(d, W) * step(0.1, hash(cell + 5.3)));
		}
	}
	ALBEDO = c;
	ROUGHNESS = 0.95;
	SPECULAR = 0.1;
}
"""


func _league_field() -> void:
	_box_collider(Vector3(0, -0.5, 0), Vector3(STONE_R * 2.0 + 30.0, 1.0, STONE_R * 2.0 + 30.0))
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(STONE_R * 2.0 + 1.0, STONE_R * 2.0 + 1.0)
	pm.subdivide_width = 8
	pm.subdivide_depth = 8
	mi.mesh = pm
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SH_LEAGUE_FIELD
	sm.shader = sh
	sm.set_shader_parameter("field_r", FIELD_R)
	sm.set_shader_parameter("stone_r", STONE_R)
	sm.set_shader_parameter("trainer_r", TRAINER_R)
	sm.set_shader_parameter("sand", C_SAND)
	sm.set_shader_parameter("sand_dark", C_SAND_DARK)
	sm.set_shader_parameter("jade", C_JADE)
	sm.set_shader_parameter("jade_light", C_JADE_LIGHT)
	sm.set_shader_parameter("line_col", Color("e8e2d2"))
	mi.material_override = sm
	add_child(mi)


## The fighters' limit just past the sand (an invisible wall, layer 3), and the stone
## wall's collision for projectiles and the camera (layer 1), both round.
func _league_limits() -> void:
	var n := 48
	var d := L_ROWS * L_ROW_D + 1.0
	var top := L_WALL_H + L_ROWS * L_ROW_H + 1.2
	for i in n:
		var a := TAU * (i + 0.5) / n
		var dir := Vector3(cos(a), 0.0, sin(a))
		_round_box(dir * (LIMIT_R + 0.25) + Vector3.UP * 15.0, Vector3(0.5, 30.0, TAU * LIMIT_R / n + 0.3), dir, 4)
		_round_box(dir * (STONE_R + 0.3) + Vector3.UP * L_WALL_H * 0.5, Vector3(0.6, L_WALL_H, TAU * STONE_R / n + 0.3), dir, 1)
		# The stands, for the camera only.
		_round_box(dir * (STONE_R + 0.3 + d * 0.5) + Vector3.UP * top * 0.5, Vector3(d, top, TAU * (STONE_R + d) / n + 0.6), dir, CAMERA_LAYER)


func _round_box(center: Vector3, dims: Vector3, out: Vector3, layer: int) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = dims
	cs.shape = bs
	body.add_child(cs)
	body.transform = Transform3D(Basis.looking_at(out.cross(Vector3.UP), Vector3.UP), center)
	add_child(body)


# ---------------------------------------------------------------- stone

## Weathering shared by the stone shaders: a slow change of tone over meters (no stone is
## one flat color), rain streaks running down the upright faces from where water drips,
## and grime and moss toward the ground.
const WEATHER := """
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	float a = hash(i), b = hash(i + vec2(1, 0)), c = hash(i + vec2(0, 1)), d = hash(i + vec2(1, 1));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}
// Moss and ivy grow where water stays: "ground" is the height of the piece's foot (moss
// creeps up from it in a wavy band), "top_y" the height of its top edge (ivy hangs down
// from it in clumps of different lengths; -1 for none). Moss also sits on top faces and in
// patches, in chunky clumps of 1/8 m cells so it reads as growth, not noise.
vec3 weather(vec3 c, vec3 at, vec3 n, float ground, float top_y) {
	float big = vnoise(at.xz * 0.07 + vec2(at.y * 0.04, 0.0)) * 0.6 + vnoise(at.xz * 0.23 + at.y * 0.1) * 0.4;
	c *= 0.86 + 0.24 * floor(big * 4.0) / 4.0;
	c = mix(c, c * vec3(1.03, 0.99, 0.93), step(0.6, vnoise(at.xz * 0.05 + 7.0)));
	float u = abs(n.x) > abs(n.z) ? at.z : at.x;
	vec2 chunk = abs(n.y) > 0.7 ? floor(at.xz * 8.0) : floor(vec2(u, at.y) * 8.0);
	float jit = hash(chunk);
	vec3 moss_dark = vec3(0.2, 0.3, 0.13);
	vec3 moss = vec3(0.3, 0.43, 0.18);
	vec3 moss_light = vec3(0.45, 0.55, 0.24);
	vec3 m_col = jit < 0.3 ? moss_dark : (jit < 0.8 ? moss : moss_light);
	if (abs(n.y) < 0.7) {
		// Rain streaks.
		float col = floor(u * 16.0);
		float run = vnoise(vec2(col * 0.21, floor(at.y * 16.0) / 16.0 * 0.6));
		if (hash(vec2(col, 3.0)) > 0.72 && run > 0.55) c *= 0.86;
		// Moss creeping up from the foot, its top edge wavy.
		float reach = 0.25 + 0.7 * vnoise(vec2(u * 0.45, 2.0)) + 0.15 * jit;
		if (at.y - ground < reach) c = mix(c, m_col, 0.85);
		// Ivy hanging from the top edge, in clumps of different lengths.
		if (top_y > 0.0) {
			float clump = vnoise(vec2(u * 0.5, 9.0));
			float hang = clump > 0.5 ? (clump - 0.5) * 5.0 : 0.0;
			float edge = top_y - at.y;
			float ragged = hang * (0.75 + 0.5 * vnoise(vec2(u * 3.0, 4.0)));
			if (edge >= 0.0 && edge < ragged && jit > 0.18) c = m_col;
			else if (edge >= 0.0 && edge < ragged + 0.25 && jit > 0.7) c = moss_dark;
		}
	} else if (n.y > 0.7) {
		// Moss on top faces, in patches.
		float p = vnoise(at.xz * 0.6 + 5.0);
		if (p > 0.62 && jit > 0.15) c = mix(c, m_col, 0.9);
	}
	// A darker damp band at the very foot.
	float low = 1.0 - clamp((at.y - ground) / 0.6, 0.0, 1.0);
	c *= 1.0 - 0.15 * low;
	return c;
}
"""

const SH_ASHLAR := """
shader_type spatial;
render_mode cull_back;
// Sandstone blocks (ashlar) in pixels, 16 per meter: courses of "course" meters, blocks of
// about "block" long, every other course shifted half a block, recessed dark joints with a
// lit lower lip, each block its own shade with a few chips, then weathered (WEATHER).
// Measured on the mesh's UV in meters (rings) or on the world ("world", boxes).
uniform vec3 stone : source_color;
uniform vec3 joint : source_color;
uniform float course = 0.6;
uniform float block = 1.3;
uniform float foot = 0.0;
uniform float crown = -1.0;
uniform bool world = false;
varying vec3 wp;
varying vec3 wn;
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
%s
void fragment() {
	vec2 uv = UV;
	if (world) {
		if (abs(wn.y) > 0.7) uv = wp.xz;
		else uv = vec2(abs(wn.x) > abs(wn.z) ? wp.z : wp.x, wp.y);
	}
	vec2 m = floor(uv * 16.0) / 16.0;
	float row = floor(m.y / course);
	float x = m.x / block + row * 0.5 + hash(vec2(row, 1.0)) * 0.3;
	vec2 id = vec2(floor(x), row);
	vec3 c = stone * (0.86 + 0.2 * hash(id));
	float h = hash(floor(uv * 16.0));
	c *= h < 0.12 ? 0.9 : (h > 0.93 ? 1.05 : 1.0);
	float jx = fract(x) * block;
	float jy = fract(m.y / course) * course;
	if (jx < 0.07 || jy < 0.07) c = joint;
	else if (jy < 0.13) c *= 1.08;
	c = weather(c, wp, wn, foot, crown);
	ALBEDO = c;
	ROUGHNESS = 0.95;
	SPECULAR = 0.08;
}
""" % WEATHER


func _ashlar(col: Color, course := 0.6, block := 1.3, foot := 0.0, world := false, crown := -1.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SH_ASHLAR
	m.shader = sh
	m.set_shader_parameter("stone", col)
	m.set_shader_parameter("joint", col.darkened(0.5))
	m.set_shader_parameter("course", course)
	m.set_shader_parameter("block", block)
	m.set_shader_parameter("foot", foot)
	m.set_shader_parameter("crown", crown)
	m.set_shader_parameter("world", world)
	return m


const SH_STONE := """
shader_type spatial;
render_mode cull_back;
// Dressed stone in one piece, in pixels (16 per meter on the world): a fine grain, specks
// and chips, lighter on top faces (worn by the sun), weathered (WEATHER); "flutes" carves
// vertical grooves every that many meters (the columns), "band" a carved line at that
// height above the piece's base.
uniform vec3 stone : source_color;
uniform float flutes = 0.0;
uniform float band = -1.0;
uniform float foot = 0.0;
uniform float crown = -1.0;
varying vec3 wp;
varying vec3 wn;
varying vec3 base;
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	base = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
}
%s
void fragment() {
	vec2 uv = abs(wn.y) > 0.7 ? wp.xz : vec2(abs(wn.x) > abs(wn.z) ? wp.z : wp.x, wp.y);
	vec2 cell = floor(uv * 16.0);
	float h = hash(cell);
	vec3 c = stone * (h < 0.12 ? 0.9 : (h > 0.93 ? 1.05 : 1.0));
	if (hash(floor(uv * 4.0)) > 0.94 && h > 0.5) c *= 0.85;
	if (wn.y > 0.7) c *= 1.08;
	if (flutes > 0.0 && abs(wn.y) < 0.7) {
		float f = fract(uv.x / flutes);
		if (f < 0.18) c *= 0.78;
		else if (f < 0.3) c *= 0.9;
	}
	if (band > 0.0 && abs(wn.y) < 0.7 && abs(wp.y - base.y - band) < 0.06) c *= 0.7;
	c = weather(c, wp, wn, foot, crown);
	ALBEDO = c;
	ROUGHNESS = 0.9;
	SPECULAR = 0.1;
}
""" % WEATHER


func _stone(col: Color, flutes := 0.0, band := -1.0, foot := 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SH_STONE
	m.shader = sh
	m.set_shader_parameter("stone", col)
	m.set_shader_parameter("flutes", flutes)
	m.set_shader_parameter("band", band)
	m.set_shader_parameter("foot", foot)
	return m


const SH_STEPS := """
shader_type spatial;
render_mode cull_back;
// The stands' steps: the treads (top faces) pale and worn smooth, the risers in shadowier
// stone with a thin lip; each row a slightly different shade, then weathered (WEATHER), so
// the rows read without drawing blocks on them.
uniform vec3 tread : source_color;
uniform vec3 riser : source_color;
uniform float row_h = 0.5;
uniform float wall_h = 3.2;
varying vec3 wp;
varying vec3 wn;
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
%s
void fragment() {
	float row = floor((wp.y - wall_h + 0.01) / row_h);
	float shade = 0.94 + 0.08 * hash(vec2(row, 3.0));
	vec2 cell = floor(vec2(atan(wp.z, wp.x) * length(wp.xz), wp.y + length(wp.xz)) * 16.0);
	float h = hash(cell);
	vec3 c;
	if (wn.y > 0.7) {
		c = tread * shade * (h < 0.2 ? 0.94 : 1.0);
	} else {
		c = riser * shade;
		float up = fract((wp.y - wall_h + 0.01) / row_h);
		if (up > 0.86) c = tread * shade * 0.92;
		c *= h < 0.15 ? 0.92 : 1.0;
	}
	c = weather(c, wp, wn, -10.0, -1.0);
	ALBEDO = c;
	ROUGHNESS = 0.92;
	SPECULAR = 0.1;
}
""" % WEATHER


## The wall round the stone ring: big sandstone blocks, a green stone band and a coping.
func _league_wall() -> void:
	_ring(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.0, L_WALL_H - 0.5)]), _ashlar(C_STONE, 0.8, 1.9, 0.0, false, L_WALL_H - 0.5), true, crowd_oval())
	_ring(PackedVector2Array([Vector2(0.0, L_WALL_H - 0.5), Vector2(0.0, L_WALL_H - 0.1)]), _stone(C_JADE.darkened(0.1), 0.0, -1.0, -10.0), true, crowd_oval())
	_ring(PackedVector2Array([Vector2(-0.2, L_WALL_H - 0.1), Vector2(-0.2, L_WALL_H), Vector2(0.4, L_WALL_H)]), _stone(C_STONE.lightened(0.1), 0.0, -1.0, -10.0), true, crowd_oval())


func _stands_back() -> float:
	return STONE_R + 0.3 + L_ROWS * L_ROW_D + 0.7


func _stands_top() -> float:
	return L_WALL_H + L_ROWS * L_ROW_H


func _league_stands() -> void:
	var profile := PackedVector2Array([Vector2(0.3, L_WALL_H)])
	var d := 0.3
	var y := L_WALL_H
	for k in L_ROWS:
		profile.append(Vector2(d, y + L_ROW_H))
		y += L_ROW_H
		d += L_ROW_D
		profile.append(Vector2(d, y))
	var steps := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SH_STEPS
	steps.shader = sh
	steps.set_shader_parameter("tread", C_STONE.lightened(0.06))
	steps.set_shader_parameter("riser", C_STONE_DARK.darkened(0.12))
	steps.set_shader_parameter("row_h", L_ROW_H)
	steps.set_shader_parameter("wall_h", L_WALL_H)
	_ring(profile, steps, true, crowd_oval())
	# The parapet (plain stone with a jade coping) and the outer wall: big blocks with a
	# row of arches along it.
	_ring(PackedVector2Array([Vector2(d, y), Vector2(d, y + 1.1), Vector2(d + 0.7, y + 1.1)]), _stone(C_STONE, 0.0, -1.0, -10.0), true, crowd_oval())
	_ring(PackedVector2Array([Vector2(d - 0.05, y + 1.1), Vector2(d - 0.05, y + 1.3), Vector2(d + 0.75, y + 1.3)]), _stone(C_JADE.darkened(0.05), 0.0, -1.0, -10.0), true, crowd_oval())
	_ring(PackedVector2Array([Vector2(d + 0.7, y + 1.1), Vector2(d + 0.7, 0.0)]), _ashlar(C_STONE_DARK, 0.9, 2.0), true, crowd_oval())


## The pillars between sections (up the stands, a little proud of the rows, with a cap on
## top of the parapet) and, in every other section, a tunnel opening in the lower rows.
func _sections() -> void:
	var pillar := _stone(C_STONE.lightened(0.04), 0.0, -1.0, -10.0)
	var cap := _stone(C_JADE.darkened(0.1), 0.0, -1.0, -10.0)
	var lintel := _stone(C_STONE.lightened(0.1), 0.0, 0.25, -10.0)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color("1d1914")
	dark.roughness = 1.0
	var depth := L_ROWS * L_ROW_D
	var top := _stands_top()
	for i in SECTIONS:
		var a := TAU * i / SECTIONS
		var dir := Vector3(cos(a), 0.0, sin(a))
		var mid := dir * (STONE_R + 0.3 + depth * 0.5)
		var b := Basis.looking_at(dir, Vector3.UP)
		var rise := Basis(Vector3(-dir.z, 0.0, dir.x), atan2(L_ROW_H, L_ROW_D))
		_box(Vector3(0.7, 0.9, depth + 1.2), mid + Vector3.UP * (L_WALL_H + top) * 0.5 + Vector3.UP * 0.25, pillar, rise * b)
		_box(Vector3(1.1, 0.5, 1.1), dir * (STONE_R + 0.3 + depth + 0.35) + Vector3.UP * (top + 1.55), cap, b)
		if i % 2 == 0:
			var ta := a + TAU / SECTIONS * 0.5
			var td := Vector3(cos(ta), 0.0, sin(ta))
			var tb := Basis.looking_at(td, Vector3.UP)
			var tp := td * (STONE_R + 0.3 + L_ROW_D * 2.0)
			_box(Vector3(2.2, 2.3, 3.4), tp + Vector3.UP * (L_WALL_H + 1.15), dark, tb)
			_box(Vector3(3.2, 0.55, 0.7), td * (STONE_R + 0.6) + Vector3.UP * (L_WALL_H + 2.5), lintel, tb)
			for s in [-1.0, 1.0]:
				var side: Vector3 = Vector3(-td.z, 0.0, td.x) * s * 1.35
				_box(Vector3(0.5, 2.5, 0.6), td * (STONE_R + 0.6) + side + Vector3.UP * (L_WALL_H + 1.25), pillar, tb)


# ---------------------------------------------------------------- the perimeter wall

## A wall all round behind the stands, standing on the ground outside them: big grey
## bricks up past the stands' top, a coping, and a row of small square openings near the
## top every few meters.
func _perimeter_wall() -> void:
	var r := _stands_back() + 0.9
	var top := _stands_top() + 2.6
	var bricks := _ashlar(C_STONE_DARK, 0.45, 1.1, 0.0, false, top)
	var coping := _stone(C_STONE.lightened(0.08), 0.0, -1.0, -10.0)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color("1b1d1a")
	dark.roughness = 1.0
	var oval := Vector3(r, r, r)
	_ring(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.0, top), Vector2(0.9, top), Vector2(0.9, 0.0)]), bricks, true, oval)
	_ring(PackedVector2Array([Vector2(-0.15, top), Vector2(-0.15, top + 0.3), Vector2(1.05, top + 0.3), Vector2(1.05, top)]), coping, true, oval)
	var n := 48
	for i in n:
		var a := TAU * (i + 0.5) / n
		var d := Vector3(cos(a), 0.0, sin(a))
		_box(Vector3(0.7, 0.7, 0.3), d * (r - 0.12) + Vector3.UP * (top - 1.0), dark, Basis.looking_at(d, Vector3.UP))


## A straight bar from a to b, "w" meters thick.
func _beam(a: Vector3, b: Vector3, w: float, mat: Material) -> void:
	var d := b - a
	var up := Vector3.UP if absf(d.normalized().y) < 0.95 else Vector3.RIGHT
	_box(Vector3(w, w, d.length()), (a + b) * 0.5, mat, Basis.looking_at(d.normalized(), up))


# ---------------------------------------------------------------- the scoreboard tower

## The scoreboard on its own tower, behind the far stands (built on the ground outside
## them, not in them): two stone pylons in big blocks rising above the stands' top, a
## crossbeam with a bronze Poké Ball emblem, the screen between them in a jade frame,
## tilted a little down toward the field, and a long banner hanging on each pylon.
func _scoreboard_tower() -> void:
	var blocks := _ashlar(C_STONE, 0.9, 2.0, 0.0, true)
	var light := _stone(C_STONE.lightened(0.1), 0.0, -1.0, -10.0)
	var jade := _stone(C_JADE.darkened(0.05), 0.0, -1.0, -10.0)
	var bronze := _material(C_BRONZE, 0.55, 0.5, "metal")
	var z := -(_stands_back() + 3.4)
	var top := _stands_top() + 1.3
	var py := 25.0
	for s in [-1.0, 1.0]:
		var x: float = s * 10.6
		_box(Vector3(3.0, 1.0, 3.6), Vector3(x, 0.5, z), light)
		_box(Vector3(2.4, py, 3.0), Vector3(x, py * 0.5, z), blocks)
		_box(Vector3(3.0, 0.8, 3.6), Vector3(x, py + 0.4, z), jade)
		_box(Vector3(2.0, 1.6, 2.6), Vector3(x, py + 1.6, z), light)
		# The banner down the pylon's field side.
		var flag := MeshInstance3D.new()
		var fq := QuadMesh.new()
		fq.size = Vector2(1.7, 9.0)
		flag.mesh = fq
		var fm := StandardMaterial3D.new()
		fm.albedo_color = C_RED if s < 0.0 else C_BLUE_FLAG
		fm.cull_mode = BaseMaterial3D.CULL_DISABLED
		fm.roughness = 0.9
		flag.material_override = fm
		flag.position = Vector3(x, py - 6.0, z + 1.52)
		add_child(flag)
	# Crossbeams, top and bottom, and the emblem.
	_box(Vector3(23.6, 1.4, 2.2), Vector3(0, py - 0.3, z), light)
	_box(Vector3(19.0, 0.9, 1.6), Vector3(0, top + 0.6, z), light)
	var ball := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.2
	cm.bottom_radius = 1.2
	cm.height = 0.35
	cm.radial_segments = 24
	ball.mesh = cm
	ball.material_override = bronze
	ball.rotation.x = PI * 0.5
	ball.position = Vector3(0, py + 1.2, z + 0.4)
	add_child(ball)
	_box(Vector3(2.4, 0.26, 0.4), Vector3(0, py + 1.2, z + 0.45), light)
	var btn := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.4
	bm.bottom_radius = 0.4
	bm.height = 0.5
	bm.radial_segments = 16
	btn.mesh = bm
	btn.material_override = light
	btn.rotation.x = PI * 0.5
	btn.position = Vector3(0, py + 1.2, z + 0.5)
	add_child(btn)
	# The screen in its frame, tilted toward the field.
	var holder := Node3D.new()
	holder.position = Vector3(0, (top + 1.1 + py - 1.0) * 0.5, z + 0.3)
	holder.rotation.x = -0.14
	add_child(holder)
	var fw := 17.6
	var fh := py - 1.0 - (top + 1.1) - 0.4
	var frame := MeshInstance3D.new()
	var fb := BoxMesh.new()
	fb.size = Vector3(fw + 0.8, fh + 0.8, 0.8)
	frame.mesh = fb
	frame.material_override = jade
	holder.add_child(frame)
	var vp := SubViewport.new()
	vp.size = Scoreboard.SIZE
	vp.transparent_bg = false
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	board = Scoreboard.new()
	board.colors = [C_RED, C_BLUE_FLAG]
	vp.add_child(board)
	add_child(vp)
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(fw, minf(fh, fw * 84.0 / 192.0))
	q.mesh = qm
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SH_BOARD
	sm.shader = sh
	sm.set_shader_parameter("board", vp.get_texture())
	q.material_override = sm
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	q.position.z = 0.42
	holder.add_child(q)
	scoreboards.append(sm)


# ---------------------------------------------------------------- the zone

const SH_ZONE_WALL := """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, blend_mix, depth_draw_never;
// The closing wall as a low aurora: thin vertical rays hanging over the edge, deep green
// at the foot shading to teal and violet at the tips, rippling sideways, fading out at
// the top and near the camera (so it never covers the view when the camera is out past
// it). In pixel cells measured in meters, moving in steps.
uniform float t = 0.0;
varying vec3 wp;
varying float hgt;
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	hgt = VERTEX.y + 0.5;
}
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void fragment() {
	float around = atan(wp.z, wp.x) * length(wp.xz);
	float tt = floor(t * 10.0) / 10.0;
	vec2 cell = floor(vec2(around, wp.y) * 10.0);
	float x = cell.x / 10.0;
	float ripple = sin(x * 0.6 + tt * 1.2) * 0.6 + sin(x * 1.7 - tt * 1.9) * 0.4;
	// Rays: thin, uneven in height.
	float ray = step(0.78, fract(x * 1.6 + ripple * 0.35));
	float tall = 0.45 + 0.55 * hash(vec2(floor(x * 2.2 + ripple * 0.35), floor(tt * 1.5)));
	float h = hgt / tall;
	if (h > 1.0) discard;
	vec3 col = mix(vec3(0.3, 1.0, 0.6), vec3(0.3, 0.85, 1.0), smoothstep(0.25, 0.6, h));
	col = mix(col, vec3(0.7, 0.45, 1.0), smoothstep(0.6, 1.0, h));
	// Only the rays show, thin and apart, fading fast upward; between them nothing.
	if (ray < 0.5) discard;
	float a = 0.42 * (1.0 - h) * (1.0 - h);
	// The foot: a thin line of light on the floor.
	if (hgt < 0.04) { a = 0.55; col = vec3(0.5, 1.0, 0.75); }
	a *= smoothstep(1.5, 5.0, length(VERTEX));
	a = floor(a * 8.0) / 8.0;
	if (a < 0.04) discard;
	ALBEDO = col;
	EMISSION = col * 0.35;
	ALPHA = a;
}
"""

const SH_ZONE_GROUND := """
shader_type spatial;
render_mode unshaded, shadows_disabled, blend_mix, depth_draw_never;
// The ground outside the field as it is now, tinted; and the next ring, dashed, while it is
// announced (a slow pulse, no blinking).
uniform float r = 16.0;
uniform float field_r = 16.0;
uniform float next_r = -1.0;
uniform float t = 0.0;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 cell = floor(wp.xz * 16.0);
	vec2 p = (cell + 0.5) / 16.0;
	float d = length(p);
	float a = 0.0;
	vec3 c = vec3(0.2, 0.3, 0.32);
	if (d > field_r) discard;
	if (d > r && r < field_r - 0.01) a = 0.2;
	if (next_r > 0.0 && abs(d - next_r) < 0.22) {
		float dash = step(0.4, fract(atan(p.y, p.x) * next_r / 1.0));
		c = vec3(0.95, 0.2, 0.12);
		a = dash * (0.7 + 0.25 * sin(t * 6.2831 * 1.2));
	}
	if (a < 0.02) discard;
	ALBEDO = c;
	ALPHA = a;
}
"""


func _zone() -> void:
	_zone_mesh = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.0
	cm.bottom_radius = 1.0
	cm.height = 2.2
	cm.radial_segments = 96
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	_zone_mesh.mesh = cm
	_zone_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SH_ZONE_WALL
	_zone_mat.shader = sh
	_zone_mesh.material_override = _zone_mat
	_zone_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_zone_mesh.position.y = 1.1
	_zone_mesh.visible = false
	add_child(_zone_mesh)
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(FIELD_R * 2.0 + 0.5, FIELD_R * 2.0 + 0.5)
	g.mesh = pm
	_ground_mat = ShaderMaterial.new()
	var sh2 := Shader.new()
	sh2.code = SH_ZONE_GROUND
	_ground_mat.shader = sh2
	_ground_mat.set_shader_parameter("field_r", FIELD_R)
	g.material_override = _ground_mat
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.position.y = 0.02
	add_child(g)
