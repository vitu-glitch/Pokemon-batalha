class_name Arena
extends Node3D
## Base of the stages (NightStadium, FloatingStadium): the field's size, the battle events
## a stage can react to, whether a point is inside, and shared pieces (pixel-grain
## materials, colliders, the crowd's shader). Each stage builds itself in build().
## Physical limits on layer 1 (world).

const LENGTH := 36.0          # X axis
const WIDTH := 22.0          # Z axis
## Collision layer only the battle camera looks at (stands it must not go into).
const CAMERA_LAYER := 16

var main: Node
var stage := ""
## Stages with a void (no walls, you can fall off): a fighter below this height is KO'd.
## -INF on stages with walls.
var void_y := -INF
var _t := 0.0


const SH_CROWD := """
shader_type spatial;
// Pixel crowd: head with hair, clothes with a per-person pattern (plain, striped or
// two-tone) in 1/16 m cells and flat light, without the gradient of smooth
// capsules.
uniform float head_height = 0.82;
varying float height;
varying vec3 local;
varying float phase;
void vertex() {
	height = VERTEX.y;
	local = VERTEX;
	phase = INSTANCE_CUSTOM.x;
	float cheer = INSTANCE_CUSTOM.y;
	VERTEX.y += max(0.0, sin(TIME * (2.4 + cheer * 2.0) + phase * 6.2831)) * 0.07 * cheer;
	VERTEX.x += sin(TIME * 1.3 + phase * 6.2831) * 0.03 * VERTEX.y;
	NORMAL = vec3(0.0, 1.0, 0.0);
}
void fragment() {
	vec2 cell = floor(vec2(local.x, local.y) * 16.0);
	float sel = fract(COLOR.a * 7.31);
	vec3 skin = sel < 0.33 ? vec3(0.95, 0.78, 0.63) : (sel < 0.66 ? vec3(0.78, 0.57, 0.42) : vec3(0.45, 0.3, 0.2));
	float hs = fract(phase * 13.7);
	vec3 hair = hs < 0.3 ? vec3(0.16, 0.11, 0.08) : (hs < 0.55 ? vec3(0.45, 0.28, 0.14) : (hs < 0.75 ? vec3(0.85, 0.7, 0.35) : vec3(0.25, 0.25, 0.3)));
	vec3 clothes = COLOR.rgb;
	float pattern = fract(phase * 5.3);
	if (pattern < 0.3) {
		clothes = mix(clothes, clothes * 0.6 + 0.35, step(0.5, mod(cell.y, 3.0)) * 0.6);      // stripes
	} else if (pattern < 0.5) {
		clothes = mix(clothes, vec3(0.92), step(0.55, (height - 0.4) / 0.3));                 // two-tone
	}
	vec3 c = clothes;
	if (height > head_height) {
		c = skin;
		if (height > head_height + 0.24 || local.z > 0.09) c = hair;
	}
	ALBEDO = c * (0.92 + 0.08 * step(0.5, fract(sin(dot(cell, vec2(12.9, 78.2))) * 43758.5)));
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
"""

func build() -> void:
	pass


## Battle events, for stages whose crowd reacts (NightStadium). Nothing here.
func on_hit(_attacker: Fighter, _target: Fighter, _damage: float) -> void:
	pass


func on_dodge(_f: Fighter) -> void:
	pass


func on_ko(_winner: Fighter) -> void:
	pass


func on_rematch() -> void:
	pass


## Where the trainer of the Pokémon starting on this side (sign of its x) stands.
func trainer_spot(side: float) -> Vector3:
	return Vector3(side * (LENGTH * 0.5 + 2.6), 0.0, 0.0)


func inside(p: Vector3, margin := 0.0) -> bool:
	return absf(p.x) < LENGTH * 0.5 - margin and absf(p.z) < WIDTH * 0.5 - margin


func _process(delta: float) -> void:
	_t += delta


func _material(col: Color, rough := 0.85, metal := 0.0, kind := "plain") -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	m.albedo_texture = _grain(kind)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * 0.5        # the texture is 32 px: 2 m
	return m


var _grains := {}


## 32 × 32 texture in flat tones, generated here (no files): specks in three tones;
## metal also gets a panel seam every meter and rivets.
func _grain(kind: String) -> ImageTexture:
	if _grains.has(kind):
		return _grains[kind]
	var img := Image.create(32, 32, true, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	for y in 32:
		for x in 32:
			var h := rng.randf()
			var v := 1.0
			match kind:
				"concrete":
					v = 0.86 if h < 0.12 else (1.06 if h > 0.9 else 0.97)
					if y % 16 == 15:
						v *= 0.82
				"metal":
					v = 0.95 if h < 0.2 else 1.0
					if x % 16 == 0 or y % 16 == 0:
						v = 0.78
					elif x % 16 == 1 or y % 16 == 1:
						v = 1.08
					if (x % 16 == 3 or x % 16 == 13) and (y % 16 == 3 or y % 16 == 13):
						v = 0.7
				_:
					v = 0.93 if h < 0.15 else 1.0
			img.set_pixel(x, y, Color(v * 0.92, v * 0.92, v * 0.92))
	img.generate_mipmaps()
	_grains[kind] = ImageTexture.create_from_image(img)
	return _grains[kind]


func _box_collider(center: Vector3, dims: Vector3, layer := 1) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = dims
	cs.shape = bs
	body.add_child(cs)
	body.position = center
	add_child(body)


## Called by main at the start of each battle, with the two Pokémon's portraits.
func screens(_tex_a: Texture2D, _tex_b: Texture2D, _col_a: Color, _col_b: Color) -> void:
	pass
