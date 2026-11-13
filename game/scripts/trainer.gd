class_name Trainer
extends Node3D
## A trainer on the field: their sprite from the games (TrainerData), standing in their
## side's trainer area (Arena.trainer_spot), turned to the camera on the vertical axis like
## the sprites of the DS games, with a soft shadow at their feet. They are only for show:
## no collision and nothing they do touches the battle.
##
## They are not still: they breathe, lean forward when their Pokémon uses a move, hop when
## it lands a hit, flinch when it takes a heavy one, and at the end jump for joy or slump.
## At the start they throw the Poké Ball that brings their Pokémon out (Battle intro, in
## main.gd). All the motion is slow and smooth (nothing blinks).

const HOP := 0.32              # meters of a cheering hop

var main: Node
var id := ""
var fighter: Fighter           # their Pokémon
var display_name := ""         # as the log names them
var _pivot: Node3D             # turned to the camera
var _body: Node3D              # the pose, from the feet: hop, lean, squash
var _sprite: MeshInstance3D
var _mat: ShaderMaterial
var _t := 0.0
var _hop := 0.0                # time left in a hop
var _lean := 0.0               # current lean (radians, + forward toward the field)
var _lean_to := 0.0
var _lean_t := 0.0             # how long the lean is held
var _shake := 0.0
var _mood := ""                # "", "win", "lose"
var _throw := -1.0             # time since the throw started (-1: not throwing)

const SH_TRAINER := """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
uniform sampler2D tex : source_color, filter_nearest;
uniform float flip = 1.0;
uniform float dim = 1.0;
void fragment() {
	vec4 c = texture(tex, vec2(flip > 0.0 ? UV.x : 1.0 - UV.x, UV.y));
	if (c.a < 0.5) discard;
	ALBEDO = c.rgb * dim;
}
"""


func setup(m: Node, trainer_id: String, f: Fighter) -> void:
	main = m
	id = TrainerData.valid(trainer_id)
	fighter = f
	var d: Dictionary = TrainerData.LIST[id]
	var size := 80.0 * TrainerData.PX
	# Soft shadow on the ground.
	var sh := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1.1, 0.55)
	sh.mesh = pm
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var g := GradientTexture2D.new()
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(1.0, 0.5)
	var gr := Gradient.new()
	gr.set_color(0, Color(0, 0, 0, 0.5))
	gr.set_color(1, Color(0, 0, 0, 0.0))
	g.gradient = gr
	sm.albedo_texture = g
	sh.material_override = sm
	sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sh.position.y = 0.03
	add_child(sh)
	_pivot = Node3D.new()
	add_child(_pivot)
	_body = Node3D.new()
	_pivot.add_child(_body)
	_sprite = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	_sprite.mesh = q
	_mat = ShaderMaterial.new()
	_mat.shader = Shader.new()
	_mat.shader.code = SH_TRAINER
	_mat.set_shader_parameter("tex", TrainerData.texture(id))
	_sprite.material_override = _mat
	_sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The quad's center, so its "foot" row of pixels touches the ground.
	_sprite.position.y = size * 0.5 - (80.0 - float(d.foot)) * TrainerData.PX
	_body.add_child(_sprite)


## The point their hand throws from (in the world).
func hand() -> Vector3:
	return global_position + Vector3.UP * 1.35


# ---------------------------------------------------------------- reactions (visual only)

func command() -> void:
	_lean_to = 0.14
	_lean_t = 0.35


func cheer() -> void:
	if _hop <= 0.0:
		_hop = 0.42


func flinch() -> void:
	_lean_to = -0.16
	_lean_t = 0.4
	_shake = 0.3


func win() -> void:
	_mood = "win"


func lose() -> void:
	_mood = "lose"


func reset() -> void:
	_mood = ""
	_hop = 0.0
	_lean = 0.0
	_lean_to = 0.0
	_shake = 0.0
	_throw = -1.0


## The throw: wind up (leaning back), then the arm goes forward and the ball leaves.
func throw() -> void:
	_throw = 0.0


func _process(delta: float) -> void:
	_t += delta
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam:
		# Turned to the camera on the vertical axis only.
		var to := cam.global_position - global_position
		_pivot.rotation.y = atan2(to.x, to.z)
	# Lean: toward the field is "forward"; seen from the camera it is a tilt to the side
	# the field is on, so it reads from any angle.
	_lean_t -= delta
	if _lean_t <= 0.0:
		_lean_to = 0.0
	var mood_lean := 0.0
	var squash := 1.0 + 0.015 * sin(_t * TAU * 0.5)
	var lift := 0.0
	match _mood:
		"win":
			lift = absf(sin(_t * PI * 1.6)) * HOP
		"lose":
			mood_lean = 0.1
			squash *= 0.94
	if _throw >= 0.0:
		_throw += delta
		if _throw < 0.25:
			_lean_to = -0.28 * (_throw / 0.25)
		elif _throw < 0.6:
			_lean_to = 0.3
		else:
			_lean_to = 0.0
			_throw = -1.0
		_lean_t = 0.1
	_lean = lerpf(_lean, _lean_to + mood_lean, 1.0 - exp(-12.0 * delta))
	if _hop > 0.0:
		_hop -= delta
		var k := clampf(1.0 - _hop / 0.42, 0.0, 1.0)
		lift = maxf(lift, sin(k * PI) * HOP)
	var wobble := 0.0
	if _shake > 0.0:
		_shake -= delta
		wobble = sin(_t * 40.0) * 0.04 * (_shake / 0.3)
	# Which way is the field on screen: the lean tips toward it.
	var side := 1.0
	if cam:
		var right := cam.global_transform.basis.x
		side = signf(right.dot(-global_position)) if absf(global_position.x) > 0.1 else 1.0
	_body.rotation.z = -(_lean * side) + wobble
	_body.position.y = lift
	_body.scale = Vector3(1.0 / sqrt(squash), squash, 1.0)
	_mat.set_shader_parameter("dim", 0.78 if _mood == "lose" else 1.0)
