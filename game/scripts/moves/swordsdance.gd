extends Action
## Swords Dance: Scizor spins with Cobblemon's swords around it. It is vulnerable while
## dancing (any hit cuts it). If it finishes, its next "boosted_hits" physical hits deal
## "mult" for "boost_dur" seconds (applied by Fighter.outgoing_mod); the pincers glow
## while it lasts.

var _spin := 0.0


func on_start() -> void:
	faces_rival = false
	play_sound("swordsdance", -2.0)


func in_active(delta: float) -> void:
	_spin += delta * 9.0
	tint_col = Color(1.0, 0.85, 0.5)
	tint_k = 0.3 * sin(t / d.active * PI)
	if int(total * 20.0) % 3 == 0:
		l.main.vfx.burst("stars", l.center() + Vector3.UP * 0.5, Vector3.UP, Color(1.0, 0.9, 0.6), 0.3)


func on_recovery() -> void:
	l.boosted_hits = d.boosted_hits
	l._boost_t = d.boost_dur
	l.main.vfx.cobble("swordsdance_sparkle", l.center(), null, l.data.height)
	l.main.vfx.wave(l.global_position, 2.0, 0.3, Color(1.0, 0.85, 0.5), 0.06)
	tint_k = 0.0


func pose() -> Dictionary:
	match phase:
		"startup":
			return {"stretch": 0.95}
		"active":
			return {"spin": fmod(_spin, TAU), "stretch": 1.0 + 0.04 * sin(_spin * 2.0)}
	return {"stretch": 1.03}
