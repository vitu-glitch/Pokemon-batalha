extends Action
## Straight-line dash (Quick Attack, Aqua Jet, Extreme Speed, Wing Attack): shoots forward
## hitting whatever is in the way. It is not a dodge: no invulnerability, and if it misses
## the recovery is exposed. Color, particles and sound come from the move data.

var _dir := Vector3.FORWARD
var _cap_y := INF


func on_start() -> void:
	turn_mult = 4.0
	no_brake = true


func in_startup(_delta: float) -> void:
	tint_col = d.get("color", Color(1, 1, 1))
	tint_k = 0.35


func on_active() -> void:
	# Toward the target, including its height (if it flies, or if the dash starts in the
	# air). It rises at most to where the target was: if the target dodges, it carries on
	# horizontally at that height instead of shooting into the sky.
	_dir = l.attack_dir()
	if l.is_on_floor() and absf(_dir.y) < 0.2:
		_dir = Vector3(_dir.x, 0.0, _dir.z).normalized()
	_cap_y = minf(l.target_center().y - l.data.height * 0.5 + 0.3, l.attack_ceiling()) if _dir.y > 0.0 else INF
	faces_rival = false
	no_gravity = not l.is_on_floor() or absf(_dir.y) > 0.01
	if d.has("rise") and absf(_dir.y) < 0.01:
		l.velocity.y = d.rise
		no_gravity = false
	var height: float = l.data.height
	hit({"shape": "capsule", "a": Vector3(0, height * 0.45, -0.2), "b": Vector3(0, height * 0.45, l.data.radius + 0.5), "radius": l.data.radius * 0.9})
	l.main.vfx.dust(l.global_position, 1.0)
	l.main.vfx.burst(d.get("particles", "wind"), l.center(), -_dir)
	# Trail along the whole path: a vertical ribbon that follows the body.
	var body_h: float = l.data.height
	l.main.vfx.ribbon(func(): return [l.global_position + Vector3.UP * body_h * 0.15, l.global_position + Vector3.UP * body_h * 0.85],
		d.get("color", Color(1.0, 0.97, 0.85)), d.active, 0.22)
	l.main.vfx.light(l.center(), d.get("color", Color(1.0, 0.95, 0.8)), 2.5, 4.0, 0.15)
	play_sound(d.get("sound", "quickattack"), 0.0)


func in_active(_delta: float) -> void:
	tint_k = 0.2
	if _dir.y > 0.0 and l.global_position.y >= _cap_y:
		_dir = Vector3(_dir.x, 0.0, _dir.z).normalized()
	var v: Vector3 = _dir * d.dist / d.active
	l.velocity = Vector3(v.x, v.y if no_gravity else l.velocity.y, v.z)
	if int(total * 40.0) % 2 == 0:
		l.main.vfx.afterimage(l, d.get("color", Color(1.0, 0.95, 0.7)))
	if d.has("particles") and int(total * 40.0) % 3 == 0:
		l.main.vfx.burst(d.particles, l.center(), -_dir, Color(0, 0, 0, 0), 0.4)


func on_recovery() -> void:
	no_gravity = false
	no_brake = false
	tint_k = 0.0
	# If the dash ends while rising (the target was higher than it can reach), the
	# climb is cut here: at Extreme Speed's velocity (71 m/s) the leftover inertia used
	# to launch it over 70 m into the air.
	l.velocity.y = minf(l.velocity.y, 0.0)
	l.velocity.x *= 0.3
	l.velocity.z *= 0.3


func pose() -> Dictionary:
	match phase:
		"startup":
			return {"tilt": -0.2, "stretch": 0.8}
		"active":
			return {"tilt": 0.55, "stretch": 1.2, "anim": d.get("anim", ""), "anim_speed": 2.0}
	return {"tilt": -0.15 * (1.0 - t / d.recovery), "stretch": 0.95}
