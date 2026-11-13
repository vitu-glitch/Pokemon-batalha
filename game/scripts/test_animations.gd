extends Node
## Animation test (godot --path game -- --test=animations [--p1=species]):
## each Pokémon goes through all its states in the game, and the transitions between
## them, against a still rival, and every frame looks for four failures:
##   T-pose      many of the bones the idle moves away from rest go back to it
##   sunk        some body bone ends up well below the ground
##   stuck       still and free for more than 0.6 s without being in the idle animation
##   turned      walking forward, the face deviates more than 25° from its direction
## With a display, also a contact sheet per Pokémon in captures/anim_<species>.png.

var main: Node
var _t := 0.0
var _step := ""
var _fails: Array = []
var _moved: Array = []        # bones the idle moves away from rest
var _still := 0.0
var _photos: Array = []
var _warned := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://").path_join("../captures"))
	_run.call_deferred()


func _run() -> void:
	var species_list: Array = main.menu.pokemon_list()
	if main._args.has("p1") and main._args.p1 in species_list:
		species_list = [main._args.p1]
	var summary: Array = []
	for sp in species_list:
		_fails.clear()
		_warned.clear()
		_photos.clear()
		await _traverse(sp)
		summary.append([sp, _fails.duplicate()])
		_leaf(sp)
	print("")
	print("==== ANIMATION SUMMARY ====")
	var total := 0
	for r in summary:
		print("%-10s %s" % [r[0], "ok" if r[1].is_empty() else "%d failures" % r[1].size()])
		for f in r[1]:
			print("    ", f)
		total += r[1].size()
	print("TOTAL: %d failures" % total)
	get_tree().quit()


func _next_frame() -> void:
	await get_tree().physics_frame
	_t += get_physics_process_delta_time()
	_watch()


func _wait(s: float) -> void:
	var end_pos := _t + s
	while _t < end_pos:
		await _next_frame()


func _j() -> Fighter:
	return main.fighters[0]


