extends Action
## Energy Ball: like in the DS games, it gathers nature's energy into a green ball (leaves
## drawn in toward it) and throws it. It flies at a fair speed, following a little, with
## Cobblemon's small leaves circling it, and bursts in green with leaves where it hits. It
## can lower the target's Sp. Def. It can be broken or sent back.

const GREEN := Color(0.55, 0.95, 0.35)

var _ball: Node3D
var _gather := 0.0


func _hold() -> Vector3:
	return mouth() + l.forward() * 0.5


func on_start() -> void:
	turn_mult = 2.5
	_ball = l.main.vfx.pixel_ball("energyball", 6, 1.4, GREEN, 12.0)
	_ball.scale = Vector3.ONE * 0.2
	play_sound("charge", -10.0)


func in_startup(delta: float) -> void:
	var k := clampf(t / maxf(startup_len(), 0.01), 0.0, 1.0)
	tint_col = Roster.TYPE_COLOR.grass
	tint_k = 0.15 + 0.2 * k
	if is_instance_valid(_ball):
		_ball.global_position = _hold()
		_ball.scale = Vector3.ONE * lerpf(0.2, 1.0, k)
	# Leaves drawn in toward the ball.
	_gather -= delta
	if _gather <= 0.0:
		_gather = 0.05
		var c := _hold()
		var from_pos: Vector3 = c + Vector3(randf_range(-1, 1), randf_range(-0.6, 1), randf_range(-1, 1)).normalized() * 1.2
		l.main.fx.anim("generic/grass/smallleaf.png", from_pos.lerp(c, 0.4), 0.3, 1, 0.12)
		l.main.vfx.burst("leaves", from_pos, (c - from_pos).normalized(), Color(0, 0, 0, 0), 0.3)


func on_active() -> void:
	tint_k = 0.0
	var dir := aim(0.8)
	var vfx: Vfx = l.main.vfx
	var fx: Fx = l.main.fx
	var g := Hit.new()
	g.user = l
	g.move_id = id
	g.type = "grass"
	g.cat = "special"
	g.damage = d.damage
	g.stun = d.stun
	g.strength = d.strength
	g.hitstop = 0.07
	g.contact = false
	var ball := _ball
	_ball = null
	if not is_instance_valid(ball):
		ball = vfx.pixel_ball("energyball", 6, 1.4, GREEN, 12.0)
	ball.scale = Vector3.ONE
	var life: float = d.reach / d.speed
	var p: Dictionary = l.main.combat.projectile({"user": l, "pos": _hold(), "velocity": dir * d.speed, "radius": d.radius,
		"lifetime": life, "hit": g, "node": ball, "target": l.rival,
		"on_impact": func(pos: Vector3, _against: String):
			vfx.impact(pos, "grass", 2, false)
			vfx.burst("leaves", pos, Vector3.UP, Color(0, 0, 0, 0), 1.4)
			for i in 8:
				var a := TAU * i / 8.0
				fx.anim("generic/grass/smallleaf.png", pos + Vector3(cos(a), randf_range(-0.4, 0.6), sin(a)) * 0.9, 0.35, 1, 0.3)
			vfx.wave(Vector3(pos.x, l.main.ground_y, pos.z), 1.8, 0.3, GREEN, 0.08)})
	# Leaves circling the ball as it flies.
	var clock := {"t": 0.0, "a": 0.0}
	vfx.live(Node3D.new(), life, func(_k: float):
		var dt := vfx.get_process_delta_time()
		clock.t += dt
		clock.a += dt * 10.0
		if p.alive and clock.t > 0.03:
			clock.t = 0.0
			var fwd: Vector3 = p.velocity.normalized()
			var side := fwd.cross(Vector3.UP).normalized()
			var up := side.cross(fwd)
			for i in 3:
				var a: float = clock.a + i * TAU / 3.0
				fx.anim("generic/grass/smallleaf.png", p.pos + (side * cos(a) + up * sin(a)) * 0.75, 0.32, 1, 0.08)
			if randf() < 0.4:
				vfx.burst("leaves", p.pos, -fwd, Color(0, 0, 0, 0), 0.3))
	play_sound(id, 0.0)


func on_end(_interrupted: bool) -> void:
	if is_instance_valid(_ball):
		_ball.queue_free()


func pose() -> Dictionary:
	match phase:
		"startup":
			return {"tilt": -0.15, "stretch": 0.94, "anim": "special", "reset": t < 0.02}
		"active":
			return {"tilt": 0.2, "stretch": 1.08}
	return {}
