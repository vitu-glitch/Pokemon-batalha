extends Action
## Close-range blows with a body motion of their own ("motion" in the data), each one read
## from its wind-up:
##   headbutt  rears back, then hops forward head first (Headbutt). Stars on a flinch.
##   shove     braces low, kicking up dust, and drives both arms forward (Strength): the
##             ground ripples and it pushes hard.
##   kick      winds up turning, then spins into a kick (Mega Kick): the foot leaves a trail.
##   chop      raises the arm high and brings it straight down (Brick Break): a crack opens
##             on the ground where it lands.
##   rage      shakes with anger, then charges in (Facade); red while it hits twice as hard.
## Where it hits: a sphere "reach" in front at "hit_height" (share of its height), radius
## "radius"; "advance" meters forward while active.

var _dust := 0.0


func on_start() -> void:
	turn_mult = 2.0
	if d.motion == "rage":
		l.main.vfx.cobble("superfang_actorrage", l.point("locator_head") + Vector3.UP * 0.3, null, l.data.height)


func in_startup(delta: float) -> void:
	var k: float = t / startup_len()
	tint_col = _color()
	tint_k = 0.3 * k
	_dust -= delta
	match d.motion:
		"shove":
			if _dust <= 0.0:
				_dust = 0.08
				l.main.vfx.dust(l.global_position, l.data.radius * 1.2)
		"rage":
			if _dust <= 0.0:
				_dust = 0.12
				l.main.vfx.burst("stars", l.point("locator_head"), Vector3.UP, _color(), 0.3)
		"kick":
			if _dust <= 0.0:
				_dust = 0.1
				l.main.vfx.burst("wind", l.global_position + Vector3.UP * 0.3, Vector3.UP, Color(0, 0, 0, 0), 0.4)


func _color() -> Color:
	if d.motion == "rage" and l.has_status():
		return Color(1.0, 0.35, 0.25)          # Facade at full power
	return d.get("color", Roster.TYPE_COLOR[d.type])


func on_active() -> void:
	var h: float = l.data.height
	if d.motion == "headbutt":
		l.velocity.y = maxf(l.velocity.y, 3.5)
	advance_by(float(d.get("advance", 2.0)) / d.active * 0.5)
	hit({"shape": "sphere", "center": Vector3(0, h * float(d.get("hit_height", 0.5)), l.data.radius + d.reach * 0.5), "radius": d.radius})
	var col := _color()
	match d.motion:
		"shove":
			l.main.vfx.wave(l.global_position + l.forward() * (l.data.radius + 0.8), 2.6, 0.35, col, 0.07)
			l.main.shake_camera(0.12, l.global_position)
		"kick":
			l.main.vfx.ribbon(func(): return [l.center(), l.global_position + l.forward() * (l.data.radius + d.reach) + Vector3.UP * h * 0.35],
				col, d.active + 0.05, 0.16)
		"chop":
			l.main.vfx.ribbon(func(): return [l.center() + Vector3.UP * h * 0.4, l.point("locator_hand_primary")], col, d.active + 0.05, 0.14)
			var at: Vector3 = l.global_position + l.forward() * (l.data.radius + d.reach * 0.6)
			l.main.vfx.mark(Vector3(at.x, l.main.ground_y, at.z), "crack", 0.9, 2.5)
			l.main.vfx.burst("debris", at, Vector3.UP, Color(0, 0, 0, 0), 0.6)
		"headbutt", "rage":
			l.main.vfx.burst("dust", l.global_position, -l.forward(), Color(0, 0, 0, 0), 0.6)
	l.main.audio.play_sound("dodge", l.global_position, -6.0, 0.8)
	play_sound(d.get("sound", "bodyslam"), -2.0)


func on_recovery() -> void:
	tint_k = 0.0


func pose() -> Dictionary:
	var k: float = clampf(t / maxf(startup_len(), 0.01), 0.0, 1.0)
	match [d.motion, phase]:
		["headbutt", "startup"]:
			return {"tilt": -0.35 * k, "stretch": 0.92}
		["headbutt", "active"]:
			return {"tilt": 0.7, "stretch": 1.15, "anim": "physical"}
		["shove", "startup"]:
			return {"tilt": -0.15, "stretch": 1.0 - 0.12 * k, "height": -0.1 * k}
		["shove", "active"]:
			return {"tilt": 0.45, "stretch": 1.12, "anim": "physical"}
		["kick", "startup"]:
			return {"spin": -0.9 * k, "stretch": 0.95, "tilt": -0.1}
		["kick", "active"]:
			return {"spin": lerpf(-0.9, TAU, clampf(t / d.active, 0.0, 1.0)), "tilt": -0.15, "stretch": 1.05, "anim": "physical"}
		["chop", "startup"]:
			return {"tilt": -0.45 * k, "stretch": 1.0 + 0.1 * k, "height": 0.15 * k}
		["chop", "active"]:
			return {"tilt": 0.8, "stretch": 0.95, "anim": "physical"}
		["rage", "startup"]:
			return {"side": 0.08 * sin(t * 60.0), "stretch": 1.04, "tilt": -0.1}
		["rage", "active"]:
			return {"tilt": 0.5, "stretch": 1.1, "anim": "physical"}
	return {"tilt": 0.12 * (1.0 - t / maxf(d.recovery, 0.01))}
