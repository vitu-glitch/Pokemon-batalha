extends Action
## Detect: Lucario plants its feet and reads the attack. During a short window (the
## active phase), a hit that reaches it does nothing and the attacker is stunned: that
## is its counter. If nobody hits it, it is left exposed in a long recovery. Visible as a
## blue flash at the start and a ring when it succeeds.

var _landed := false


func on_start() -> void:
	faces_rival = true
	turn_mult = 3.0
	play_sound("detect", -2.0)


func on_active() -> void:
	tint_col = Color(0.5, 0.75, 1.0)
	tint_k = 0.45
	l.main.vfx.light(l.center(), Color(0.5, 0.75, 1.0), 2.5, 4.0, 0.3)


func in_active(_delta: float) -> void:
	tint_k = 0.45 * (1.0 - t / d.active) + 0.1


## Called by the fighter when it receives a hit: during the window, it cancels it.
func intercept(info: Dictionary) -> String:
	if phase != "active":
		return ""
	var at = info.attacker
	_landed = true
	landed = true
	var vfx: Vfx = l.main.vfx
	vfx.wave(l.global_position, 2.5, 0.3, Color(0.5, 0.75, 1.0), 0.08)
	vfx.burst("stars", l.center(), Vector3.UP, Color(0.6, 0.8, 1.0), 1.4)
	l.main.fx.anim("generic/exclamation.png", l.center() + Vector3.UP * (l.data.height * 0.5 + 0.5), 0.8, 11, 0.6)
	l.main.shake_camera(0.12, l.center())
	l.main.audio.play_sound("armor", l.global_position, 0.0)
	if at and is_instance_valid(at) and at.has_method("effect"):
		at.effect("stun", d.rival_stun)
	l.invulnerable = 0.35
	# Leaves the guard right away: the short recovery is its reward.
	_go_to("recovery")
	return "detected"


func in_recovery(_delta: float) -> void:
	tint_k = 0.0
	if _landed and t >= d.recovery_on_hit:
		finish(false)


func pose() -> Dictionary:
	match phase:
		"startup":
			return {"tilt": -0.1, "stretch": 0.96}
		"active":
			return {"tilt": -0.08, "side": 0.15, "stretch": 0.94, "anim": "special"}
	if _landed:
		return {"tilt": 0.15, "stretch": 1.04}
	return {"tilt": 0.12 * (1.0 - t / d.recovery), "stretch": 0.98}
