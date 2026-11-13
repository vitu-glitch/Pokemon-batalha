extends Action
## Rock Slide: like in the DS games and the anime, boulders fall from above on the rival.
## "rocks" of them, one every "interval" seconds: the first where the rival stands, the
## rest round it in a pentagon "spread" metres out, each spot taken from where the rival
## is when that rock appears (a fixed pattern, no dice: online both screens agree). Each
## spot is marked on the ground "fall" seconds before its rock lands, so you can step out
## of the rain. The rival takes one hit at most (it can flinch, as in the games). The rocks
## keep falling after the user is free again (the timers' lambdas keep this Action alive).
## Out of reach it rains in front.

const PATTERN := [0.0, 0.0, 1.0, 144.0, 1.0, 288.0, 1.0, 72.0, 1.0, 216.0]   # (distance share, angle) pairs

var _stone_a: Material
var _stone_b: Material


func on_start() -> void:
	turn_mult = 2.0
	_stone_a = l.main.arena._material(Color("8d7a62"), 0.95, 0.0, "concrete")
	_stone_b = l.main.arena._material(Color("6f604d"), 0.95, 0.0, "concrete")
	play_sound("charge", -12.0)


func in_startup(_delta: float) -> void:
	tint_col = Roster.TYPE_COLOR.rock
	tint_k = 0.3 * clampf(t / maxf(startup_len(), 0.01), 0.0, 1.0)


func on_active() -> void:
	tint_k = 0.0
	l.main.shake_camera(0.1, l.global_position)
	play_sound(id, 0.0)
	var yaw := atan2(l.forward().x, l.forward().z)
	var struck := {"done": false}
	for i in int(d.rocks):
		var share: float = PATTERN[(i * 2) % PATTERN.size()]
		var angle: float = deg_to_rad(PATTERN[(i * 2 + 1) % PATTERN.size()]) + yaw
		var offset := Vector3(sin(angle), 0.0, cos(angle)) * share * float(d.spread)
		var when: float = i * float(d.interval)
		if when <= 0.0:
			_rock(offset, struck)
		else:
			l.get_tree().create_timer(when, false, true).timeout.connect(func(): _rock(offset, struck))


## Where the rain falls now: on the rival, or in front as far as it reaches.
func _center() -> Vector3:
	var r: Node3D = l.aim_target() if is_instance_valid(l) else null
	var at: Vector3 = l.global_position + l.forward() * 8.0
	if r and is_instance_valid(r) and not (r is Fighter and r.state == "ko") \
			and Vector2(r.global_position.x - l.global_position.x, r.global_position.z - l.global_position.z).length() <= d.reach:
		at = r.global_position
	at.y = l.main.ground_y
	return at


func _rock(offset: Vector3, struck: Dictionary) -> void:
	if not is_instance_valid(l) or l.state == "ko":
		return
	var vfx: Vfx = l.main.vfx
	var spot: Vector3 = _center() + offset
	var fall: float = d.fall
	vfx.telegraph(spot, d.radius, fall, Roster.TYPE_COLOR.rock)
	# A chunky boulder: two boxes at odd angles, falling from high up with a slow spin.
	var rock := Node3D.new()
	vfx.add_child(rock)
	var size := randf_range(0.9, 1.3)
	for k in 2:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(size, size * 0.8, size * 0.9) * (1.0 if k == 0 else 0.7)
		mi.mesh = bm
		mi.material_override = _stone_a if k == 0 else _stone_b
		rock.add_child(mi)
		mi.position = Vector3(0.0, 0.0, 0.0) if k == 0 else Vector3(size * 0.3, size * 0.25, -size * 0.2)
		mi.rotation = Vector3(randf_range(-0.6, 0.6), randf_range(0, TAU), randf_range(-0.6, 0.6))
	var top := 9.0
	var spin := Vector3(randf_range(-4, 4), randf_range(-2, 2), randf_range(-4, 4))
	vfx.live(rock, fall + 0.5, func(k: float):
		var tk := clampf(k * (fall + 0.5) / fall, 0.0, 1.0)
		if tk < 1.0:
			rock.global_position = spot + Vector3.UP * (size * 0.4 + top * (1.0 - tk * tk))
			rock.rotation = spin * tk
		else:
			# Landed: it sinks and crumbles in steps.
			var after := (k * (fall + 0.5) - fall) / 0.5
			rock.scale = Vector3.ONE * snappedf(1.0 - after * 0.8, 0.2))
	l.get_tree().create_timer(fall, false, true).timeout.connect(func(): _land(spot, size, struck))


func _land(spot: Vector3, size: float, struck: Dictionary) -> void:
	if not is_instance_valid(l):
		return
	var vfx: Vfx = l.main.vfx
	var g := Hit.new()
	g.user = l
	g.move_id = id
	g.local = false
	g.shape = "sphere"
	g.center = spot + Vector3.UP * 0.8
	g.radius = d.radius
	g.type = "rock"
	g.cat = "physical"
	g.damage = d.damage
	g.stun = d.stun
	g.strength = d.strength
	g.hitstop = 0.06
	g.contact = false
	g.lifetime = 0.1
	g.on_strike = func(_o, _r): struck.done = true
	if not struck.done:
		l.main.combat.add_hit(g)
	vfx.cobble("rockslide_targetbreak", spot + Vector3.UP * 0.3, null, size)
	vfx.dust(spot, 1.6)
	vfx.mark(spot, "crack", d.radius * 0.9, 3.0)
	l.main.audio.play_sound(id + "_hit", spot, -2.0)
	l.main.shake_camera(0.12, spot)


func pose() -> Dictionary:
	match phase:
		"startup":
			var k: float = clampf(t / maxf(startup_len(), 0.01), 0.0, 1.0)
			return {"stretch": 1.0 + 0.12 * k, "tilt": -0.2 * k, "anim": "special", "reset": t < 0.02}
		"active":
			return {"stretch": 0.9, "tilt": 0.15}
	return {}
