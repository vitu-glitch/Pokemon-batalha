extends Action
## Surf: like in the DS games and the anime, a great wave. The user raises the water round
## it; in front a wave rises tall ("tall" m), crashes down over the first metres with a
## burst of spray and rolls on low ("low" m) along the ground at "speed" m/s until "reach"
## metres, foaming at its foot and leaving the ground wet. Its hit follows its height: up
## close it is too tall to jump and catches low fliers; further away it can be jumped. It
## hits once. To read as water from any side it is a real curved wave (a mesh: a slope
## rising from the back to a crest that curls forward, its ends bent back and lower) with
## pixel water running up it (VfxShaders.WAVE), and spray, foam and suds all along. It is not a projectile:
## it cannot be sent back or broken.

## The wave's cross-section, from its foot at the back to the tip of the lip, for a wave
## 1 m tall: (height, distance forward; +z is behind).
const PROFILE := [Vector2(0.0, 1.3), Vector2(0.38, 0.95), Vector2(0.72, 0.5), Vector2(0.94, 0.08),
	Vector2(1.0, -0.25), Vector2(0.9, -0.52), Vector2(0.7, -0.66)]
const RISE := 0.22            # s rising in place
const CRASH := 0.35           # s crashing down while it surges ahead

var _splash := 0.0


func on_start() -> void:
	turn_mult = 2.0
	play_sound("charge", -12.0)


func in_startup(delta: float) -> void:
	tint_col = Roster.TYPE_COLOR.water
	tint_k = 0.3 * clampf(t / maxf(startup_len(), 0.01), 0.0, 1.0)
	# The water rises round its feet.
	_splash -= delta
	if _splash <= 0.0:
		_splash = 0.06
		var a := randf() * TAU
		var at: Vector3 = l.global_position + Vector3(cos(a), 0.1, sin(a)) * l.data.radius * 1.6
		l.main.vfx.burst("water_fx", at, Vector3.UP, Color(0, 0, 0, 0), 0.6)


func on_active() -> void:
	tint_k = 0.0
	var vfx: Vfx = l.main.vfx
	var aim_dir := aim(0.8)
	var dir := Vector3(aim_dir.x, 0.0, aim_dir.z).normalized()
	var side := dir.cross(Vector3.UP).normalized()
	var ground: float = l.main.ground_y
	var start: Vector3 = l.global_position + dir * (l.data.radius + 0.8)
	start.y = ground
	var width: float = d.width
	var tall: float = d.tall
	var low: float = d.low
	var speed: float = d.speed
	# Time to roll the whole way: rising in place, the crash (surging at 1.4x) and the rest.
	var crash_run: float = speed * 1.4 * CRASH
	var life: float = RISE + CRASH + maxf(0.0, d.reach - crash_run) / speed
	# The wave: the mesh on a root turned along its way (scaled to its height as it goes).
	var wave := Node3D.new()
	vfx.add_child(wave)
	wave.global_basis = Basis.looking_at(dir, Vector3.UP)
	wave.global_position = start
	var body := MeshInstance3D.new()
	body.mesh = _wave_mesh(width)
	var water: ShaderMaterial = vfx.mat("wave", VfxShaders.WAVE, {"cells_u": roundf(width * 13.0), "cells_v": 30.0})
	body.material_override = water
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wave.add_child(body)
	# Its hit: a capsule across the wave, as high as the wave is.
	var g := Hit.new()
	g.user = l
	g.move_id = id
	g.local = false
	g.shape = "capsule"
	g.type = "water"
	g.cat = "special"
	g.damage = d.damage
	g.lift = d.lift
	g.stun = d.stun
	g.strength = d.strength
	g.hitstop = 0.08
	g.contact = false
	g.lifetime = life
	l.main.combat.add_hit(g)
	var fx: Fx = l.main.fx
	var state := {"t": 0.0, "run": 0.0, "spray": 0.0, "foam": 0.0, "wet": 0.0, "crashed": false}
	vfx.live(wave, life + 0.2, func(_k: float):
		var dt := vfx.get_process_delta_time()
		state.t += dt
		var tt: float = state.t
		var h: float
		if tt < RISE:
			h = lerpf(0.35, 1.0, tt / RISE) * tall
			state.run += speed * 0.15 * dt
		elif tt < RISE + CRASH:
			var c: float = (tt - RISE) / CRASH
			h = lerpf(tall, low, c * c)
			state.run += speed * 1.4 * dt
		else:
			h = low * (1.0 + 0.08 * sin(tt * 9.0))
			state.run += speed * dt
		# It sinks away at the end.
		var sink := clampf((tt - life + 0.2) / 0.2, 0.0, 1.0)
		h *= 1.0 - sink
		var at: Vector3 = start + dir * state.run
		wave.global_position = at
		wave.scale = Vector3(1.0, maxf(h, 0.01), clampf(h * 0.55, 0.6, 1.8))
		water.set_shader_parameter("t", tt)
		var r: float = clampf(h * 0.5, 0.5, 1.9)
		g.radius = r
		g.a = at - side * width * 0.42 + Vector3.UP * r
		g.b = at + side * width * 0.42 + Vector3.UP * r
		if h < 0.05:
			g.active = false
		# The crash: spray bursting all along it.
		if tt >= RISE + CRASH and not state.crashed:
			state.crashed = true
			for k in 5:
				var p: Vector3 = at + side * (k - 2) * width * 0.2
				fx.play("waterpulse_targetsplash", p + Vector3.UP * 0.5, null, {"height": 2.0, "width": 1.6})
				vfx.burst("water_fx", p + Vector3.UP * 0.8, Vector3.UP + dir * 0.5, Color(0, 0, 0, 0), 1.6)
			l.main.shake_camera(0.15, at)
			l.main.audio.play_sound("surf_hit", at, -4.0)
		# Spray off the crest, many and small.
		state.spray -= dt
		while state.spray <= 0.0 and h > 0.05:
			state.spray += 0.025
			var crest: Vector3 = at + side * randf_range(-0.5, 0.5) * width + Vector3.UP * h * randf_range(0.75, 1.0)
			vfx.burst("water_fx", crest, dir * 0.6 + Vector3.UP, Color(0, 0, 0, 0), randf_range(0.5, 0.9))
		# Foam and suds churning at its foot.
		state.foam -= dt
		if state.foam <= 0.0 and h > 0.05:
			state.foam = 0.07
			var foot: Vector3 = at + side * randf_range(-0.5, 0.5) * width + dir * 0.4 + Vector3.UP * 0.15
			vfx.burst("steam", foot, Vector3.UP, Color(0, 0, 0, 0), 0.8)
			fx.play("waterpulse_actorsuds" if randf() < 0.5 else "watergun_targetfoam", foot, null, {"height": 1.4, "width": 1.2})
		state.wet -= dt
		if state.wet <= 0.0 and h > 0.05:
			state.wet = 0.16
			vfx.mark(at - dir * 0.8, "wet", width * 0.36, 3.5))
	vfx.cobble("waterpulse_actorsplash", l.center(), l.center() + dir, l.data.height)
	play_sound(id, 0.0)


