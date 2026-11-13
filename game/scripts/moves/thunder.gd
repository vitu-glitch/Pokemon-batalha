extends Action
## Thunder, like in the anime and Cobblemon: the user crackles and shoots a bolt straight
## up into the sky; a dark storm cloud gathers over the rival and a wide ring on the ground
## under it follows the rival, slower than it can run ("follow" m/s). A moment before
## ("lock" seconds) the ring stops and turns white, and a huge bolt comes down from the
## cloud onto it: it hits anyone in that column, in the air too, and can paralyze. Slow to
## come, easy to read, very hard if you stay. Reach "reach" metres.

const OUTLINE := Color(0.85, 0.42, 0.05)
const CORE := Color(1.0, 0.95, 0.45)
const CLOUD := Color(0.55, 0.55, 0.66)

var _ring: MeshInstance3D
var _at := Vector3.ZERO
var _locked := false
var _up := false
var _crackle := 0.0
var _cloud := 0.0


func on_start() -> void:
	turn_mult = 2.0
	_locked = false
	_up = false
	_at = _target_spot()
	_ring = l.main.vfx.telegraph(_at, d.radius + 0.2, startup_len() + 0.05, Roster.TYPE_COLOR.electric)
	_ring.material_override = _ring.material_override.duplicate()     # its own, to turn it white
	l.main.vfx.cobble("thunderbolt_actorsparks", l.center(), null, l.data.height)
	play_sound("charge", -8.0)


func _target_spot() -> Vector3:
	var r: Node3D = l.aim_target()
	var spot: Vector3 = l.global_position + l.forward() * minf(8.0, d.reach)
	if r and is_instance_valid(r) and not (r is Fighter and r.state == "ko"):
		spot = r.global_position
	var flat := Vector3(spot.x - l.global_position.x, 0, spot.z - l.global_position.z)
	if flat.length() > d.reach:
		spot = l.global_position + flat.normalized() * d.reach
	spot.y = l.main.ground_y
	return spot


func in_startup(delta: float) -> void:
	var k := clampf(t / maxf(startup_len(), 0.01), 0.0, 1.0)
	var vfx: Vfx = l.main.vfx
	tint_col = Roster.TYPE_COLOR.electric
	tint_k = 0.2 + 0.3 * k
	# The bolt into the sky, early in the charge.
	if not _up and k > 0.18:
		_up = true
		var top := l.center() + Vector3.UP * 18.0
		vfx.bolt(l.center(), top, CORE, 0.3, 0.45, 2, OUTLINE)
		vfx.cobble("thunder_actor", l.global_position, null, l.data.height)
		vfx.cobble("thunder_actorring", l.global_position, null, l.data.height)
		vfx.light(l.center(), CORE, 5.0, 6.0, 0.25)
		play_sound("thunder_up", 0.0)
	if not _locked:
		_at = _at.move_toward(_target_spot(), float(d.follow) * delta)
		if t >= startup_len() - float(d.lock):
			_locked = true
			if is_instance_valid(_ring):
				_ring.material_override.set_shader_parameter("color", Color(1, 1, 1))
	if is_instance_valid(_ring):
		_ring.global_position = _at + Vector3.UP * 0.04
		_ring.material_override.set_shader_parameter("k", k)
	# Crackling on the body.
	_crackle -= delta
	if _crackle <= 0.0:
		_crackle = 0.08
		var c := l.center()
		var a: Vector3 = c + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized() * l.data.height * 0.5
		vfx.bolt(c, a, CORE, 0.08, 0.1, 0, OUTLINE)
	# The storm cloud gathering over the ring, darker and wider as it comes, with flickers
	# of lightning inside it once it has formed.
	if _up:
		_cloud -= delta
		if _cloud <= 0.0:
			_cloud = 0.05
			var sky := _at + Vector3.UP * float(d.cloud_h)
			var spread: float = (d.radius + 1.0) * (0.6 + 0.6 * k)
			var p := sky + Vector3(randf_range(-1, 1), randf_range(-0.2, 0.3), randf_range(-1, 1)) * spread
			vfx.burst("smoke", p, Vector3.DOWN, CLOUD, 2.4 + 1.6 * k)
			if k > 0.6 and randf() < 0.3:
				var q := sky + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * spread
				vfx.bolt(q, q + Vector3(randf_range(-1.5, 1.5), randf_range(-0.6, 0.0), randf_range(-1.5, 1.5)), CORE, 0.07, 0.12, 0, OUTLINE)


func on_active() -> void:
	tint_k = 0.0
	var vfx: Vfx = l.main.vfx
	var at := _at
	var sky := at + Vector3.UP * float(d.cloud_h)
	var g := hit({"shape": "capsule", "local": false, "a": at + Vector3.UP * 0.2, "b": at + Vector3.UP * 6.0, "radius": d.radius,
		"lifetime": 0.1, "contact": false})
	# The bolt: a huge one with two thinner strands round it, and a star of bolts on the
	# ground where it lands.
	vfx.bolt(sky, at, CORE, 0.4, 0.8, 3, OUTLINE)
	for i in 2:
		var off := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * 0.8
		vfx.bolt(sky + off * 2.0, at + off * 0.4, CORE, 0.28, 0.25, 1, OUTLINE)
	for i in 6:
		var a := TAU * i / 6.0 + randf() * 0.4
		vfx.bolt(at + Vector3.UP * 0.1, at + Vector3(cos(a), 0.1, sin(a)) * (d.radius + 1.4), CORE, 0.25, 0.16, 1, OUTLINE)
	vfx.cobble("thunder_target", at, null, 2.0)
	vfx.cobble("thunder_actorfloorscorch", at, null, 1.6)
	vfx.cobble("thunder_actorsmoke", at, null, 1.6)
	vfx.cobble("thunder_targetfloorsparks", at, null, 1.6)
	vfx.light(at + Vector3.UP * 2.0, CORE, 8.0, 14.0, 0.35)
	vfx.wave(at + Vector3.UP * 0.05, d.radius + 2.0, 0.35, CORE, 0.1)
	vfx.mark(at, "burned", d.radius + 0.4, 4.0)
	vfx.mark(at, "crack", d.radius, 4.0)
	g.on_strike = func(o: Node, _r: String):
		var c: Callable = func(): return (o as Node3D).global_position + Vector3.UP * (o.data.height * 0.5 if o is Fighter else 0.5)
		vfx.crackle(c, (o.data.radius if o is Fighter else 0.6) + 0.3, 0.6, CORE, OUTLINE)
	if is_instance_valid(_ring):
		_ring.queue_free()
	l.main.shake_camera(0.6, at)
	play_sound(id, 3.0)


func on_end(_interrupted: bool) -> void:
	if is_instance_valid(_ring):
		_ring.queue_free()


## Arms (and cheeks) up to the sky while it calls the bolt down.
func pose() -> Dictionary:
	match phase:
		"startup":
			var k: float = clampf(t / maxf(startup_len(), 0.01), 0.0, 1.0)
			return {"tilt": -0.25 * k, "stretch": 1.0 + 0.1 * k + 0.02 * sin(total * 30.0), "anim": "special", "reset": t < 0.02}
		"active":
			return {"tilt": 0.1, "stretch": 0.94}
	return {}
