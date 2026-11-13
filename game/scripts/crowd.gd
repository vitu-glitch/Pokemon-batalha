class_name Crowd
extends Node3D
## The night stadium's crowd: 2D pixel sprites in a single MultiMesh (thousands of people
## in one draw call) animated on the GPU, and a "director" that reads the battle and
## decides how each half of the stands feels.
##
## The sprite (12 × 20 px) is drawn here in 8 poses: seated, clap A and B, standing, arms
## up, jumping, hands on the head and waving a light stick. It carries no colors: each
## pixel stores what it is (skin, hair, shirt...) and the shader colors each person, so
## nobody repeats.
##
## Each half cheers for one fighter (pink on the left, x < 0; cyan on the right; the
## middle is neutral). What lifts the mood, from less to more:
##   normal hit < big hit (by how much HP it takes) < last-moment dodge <
##   comeback (whoever was far behind takes the lead) < close finish.
## Tension (hands on the head) rises when someone is low on HP. If the mood stays high
## for a while, the wave starts. At the end, the ovation grows with how good the battle
## was (quality 0-1).

const SPRITE_W := 12
const SPRITE_H := 20
const POSES := 8
const OCCUPANCY := 0.86

# What each pixel stores (red channel / 8).
const EMPTY := 0
const SKIN := 1
const HAIR := 2
const SHIRT := 3
const SHIRT_SHADE := 4
const LEGS := 5
const OUTLINE := 6
const STICK := 7