static var _meshes := {}


## The wave's mesh, "width" across: the cross-section swept from side to side, its ends
## bent back (a curved front) and lower (it fades into the water at the sides).
static func _wave_mesh(width: float) -> ArrayMesh:
	if _meshes.has(width):
		return _meshes[width]
	var across := 24
	var down := 18
	# The cross-section, smoothed (Catmull-Rom through PROFILE).
	var pts: Array = []
	for i in down + 1:
		var u := float(i) / down * (PROFILE.size() - 1)
		var k := mini(int(u), PROFILE.size() - 2)
		var f := u - k
		var p0: Vector2 = PROFILE[maxi(k - 1, 0)]
		var p1: Vector2 = PROFILE[k]
		var p2: Vector2 = PROFILE[k + 1]
		var p3: Vector2 = PROFILE[mini(k + 2, PROFILE.size() - 1)]
		pts.append(0.5 * ((2.0 * p1) + (-p0 + p2) * f + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * f * f + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * f * f * f))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var vert := func(i: int, j: int) -> Vector3:
		var a := float(i) / across * 2.0 - 1.0          # -1 to 1 across
		var low := 1.0 - 0.45 * pow(absf(a), 5.0)
		var p: Vector2 = pts[j]
		return Vector3(a * width * 0.5, p.x * low, p.y * low + 0.9 * a * a)
	for i in across:
		for j in down:
			var quad := [[i, j], [i + 1, j], [i + 1, j + 1], [i, j], [i + 1, j + 1], [i, j + 1]]
			for q in quad:
				st.set_uv(Vector2(float(q[0]) / across, float(q[1]) / down))
				st.add_vertex(vert.call(q[0], q[1]))
	var mesh := st.commit()
	_meshes[width] = mesh
	return mesh


func pose() -> Dictionary:
	match phase:
		"startup":
			var k: float = clampf(t / maxf(startup_len(), 0.01), 0.0, 1.0)
			return {"stretch": 1.0 + 0.15 * k, "height": 0.4 * k, "tilt": -0.15 * k, "anim": "special", "reset": t < 0.02}
		"active":
			return {"stretch": 1.08, "height": 0.4, "tilt": 0.25}
	return {"height": 0.4 * (1.0 - t / maxf(float(d.recovery), 0.01))}
