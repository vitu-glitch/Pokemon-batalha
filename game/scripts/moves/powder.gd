extends Action
## Powders (Sleep Powder, Poison Powder): the Pokémon shakes a cloud of powder out in front
## of it with Cobblemon's particles. Short reach: it has to get close, so it does not
## reward running away. Whoever is in the cloud while it lasts gets the status; Grass types
## and Overcoat are immune to powders, as in the games (Fighter._status_move).

var _g: Hit
var _puff := 0.0


func on_start() -> void:
	turn_mult = 2.5


func in_startup(_delta: float) -> void:
	tint_col = d.color
	tint_k = 0.2 + 0.15 * float(int(total * 12.0) % 2)


func on_active() -> void:
	tint_k = 0.0
	_g = hit({"shape": "cone", "local": false, "center": _origin(), "dir": l.forward(), "length": d.length, "angle": d.angle,
		"damage": 0.0, "stun": 0.0, "hitstop": 0.0, "strength": 0, "contact": false})
	l.main.vfx.cobble(id, _origin(), _origin() + l.forward() * 3.0, l.data.height)
	play_sound(id, -2.0)


func in_active(delta: float) -> void:
	_g.center = _origin()
	_g.dir = l.forward()
	_puff -= delta
	if _puff <= 0.0:
		_puff = 0.12
		# Clouds scattered through the cone, low and drifting.
		for k in 2:
			var ang := randf_range(-d.angle, d.angle) * 0.8
			var p := l.global_position + l.forward().rotated(Vector3.UP, ang) * randf_range(0.9, d.length) + Vector3.UP * randf_range(0.3, 1.1)
			l.main.vfx.cobble(id + "_cloud", p, null, 1.0)


func on_recovery() -> void:
	remove_hits()


func _origin() -> Vector3:
	return l.global_position + Vector3.UP * l.data.height * 0.6 + l.forward() * l.data.radius * 0.5


func pose() -> Dictionary:
	match phase:
		"startup":
			return {"stretch": 0.92, "tilt": -0.1}
		"active":
			# It shakes itself: a quick side to side in steps.
			return {"side": 0.12 * (1.0 if int(total * 16.0) % 2 == 0 else -1.0), "stretch": 1.04}
	return {}
