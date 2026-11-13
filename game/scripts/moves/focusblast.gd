extends Action
## Focus Blast, like in the DS games and the anime: the user draws its fighting spirit in
## between its hands (orange streaks rushing in, the ball swelling) and hurls a big ball of
## it. It flies slow and straight, without following (that is its poor accuracy here: easy
## to step out of), and bursts in a wide blast where it lands. It can lower the target's
## Sp. Def. It can be sent back.

const ORANGE := Color(1.0, 0.55, 0.15)
const GOLD := Color(1.0, 0.85, 0.4)

var _ball: Node3D
var _gather := 0.0


func _hold() -> Vector3:
	return l.center() + l.forward() * (l.data.radius + 0.9)


func on_start() -> void:
	turn_mult = 2.0
	_ball = l.main.vfx.pixel_ball("focusblast", 6, 2.4, ORANGE, 14.0)
	_ball.scale = Vector3.ONE * 0.1
	l.main.vfx.cobble("closecombat_actor", l.global_position, null, l.data.height)
	play_sound("charge", -6.0)


func in_startup(delta: float) -> void:
	var k := clampf(t / maxf(startup_len(), 0.01), 0.0, 1.0)
	tint_col = Roster.TYPE_COLOR.fighting
	tint_k = 0.12 + 0.2 * k
	var c := _hold()
	if is_instance_valid(_ball):
		_ball.global_position = c
		_ball.scale = Vector3.ONE * lerpf(0.1, 1.0, k * k)
	# Streaks of spirit rushing in from all round.
	_gather -= delta
	if _gather <= 0.0:
		_gather = 0.035
		var from_pos: Vector3 = c + Vector3(randf_range(-1, 1), randf_range(-0.8, 1), randf_range(-1, 1)).normalized() * randf_range(1.8, 2.8)
		l.main.vfx.burst("sparks", from_pos, (c - from_pos).normalized(), GOLD if randf() < 0.5 else ORANGE, 0.35)
		if randf() < 0.2:
			l.main.vfx.wave(Vector3(l.global_position.x, l.main.ground_y, l.global_position.z), l.data.radius + 1.8, 0.25, ORANGE, 0.06)


func on_active() -> void:
	tint_k = 0.0
	var dir := aim(0.6)
	var vfx: Vfx = l.main.vfx
	var g := Hit.new()
	g.user = l
	g.move_id = id
	g.type = "fighting"
	g.cat = "special"
	# Straight on the body it is the whole blast (see Electro Ball).
	g.damage = d.damage
	g.stun = d.stun
	g.strength = 2
	g.hitstop = 0.11
	g.contact = false
	var ball := _ball
	_ball = null
	if not is_instance_valid(ball):
		ball = vfx.pixel_ball("focusblast", 6, 2.4, ORANGE, 14.0)
	ball.scale = Vector3.ONE
	var life: float = d.reach / d.speed
	var p: Dictionary = l.main.combat.projectile({"user": l, "pos": _hold(), "velocity": dir * d.speed, "radius": d.radius,
		"lifetime": life, "hit": g, "node": ball, "target": null,
		"on_impact": func(pos: Vector3, against: String): _blast(pos, against == "body")})
	# A wake of sparks and heat behind it.
	var clock := {"t": 0.0}
	vfx.live(Node3D.new(), life, func(_k: float):
		clock.t += vfx.get_process_delta_time()
		if p.alive and clock.t > 0.04:
			clock.t = 0.0
			var back: Vector3 = p.pos - p.velocity.normalized() * d.radius
			vfx.burst("sparks", back + Vector3(randf_range(-0.4, 0.4), randf_range(-0.4, 0.4), randf_range(-0.4, 0.4)), -p.velocity.normalized(), ORANGE, 0.4))
	l.velocity -= dir * 2.5
	play_sound(id, 0.0)


func _blast(pos: Vector3, direct: bool) -> void:
	if not is_instance_valid(l):
		return
	var vfx: Vfx = l.main.vfx
	if not direct:
		var g := Hit.new()
		g.user = l
		g.move_id = id
		g.local = false
		g.shape = "sphere"
		g.center = pos
		g.radius = d.blast_radius
		g.type = "fighting"
		g.cat = "special"
		g.damage = d.damage
		g.stun = d.stun
		g.strength = 2
		g.hitstop = 0.11
		g.contact = false
		g.lifetime = 0.08
		l.main.combat.add_hit(g)
	vfx.impact(pos, "fighting", 2, false)
	vfx.cobble("explosion_burst_flash", pos, null, 1.2)
	vfx.cobble("closecombat_targetimpact", pos, null, 1.6)
	for i in 12:
		var a := TAU * i / 12.0
		vfx.burst("sparks", pos, Vector3(cos(a), randf_range(0.0, 0.8), sin(a)).normalized(), ORANGE if i % 2 == 0 else GOLD, 0.8)
	var ground := Vector3(pos.x, l.main.ground_y, pos.z)
	vfx.wave(ground + Vector3.UP * 0.05, d.blast_radius * 1.4, 0.35, ORANGE, 0.12)
	vfx.wave(ground + Vector3.UP * 0.05, d.blast_radius * 1.0, 0.45, GOLD, 0.08)
	vfx.light(pos, ORANGE, 6.0, d.blast_radius * 4.0, 0.3)
	vfx.mark(ground, "crack", d.blast_radius * 0.7, 3.5)
	vfx.dust(ground, 2.0)
	l.main.audio.play_sound("focusblast_hit", pos, 0.0)
	l.main.shake_camera(0.4, pos)


func on_end(_interrupted: bool) -> void:
	if is_instance_valid(_ball):
		_ball.queue_free()


## Both hands drawn back to the side while it gathers, thrust forward to hurl it.
func pose() -> Dictionary:
	match phase:
		"startup":
			return {"tilt": -0.18, "stretch": 0.92 + 0.02 * sin(total * 24.0), "anim": "special", "reset": t < 0.02}
		"active":
			return {"tilt": 0.25, "stretch": 1.1}
	return {}
