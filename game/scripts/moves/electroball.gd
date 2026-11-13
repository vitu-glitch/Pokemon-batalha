extends Action
## Electro Ball, like in the anime: Pikachu gathers electricity on the tip of its tail,
## turns and flings it with a tail flip. It flies in an arc (rises a little and falls),
## homes slightly on the rival and bursts in an area with paralysis. It is not
## chargeable (Aura Sphere is the chargeable one, like in Smash).

var _ball: Node3D
var _sparks := 0.0


func on_start() -> void:
	turn_mult = 2.0
	_ball = l.main.vfx.pixel_ball("electroball", 6, 0.6, Roster.TYPE_COLOR.electric, 16.0)
	_ball.scale = Vector3.ONE * 0.2
	play_sound("charge", -6.0)


func _tail() -> Vector3:
	return l.point("locator_tail_tip")


func in_startup(delta: float) -> void:
	var k: float = clampf(t / d.startup, 0.0, 1.0)
	tint_col = Roster.TYPE_COLOR.electric
	tint_k = 0.15 + 0.2 * k
	if is_instance_valid(_ball):
		_ball.global_position = _tail()
		_ball.scale = Vector3.ONE * lerpf(0.25, 1.25, k)
	_sparks -= delta
	if _sparks <= 0.0:
		_sparks = 0.1
		# An arc from the cheek to the tail, with Cobblemon paralysis sparks around it.
		var c := _tail()
		l.main.vfx.bolt(l.point("cheek_active_left"), c, Roster.TYPE_COLOR.electric, 0.08, 0.07, 0)
		l.main.fx.anim("generic/status/paralysis_spark.png", c + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized() * 0.5,
			0.35, 10, 0.3)


func on_active() -> void:
	var dir := aim(0.8)
	dir = (dir + Vector3.UP * float(d.arc)).normalized()
	var g := Hit.new()
	g.user = l
	g.move_id = id
	g.type = "electric"
	g.cat = "special"
	# Straight on the body it is the whole burst (the burst's own hit would expire while
	# the user is frozen by this one); the burst's hit is for near misses.
	g.damage = d.damage
	g.lift = d.lift
	g.stun = d.stun
	g.effect = d.get("effect", "")
	g.strength = 2
	g.hitstop = 0.1
	g.contact = false
	var ball := _ball
	_ball = null
	if not is_instance_valid(ball):
		ball = l.main.vfx.pixel_ball("electroball", 6, 0.6, Roster.TYPE_COLOR.electric, 16.0)
	ball.scale = Vector3.ONE * 1.25
	var radius := 0.55
	var p: Dictionary = l.main.combat.projectile({"user": l, "pos": _tail(), "velocity": dir * d.speed, "radius": radius, "lifetime": 3.0,
		"gravity": d.gravity, "hit": g, "node": ball, "homing": 0.8, "target": l.rival,
		"on_impact": func(pos: Vector3, against: String): _burst(pos, against == "body")})
	# Sheds sparks while it flies.
	var clock := {"t": 0.0}
	l.main.vfx.live(Node3D.new(), 3.0, func(_k):
		clock.t += l.get_process_delta_time()
		if p.alive and clock.t > 0.07:
			clock.t = 0.0
			l.main.fx.anim("generic/status/paralysis_spark.png", p.pos + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized() * radius * 1.6,
				0.35, 10, 0.3))
	play_sound("electroball", -2.0)


func _burst(pos: Vector3, direct := false) -> void:
	var g := Hit.new()
	g.user = l
	g.move_id = id
	g.local = false
	g.shape = "sphere"
	g.center = pos
	g.radius = d.blast_radius
	g.type = "electric"
	g.cat = "special"
	g.damage = d.damage
	g.lift = d.lift
	g.stun = d.stun
	g.effect = d.get("effect", "")
	g.strength = 2
	g.hitstop = 0.1
	g.contact = false
	g.lifetime = 0.08
	if not direct:
		l.main.combat.add_hit(g)
	var vfx: Vfx = l.main.vfx
	var col := Roster.TYPE_COLOR.electric
	vfx.impact(pos, "electric", 2, false)
	vfx.wave(pos - Vector3.UP * (pos.y - l.main.ground_y), d.blast_radius * 1.1, 0.35, col, 0.1)
	vfx.light(pos, col, 5.0, d.blast_radius * 3.0, 0.25)
	vfx.cobble("thunder_targetboom", pos, null, 1.0)
	vfx.cobble("thunder_targetfloorsparks", Vector3(pos.x, l.main.ground_y, pos.z), null, 1.0)
	for i in 3:
		vfx.bolt(pos, pos + Vector3(randf_range(-1, 1), randf_range(-0.2, 1), randf_range(-1, 1)).normalized() * d.blast_radius * 1.3, col, 0.18, 0.18, 1)
	vfx.mark(Vector3(pos.x, l.main.ground_y, pos.z), "burned", d.blast_radius * 0.8, 3.0)
	l.main.audio.play_sound("electroball_burst", pos, 0.0)
	l.main.shake_camera(0.35, pos)


func on_end(_interrupted: bool) -> void:
	if is_instance_valid(_ball):
		_ball.queue_free()


## The tail flip: at the end of the startup it turns its back (tail toward the rival),
## releases the ball and finishes the turn during the recovery.
func pose() -> Dictionary:
	match phase:
		"startup":
			var k: float = clampf((t - d.startup * 0.55) / (d.startup * 0.45), 0.0, 1.0)
			return {"tilt": -0.1, "stretch": 0.95, "anim": "special", "spin": PI * k * k}
		"active":
			return {"tilt": 0.15, "stretch": 1.08, "spin": PI}
		"recovery":
			return {"spin": lerpf(PI, TAU, clampf(t / (d.recovery * 0.7), 0.0, 1.0))}
	return {}
