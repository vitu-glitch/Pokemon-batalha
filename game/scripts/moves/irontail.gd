extends Action
## Iron Tail: the tail turns to steel (it glows during the startup) while it leaps toward
## the rival ("leap" meters at most), flips in the air and comes down tail first like a
## steel hammer: it hits where it lands and in a small shockwave around ("slam_radius"),
## launching the target. Used in the air, it dives straight from there.

var _air := false
var _dive: Hit
var _shine := 0.0


func on_start() -> void:
	_air = not l.is_on_floor()
	turn_mult = 2.0
	if not _air:
		# The leap: toward the rival, up to "leap" meters, peaking as the startup ends.
		var dist: float = d.leap
		if l.rival and is_instance_valid(l.rival) and l.rival.state != "ko":
			var to := l.rival.global_position - l.global_position
			dist = clampf(Vector2(to.x, to.z).length() - l.data.radius - 0.4, 0.0, d.leap)
		var up: float = l.data.gravity * startup_len()
		l.velocity = l.forward() * (dist / (startup_len() + 0.25)) + Vector3.UP * up
		no_brake = true
	play_sound("charge", -10.0)


func in_startup(delta: float) -> void:
	tint_col = Roster.TYPE_COLOR.steel
	tint_k = 0.2 + 0.3 * (t / d.startup)
	_shine -= delta
	if _shine <= 0.0:
		_shine = 0.07
		l.main.vfx.burst("stars", l.point("locator_tail_tip"), Vector3.UP)
	if _air:
		l.velocity.y = maxf(l.velocity.y, 0.5)


func on_active() -> void:
	# Always comes down from the air (the leap, or a jump): tail first.
	no_gravity = true
	var fwd := Vector3(l.velocity.x, 0.0, l.velocity.z).limit_length(6.0)
	l.velocity = fwd + Vector3.DOWN * 18.0
	_dive = hit({"shape": "sphere", "center": Vector3(0, 0.2, l.data.radius * 0.5), "radius": 1.0})
	var col := Roster.TYPE_COLOR.steel
	l.main.vfx.ribbon(func():
		var base := l.point("locator_tail")
		var tip := l.point("locator_tail_tip")
		return [base, tip + (tip - base) * 0.9], col, d.active + 0.05, 0.2)
	l.main.vfx.light(l.point("locator_tail_tip"), Color(0.9, 0.95, 1.0), 2.5, 3.0, 0.2)
	l.main.vfx.sprite_anim(Vfx.TEX + "impact/impact_steel.png", l.point("locator_tail_tip"), 1.2, Vector2i(2, 7), 0.2)
	l.main.audio.play_sound("dodge", l.global_position, -4.0, 0.7)


func in_active(_delta: float) -> void:
	if l.is_on_floor() and t > 0.02:
		_ground_impact()
		_go_to("recovery")


## Landing: a small steel shockwave that also hits whoever is right around.
func _slam() -> void:
	var g := Hit.new()
	g.user = l
	g.move_id = id
	g.local = false
	g.shape = "sphere"
	g.center = l.global_position + Vector3.UP * 0.4
	g.radius = d.slam_radius
	g.type = d.type
	g.cat = d.cat
	g.damage = d.damage
	g.lift = d.lift
	g.stun = 0.5
	g.knocks_down = true
	g.strength = 2
	g.hitstop = d.hitstop
	g.lifetime = 0.08
	# Whoever the tail already hit on the way down is not hit again by the shockwave.
	if _dive:
		g.hit_list = _dive.hit_list.duplicate()
	l.main.combat.add_hit(g)


func on_recovery() -> void:
	no_gravity = false
	tint_k = 0.0


func _ground_impact() -> void:
	_slam()
	var p := l.global_position
	l.main.vfx.wave(p, 2.5, 0.35, Roster.TYPE_COLOR.steel)
	l.main.vfx.burst("dust", p, Vector3.UP, Color(0, 0, 0, 0), 1.5)
	l.main.vfx.mark(p, "crack", 1.0, 3.0)
	l.main.shake_camera(0.2, p)


func pose() -> Dictionary:
	match phase:
		"startup":
			return {"tilt": -0.3, "stretch": 0.9, "turn": -t / d.startup * 0.6}
		"active":
			return {"tilt": 0.9, "stretch": 1.1, "spin": TAU * clampf(t / 0.2, 0.0, 1.0), "anim": "physical"}
	return {"tilt": 0.15 * (1.0 - t / d.recovery)}
