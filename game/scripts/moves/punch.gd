extends Action
## Punch (Ice, Fire and Thunder Punch, Meteor Mash, Bullet Punch, Mega Punch, Rock Smash,
## Focus Punch): the fist charges with its element during the startup, then advances and hits
## in front. The data sets the effect (freeze, burn, paralysis) and how far it lunges.
## "boom" (the elemental punches): a long lunge, and the fist breaks the sound barrier as it
## sets off: cones of shock in its element's color left in the air behind it, speed lines,
## and a ring of the same color bursting where it lands.
## "focus" (Focus Punch): a long wind-up with rings closing on the fist; any hit taken
## meanwhile cuts it ("lost its focus"), as in the games.

var _shine := 0.0


func on_start() -> void:
	turn_mult = 2.0


func _particles() -> String:
	return {"ice": "steam", "fire": "fire_fx", "electric": "sparks", "steel": "sparks_metal", "fighting": "stars"}.get(d.type, "dust")


func in_startup(delta: float) -> void:
	tint_col = Roster.TYPE_COLOR[d.type]
	tint_k = 0.25 * (t / d.startup)
	_shine -= delta
	if _shine <= 0.0:
		_shine = 0.06 if not d.get("focus", false) else 0.18
		var hand := l.point("locator_hand_primary")
		if d.get("focus", false):
			l.main.vfx.wave(hand, lerpf(1.4, 0.35, clampf(t / startup_len(), 0.0, 1.0)), 0.16, Roster.TYPE_COLOR[d.type], 0.05)
		l.main.vfx.burst(_particles(), hand, Vector3.UP, Color(0, 0, 0, 0), 0.35)
		match d.type:
			"ice":
				l.main.vfx.burst("ice_fx", hand, Vector3.UP, Color(0, 0, 0, 0), 0.5)
			"fire":
				# The fist wrapped in flames.
				l.main.vfx.burst("fire_fx", hand, Vector3.UP, Color(0, 0, 0, 0), 0.7)
				l.main.vfx.light(hand, Roster.TYPE_COLOR.fire, 2.5, 3.0, 0.08)
			"electric":
				# Small bolts crackling round the fist.
				for k in 2:
					var o := Vector3(randf_range(-0.5, 0.5), randf_range(-0.2, 0.5), randf_range(-0.5, 0.5))
					l.main.vfx.bolt(hand, hand + o, Roster.TYPE_COLOR.electric, 0.06, 0.06, 0)
				l.main.vfx.light(hand, Roster.TYPE_COLOR.electric, 2.0, 3.0, 0.06)


func on_active() -> void:
	advance_by(d.advance / d.active * 0.5)
	hit({"shape": "sphere", "center": Vector3(0, l.data.height * 0.5, l.data.radius + d.reach * 0.5), "radius": d.radius})
	var col: Color = Roster.TYPE_COLOR[d.type]
	l.main.vfx.ribbon(func(): return [l.center(), l.point("locator_hand_primary")], col, d.active + 0.05, 0.15)
	# Each element its own touch on the swing: fire leaves embers behind the lunge,
	# electricity jumps from the fist.
	var hand := l.point("locator_hand_primary")
	match d.type:
		"fire":
			l.main.vfx.ribbon(func(): return [l.center(), l.point("locator_hand_primary")], Color(1.0, 0.5, 0.15), d.active + 0.15, 0.32)
			l.main.vfx.burst("embers", hand, -l.forward(), Color(0, 0, 0, 0), 1.2)
		"electric":
			for k in 3:
				l.main.vfx.bolt(hand, hand + Vector3(randf_range(-0.7, 0.7), randf_range(-0.3, 0.6), randf_range(-0.7, 0.7)), Roster.TYPE_COLOR.electric, 0.08, 0.08, 0)
	if d.get("boom", false):
		_sonic_boom(col)
	l.main.audio.play_sound("dodge", l.global_position, -6.0, 0.8)


