extends Action
## Body Slam: crouches, jumps and lands with all its weight. During the startup and the
## jump it has armor (light hits do not interrupt it). The landing throws up a cloud of
## dust that bursts out and up like an upturned cone, widening to "dust_r" in "dust_t"
## seconds: whoever it catches outside the slam itself takes a lighter hit ("dust_damage").
## After landing it stays down for a good while: that is the punish window.

var _from := Vector3.ZERO
var _to := Vector3.ZERO
const CLOUD := Color(0.93, 0.91, 0.86)     # off-white: a cloud of the impact, not of earth
var _warning: MeshInstance3D
var _dust: Hit
var _dust_t := -1.0


func on_start() -> void:
	turn_mult = 1.2
	play_sound("charge", -12.0)


func in_startup(_delta: float) -> void:
	tint_col = Color(1, 0.85, 0.6)
	tint_k = 0.15 * (t / d.startup)
	if t > d.startup * 0.5 and _warning == null:
		_compute_target()
		_warning = l.main.vfx.telegraph(_to, 2.8, d.startup * 0.5 + d.active, Color(1.0, 0.55, 0.25))


func _compute_target() -> void:
	_from = l.global_position
	var dist: float = d.dist
	if l.rival and is_instance_valid(l.rival):
		dist = clampf(Vector2(l.rival.global_position.x - _from.x, l.rival.global_position.z - _from.z).length(), 2.0, d.dist)
	_to = _from + l.forward() * dist
	_to.y = l.main.ground_y


func on_active() -> void:
	if _warning == null:
		_compute_target()
	faces_rival = false
	no_gravity = true
	no_brake = true
	play_sound("bodyslam", 0.0)
	l.main.vfx.dust(l.global_position, 2.0)


func in_active(_delta: float) -> void:
	var k := clampf(t / d.active, 0.0, 1.0)
	var p := _from.lerp(_to, k)
	p.y = _from.y + sin(k * PI) * 3.2
	l.velocity = (p - l.global_position) / maxf(l.get_physics_process_delta_time(), 0.001)


func _landing() -> void:
	l.velocity = Vector3.ZERO
	var slam := hit({"shape": "sphere", "local": false, "center": l.global_position + Vector3.UP * 0.5, "radius": 2.8, "lifetime": 0.06})
	var p := l.global_position
	var vfx: Vfx = l.main.vfx
	vfx.wave(p, float(d.dust_r) + 0.3, 0.35, CLOUD, 0.08)
	vfx.burst("dust", p, Vector3.UP, CLOUD, 2.0)
	# The dust cloud's hit: a ring from the slam's edge outward, rising with the cloud.
	_dust = hit({"shape": "ring", "local": false, "center": p, "r_in": 2.8, "r_out": 2.8, "damage": d.dust_damage,
		"lift": 2.5, "knocks_down": false, "strength": 1, "hitstop": 0.06, "stun": 0.4, "quiet": true, "knock": 2.0})
	_dust_t = 0.0
	# Whoever the slam itself hits is not hit again by the dust.
	var dust := _dust
	slam.on_strike = func(o: Node, _r: String):
		if dust and is_instance_valid(o):
			dust.hit_list[o.get_instance_id()] = 0.0
	vfx.mark(p, "crack", 1.5, 4.0)
	vfx.cobble("bodyslam_impactfloor", p, l.rival.center() if l.rival else null, l.data.height)
	vfx.cobble("bodyslam_actor_smoke", p, null, l.data.height)
	l.main.audio.play_sound("fall", p, 2.0, 0.7)
	l.main.audio.play_sound("bodyslam_hit", p, 0.0)
	l.main.shake_camera(0.5, p)


## The landing happens as the recovery starts: hits made on the last active frame are
## removed by the phase change before combat ever checks them.
func on_recovery() -> void:
	_landing()
	no_gravity = false
	no_brake = false
	tint_k = 0.0


## The cloud: rings of dust puffs, each wider and higher than the last, thrown outward and
## up (an upturned cone), and the hit's ring widening with it.
func in_recovery(delta: float) -> void:
	if _dust_t < 0.0:
		return
	var dur: float = d.dust_t
	var was := _dust_t
	_dust_t += delta
	var k := clampf(_dust_t / dur, 0.0, 1.0)
	var r: float = lerpf(2.8, float(d.dust_r), 1.0 - pow(1.0 - k, 2.0))
	if _dust:
		_dust.r_out = r
	var p := l.global_position
	p.y = l.main.ground_y
	var vfx: Vfx = l.main.vfx
	var step := 0.06
	if int(was / step) != int(_dust_t / step) and _dust_t < dur:
		var n := int(10 + r * 2.5)
		var y: float = 0.2 + k * 2.4
		for i in n:
			var a := TAU * (i + randf() * 0.5) / n
			var out := Vector3(cos(a), 0.0, sin(a))
			# Big puffs where the cone's wall is now (each stays and fades: together they draw
			# the cone), a spray of dust thrown out and up from them.
			if i % 3 == 0:
				vfx.sprite_anim(Vfx.TEX + "smoke/smoke.png", p + out * r + Vector3.UP * y, 0.7 + k * 0.6, Vector2i(1, 6),
					0.4 + 0.15 * k, CLOUD * 0.42)
			vfx.burst("dust", p + out * r + Vector3.UP * y, (out * 0.4 + Vector3.UP).normalized(), CLOUD, 1.3 + k)
	if _dust_t >= dur and _dust:
		l.main.combat.remove(_dust)
		_dust = null
		_dust_t = -1.0


func on_end(_i: bool) -> void:
	if _dust:
		l.main.combat.remove(_dust)
		_dust = null
	if is_instance_valid(_warning):
		_warning.queue_free()


func pose() -> Dictionary:
	match phase:
		"startup":
			var k: float = t / d.startup
			return {"stretch": 1.0 - 0.28 * k, "tilt": -0.1 * k}
		"active":
			return {"stretch": 1.15 if t < d.active * 0.5 else 0.9, "tilt": 0.3 + t / d.active * 0.9}
	var r: float = t / d.recovery
	return {"tilt": lerpf(1.2, 0.0, smoothstep(0.5, 1.0, r)), "stretch": 0.85 + 0.15 * r}
