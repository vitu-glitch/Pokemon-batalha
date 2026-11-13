extends Action
## Air Slash: a crescent-shaped blade of air that cuts horizontally. Wide but flat: it
## can be jumped over. Also usable in the air. It looks like two nested crescents (a pale
## outer edge and a bright inner one) that wobble as they fly and leave streaks of wind.

func on_start() -> void:
	turn_mult = 2.5
	if not l.is_on_floor():
		no_gravity = true
		l.velocity.y = 1.0


func on_active() -> void:
	var from_pos := to_world(Vector3(0, l.data.height * 0.55, l.data.radius + 0.4))
	var dir := aim(0.7)
	var g := Hit.new()
	g.user = l
	g.move_id = id
	g.type = "flying"
	g.cat = "special"
	g.damage = d.damage
	g.stun = d.stun
	g.contact = false
	g.strength = 1
	var node := _blade()
	l.main.combat.projectile({"user": l, "pos": from_pos, "velocity": dir * d.speed, "radius": d.radius, "lifetime": d.reach / d.speed,
		"hit": g, "node": node, "on_impact": func(pos: Vector3, _c: String):
			l.main.vfx.burst("wind", pos, -dir)
			l.main.audio.play_sound("airslash_hit", pos, -4.0)})
	l.main.vfx.burst("wind", from_pos, dir)
	l.main.vfx.cobble("gust_actor", from_pos, from_pos + dir * 4.0, l.data.height)
	# Streaks of wind behind it while it flies, and a slight wobble (in steps).
	var vfx: Vfx = l.main.vfx
	var streak := [0.0]
	vfx.live(node, d.reach / d.speed, func(k: float):
		if not is_instance_valid(node):
			return
		node.get_child(0).rotation.z = 0.12 * sin(floorf(k * 40.0) * 0.9)
		streak[0] += 1.0
		if int(streak[0]) % 3 == 0:
			vfx.burst("wind", node.global_position - dir * 0.6, -dir, Color(0, 0, 0, 0), 0.35))
	play_sound("airslash", 0.0)


## Crescent of air: a curved ribbon using the same shader as the trails.
func _blade() -> Node3D:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 12
	for i in n:
		var a0 := lerpf(-1.2, 1.2, float(i) / n)
		var a1 := lerpf(-1.2, 1.2, float(i + 1) / n)
		var r0 := 0.9
		var width0 := 0.28 * cos(a0 * 1.2)
		var width1 := 0.28 * cos(a1 * 1.2)
		var p0 := Vector3(sin(a0) * r0, 0, cos(a0) * r0 - r0)
		var p1 := Vector3(sin(a1) * r0, 0, cos(a1) * r0 - r0)
		var q0 := Vector3(sin(a0) * (r0 - width0), 0, cos(a0) * (r0 - width0) - r0)
		var q1 := Vector3(sin(a1) * (r0 - width1), 0, cos(a1) * (r0 - width1) - r0)
		for v in [[q0, 0.0], [p0, 1.0], [p1, 1.0], [q0, 0.0], [p1, 1.0], [q1, 0.0]]:
			im.surface_set_color(Color(1, 1, 1, 1))
			im.surface_set_uv(Vector2(0, v[1]))
			im.surface_add_vertex(v[0])
	im.surface_end()
	mi.mesh = im
	mi.material_override = l.main.vfx.mat("ribbon", VfxShaders.RIBBON, {"color": Color(0.75, 0.85, 1.0), "energy": 3.0})
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.rotation.y = PI
	root.add_child(mi)
	# Inner crescent: thinner, brighter, a little behind.
	var inner := MeshInstance3D.new()
	inner.mesh = im
	inner.material_override = l.main.vfx.mat("ribbon_core", VfxShaders.RIBBON, {"color": Color(0.95, 0.98, 1.0), "energy": 4.0})
	inner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inner.rotation.y = PI
	inner.scale = Vector3(0.7, 1.0, 0.7)
	inner.position = Vector3(0, 0, 0.12)
	mi.add_child(inner)
	l.main.vfx.add_child(root)
	return root


func on_recovery() -> void:
	no_gravity = false


func pose() -> Dictionary:
	var a := "air_special" if not l.is_on_floor() and l.model.has_anim("air_special") else "special"
	match phase:
		"startup":
			return {"tilt": -0.15, "side": 0.3, "anim": a, "reset": t < 0.02}
		"active":
			return {"tilt": 0.2, "side": -0.35}
	return {}
