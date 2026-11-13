extends Action
## Stone Edge: Garchomp strikes the ground; during the startup, cracks open in a line
## toward the rival (the line is then locked) and clusters of faceted rock spikes burst
## out one after another along it, splaying outward, ending in a bigger crown. Each
## cluster launches whoever stands on it; the rival only takes one hit even if it touches
## several. Avoid it by leaving the line or jumping a cluster. The spikes shatter into
## rubble as they sink.

var _dir := Vector3.FORWARD
var _origin_pos := Vector3.ZERO
var _exits := 0
var _on_hit := false
var _spikes: Array = []
var _stone_a: Material
var _stone_b: Material


func on_start() -> void:
	turn_mult = 2.5
	_stone_a = l.main.arena._material(Color("8d7a62"), 0.95, 0.0, "concrete")
	_stone_b = l.main.arena._material(Color("b3a487"), 0.9, 0.0, "concrete")
	play_sound("charge", -10.0)


func in_startup(_delta: float) -> void:
	tint_col = Roster.TYPE_COLOR.rock
	tint_k = 0.25 * (t / d.startup)
	# The line locks halfway through the startup; before that it follows the rival.
	if t < d.startup * 0.5 or _origin_pos == Vector3.ZERO:
		var a := aim(0.9)
		_dir = Vector3(a.x, 0, a.z).normalized()
		_origin_pos = l.global_position + _dir * (l.data.radius + 0.9)
		_origin_pos.y = l.main.ground_y
	if t >= d.startup * 0.5 and not has_meta("cracks"):
		set_meta("cracks", true)
		for i in d.spikes:
			l.main.vfx.mark(_origin_pos + _dir * (i * d.spacing), "crack", 0.8, d.startup + d.active + 0.8)


func on_active() -> void:
	l.main.shake_camera(0.15, l.global_position)
	play_sound("stoneedge", 0.0)


func in_active(_delta: float) -> void:
	var should := int(clampf(t / d.active, 0.0, 1.0) * d.spikes) + 1
	while _exits < mini(should, d.spikes):
		_spike(_origin_pos + _dir * (_exits * d.spacing))
		_exits += 1


func _spike(p: Vector3) -> void:
	var last := _exits == int(d.spikes) - 1
	var g := hit({"shape": "sphere", "local": false, "center": p + Vector3.UP * 0.7, "radius": d.radius * (1.25 if last else 1.0), "lifetime": 0.12})
	g.on_strike = func(_o, _r): _on_hit = true
	if _on_hit:
		g.active = false
	# A cluster: one tall shard in the middle and others splayed outward (a crown of five
	# at the end of the line).
	var side := _dir.cross(Vector3.UP)
	var shards: Array = [[Vector3.ZERO, 0.0, 2.2]]
	if last:
		for i in 5:
			var a := TAU * i / 5.0 + randf() * 0.3
			var out := Vector3(cos(a), 0, sin(a))
			shards.append([out * 0.9, 0.5, 1.8])
	else:
		for s in [-1.0, 1.0]:
			shards.append([side * s * 0.75, 0.45 * s, randf_range(1.3, 1.7)])
	for sh in shards:
		_shard(p + sh[0], sh[1], sh[2], sh[0])
	var vfx: Vfx = l.main.vfx
	vfx.burst("debris", p, Vector3.UP, Color(0, 0, 0, 0), 1.1 if last else 0.8)
	vfx.burst("dust", p, Vector3.UP, Color(0, 0, 0, 0), 0.8)
	l.main.audio.play_sound("stoneedge_hit", p, -6.0)


## A faceted rock shard (a four-sided spike, two-tone like broken stone) that shoots up,
## holds a moment and sinks, shattering into rubble.
func _shard(p: Vector3, lean: float, height: float, out: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = 0.38 * height / 2.0 + 0.12
	cm.height = height
	cm.radial_segments = 4
	cm.rings = 1
	mi.mesh = cm
	# Same pixel grain as the stages; two tones so the facets read as stone.
	mi.material_override = _stone_a if randf() < 0.6 else _stone_b
	var vfx: Vfx = l.main.vfx
	vfx.add_child(mi)
	var tilt_axis := out.cross(Vector3.UP).normalized() if out.length() > 0.01 else _dir.cross(Vector3.UP)
	var b := Basis(tilt_axis, -absf(lean) - randf() * 0.15) * Basis(Vector3.UP, randf() * TAU) if out.length() > 0.01 else Basis(Vector3.UP, randf() * TAU)
	var sunk := false
	vfx.live(mi, 1.0, func(k: float):
		var y: float = -height * 0.5 + height * clampf(k / 0.1, 0.0, 1.0) - height * clampf((k - 0.72) / 0.28, 0.0, 1.0)
		mi.global_transform = Transform3D(b, p + Vector3.UP * snappedf(y, 0.0625))
		if k > 0.72 and not sunk:
			sunk = true
			vfx.burst("debris", p + Vector3.UP * 0.3, Vector3.UP, Color(0, 0, 0, 0), 0.5))


func pose() -> Dictionary:
	match phase:
		"startup":
			return {"tilt": -0.2 * (t / d.startup), "stretch": 1.05, "anim": "physical_blunt" if t < 0.05 else ""}
		"active":
			return {"tilt": 0.35, "stretch": 0.92}
	return {"tilt": 0.1}