const SH_CROWD := """
shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha;
// People as pixel sprites facing the camera (turning only around the vertical).
// CUSTOM: x phase, y temperament, z side (0 pink, 0.5 neutral, 1 cyan), w place in the stands (0-1).
// COLOR: clothes (rgb) and skin and hair seed (a).
uniform sampler2D poses : filter_nearest;
uniform float mood_pink = 0.1;
uniform float mood_cyan = 0.1;
uniform float tension_pink = 0.0;
uniform float tension_cyan = 0.0;
uniform float wave_pos = 0.0;
uniform float wave_strength = 0.0;
uniform float ovation = 0.0;
uniform float flashes = 0.003;
uniform float brightness = 1.0;
uniform vec3 pink : source_color;
uniform vec3 cyan : source_color;
varying vec4 cus;
varying vec4 col;
varying float pose;
varying float hop;
float hash(float n) { return fract(sin(n * 91.3458) * 47453.5453); }

void vertex() {
	cus = INSTANCE_CUSTOM;
	col = COLOR;
	float side = cus.z;
	float mood = side < 0.25 ? mood_pink : (side > 0.75 ? mood_cyan : (mood_pink + mood_cyan) * 0.5);
	float tension = side < 0.25 ? tension_pink : (side > 0.75 ? tension_cyan : max(tension_pink, tension_cyan) * 0.7);
	float temp = cus.y;
	// Everyone reacts their own way: the calm ones take longer to stand up.
	float me = clamp(mood + (temp - 0.5) * 0.4, 0.0, 1.0);
	me = max(me, ovation * (0.55 + temp * 0.45));
	float t = TIME + cus.x * 7.0;
	float stick = step(0.78, hash(cus.x * 13.1));
	hop = 0.0;
	float d_wave = abs(fract(cus.w - wave_pos + 0.5) - 0.5);
	if (wave_strength > 0.0 && d_wave < 0.025) {
		pose = 4.0;
		hop = 0.12 * (1.0 - d_wave / 0.025);
	} else if (tension > 0.35 && hash(cus.x * 5.7 + floor(TIME * 0.5)) < tension) {
		pose = 6.0;
	} else if (me < 0.25) {
		// Seated; now and then a little clapping.
		pose = step(0.93, hash(cus.x + floor(t * 0.4))) * (1.0 + step(0.5, fract(t * 2.5)));
	} else if (me < 0.5) {
		pose = stick > 0.5 ? 7.0 : 1.0 + step(0.5, fract(t * (2.0 + temp * 1.5)));
	} else if (me < 0.8) {
		pose = stick > 0.5 ? 7.0 : (fract(t * 0.9) > 0.5 ? 4.0 : 3.0);
	} else {
		pose = stick > 0.5 ? 7.0 : 5.0;
		hop = abs(sin(t * (3.0 + temp))) * 0.2;
	}
	// A card that always faces the camera (turning only around the vertical). Instances
	// are not rotated, so orienting the card here is enough and Godot lights and shades it
	// like everything else.
	vec3 right = normalize(vec3(INV_VIEW_MATRIX[0].x, 0.0, INV_VIEW_MATRIX[0].z));
	vec3 toward = normalize(vec3(INV_VIEW_MATRIX[2].x, 0.0, INV_VIEW_MATRIX[2].z));
	VERTEX = right * VERTEX.x + vec3(0.0, VERTEX.y + hop, 0.0);
	NORMAL = normalize(toward + vec3(0.0, 0.35, 0.0));
}

void fragment() {
	vec2 uv = vec2((UV.x + floor(pose + 0.5)) / 8.0, UV.y);
	float what = floor(texture(poses, uv).r * 8.0 + 0.5);
	if (what < 0.5) discard;
	float s = col.a;
	vec3 skin = s < 0.33 ? vec3(0.95, 0.78, 0.63) : (s < 0.66 ? vec3(0.76, 0.55, 0.4) : vec3(0.42, 0.28, 0.19));
	float hs = fract(s * 13.7);
	vec3 hair = hs < 0.3 ? vec3(0.14, 0.1, 0.08) : (hs < 0.55 ? vec3(0.42, 0.26, 0.13) : (hs < 0.75 ? vec3(0.86, 0.72, 0.36) : vec3(0.3, 0.3, 0.36)));
	vec3 side_col = cus.z < 0.25 ? pink : (cus.z > 0.75 ? cyan : mix(pink, cyan, step(0.5, hash(cus.x))));
	vec3 c = col.rgb;
	if (what == 1.0) c = skin;
	else if (what == 2.0) c = hair;
	else if (what == 4.0) c = col.rgb * 0.7;
	else if (what == 5.0) c = vec3(0.18, 0.2, 0.26);
	else if (what == 6.0) c = vec3(0.06, 0.06, 0.08);
	vec3 glow = vec3(0.0);
	if (what == 7.0) glow = side_col * 3.5;
	// Phone flash: a single person, for an instant, next to the face.
	float slot = floor(TIME / 0.6);
	float flash = step(hash(cus.x * 31.7 + slot), flashes) * step(fract(TIME / 0.6), 0.12);
	if (flash > 0.5 && UV.y < 0.45 && UV.y > 0.25 && abs(UV.x - 0.72) < 0.12) glow = vec3(7.0);
	ALBEDO = c * brightness;
	// Almost no light of their own (the crowd stays dark): reactions read through movement.
	EMISSION = glow;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
"""

var mat: ShaderMaterial
var mood := [0.1, 0.1]       # 0 = pink (left, x < 0), 1 = cyan (right)
var tension := [0.0, 0.0]
var ovation := 0.0
var wave_pos := 0.0
var wave_strength := 0.0
var _high_t := 0.0             # how long the mood has been high (to start the wave)
var _hp := [1.0, 1.0]
var _worst_gap := [0.0, 0.0]   # the furthest behind each side has been
var _leader := 0
var lead_changes := 0
var best_comeback := 0.0
var _stadium: NightStadium


func build(stadium: NightStadium) -> void:
	_stadium = stadium
	_seats_and_people()


## Back to a calm crowd for a new battle (rematch).
func reset() -> void:
	mood = [0.1, 0.1]
	tension = [0.0, 0.0]
	ovation = 0.0
	wave_strength = 0.0
	_high_t = 0.0
	_hp = [1.0, 1.0]
	_worst_gap = [0.0, 0.0]
	_leader = 0
	lead_changes = 0
	best_comeback = 0.0


# ---------------------------------------------------------------- sprite

