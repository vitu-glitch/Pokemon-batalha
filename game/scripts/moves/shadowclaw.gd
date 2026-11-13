extends Action
## Shadow Claw: the hand fills with shadow (Cobblemon's own), then one wide swipe of a
## giant shadow claw, like in the DS games and the anime: three curved slashes standing in
## the air in front of it, turned in the world (not toward the camera), reaching further
## than its body ("reach"). It steps in as it swipes. The swipe breaks shots it meets
## ("deflects" 1).

func on_start() -> void:
	turn_mult = 3.0


func in_startup(_delta: float) -> void:
	tint_col = Roster.TYPE_COLOR.ghost
	tint_k = 0.35 * clampf(t / maxf(startup_len(), 0.01), 0.0, 1.0)
	if int(total * 40.0) % 3 == 0:
		l.main.vfx.burst("shadow", l.point("locator_hand_primary"), Vector3.UP, Color(0.3, 0.15, 0.4), 0.35)


func on_active() -> void:
	tint_k = 0.0
	advance_by(d.advance / d.active * 0.5)
	hit({"shape": "sphere", "center": Vector3(0, l.data.height * 0.55, l.data.radius + d.reach * 0.5), "radius": d.radius})
	var vfx: Vfx = l.main.vfx
	# The claw, standing across its way and tilted so the slashes fall diagonally.
	var fwd := l.forward()
	var basis := Basis.looking_at(fwd, Vector3.UP).rotated(fwd, deg_to_rad(-20.0))
	var at: Vector3 = l.center() + fwd * (l.data.radius + d.reach * 0.55) + Vector3.UP * 0.2
	vfx.flat_sprite("res://fx/tex/custom/shadow_claw.png", 4, d.claw, at, basis, 0.3, Color.WHITE, 0.0, Callable(), 0.14)
	vfx.ribbon(func(): return [l.center(), l.point("locator_hand_primary")], Roster.TYPE_COLOR.ghost, d.active + 0.08, 0.2)
	vfx.burst("shadow", at, fwd, Color(0.25, 0.1, 0.35), 0.8)
	l.main.audio.play_sound("dodge", l.global_position, -6.0, 0.7)


func on_recovery() -> void:
	if landed:
		play_sound(id, 0.0)


func pose() -> Dictionary:
	match phase:
		"startup":
			return {"tilt": -0.2, "stretch": 0.92, "spin": -0.35}
		"active":
			return {"tilt": 0.35, "stretch": 1.1, "spin": 0.4, "anim": "physical"}
	return {"tilt": 0.2 * (1.0 - t / maxf(float(d.recovery), 0.01))}
