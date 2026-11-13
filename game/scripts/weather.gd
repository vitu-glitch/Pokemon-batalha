class_name Weather
extends Node3D
## The battle's weather, as in the games. Sunny Day, Rain Dance, Sandstorm and Snowscape
## start it and it lasts 5 turns; a turn is TURN seconds of real time. A new weather
## replaces the old one. What it does:
##   sun   Fire moves x1.5, Water x0.5. Chlorophyll doubles Speed; Solar Power raises
##         Sp. Atk x1.5 but loses 1/8 of its max HP each turn; Solar Beam barely charges.
##   rain  Water moves x1.5, Fire x0.5. Rain Dish heals 1/16 of its max HP each turn.
##   sand  Rock types' Sp. Def x1.5. Everyone else loses 1/16 of its max HP each turn,
##         except Ground and Steel types and Sand Veil, which also makes projectiles
##         track it worse (x0.8, its evasion in the games).
##   snow  Ice types' Defense x1.5.
## Each copy applies the per-turn effects to its own Pokémon (online, HP travels with the
## state). On screen: a tint, falling rain, sand or snow, and the turns left on the HUD.

const TURN := 3.0
const TURNS := 5
const TINT := {"sun": Color(1.0, 0.8, 0.4, 0.16), "rain": Color(0.25, 0.35, 0.55, 0.18),
	"sand": Color(0.8, 0.6, 0.32, 0.32), "snow": Color(0.85, 0.92, 1.0, 0.18)}
## Where the falling particles start, relative to the camera (sand blows across the view).
const EMIT_Y := {"rain": 6.0, "snow": 4.0, "sand": -1.0}

var main: Node
var kind := ""
var left := 0.0
var _turn_t := 0.0
var _tint: ColorRect
var _fall: GPUParticles3D


func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = -1                   # over the 3D world, under the HUD
	add_child(layer)
	_tint = ColorRect.new()
	_tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tint.color = Color(0, 0, 0, 0)
	layer.add_child(_tint)


func is_on(k: String) -> bool:
	return kind == k


## Damage multiplier of a move's type under this weather.
func type_mult(type: String) -> float:
	match kind:
		"sun":
			return 1.5 if type == "fire" else (0.5 if type == "water" else 1.0)
		"rain":
			return 1.5 if type == "water" else (0.5 if type == "fire" else 1.0)
	return 1.0


## Defense multiplier of a target under this weather (sand: Rock Sp. Def; snow: Ice Def).
func defense_mult(types: Array, physical: bool) -> float:
	if kind == "sand" and not physical and "rock" in types:
		return 1.5
	if kind == "snow" and physical and "ice" in types:
		return 1.5
	return 1.0


func start(k: String) -> void:
	if not TINT.has(k):
		return
	var same := k == kind
	kind = k
	left = TURNS * TURN
	_turn_t = TURN
	if not same:
		main.hud.log_entry(_text(k, "start"))
		_visuals()


func clear() -> void:
	kind = ""
	left = 0.0
	_visuals()


## What the HUD shows: "Rain 4" (name and turns left), or nothing.
func label() -> String:
	if kind == "":
		return ""
	return "%s %d" % [_text(kind, "name"), ceili(left / TURN)]


func _physics_process(delta: float) -> void:
	if kind == "" or main.paused or main._end_t >= 0.0:
		return
	left -= delta
	_turn_t -= delta
	if _turn_t <= 0.0:
		_turn_t += TURN
		_end_of_turn()
	if left <= 0.0:
		main.hud.log_entry(_text(kind, "end"))
		clear()


