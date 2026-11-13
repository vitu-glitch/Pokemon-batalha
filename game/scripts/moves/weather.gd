extends Action
## Sunny Day, Rain Dance, Sandstorm and Snowscape ("weather" in the data): the Pokémon
## rears up and calls the weather, which lasts 5 turns (see Weather). It is open while it
## calls it: any hit cuts it and the weather does not come.

const COLORS := {"sun": Color(1.0, 0.8, 0.35), "rain": Color(0.4, 0.6, 1.0), "sand": Color(0.85, 0.65, 0.4),
	"snow": Color(0.85, 0.95, 1.0)}


func on_start() -> void:
	faces_rival = false
	l.main.audio.cry(l.species, l.global_position, 0.8)


func in_startup(_delta: float) -> void:
	tint_col = COLORS.get(d.weather, Color.WHITE)
	tint_k = 0.35 * (t / d.startup)


func on_active() -> void:
	var col: Color = COLORS.get(d.weather, Color.WHITE)
	l.main.weather.start(d.weather)
	l.main.vfx.wave(l.global_position, 3.0, 0.4, col, 0.08)
	for i in 3:
		l.main.vfx.burst("stars", l.center() + Vector3.UP * (0.6 + i * 0.6), Vector3.UP, col, 0.5)
	l.main.vfx.light(l.center() + Vector3.UP * 2.0, col, 3.0, 8.0, 0.4)


func on_recovery() -> void:
	tint_k = 0.0


func pose() -> Dictionary:
	match phase:
		"startup":
			return {"tilt": -0.25 * (t / d.startup), "stretch": 1.0 + 0.06 * (t / d.startup), "anim": "status"}
		"active":
			return {"tilt": -0.25, "stretch": 1.06}
	return {"tilt": -0.1}
