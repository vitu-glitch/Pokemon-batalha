extends Action
## Substitute: Gengar leaves an identical doll where it stood and the rival locks onto
## the doll (its camera and its moves go there; the AI falls for it too). Gengar turns
## truly invisible, and faster, for "dur" or until it uses a move. The doll lasts
## "decoy_dur" or until the first hit. Whoever plays Gengar sees it as a faint ghost.


func on_start() -> void:
	faces_rival = false


func on_active() -> void:
	var main: Node = l.main
	# Only one decoy at a time.
	for o in main.combat.targets.duplicate():
		if o is Decoy and o.user == l:
			o.undo()
	var decoy := Decoy.new()
	main.add_child(decoy)
	decoy.setup(main, l, d.decoy_dur)
	main.combat.targets.append(decoy)
	l.translucent = d.dur
	var r: Fighter = l.rival
	if r and is_instance_valid(r):
		r.fooled_by = decoy
	main.vfx.burst("shadow", l.center(), Vector3.UP, Color(0, 0, 0, 0), 1.4)
	main.vfx.burst("smoke", l.global_position, Vector3.UP, Color(0, 0, 0, 0), 1.0)
	play_sound("substitute", -2.0)
	# Shoots off sideways to get away from the decoy.
	var side := l.forward().cross(Vector3.UP) * (1.0 if randf() < 0.5 else -1.0)
	if l.is_player and l.ctrl.move_input.length() > 0.3:
		side = l._world_dir(l.ctrl.move_input)
	l.velocity.x = side.x * 9.0
	l.velocity.z = side.z * 9.0
	no_brake = true


func on_recovery() -> void:
	no_brake = false


func pose() -> Dictionary:
	match phase:
		"startup":
			return {"stretch": 0.9}
		"active":
			return {"stretch": 1.08, "side": 0.3}
	return {}
