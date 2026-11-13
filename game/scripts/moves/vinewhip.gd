extends Action
## Vine Whip: two vines come out of the body and lash forward with long reach. If they
## land, they pull the rival toward Venusaur (into its zone). It telegraphs: the vines
## pull back before striking.

var _vines: Array = []


func on_start() -> void:
	turn_mult = 2.2
	play_sound("charge", -14.0)


func in_startup(_delta: float) -> void:
	tint_col = Roster.TYPE_COLOR.grass
	tint_k = 0.25 * (t / d.startup)


func _root(side: float) -> Vector3:
	return to_world(Vector3(side * l.data.radius * 0.55, l.data.height * 0.62, l.data.radius * 0.4))


func on_active() -> void:
	var height: float = l.data.height
	# The hit is a long capsule in front; the negative push pulls the target in.
	hit({"shape": "capsule", "a": Vector3(0, height * 0.45, l.data.radius), "b": Vector3(0, height * 0.35, l.data.radius + d.reach),
		"radius": d.radius, "push_dir": Vector3(0, 0.15, -1.0), "push": d.yank})
	var col := Roster.TYPE_COLOR.grass.darkened(0.25)
	for side in [-1.0, 1.0]:
		var clock := {"t": 0.0}
		var dur: float = d.active + 0.12
		var vfx: Vfx = l.main.vfx
		vfx.ribbon(func():
			clock.t += vfx.get_process_delta_time()
			var k := clampf(clock.t / dur, 0.0, 1.0)
			# Extends, reaches the end and returns, lashing from side to side.
			var length: float = d.reach * sin(k * PI)
			var base := _root(side)
			var dir := l.forward().rotated(Vector3.UP, side * (0.35 - k * 0.6))
			var tip: Vector3 = base + dir * length + Vector3.DOWN * (l.data.height * 0.25 * k)
			return [base, tip], col, dur, 0.12)
	play_sound("vinewhip", -2.0)


func on_recovery() -> void:
	tint_k = 0.0


func pose() -> Dictionary:
	match phase:
		"startup":
			return {"tilt": -0.18, "stretch": 0.95}
		"active":
			return {"tilt": 0.2, "stretch": 1.04}
	return {"tilt": 0.05}