## The sound barrier: two cones of shock at the fist, facing along the lunge and left in
## the air behind it, widening and fading in steps; a third a moment later along the way;
## and speed lines streaming back from the body.
func _sonic_boom(col: Color) -> void:
	var vfx: Vfx = l.main.vfx
	var fwd := l.forward()
	var face := Basis.looking_at(fwd, Vector3.UP)
	var bright := col.lerp(Color.WHITE, 0.45)
	var ring := func(at: Vector3, size: float, tint: Color, dur: float):
		vfx.flat_sprite("res://fx/tex/custom/psy_ring.png", 1, size, at, face, dur, tint, 0.0,
			func(n: MeshInstance3D, k: float):
				n.scale = Vector3.ONE * snappedf(1.0 + k * 1.6, 0.2)
				n.material_override.set_shader_parameter("tint", Color(tint, 1.0 - snappedf(k, 0.25))), 0.05)
	var at := l.point("locator_hand_primary") + fwd * 0.3
	ring.call(at, 1.2, bright, 0.26)
	ring.call(at - fwd * 0.5, 1.8, col, 0.32)
	l.get_tree().create_timer(d.active * 0.45, false, true).timeout.connect(func():
		if is_instance_valid(l):
			ring.call(l.point("locator_hand_primary") + l.forward() * 0.3, 1.5, bright, 0.24))
	for k in 6:
		var off := Vector3(randf_range(-0.6, 0.6), randf_range(-0.4, 0.6), 0.0)
		vfx.burst("sparks", l.center() + face * off, -fwd, bright, 0.5)
	vfx.light(at, col, 4.0, 4.0, 0.15)
	l.main.shake_camera(0.12, at)


func on_end(interrupted: bool) -> void:
	if interrupted and phase == "startup" and d.get("focus", false):
		l.main.vfx.text(l.center() + Vector3.UP * 1.0, l.tr("It lost its focus!"), Color(0.8, 0.8, 0.9))


func on_recovery() -> void:
	tint_k = 0.0
	if landed:
		play_sound(d.get("sound_hit", "icepunch"), 0.0)
		# On the hit: a flare of fire and a scorch mark, or bolts from the fist to the rival.
		var r: Node3D = l.aim_target()
		var at: Vector3 = r.center() if r and is_instance_valid(r) else l.point("locator_hand_primary") + l.forward()
		if d.get("boom", false):
			var col: Color = Roster.TYPE_COLOR[d.type]
			l.main.vfx.flat_sprite("res://fx/tex/custom/psy_ring.png", 1, 1.4, at, Basis.looking_at(l.forward(), Vector3.UP), 0.3,
				col.lerp(Color.WHITE, 0.3), 0.0, func(n: MeshInstance3D, k: float):
					n.scale = Vector3.ONE * snappedf(1.0 + k * 2.4, 0.25), 0.05)
		match d.type:
			"fire":
				l.main.vfx.burst("fire_fx", at, Vector3.UP, Color(0, 0, 0, 0), 1.6)
				l.main.vfx.mark(Vector3(at.x, l.main.ground_y, at.z), "burned", 0.9, 3.0)
			"electric":
				var hand := l.point("locator_hand_primary")
				for k in 3:
					l.main.vfx.bolt(hand, at + Vector3(randf_range(-0.4, 0.4), randf_range(-0.4, 0.4), randf_range(-0.4, 0.4)), Roster.TYPE_COLOR.electric, 0.12, 0.12, 1)


func pose() -> Dictionary:
	match phase:
		"startup":
			if d.get("focus", false):
				return {"tilt": -0.25, "side": 0.35, "stretch": 0.92 + 0.02 * sin(total * 30.0)}
			return {"tilt": -0.2, "side": 0.25, "stretch": 0.95}
		"active":
			return {"tilt": 0.35, "side": -0.3, "stretch": 1.08, "anim": "physical"}
	return {"tilt": 0.15 * (1.0 - t / d.recovery)}
