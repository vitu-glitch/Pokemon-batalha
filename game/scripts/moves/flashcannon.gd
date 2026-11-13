extends Action
## Flash Cannon, like in the DS games: light gathers into a small, blinding ball in front
## of the user (a glint that turns, silver rings closing in on it) and is shot off very
## fast in a straight line, leaving a trail of glints behind it. It bursts in a white
## flash with silver sparks. It can lower the target's Sp. Def. It can be sent back.

const SILVER := Color(0.8, 0.86, 0.96)
const WHITE := Color(1.0, 1.0, 1.0)

var _ball: Node3D
var _gather := 0.0


func _hold() -> Vector3:
	return mouth() + l.forward() * 0.7


func on_start() -> void:
	turn_mult = 2.5
	_ball = l.main.vfx.pixel_ball("flashcannon_ball", 4, 1.6, WHITE, 12.0)
	_ball.scale = Vector3.ONE * 0.1
	play_sound("charge", -8.0)


func in_startup(delta: float) -> void:
	var k := clampf(t / maxf(startup_len(), 0.01), 0.0, 1.0)
	tint_col = SILVER
	tint_k = 0.15 + 0.25 * k
	var c := _hold()
	if is_instance_valid(_ball):
		_ball.global_position = c
		_ball.scale = Vector3.ONE * lerpf(0.1, 1.0, k)
	_gather -= delta
	if _gather <= 0.0:
		_gather = 0.09
		l.main.vfx.flat_sprite("res://fx/tex/custom/psy_ring.png", 1, 2.2, c, Basis.looking_at(l.forward(), Vector3.UP), 0.16,
			SILVER, 0.0, func(n: MeshInstance3D, rk: float):
				if is_instance_valid(l):
					n.global_position = _hold()
				n.scale = Vector3.ONE * maxf(0.05, snappedf(1.0 - rk, 0.2)), 0.04)
		l.main.vfx.burst("stars", c + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized() * 1.2, Vector3.UP, Color(0, 0, 0, 0), 0.3)


func on_active() -> void:
	tint_k = 0.0
	var dir := aim(0.7)
	var vfx: Vfx = l.main.vfx
	var g := Hit.new()
	g.user = l
	g.move_id = id
	g.type = "steel"
	g.cat = "special"
	g.damage = d.damage
	g.stun = d.stun
	g.strength = 1
	g.hitstop = 0.08
	g.contact = false
	var ball := _ball
	_ball = null
	if not is_instance_valid(ball):
		ball = vfx.pixel_ball("flashcannon_ball", 4, 1.6, WHITE, 12.0)
	ball.scale = Vector3.ONE
	var from_pos := _hold()
	var life: float = d.reach / d.speed
	var p: Dictionary = l.main.combat.projectile({"user": l, "pos": from_pos, "velocity": dir * d.speed, "radius": d.radius,
		"lifetime": life, "hit": g, "node": ball, "target": l.rival,
		"on_impact": func(pos: Vector3, _against: String):
			vfx.impact(pos, "steel", 1, false)
			vfx.light(pos, WHITE, 7.0, 6.0, 0.2)
			vfx.burst("sparks_metal", pos, -dir, Color(0, 0, 0, 0), 1.2)
			vfx.burst("stars", pos, Vector3.UP, Color(0, 0, 0, 0), 0.8)})
	# A trail of glints and white sparks left along its way.
	var clock := {"t": 0.0}
	vfx.live(Node3D.new(), life, func(_k: float):
		clock.t += vfx.get_process_delta_time()
		if p.alive and clock.t > 0.02:
			clock.t = 0.0
			var back: Vector3 = -p.velocity.normalized()
			vfx.burst("sparks", p.pos + back * 0.3, back, WHITE, 0.45)
			if randf() < 0.35:
				vfx.burst("stars", p.pos + back * 0.6, Vector3.UP, Color(0, 0, 0, 0), 0.3))
	vfx.light(from_pos, WHITE, 5.0, 6.0, 0.15)
	play_sound(id, 0.0)


func on_end(_interrupted: bool) -> void:
	if is_instance_valid(_ball):
		_ball.queue_free()


func pose() -> Dictionary:
	match phase:
		"startup":
			return {"tilt": -0.12, "stretch": 0.94, "anim": "special", "reset": t < 0.02}
		"active":
			return {"tilt": 0.22, "stretch": 1.08}
	return {}
