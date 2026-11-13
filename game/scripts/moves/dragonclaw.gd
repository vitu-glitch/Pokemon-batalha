extends Action
## Dragon Claw (and X-Scissor with its own data): two advancing swipes in a row, with
## trails in the type's color. If it lands, it can be cancelled into another move.
## "cross": the two slashes cross in an X; "final_strength": the second one's strength.

var _second := false


func on_start() -> void:
	turn_mult = 3.0


func in_startup(_delta: float) -> void:
	tint_col = Roster.TYPE_COLOR[d.type]
	tint_k = 0.3 * (t / d.startup)
	if int(total * 40.0) % 3 == 0:
		l.main.vfx.burst(d.get("particles", "sparks_dragon"), l.point("locator_hand_primary"), Vector3.UP, Color(0, 0, 0, 0), 0.4)


func _swipe(hand: String, side: float) -> void:
	remove_hits()
	advance_by(d.advance / 0.18)
	var strong: bool = side < 0.0 and d.has("final_strength")
	hit({"shape": "sphere", "center": Vector3(0, l.data.height * 0.5, l.data.radius + d.reach * 0.5), "radius": d.radius,
		"strength": d.final_strength if strong else d.get("strength", 1), "damage": d.damage * (1.3 if strong else 1.0)})
	var col: Color = Roster.TYPE_COLOR[d.type]
	var cross_sign: float = (-1.0 if side < 0.0 else 1.0) if d.get("cross", false) else 1.0
	var clock := {"t": 0.0}
	l.main.vfx.ribbon(func():
		clock.t += l.get_process_delta_time()
		var k := clampf(clock.t / 0.14, 0.0, 1.0)
		var c := l.center() + Vector3.UP * 0.3
		var dir := l.forward().rotated(Vector3.UP, lerpf(1.0, -1.0, k) * side) + Vector3.DOWN * (k - 0.5) * (1.6 if d.get("cross", false) else 0.8) * cross_sign
		return [c + dir * 0.6, c + dir * (l.data.radius + d.reach)], col, 0.14, 0.15)
	play_sound(d.get("sound", "dragonclaw"), -2.0)


func on_active() -> void:
	_swipe("locator_hand_primary", 1.0)


func in_active(_delta: float) -> void:
	if not _second and t >= 0.18:
		_second = true
		_swipe("locator_hand_secondary", -1.0)


func on_recovery() -> void:
	tint_k = 0.0


func pose() -> Dictionary:
	match phase:
		"startup":
			return {"tilt": -0.15, "side": 0.2, "anim": "physical", "reset": t < 0.02}
		"active":
			var side := 1.0 if not _second else -1.0
			return {"tilt": 0.3, "side": -0.3 * side, "stretch": 1.05, "anim": "physical", "reset": _second and t < 0.2}
	return {}
