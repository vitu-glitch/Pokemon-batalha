extends Action
## Water Shuriken: three shuriken in a row during the active phase, each one aimed at the
## rival as it is released (pressure with several projectiles: you have to move in a
## curve). Uses Cobblemon's three-throw animation.

var _thrown := 0


func on_start() -> void:
	turn_mult = 3.0
	no_gravity = not l.is_on_floor()
	if no_gravity:
		l.velocity.y = 1.0


func in_startup(_delta: float) -> void:
	tint_col = Roster.TYPE_COLOR.water
	tint_k = 0.2 * (t / d.startup)


func in_active(_delta: float) -> void:
	var touches := int(t / (d.active / d.count))
	while _thrown <= mini(touches, d.count - 1):
		_throw(_thrown)
		_thrown += 1


func _throw(i: int) -> void:
	var hand := "locator_hand_primary" if i % 2 == 0 else "locator_hand_secondary"
	var from_pos := l.point(hand) + l.forward() * 0.3
	var dir := aim(0.9)
	var g := Hit.new()
	g.user = l
	g.move_id = id
	g.type = "water"
	g.cat = "special"
	g.damage = d.damage
	g.stun = d.stun
	g.strength = d.strength
	g.contact = false
	var vfx: Vfx = l.main.vfx
	l.main.combat.projectile({"user": l, "pos": from_pos, "velocity": dir * d.speed, "radius": d.radius, "lifetime": d.reach / d.speed,
		"hit": g, "node": _shuriken(), "on_impact": func(pos: Vector3, _c: String):
			vfx.burst("water_fx", pos, -dir, Color(0, 0, 0, 0), 0.6)})
	vfx.burst("water_fx", from_pos, dir, Color(0, 0, 0, 0), 0.3)
	play_sound("watershuriken", -4.0)


## Pixel water shuriken (fx/tex/custom/watershuriken.png, from tools/move_sprites.py):
## lying almost flat, like a thrown star, tipped back a little toward the thrower so it
## reads from behind; it spins through its frames. The projectile points the root along
## its way, so the star keeps its tilt whichever way it flies.
func _shuriken() -> Node3D:
	var root := Node3D.new()
	var vfx: Vfx = l.main.vfx
	vfx.add_child(root)
	var s := vfx.flat_sprite("res://fx/tex/custom/watershuriken.png", 4, 1.0, Vector3.ZERO, Basis.IDENTITY,
		d.reach / d.speed + 0.1, Color.WHITE, 20.0, Callable(), 0.08)
	s.reparent(root, false)
	s.transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-65.0)), Vector3.ZERO)
	vfx.live(root, d.reach / d.speed + 0.1)
	return root


func on_recovery() -> void:
	no_gravity = false
	tint_k = 0.0


func pose() -> Dictionary:
	match phase:
		"startup":
			return {"tilt": -0.1, "anim": d.get("anim", ""), "reset": t < 0.02}
		"active":
			return {"tilt": 0.12, "side": 0.2 * sin(t * 30.0)}
	return {}
