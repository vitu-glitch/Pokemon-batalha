extends Action
## Psychic: telekinesis, like in the anime. The user's eyes glow and pink waves leave it
## while a ring at the rival's feet follows it; a moment before ("lock" seconds) the ring
## stops and turns white. Whoever stands there then is wrapped in a band of psychic light
## (an outline round its body), lifted into the air with pink sparks rising off it and, at
## the top ("hold" seconds later), slammed down onto the ground, which cracks. The lift does a
## share of the damage ("lift_share"), the slam the rest. Dodge it (or leave the ring) when
## it turns white. It is not a projectile: it cannot be sent back. Reach "reach" metres.

const PINK := Color(1.0, 0.45, 0.85)

var _ring: MeshInstance3D
var _at := Vector3.ZERO
var _locked := false
var _wave := 0.0


func on_start() -> void:
	turn_mult = 2.5
	_locked = false
	_at = _target_spot()
	_ring = l.main.vfx.telegraph(_at, d.radius + 0.3, startup_len() + 0.05, PINK)
	_ring.material_override = _ring.material_override.duplicate()     # its own, to turn it white
	l.main.vfx.cobble("psychic_actor", l.global_position, null, l.data.height)
	l.main.vfx.cobble("psychic_actordots", l.global_position, null, l.data.height)
	play_sound("charge", -10.0)


func _target_spot() -> Vector3:
	var r: Node3D = l.aim_target()
	var spot: Vector3 = l.global_position + l.forward() * d.reach
	if r and is_instance_valid(r) and not (r is Fighter and r.state == "ko"):
		spot = r.global_position
	var flat := Vector3(spot.x - l.global_position.x, 0, spot.z - l.global_position.z)
	if flat.length() > d.reach:
		spot = l.global_position + flat.normalized() * d.reach
	spot.y = l.main.ground_y
	return spot


func in_startup(delta: float) -> void:
	var k := clampf(t / maxf(startup_len(), 0.01), 0.0, 1.0)
	tint_col = PINK
	tint_k = 0.15 + 0.25 * k
	if not _locked:
		_at = _at.move_toward(_target_spot(), 12.0 * delta)
		if t >= startup_len() - float(d.lock):
			_locked = true
			if is_instance_valid(_ring):
				_ring.material_override.set_shader_parameter("color", Color(1, 1, 1))
	if is_instance_valid(_ring):
		_ring.global_position = _at + Vector3.UP * 0.04
		_ring.material_override.set_shader_parameter("k", k)
	# Glowing eyes and pink waves leaving its body.
	_wave -= delta
	if _wave <= 0.0:
		_wave = 0.16
		var eyes: Vector3 = l.global_position + Vector3.UP * l.data.height * 0.85 + l.forward() * l.data.radius * 0.8
		l.main.vfx.light(eyes, PINK, 2.5, 3.0, 0.18)
		l.main.vfx.wave(Vector3(l.global_position.x, l.main.ground_y, l.global_position.z), l.data.radius + 1.6, 0.3, PINK, 0.06)


func on_active() -> void:
	tint_k = 0.0
	var vfx: Vfx = l.main.vfx
	var at := _at
	var share: float = d.lift_share
	var g := hit({"shape": "capsule", "local": false, "a": at + Vector3.UP * 0.2, "b": at + Vector3.UP * 2.2, "radius": d.radius,
		"lifetime": 0.08, "contact": false, "damage": float(d.damage) * share, "knock": 0.0})
	vfx.light(at + Vector3.UP, PINK, 4.0, 5.0, 0.4)
	var user := l
	var hold: float = d.hold
	var rest: float = float(d.damage) * (1.0 - share)
	g.on_strike = func(o: Node, _res: String):
		vfx.outline(o, PINK, hold + 0.35)
		# Pink sparks rising off it while it is held up.
		var clock := {"t": 0.0}
		vfx.live(Node3D.new(), hold, func(_k: float):
			clock.t += vfx.get_process_delta_time()
			if clock.t > 0.05 and is_instance_valid(o):
				clock.t = 0.0
				var c: Vector3 = (o as Node3D).global_position + Vector3.UP * (o.data.height * 0.5 if o is Fighter else 0.5)
				vfx.burst("sparks", c + Vector3(randf_range(-0.6, 0.6), randf_range(-0.5, 0.5), randf_range(-0.6, 0.6)), Vector3.UP, PINK, 0.3))
		# At the top it is slammed down.
		l.get_tree().create_timer(hold, false, true).timeout.connect(func(): _slam(user, o, rest))
	if is_instance_valid(_ring):
		_ring.queue_free()
	play_sound(id, 0.0)


## The slam: a hit where the target is now, pushing it straight down (the combo falloff of
## a second hit is made up for, so the two add up to the move's damage), and the ground
## cracking where it lands.
func _slam(user: Fighter, o: Node, damage: float) -> void:
	if not is_instance_valid(user) or not is_instance_valid(o) or (o is Fighter and o.state == "ko"):
		return
	var vfx: Vfx = user.main.vfx
	var where: Vector3 = (o as Node3D).global_position
	var g := Hit.new()
	g.user = user
	g.move_id = id
	g.local = false
	g.shape = "sphere"
	g.center = (o.center() if o.has_method("center") else where)
	g.radius = 1.2
	g.type = "psychic"
	g.cat = "special"
	g.damage = damage / 0.88
	g.knock = 0.0
	g.push = d.slam
	g.push_dir = Vector3.DOWN
	g.knocks_down = true
	g.stun = d.stun
	g.strength = 2
	g.hitstop = 0.08
	g.contact = false
	g.quiet = true
	g.lifetime = 0.08
	user.main.combat.add_hit(g)
	vfx.light(g.center, PINK, 5.0, 5.0, 0.3)
	var ground := Vector3(where.x, user.main.ground_y, where.z)
	var fall: float = clampf((where.y - user.main.ground_y) / float(d.slam), 0.05, 0.3)
	user.get_tree().create_timer(fall, false, true).timeout.connect(func():
		if not is_instance_valid(user):
			return
		vfx.mark(ground, "crack", 1.6, 4.0)
		vfx.dust(ground, 2.0)
		vfx.burst("sparks", ground + Vector3.UP * 0.3, Vector3.UP, PINK, 1.0)
		user.main.audio.play_sound("psychic_hit", ground, 0.0)
		user.main.shake_camera(0.35, ground))


func on_end(_interrupted: bool) -> void:
	if is_instance_valid(_ring):
		_ring.queue_free()


func pose() -> Dictionary:
	match phase:
		"startup":
			return {"tilt": -0.08, "stretch": 0.95 + 0.02 * sin(total * 20.0), "anim": "special", "reset": t < 0.02}
		"active":
			return {"tilt": 0.15, "stretch": 1.08}
	return {}
