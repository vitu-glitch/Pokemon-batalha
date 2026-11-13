extends Action
## Double Team: two copies of Greninja appear at its sides (with a speed flash) and run
## around the rival on their own until "decoy_dur" runs out or the first hit. If the rival
## had Greninja locked on, it loses the lock (and it does not jump onto a copy). They fool
## the AI just like Gengar's decoy; the real one has a shadow.


func on_start() -> void:
	faces_rival = false


func on_active() -> void:
	var main: Node = l.main
	for o in main.combat.targets.duplicate():
		if o is Decoy and o.user == l:
			o.undo()
	var side := l.forward().cross(Vector3.UP)
	for s in [-1.0, 1.0]:
		var copy := Decoy.new()
		main.add_child(copy)
		copy.setup(main, l, d.decoy_dur)
		copy.kind = "clone"
		copy.wander = true
		copy.global_position = l.global_position + side * s * d.separation
		main.combat.targets.append(copy)
		main.vfx.afterimage(l, Color(0.6, 0.8, 1.0))
		main.vfx.burst("wind", copy.center(), side * s, Color(0, 0, 0, 0), 0.8)
	l.invulnerable = maxf(l.invulnerable, 0.2)
	# A player who had it locked on loses the lock.
	var r: Fighter = l.rival
	if r and is_instance_valid(r) and r.is_player and r.locked:
		r.locked = false
	play_sound("doubleteam", -2.0)


func pose() -> Dictionary:
	match phase:
		"startup":
			return {"stretch": 0.92}
		"active":
			return {"stretch": 1.05}
	return {}
