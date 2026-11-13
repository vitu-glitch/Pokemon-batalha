extends Action
## Razor Leaf: three leaves in a fan from the flower. Up close all three hit; far away
## they spread and you can slip between them. The leaves spin as they fly.


func on_start() -> void:
	turn_mult = 2.5


func in_startup(_delta: float) -> void:
	tint_col = Roster.TYPE_COLOR.grass
	tint_k = 0.2 * (t / d.startup)
	if int(total * 30.0) % 3 == 0:
		l.main.vfx.burst("leaves", l.point("locator_special"), Vector3.UP, Color(0, 0, 0, 0), 0.3)


func on_active() -> void:
	var from_pos := l.point("locator_special") + l.forward() * 0.6
	var dir := aim(0.6)
	for i in 3:
		var ang: float = (i - 1) * d.fan
		var dir_i := dir.rotated(Vector3.UP, ang)
		var g := Hit.new()
		g.user = l
		g.move_id = id
		g.type = "grass"
		g.cat = "special"
		g.damage = d.damage
		g.stun = d.stun
		g.contact = false
		g.strength = 0
		l.main.combat.projectile({"user": l, "pos": from_pos, "velocity": dir_i * d.speed, "radius": d.radius, "lifetime": d.reach / d.speed,
			"hit": g, "node": _leaf(), "on_impact": func(pos: Vector3, _c: String):
				l.main.vfx.burst("leaves", pos, -dir_i, Color(0, 0, 0, 0), 0.6)})
	l.main.vfx.burst("leaves", from_pos, dir, Color(0, 0, 0, 0), 0.8)
	play_sound("razorleaf", 0.0)


## A Cobblemon leaf that spins on itself as it flies.
func _leaf() -> Node3D:
	var root := Node3D.new()
	var s := Sprite3D.new()
	s.texture = load(Vfx.TEX + "grass/leaf.png")
	s.vframes = 4
	s.frame = randi() % 4
	s.pixel_size = 0.045
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.shaded = false
	s.modulate = Color(0.85, 1.0, 0.7)
	root.add_child(s)
	l.main.vfx.add_child(root)
	var vfx: Vfx = l.main.vfx
	vfx.live(root, d.reach / d.speed + 0.1, func(_k: float):
		if is_instance_valid(s):
			s.rotation.z += 0.5)
	return root


func pose() -> Dictionary:
	match phase:
		"startup":
			return {"tilt": -0.15, "stretch": 0.96}
		"active":
			return {"tilt": 0.12, "stretch": 1.05}
	return {}