func _sprite() -> ImageTexture:
	var img := Image.create(SPRITE_W * POSES, SPRITE_H, false, Image.FORMAT_R8)
	for p in POSES:
		_draw_pose(img, p)
	return ImageTexture.create_from_image(img)


func _rect(img: Image, ox: int, x: int, y: int, w: int, h: int, what: int) -> void:
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			if xx >= 0 and xx < SPRITE_W and yy >= 0 and yy < SPRITE_H:
				img.set_pixel(ox + xx, yy, Color(what / 8.0 + 0.01, 0, 0))


## Pose p in column p of the atlas. Standing, the body rises 3 px; the arms change with
## the pose.
func _draw_pose(img: Image, p: int) -> void:
	var ox := p * SPRITE_W
	var standing := p in [3, 4, 5, 6, 7]
	var dy := -3 if standing else 0
	var head := 4 + dy
	# Head: hair on top, face, outline at the sides.
	_rect(img, ox, 4, head - 1, 4, 2, HAIR)
	_rect(img, ox, 4, head + 1, 4, 3, SKIN)
	_rect(img, ox, 3, head, 1, 3, HAIR)
	_rect(img, ox, 8, head, 1, 3, HAIR)
	_rect(img, ox, 5, head + 2, 1, 1, OUTLINE)    # eyes
	_rect(img, ox, 7, head + 2, 1, 1, OUTLINE)
	# Torso with a shaded side.
	_rect(img, ox, 3, head + 4, 6, 6, SHIRT)
	_rect(img, ox, 7, head + 4, 2, 6, SHIRT_SHADE)
	# Legs: seated they look short (knees forward); standing, long.
	if standing:
		_rect(img, ox, 3, head + 10, 2, 6, LEGS)
		_rect(img, ox, 7, head + 10, 2, 6, LEGS)
	else:
		_rect(img, ox, 3, head + 10, 6, 3, LEGS)
	# Arms.
	match p:
		0, 3:
			_rect(img, ox, 2, head + 5, 1, 5, SHIRT_SHADE)
			_rect(img, ox, 9, head + 5, 1, 5, SHIRT_SHADE)
			_rect(img, ox, 2, head + 10, 1, 1, SKIN)
			_rect(img, ox, 9, head + 10, 1, 1, SKIN)
		1:
			_rect(img, ox, 2, head + 6, 2, 1, SHIRT_SHADE)
			_rect(img, ox, 8, head + 6, 2, 1, SHIRT_SHADE)
			_rect(img, ox, 5, head + 6, 2, 2, SKIN)
		2:
			_rect(img, ox, 2, head + 5, 1, 2, SHIRT_SHADE)
			_rect(img, ox, 9, head + 5, 1, 2, SHIRT_SHADE)
			_rect(img, ox, 3, head + 4, 1, 1, SKIN)
			_rect(img, ox, 8, head + 4, 1, 1, SKIN)
		4, 5:
			_rect(img, ox, 2, head - 3, 1, 8, SHIRT_SHADE)
			_rect(img, ox, 9, head - 3, 1, 8, SHIRT_SHADE)
			_rect(img, ox, 2, head - 4, 1, 1, SKIN)
			_rect(img, ox, 9, head - 4, 1, 1, SKIN)
		6:
			_rect(img, ox, 2, head + 1, 1, 4, SHIRT_SHADE)
			_rect(img, ox, 9, head + 1, 1, 4, SHIRT_SHADE)
			_rect(img, ox, 3, head - 1, 1, 2, SKIN)
			_rect(img, ox, 8, head - 1, 1, 2, SKIN)
		7:
			_rect(img, ox, 2, head + 5, 1, 5, SHIRT_SHADE)
			_rect(img, ox, 9, head - 2, 1, 7, SHIRT_SHADE)
			_rect(img, ox, 9, head - 3, 1, 1, SKIN)
			_rect(img, ox, 9, head - 8, 1, 5, STICK)
			_rect(img, ox, 10, head - 7, 1, 3, STICK)


# ---------------------------------------------------------------- stands

