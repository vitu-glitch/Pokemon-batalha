extends Action
## Dark Pulse: like in the DS games, dark energy bursts out of the user all round. It
## gathers darkness (rings closing in on it), then a dome of darkness swells out of it up to
## "r_max" metres in "active" seconds (fast at first, slower at the edge) and hits anyone it
## takes in, on the ground or in the air. It can make the target flinch. Energy, not a
## thing: it cannot be batted back ("deflectable" 0).

const DARK := Color(0.42, 0.22, 0.55)
const DEEP := Color(0.16, 0.06, 0.22)

var _gather := 0.0
var _g: Hit
var _center := Vector3.ZERO
var _edge := 0.0


func on_start() -> void:
	turn_mult = 2.5
	play_sound("charge", -12.0)


func in_startup(delta: float) -> void:
	var k := clampf(t / maxf(startup_len(), 0.01), 0.0, 1.0)
	tint_col = DEEP
	tint_k = 0.2 + 0.3 * k
	# Rings closing in on it.
	_gather -= delta
	if _gather <= 0.0:
		_gather = 0.1
		var c := l.center()
		var col := DARK if randf() < 0.5 else DEEP
		l.main.vfx.flat_sprite("res://fx/tex/custom/psy_ring.png", 1, l.data.height * 2.4, c, Basis.looking_at(l.forward(), Vector3.UP),
			0.18, col, 0.0, func(n: MeshInstance3D, rk: float):
				n.global_position = l.center() if is_instance_valid(l) else n.global_position
				n.scale = Vector3.ONE * maxf(0.05, snappedf(1.0 - rk, 0.2)), 0.06)
		l.main.vfx.burst("shadow", c + Vector3(randf_range(-1, 1), randf_range(-0.5, 1), randf_range(-1, 1)), Vector3.UP, DEEP, 0.3)


func on_active() -> void:
	tint_k = 0.0
	var vfx: Vfx = l.main.vfx
	_center = l.global_position
	_center.y = l.main.ground_y
	_edge = 0.0
	_g = hit({"shape": "sphere", "local": false, "center": _center, "radius": 0.5, "contact": false, "hitstop": 0.07})
	# The dome, and a darker one inside it a step behind: it lives on after the hit is gone.
	var r_max: float = d.r_max
	var grow: float = d.active
	for layer in 2:
		var dm := vfx.dome()
		dm.global_position = _center
		var m: ShaderMaterial = dm.material_override
		if layer == 1:
			m.set_shader_parameter("body", Color(0.06, 0.02, 0.09))
			m.set_shader_parameter("rim", DARK)
		var late := 0.06 * layer
		var size := r_max * (1.0 - 0.15 * layer)
		var total := grow + 0.3
		vfx.live(dm, total, func(k: float):
			var tt := k * total
			var gk := clampf((tt - late) / grow, 0.0, 1.0)
			var r := maxf(0.2, size * (1.0 - pow(1.0 - gk, 2.5)))
			dm.scale = Vector3.ONE * r
			m.set_shader_parameter("radius", r)
			m.set_shader_parameter("t", tt)
			m.set_shader_parameter("faded", clampf((tt - grow) / 0.3, 0.0, 1.0)))
	# Rings of darkness running out along the ground, and the ground darkened under it.
	for i in 3:
		vfx.wave(_center, r_max * (1.05 - 0.15 * i), grow + 0.1 * i, DARK if i % 2 == 0 else DEEP, 0.12)
	vfx.mark(_center, "burned", 1.2, 2.0)
	vfx.cobble("nightshade_actorpulse1", l.center(), null, l.data.height)
	vfx.light(l.center(), DARK, 4.0, r_max * 1.5, grow + 0.2)
	l.main.shake_camera(0.25, _center)
	play_sound(id, 0.0)


func in_active(_delta: float) -> void:
	var k := clampf(t / d.active, 0.0, 1.0)
	var r: float = d.r_max * (1.0 - pow(1.0 - k, 2.5))
	if _g:
		_g.radius = maxf(0.5, r)
	# Shadow bursting up from the ground where the edge passes.
	while _edge + 1.0 < r:
		_edge += 1.0
		var n := int(_edge * 1.5) + 3
		for i in n:
			var a := TAU * (i + randf() * 0.5) / n
			if randf() < 0.2:
				l.main.vfx.burst("shadow", _center + Vector3(cos(a), 0.1, sin(a)) * _edge, Vector3.UP, DEEP, 0.4)


func on_recovery() -> void:
	remove_hits()
	_g = null


func pose() -> Dictionary:
	match phase:
		"startup":
			return {"tilt": -0.12, "stretch": 0.93, "anim": "special", "reset": t < 0.02}
		"active":
			return {"tilt": 0.2, "stretch": 1.08}
	return {}
