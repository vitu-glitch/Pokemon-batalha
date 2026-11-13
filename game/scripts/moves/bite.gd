extends Action
## Bite and Crunch: it rears back, then lunges jaws first; where it lands, Cobblemon's jaws
## snap shut on the rival (Crunch's bigger, with rocks). The data sets how far it lunges and
## the extra (flinch, lowering Defense).

var _shade := 0.0


func on_start() -> void:
	turn_mult = 3.0


func in_startup(delta: float) -> void:
	tint_col = Roster.TYPE_COLOR.dark
	tint_k = 0.3 * (t / maxf(startup_len(), 0.01))
	_shade -= delta
	if _shade <= 0.0:
		_shade = 0.06
		l.main.vfx.burst("shadow", mouth(), Vector3.UP, Color(0.25, 0.15, 0.3), 0.25)


func on_active() -> void:
	tint_k = 0.0
	advance_by(d.advance / d.active * 0.5)
	var g := hit({"shape": "sphere", "center": Vector3(0, l.data.height * 0.6, l.data.radius + d.reach * 0.5), "radius": d.radius})
	var me := l
	var after: Array = ["bite_targetspark"] if id == "bite" else ["crunch_targetrocks", "crunch_targetspark"]
	g.on_strike = func(o: Node, _res: String):
		# Cobblemon's own: the jaws on the rival, then the sparks (and rocks for Crunch).
		var h: float = o.data.height if o is Fighter else 1.0
		var at: Vector3 = (o as Node3D).global_position
		# One round each ("dur" 1 s): these loop in Cobblemon and would bite again.
		var one := {"height": h, "width": h * 0.8, "dur": 1.0}
		me.main.fx.play(id + "_target", at, me.center(), one)
		await me.get_tree().create_timer(0.15 if id == "bite" else 0.2).timeout
		for fx in after:
			me.main.fx.play(fx, at, null, one)
	l.main.vfx.ribbon(func(): return [l.center(), mouth()], Roster.TYPE_COLOR.dark, d.active + 0.05, 0.18)


func on_recovery() -> void:
	if landed:
		play_sound(id, 0.0)


func pose() -> Dictionary:
	match phase:
		"startup":
			return {"tilt": -0.25, "stretch": 0.92}
		"active":
			return {"tilt": 0.4, "stretch": 1.1, "anim": "physical"}
	return {"tilt": 0.15 * (1.0 - t / d.recovery)}