func _seats_and_people() -> void:
	var e := _stadium
	# The stage's own look for its crowd, if it has one (the League's, in the sun).
	var look: Dictionary = e.crowd_look() if e.has_method("crowd_look") else {}
	var seat := BoxMesh.new()
	seat.size = Vector3(0.48, 0.42, 0.42)
	var sites: Array = []
	var o := e.crowd_oval()
	for f in e.crowd_rows():
		var d: float = f[0]
		var y: float = f[1]
		for p in e.spots(o.x + d, o.y + d, o.z + d, 0.55):
			var s: float = p[2]
			if fmod(s, 12.0) < 1.1:
				continue        # stairs
			if e.has_method("seat_free") and not e.seat_free(p[0] + Vector3.UP * y):
				continue
			sites.append([p[0] + Vector3.UP * y, p[1], s / p[3]])
	var mm_seats := MultiMesh.new()
	mm_seats.transform_format = MultiMesh.TRANSFORM_3D
	mm_seats.use_colors = true
	mm_seats.mesh = seat
	mm_seats.instance_count = sites.size()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var people: Array = []
	for i in sites.size():
		var pos: Vector3 = sites[i][0]
		var n: Vector3 = sites[i][1]
		mm_seats.set_instance_transform(i, Transform3D(Basis.looking_at(-n, Vector3.UP), pos + Vector3.UP * 0.21))
		mm_seats.set_instance_color(i, look.get("seat", Color("24343c") if pos.x < 0 else Color("1f3a44")))
		if rng.randf() < look.get("full", OCCUPANCY):
			people.append([pos + n * 0.08 + Vector3.UP * 0.16, sites[i][2], pos.x])
	var seats_mi := MultiMeshInstance3D.new()
	seats_mi.multimesh = mm_seats
	var seat_mat := StandardMaterial3D.new()
	seat_mat.vertex_color_use_as_albedo = true
	seat_mat.roughness = 0.6
	seats_mi.material_override = seat_mat
	add_child(seats_mi)
	# People.
	var quad := QuadMesh.new()
	quad.size = Vector2(0.62, 1.03)
	quad.center_offset = Vector3(0, 0.515, 0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = people.size()
	var clothes := [Color("c8473c"), Color("3a62c4"), Color("e9e6dc"), Color("2a2f3a"), Color("e3b740"), Color("5f8a4a"),
		Color("8a8f9c"), Color("b04a7a"), Color("d9793a"), Color("7cd0d8"), Color("e07ab0")]
	var sides := [NightStadium.C_PINK, NightStadium.C_CYAN.darkened(0.15)]
	if look.has("clothes"):
		clothes = look.clothes
		sides = look.sides
	for i in people.size():
		var g: Array = people[i]
		mm.set_instance_transform(i, Transform3D(Basis(), g[0]))
		var x: float = g[2]
		var side := 0.0 if x < -4.0 else (1.0 if x > 4.0 else 0.5)
		var c: Color = clothes[rng.randi() % clothes.size()]
		# Fans wear some of their side's color.
		if rng.randf() < 0.35 and side != 0.5:
			c = sides[0] if side == 0.0 else sides[1]
		c.a = rng.randf()
		mm.set_instance_color(i, c)
		mm.set_instance_custom_data(i, Color(rng.randf(), rng.randf(), side, g[1]))
	var people_mi := MultiMeshInstance3D.new()
	people_mi.multimesh = mm
	mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SH_CROWD
	mat.shader = sh
	mat.set_shader_parameter("poses", _sprite())
	mat.set_shader_parameter("pink", look.get("glow_a", NightStadium.C_PINK))
	mat.set_shader_parameter("cyan", look.get("glow_b", NightStadium.C_CYAN))
	mat.set_shader_parameter("brightness", look.get("brightness", 1.0))
	people_mi.material_override = mat
	people_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(people_mi)


# ---------------------------------------------------------------- the director

## A hit. side 0 = pink, 1 = cyan (who lands it). "fraction" is the share of the
## target's total HP it takes.
func hit(side: int, fraction: float) -> void:
	var other := 1 - side
	var strength := clampf(fraction * 3.0, 0.05, 1.0)
	mood[side] += 0.12 + strength * 0.5
	mood[other] -= strength * 0.15
	if strength > 0.5:
		tension[other] = maxf(tension[other], strength * 0.6)


## A last-moment dodge: the stands cheer it more than a weak hit.
func close_dodge(side: int) -> void:
	mood[side] += 0.35
	mood[1 - side] += 0.1


## Both HPs (0-1), every frame: comebacks and tension come from here.
func set_hp(a: float, b: float) -> void:
	_hp = [a, b]
	var gap := a - b
	_worst_gap[0] = minf(_worst_gap[0], gap)
	_worst_gap[1] = minf(_worst_gap[1], -gap)
	var leader := 0 if gap > 0.02 else (1 if gap < -0.02 else _leader)
	if leader != _leader:
		lead_changes += 1
		# Comeback: whoever takes the lead was far behind.
		var behind: float = -_worst_gap[leader]
		if behind > 0.25:
			best_comeback = maxf(best_comeback, behind)
			mood[leader] = 1.0
			mood[1 - leader] = maxf(mood[1 - leader], 0.45)
			_worst_gap[leader] = 0.0
		_leader = leader
	for i in 2:
		var v: float = _hp[i]
		# Tension when someone is low; more if the other one is low too.
		var t := clampf((0.3 - v) / 0.3, 0.0, 1.0)
		if t > 0.0 and _hp[1 - i] < 0.4:
			t = minf(1.0, t + 0.3)
		tension[i] = maxf(tension[i], t)


## End of the battle. Returns the quality (0-1) that sizes the ovation.
func finish(winner: int, duration: float) -> float:
	var close := 1.0 - clampf(_hp[winner] / 0.6, 0.0, 1.0)
	var long := clampf(duration / 90.0, 0.0, 1.0)
	var quality := clampf(0.3 * close + 0.25 * clampf(best_comeback / 0.5, 0.0, 1.0)
		+ 0.2 * clampf(lead_changes / 3.0, 0.0, 1.0) + 0.25 * long, 0.0, 1.0)
	ovation = 0.35 + 0.65 * quality
	mood[winner] = 1.0
	mood[1 - winner] = 0.3 + 0.5 * quality     # after a good battle both sides applaud
	tension = [0.0, 0.0]
	return quality


func _process(delta: float) -> void:
	for i in 2:
		mood[i] = clampf(move_toward(mood[i], 0.12 + ovation * 0.5, delta * 0.12), 0.0, 1.0)
		tension[i] = move_toward(tension[i], 0.0, delta * 0.25)
	ovation = move_toward(ovation, 0.0, delta * 0.03)
	# The wave: if the stands stay up for a few seconds, it starts and goes round once.
	var middle: float = (mood[0] + mood[1]) * 0.5
	_high_t = _high_t + delta if middle > 0.55 else maxf(0.0, _high_t - delta * 2.0)
	if _high_t > 3.0 and wave_strength <= 0.0:
		wave_strength = 1.0
		wave_pos = 0.0
	if wave_strength > 0.0:
		wave_pos += delta * 0.12
		if wave_pos > 1.0:
			wave_strength = 0.0
			_high_t = 0.0
	mat.set_shader_parameter("mood_pink", mood[0])
	mat.set_shader_parameter("mood_cyan", mood[1])
	mat.set_shader_parameter("tension_pink", tension[0])
	mat.set_shader_parameter("tension_cyan", tension[1])
	mat.set_shader_parameter("wave_pos", wave_pos)
	mat.set_shader_parameter("wave_strength", wave_strength)
	mat.set_shader_parameter("ovation", ovation)
	mat.set_shader_parameter("flashes", 0.002 + middle * 0.012)
	# The stadium follows the crowd (on_hype: LED strip, glass, scoreboards...).
	var hype := clampf(maxf(middle, ovation) * 1.2 - 0.2, 0.0, 1.0)
	_stadium.on_hype(hype, _hp)