func _end_of_turn() -> void:
	for f in main.fighters:
		if not is_instance_valid(f) or f.is_remote or f.state == "ko":
			continue
		var id: String = f.data.passive.id
		match kind:
			"sand":
				var spared: bool = f.types.any(func(t): return t in ["rock", "ground", "steel"]) or id == "sandveil"
				if not spared:
					f._damage_direct(f.hp_max / 16.0)
					main.vfx.text(f.center() + Vector3.UP * 0.8, tr("Buffeted by the sandstorm"), Color(0.85, 0.65, 0.4))
			"rain":
				if id == "raindish":
					f.heal(f.hp_max / 16.0)
					main.vfx.text(f.center() + Vector3.UP * 0.8, tr("Rain Dish"), Roster.TYPE_COLOR.water)
			"sun":
				if id == "solarpower":
					f._damage_direct(f.hp_max / 8.0)
					main.vfx.text(f.center() + Vector3.UP * 0.8, tr("Solar Power"), Roster.TYPE_COLOR.fire)


func _process(_delta: float) -> void:
	if is_instance_valid(_fall) and main.camera:
		_fall.global_position = main.camera.global_position + Vector3.UP * float(EMIT_Y.get(kind, 6.0))


## Tint and falling particles for the current weather (none for sun: just the light).
func _visuals() -> void:
	var tw := create_tween()
	tw.tween_property(_tint, "color", TINT[kind] if kind != "" else Color(0, 0, 0, 0), 0.6)
	if is_instance_valid(_fall):
		_fall.queue_free()
	_fall = null
	if kind in ["rain", "sand", "snow"]:
		_fall = _falling(kind)
		add_child(_fall)


## Its name and the battle-log lines, as in the games.
func _text(k: String, which: String) -> String:
	match [k, which]:
		["sun", "name"]: return tr("Harsh sunlight")
		["sun", "start"]: return tr("The sunlight turned harsh!")
		["sun", "end"]: return tr("The harsh sunlight faded.")
		["rain", "name"]: return tr("Rain")
		["rain", "start"]: return tr("It started to rain!")
		["rain", "end"]: return tr("The rain stopped.")
		["sand", "name"]: return tr("Sandstorm")
		["sand", "start"]: return tr("A sandstorm kicked up!")
		["sand", "end"]: return tr("The sandstorm subsided.")
		["snow", "name"]: return tr("Snow")
		["snow", "start"]: return tr("It started to snow!")
		["snow", "end"]: return tr("The snow stopped.")
	return ""


func _falling(k: String) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(22, 1, 22)
	var q := QuadMesh.new()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y if k == "rain" else BaseMaterial3D.BILLBOARD_ENABLED
	match k:
		"rain":
			p.amount = 700
			p.lifetime = 0.7
			pm.direction = Vector3(0.1, -1, 0)
			pm.spread = 3.0
			pm.initial_velocity_min = 22.0
			pm.initial_velocity_max = 26.0
			q.size = Vector2(0.04, 0.7)
			m.albedo_color = Color(0.75, 0.85, 1.0, 0.55)
		"snow":
			p.amount = 1200
			p.lifetime = 3.5
			pm.direction = Vector3(0.2, -1, 0.1)
			pm.spread = 25.0
			pm.initial_velocity_min = 2.0
			pm.initial_velocity_max = 3.5
			pm.emission_box_extents = Vector3(16, 1, 16)
			q.size = Vector2(0.14, 0.14)
			m.albedo_color = Color(1, 1, 1, 0.9)
		"sand":
			p.amount = 2200
			p.lifetime = 1.4
			pm.direction = Vector3(1, -0.1, 0.3)
			pm.spread = 12.0
			pm.initial_velocity_min = 14.0
			pm.initial_velocity_max = 20.0
			pm.emission_box_extents = Vector3(16, 5, 16)
			q.size = Vector2(0.12, 0.12)
			m.albedo_color = Color(0.85, 0.66, 0.4, 0.8)
	pm.gravity = Vector3.ZERO
	p.preprocess = p.lifetime          # already falling everywhere when it starts
	q.material = m
	p.process_material = pm
	p.draw_pass_1 = q
	p.visibility_aabb = AABB(Vector3(-30, -30, -30), Vector3(60, 60, 60))
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p
