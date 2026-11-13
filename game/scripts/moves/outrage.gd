extends Action
## Outrage, like in the DS games and the anime: the user flies into a rage, wrapped in a
## red, burning dragon aura with its eyes aglow, and throws itself at the rival "lunges"
## times in a row, each one aimed anew. Each lunge hits once; together they add up to the
## move's damage. Then, as in the games, the rage leaves it confused: a short recovery, then
## "confuse" seconds with its movement turned around (Fighter.confused).

const RED := Color(1.0, 0.25, 0.15)
const VIOLET := Color(0.5, 0.36, 1.0)
const COMBO_SUM := 2.64     # 1 + 0.88 + 0.76: the combo falloff of the 2nd and 3rd lunge

var _fire_fx: GPUParticles3D
var _light: OmniLight3D
var _lunge := -1
var _dir := Vector3.FORWARD
var _g: Hit
var _stars := 0.0


func on_start() -> void:
	turn_mult = 2.0
	_fire_fx = l.main.vfx.continuous_emitter("fire_fx", 80, 0.45, Vector2(1.0, 3.0), 70.0, Vector2(0.5, 1.0))
	(_fire_fx.process_material as ParticleProcessMaterial).emission_sphere_radius = l.data.radius
	_light = OmniLight3D.new()
	_light.light_color = RED
	_light.omni_range = 5.0
	l.main.vfx.add_child(_light)
	l.main.vfx.cobble("dragonrage_actor", l.global_position, null, l.data.height)
	play_sound("outrage_cry", 0.0)


func _follow() -> void:
	if is_instance_valid(_fire_fx):
		_fire_fx.global_position = l.center()
	if is_instance_valid(_light):
		_light.global_position = l.center()
		_light.light_energy = 3.0 + randf() * 1.5


func in_startup(_delta: float) -> void:
	tint_col = RED
	tint_k = 0.5 * clampf(t / maxf(startup_len(), 0.01), 0.0, 1.0)
	_follow()


func on_active() -> void:
	_lunge = -1
	no_brake = true


func in_active(_delta: float) -> void:
	var each: float = float(d.active) / float(d.lunges)
	var n := mini(int(t / each), int(d.lunges) - 1)
	if n != _lunge:
		_lunge = n
		_start_lunge(n)
	# The dash lasts the first part of each lunge; then it digs in before the next.
	var lt := t - n * each
	var dashing := lt < each * 0.55
	var v: Vector3 = _dir * (float(d.dist) / (each * 0.55) if dashing else 0.0)
	l.velocity = Vector3(v.x, l.velocity.y, v.z)
	if not dashing and _g:
		remove_hits()
		_g = null
	_follow()
	tint_k = 0.6
	if int(total * 30.0) % 2 == 0:
		l.main.vfx.burst("fire_fx", l.center() - _dir * 0.6, -_dir, Color(0, 0, 0, 0), 1.0)


func _start_lunge(n: int) -> void:
	_dir = l.forward()
	if l.rival and is_instance_valid(l.rival) and l.rival.state != "ko":
		var to: Vector3 = l.rival.global_position - l.global_position
		to.y = 0.0
		if to.length() > 0.1:
			_dir = to.normalized()
	remove_hits()
	_g = hit({"shape": "capsule", "a": Vector3(0, l.data.height * 0.45, -0.2), "b": Vector3(0, l.data.height * 0.45, l.data.radius + 0.8),
		"radius": l.data.radius + 0.2, "damage": float(d.damage) / COMBO_SUM, "quiet": n > 0,
		"stun": d.stun_last if n == int(d.lunges) - 1 else d.stun, "knocks_down": n == int(d.lunges) - 1})
	l.main.vfx.dust(l.global_position, 1.2)
	l.main.shake_camera(0.15, l.global_position)
	play_sound("outrage", -2.0)


func on_recovery() -> void:
	no_brake = false
	tint_k = 0.0
	remove_hits()
	_g = null
	l.velocity.x *= 0.2
	l.velocity.z *= 0.2
	_turn_off()
	# The rage wears off: it is left confused, its movement turned around for a while.
	l.confuse(float(d.confuse))


func in_recovery(delta: float) -> void:
	# Stars circling its head.
	_stars -= delta
	if _stars <= 0.0:
		_stars = 0.12
		var head: Vector3 = l.global_position + Vector3.UP * (l.data.height + 0.3)
		var a := total * 6.0
		l.main.vfx.burst("stars", head + Vector3(cos(a), 0.0, sin(a)) * (l.data.radius + 0.2), Vector3.UP, Color(0, 0, 0, 0), 0.35)


func on_end(_i: bool) -> void:
	_turn_off()


func _turn_off() -> void:
	l.main.vfx.stop_emitter(_fire_fx)
	_fire_fx = null
	if is_instance_valid(_light):
		_light.queue_free()
	_light = null


func pose() -> Dictionary:
	match phase:
		"startup":
			return {"tilt": -0.3, "stretch": 1.1 + 0.04 * sin(total * 30.0), "anim": "battle_cry" if l.model.has_anim("battle_cry") else ""}
		"active":
			return {"tilt": 0.6, "stretch": 1.12}
	return {"tilt": 0.15 * sin(total * 5.0), "stretch": 0.94}
