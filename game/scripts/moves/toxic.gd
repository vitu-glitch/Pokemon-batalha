extends Action
## Toxic, as in the DS games: bubbles well up from the ground under the rival. The Pokémon
## stamps and a poisoned stain runs under the ground toward the rival, popping little
## bubbles as it goes and following it as well as its accuracy lets it (Combat.track_for;
## a dodge breaks it). Under the rival it stops: the ground bubbles for "warn" seconds
## and then erupts in a column of bubbles; whoever is standing in it is badly poisoned.
## Unlike Hex (a mark that is under the rival from the start and is walked out of), this
## one comes from the user and is avoided by being off the ground when it erupts: jump,
## or dodge on the warning. Poison types never miss with it in the games: from them the
## stain runs faster and follows better, with the same warning.

const ERUPT := 0.5
const BURST := 0.15                  # only the burst poisons; the bubbles just rise after


func on_start() -> void:
	turn_mult = 3.0


func in_startup(_delta: float) -> void:
	tint_col = Status.COLOR.tox
	tint_k = 0.3 * (t / d.startup)


func on_active() -> void:
	tint_k = 0.0
	var poison: bool = "poison" in l.types
	var start: Vector3 = l.global_position + l.forward() * (l.data.radius + 0.4)
	start.y = l.main.ground_y
	var run := {"pos": start, "dir": l.forward(), "gone": 0.0, "phase": "run", "t": 0.0, "trail": 0.0,
		"speed": d.speed * (1.45 if poison else 1.0),
		"track": deg_to_rad(320.0) if poison else Combat.track_for(id),
		"target": l.aim_target(), "mark": null}
	var node := Node3D.new()
	l.main.vfx.add_child(node)
	l.main.vfx.burst("shadow", start + Vector3.UP * 0.2, Vector3.UP, Status.COLOR.tox, 0.8)
	l.main.vfx.wave(start, 1.0, 0.25, Status.COLOR.tox, 0.08)
	l.main.shake_camera(0.05, start)
	play_sound("toxic", -2.0)
	l.main.vfx.live(node, d.reach / run.speed + d.warn + ERUPT + 0.2, func(_k: float): _step(run))


## One frame of the stain: running, warning or erupting.
func _step(run: Dictionary) -> void:
	var vfx: Vfx = l.main.vfx
	var dt := vfx.get_process_delta_time()
	run.t += dt
	match run.phase:
		"run":
			var tg = run.target
			if tg and is_instance_valid(tg) and not (tg is Fighter and (tg.state in ["dodge", "ko"])):
				var to: Vector3 = tg.global_position - run.pos
				var flat := Vector2(to.x, to.z)
				if flat.length() < 0.5:
					_warn(run)
					return
				var v := Vector2(run.dir.x, run.dir.z)
				v = v.rotated(clampf(v.angle_to(flat), -run.track * dt, run.track * dt))
				run.dir = Vector3(v.x, 0, v.y)
			else:
				run.target = null
			run.pos += run.dir * run.speed * dt
			run.gone += run.speed * dt
			if run.gone >= d.reach:
				_warn(run)
				return
			# The stain under the ground: little bubbles popping and a dark trail.
			run.trail -= dt
			if run.trail <= 0.0:
				run.trail = 0.04
				var p: Vector3 = run.pos + Vector3(randf_range(-0.3, 0.3), 0.08, randf_range(-0.3, 0.3))
				vfx.sprite_anim("res://fx/tex/custom/bubble_pop.png", p, 0.5, Vector2i(1, 5), 0.3, Status.COLOR.tox)
				vfx.mark(run.pos, "poison_puddle", 0.45, 1.2)
		"warn":
			# The ground bubbles where it will erupt.
			run.trail -= dt
			if run.trail <= 0.0:
				run.trail = 0.06
				var off: Vector3 = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).limit_length(1.0) * d.radius
				vfx.sprite_anim("res://fx/tex/custom/bubble_pop.png", run.pos + off + Vector3.UP * 0.05, 0.4, Vector2i(1, 5), 0.25, Status.COLOR.tox)
			if run.t >= d.warn:
				_erupt(run)
		"erupt":
			if run.t >= ERUPT:
				run.phase = "done"


func _warn(run: Dictionary) -> void:
	run.phase = "warn"
	run.t = 0.0
	run.trail = 0.0
	l.main.vfx.telegraph(run.pos, d.radius, d.warn + 0.05, Status.COLOR.tox)
	l.main.audio.play_sound("toxic", run.pos, -10.0, 0.7)


func _erupt(run: Dictionary) -> void:
	run.phase = "erupt"
	run.t = 0.0
	var g := Hit.new()
	g.user = l
	g.move_id = id
	g.type = d.type
	g.cat = "status"
	g.damage = 0.0
	g.stun = 0.0
	g.hitstop = 0.0
	g.contact = false
	g.strength = 0
	g.local = false
	g.shape = "ring"
	g.center = run.pos
	g.r_in = 0.0
	g.r_out = d.radius
	g.ground_only = true
	g.lifetime = BURST
	l.main.combat.add_hit(g)
	# A column of bubbles rising, in steps.
	var vfx: Vfx = l.main.vfx
	for i in 14:
		var b: Node3D = vfx.pixel_ball("toxic_bubble", 4, randf_range(0.3, 0.55), Status.COLOR.tox, 8.0, i % 4 == 0)
		var off: Vector3 = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).limit_length(1.0) * d.radius * 0.8
		var base: Vector3 = run.pos + off
		var rise := randf_range(1.6, 3.2)
		var delay := randf() * 0.25
		b.global_position = base
		b.visible = false
		vfx.live(b, ERUPT + 0.35, func(k: float):
			var tk := k * (ERUPT + 0.35) - delay
			b.visible = tk > 0.0
			b.global_position = base + Vector3.UP * snappedf(maxf(tk, 0.0) * rise, 0.0625))
	vfx.burst("shadow", run.pos + Vector3.UP * 0.2, Vector3.UP, Status.COLOR.tox, 0.8)
	vfx.wave(run.pos, d.radius * 1.15, 0.3, Status.COLOR.tox, 0.1)
	vfx.mark(run.pos, "poison_puddle", d.radius, 2.5)
	l.main.audio.play_sound("toxic_hit", run.pos, -4.0)


func pose() -> Dictionary:
	match phase:
		"startup":
			return {"tilt": -0.12, "stretch": 1.05}
		"active":
			# A stamp on the ground.
			return {"tilt": 0.1, "stretch": 0.88}
	return {}