func _photo(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.resize(480, 270, Image.INTERPOLATE_BILINEAR)
	_photos.append([img, label])


func _leaf(sp: String) -> void:
	if _photos.is_empty():
		return
	var cols := 5
	var rows := int(ceil(_photos.size() / float(cols)))
	var sheet := Image.create(480 * cols, 270 * rows, false, Image.FORMAT_RGBA8)
	for i in _photos.size():
		var im: Image = _photos[i][0]
		im.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(im, Rect2i(0, 0, 480, 270), Vector2i((i % cols) * 480, (i / cols) * 270))
	sheet.save_png(ProjectSettings.globalize_path("res://").path_join("../captures/anim_%s.png" % sp))
	print("contact sheet: captures/anim_%s.png (%s)" % [sp, ", ".join(_photos.map(func(f): return f[1]))])


## A rival hit applied directly (strength 0, 1 or 2).
func _strike(strength: int, knocks_down := false, damage := 30.0) -> void:
	var j := _j()
	var g := Hit.new()
	g.user = main.fighters[1]
	g.local = false
	g.shape = "sphere"
	g.center = j.center()
	g.radius = 0.4
	g.damage = damage
	g.strength = strength
	g.stun = 0.5
	g.knocks_down = knocks_down
	g.lift = 5.0 if knocks_down else 0.0
	main.combat.apply(g, j, j.center())


func _traverse(sp: String) -> void:
	_step = "idle"
	_moved.clear()
	_still = 0.0
	var rival: String = "snorlax" if sp != "snorlax" else "pikachu"
	main.start_battle(sp, rival, "normal")
	await _next_frame()
	if main.fighters.size() < 2 or main.ai == null:
		_fails.append("[setup] the battle does not start (a script failing to compile?)")
		print("  FAIL the battle does not start")
		return
	main.ai.mode = "still"
	var j := _j()
	j.is_player = false
	j.reset(Vector3(-5, 0, 0), PI * 0.5)
	main.fighters[1].reset(Vector3(4, 0, 0), -PI * 0.5)
	main.fighters[1].ctrl.move_input = Vector2.ZERO
	_moved.clear()
	# Which bones the idle moves away from rest (measured standing still for a moment).
	_step = "idle"
	var maximum := {}
	for i in 40:
		await _next_frame()
		for b in j.model.skel.get_bone_count():
			maximum[b] = maxf(maximum.get(b, 0.0), _deviation(j, b))
	for b in maximum:
		if maximum[b] > 8.0:
			_moved.append(b)
	print("%s: %d bones moved by the idle" % [sp, _moved.size()])
	await _photo("idle")
	j.ctrl.yaw = -PI * 0.5
	_step = "walk"
	await _hold_move(Vector2(0, 0.45), 1.0)
	await _photo("walk")
	_step = "run"
	await _hold_move(Vector2(0, -1.0), 1.0)
	await _photo("run")
	_step = "stop"
	await _wait(1.0)
	_step = "jump"
	j.ctrl.press("jump")
	await _wait(0.3)
	await _photo("jump")
	await _wait(1.0)
	# Attack mid-jump (everything can be used in the air).
	_step = "air attack"
	j.energy = Fighter.ENERGY_MAX
	j.cds.clear()
	j.ctrl.press("jump")
	await _wait(0.2)
	j.ctrl.press("mov1")
	await _wait(1.8)
	j.reset(Vector3(-5, 0, 0), PI * 0.5)
	await _wait(0.3)
	# Ground move used in the air: it dives down.
	for i in 4:
		if Moves.DATA[j.data.moves[i]].get("needs_ground", false):
			_step = "dive"
			j.energy = Fighter.ENERGY_MAX
			j.cds.clear()
			j.ctrl.press("jump")
			await _wait(0.25)
			j.ctrl.press("mov%d" % (i + 1))
			await _wait(0.12)
			await _photo("dive")
			await _wait(2.5)
			j.reset(Vector3(-5, 0, 0), PI * 0.5)
			await _wait(0.3)
			break
	# Flyers: take off, hover, attack while flying, move and land.
	if j.data.has("flight"):
		_step = "flight"
		j.ctrl.press("jump")
		await _wait(0.25)
		j.ctrl.press("jump")
		var end_rise := _t + 0.8
		while _t < end_rise:
			j.ctrl.held["jump"] = true
			await _next_frame()
		await _wait(0.6)
		await _photo("flying")
		j.energy = Fighter.ENERGY_MAX
		j.cds.clear()
		j.ctrl.press("mov2")
		await _wait(1.0)
		await _hold_move(Vector2(0.6, 0.6), 0.8)
		await _photo("flying and moving")
		var end_low := _t + 2.0
		while _t < end_low and not j.is_on_floor():
			j.ctrl.held["descend"] = true
			await _next_frame()
		await _wait(0.8)
	_step = "dodge"
	j.ctrl.move_input = Vector2(1, 0)
	j.ctrl.press("dodge")
	await _wait(0.12)
	await _photo("dodge")
	j.ctrl.move_input = Vector2.ZERO
	await _wait(1.2)
	for i in 4:
		var move: String = j.data.moves[i]
		var d: Dictionary = Moves.DATA[move]
		_step = move
		j.energy = Fighter.ENERGY_MAX
		j.cds.clear()
		j.uses.clear()
		var b := "mov%d" % (i + 1)
		j.ctrl.press(b)
		var hold: bool = d.get("hold", false) or d.get("chargeable", false)
		var dur: float = 1.0 if hold else float(d.get("startup", 0.1)) + float(d.get("active", 0.1)) * 0.5
		var end_pos := _t + dur
		while _t < end_pos:
			if hold:
				j.ctrl.held[b] = true
			await _next_frame()
		await _photo(d.display_name)
		j.ctrl.release(b)
		await _wait(2.4)
		j.reset(Vector3(-5, 0, 0), PI * 0.5)
		await _wait(0.3)
	_step = "medium hit"
	_strike(1)
	await _wait(0.15)
	await _photo("hit taken")
	await _wait(1.4)
	_step = "knockdown"
	_strike(2, true)
	await _wait(0.7)
	await _photo("knocked_down")
	await _wait(1.6)
	_step = "hit in the air"
	j.ctrl.press("jump")
	await _wait(0.25)
	_strike(1)
	await _wait(1.6)
	_step = "hit during a move"
	j.energy = Fighter.ENERGY_MAX
	j.cds.clear()
	j.ctrl.press("mov1")
	await _wait(0.08)
	_strike(2)
	await _wait(1.6)
	_step = "faint"
	j.hp = 1.0
	_strike(2)
	await _wait(1.2)
	await _photo("fainted")
	await _wait(1.0)
	_step = "rematch"
	main.rematch()
	await _wait(1.2)
	await _photo("rematch")


func _hold_move(v: Vector2, s: float) -> void:
	var end_pos := _t + s
	while _t < end_pos:
		_j().ctrl.move_input = v
		await _next_frame()
	_j().ctrl.move_input = Vector2.ZERO


func _deviation(j: Fighter, b: int) -> float:
	var sk := j.model.skel
	return rad_to_deg(sk.get_bone_pose_rotation(b).angle_to(sk.get_bone_rest(b).basis.get_rotation_quaternion()))


func _is_weapon(sk: Skeleton3D, b: int) -> bool:
	while b >= 0:
		var n := sk.get_bone_name(b)
		if "weapon" in n or "kunai" in n or "blade" in n:
			return true
		b = sk.get_bone_parent(b)
	return false


func _fail(type: String, detail: String) -> void:
	var key := _step + "|" + type
	if _warned.has(key):
		return
	_warned[key] = true
	var j := _j()
	var line := "[%s] %s: %s (state %s, anim %s)" % [_step, type, detail, j.state, j.model.anim]
	_fails.append(line)
	print("  FAIL ", line)


func _watch() -> void:
	if main.fighters.is_empty():
		return
	var j := _j()
	if _moved.is_empty() or _step == "idle":
		return
	var sk := j.model.skel
	# T-pose: most of the bones the idle moves, at rest at the same time.
	var at_rest := 0
	for b in _moved:
		if _deviation(j, b) < 1.0:
			at_rest += 1
	if at_rest > _moved.size() * 0.4:
		_fail("T-pose", "%d of %d bones at rest" % [at_rest, _moved.size()])
	# Sunk: some body bone below the ground (unless it is hidden on purpose:
	# underground in Dig or during Gengar's teleport).
	var hidden: bool = not j.model.visible or (j.action != null and j.action.id == "dig")
	var minimum := INF if not hidden else 0.0
	var which := ""
	for b in sk.get_bone_count():
		var n := sk.get_bone_name(b)
		# Weapons (Greninja's kunai and everything hanging from them) sweep the ground
		# on purpose: they are not the body.
		if n.begins_with("locator") or n == j.species or _is_weapon(sk, b):
			continue
		var y := j.model.bone_world(n).y
		if y < minimum:
			minimum = y
			which = n
	if not hidden and minimum < main.ground_y - j.data.height * 0.25:
		_fail("sunk", "\"%s\" %.2f m below the ground (tilt %.2f, turn %.2f)" % [which, main.ground_y - minimum, j._pose.tilt, j._pose.turn])
	# Stuck: free, still and on the ground, but without the idle animation.
	var h := Vector2(j.velocity.x, j.velocity.z).length()
	if j.state == "free" and h < 0.3 and j.is_on_floor():
		_still += get_physics_process_delta_time()
	else:
		_still = 0.0
	# Reactions add on top of the idle: both the base layer and the one above are checked.
	var waits := ["battle_idle", "ground_idle", "air_idle"]
	var base: String = j.model.anim_player.current_animation
	if _still > 0.6 and (not base in waits or j.model.layer.is_playing()):
		_fail("stuck", "still with base \"%s\"%s" % [base, " and above it \"%s\"" % j.model.layer.current_animation if j.model.layer.is_playing() else ""])
	# Facing: walking or running forward, the face looks where it is going.
	if _step in ["walk", "run"] and j.state == "free" and Vector2(j.velocity.x, j.velocity.z).length() > 2.0:
		var sk2 := j.model.skel
		var face := ""
		for n in ["locator_face", "locator_head", "head"]:
			if sk2.find_bone(n) >= 0:
				face = n
				break
		if face != "":
			var toward := j.model.bone_world(face) - j.global_position
			toward.y = 0.0
			var move := Vector3(j.velocity.x, 0, j.velocity.z)
			if toward.length() > j.data.radius * 0.4 and move.dot(j.forward()) > 0.0:
				var deviation := rad_to_deg(toward.angle_to(j.forward()))
				if deviation > 25.0:
					_fail("turned", "the face deviates %.0f° from where it is facing" % deviation)
	if not j.pivot.global_transform.is_finite():
		_fail("NaN", "invalid transform")
