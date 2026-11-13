extends Node
## Automated tests (godot --path game -- --test=name):
##   aivsai      headless: AI vs AI for up to 3 battles; prints how it goes and checks
##               that nothing stays active after each KO and rematch
##   moves       each of the player's moves against a still rival, with captures
##   combat      AI vs AI on screen, with captures every few seconds
##   animations  each Pokémon goes through its states and transitions looking for
##               T-poses, sinking and stuck animations (see test_animations.gd)
##   mechanics   headless: concrete cases from the acceptance criteria (dodging a
##               projectile, jumping the wave, punishing a recovery, combo limit,
##               hitstop)
## Captures go to captures/ and a dated copy to captures/history/.

var main: Node
var test_name := ""
var t := 0.0
var _shots: Array = []
var _taken := 0
var _battles := 0
var _hits := 0
var _last_report := 0.0
var _plan: Array = []
var _steps: Array = []          # menu steps due, played one at a time (_process)
var _step_wait := 0
var _step := 0
var _step_t := 0.0
var _fps_sum := 0
var _fps_n := 0
var _fps_min := 9999
var _flying := {}
var _stream := {}             # aivsai: manual-aim streams, move -> [active seconds, hits]
var _strip: Array = []           # moves --sequence: frames of the current move


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(_dir())
	for l in main.fighters:
		l.hit_taken.connect(func(_q, info):
			_hits += 1
			var mid: String = info.hit.move_id
			if Moves.DATA.has(mid) and Moves.DATA[mid].get("manual_aim", false):
				_stream.get_or_add(mid, [0.0, 0])[1] += 1)
	match test_name:
		"aivsai":
			Engine.max_fps = 0
		"moves":
			main.ai.mode = "still"
			main.player.is_player = false
			main.player.locked = true
			var b: Fighter = main.fighters[1]
			# --gap=N: how far apart they start (6.5 m by default; less for melee moves).
			var gap := float(main._args.get("gap", "6.5"))
			b.reset(Vector3(-3.5, 0, 0), PI * 0.5)
			main.player.reset(Vector3(-3.5 + gap, 0, 0), -PI * 0.5)
			# --side: the camera looks from the side, to see the shape of streams and beams.
			if main._args.has("side"):
				main.camera.set_physics_process(false)
				main.camera.global_position = Vector3(0.0, 3.0, 9.5)
				main.camera.look_at(Vector3(0.0, 1.0, 0.0))
			for i in 4:
				_plan.append("mov%d" % (i + 1))
			_plan.append_array(["dodge", "jump"])
		"portraits":
			main.ai.mode = "still"
		"net":
			var pr: Node = preload("res://scripts/test_net.gd").new()
			pr.main = main
			add_child(pr)
		"menu_net":
			var pm: Node = preload("res://scripts/test_menu_net.gd").new()
			pm.main = main
			add_child(pm)
		"animations":
			var pa: Node = preload("res://scripts/test_animations.gd").new()
			pa.main = main
			add_child(pa)
		"menu":
			# [time, action, capture]: title, main menu, Battle, change Pokémon, rival,
			# then the options (stage to the floating one, difficulty up) and Fight: VS,
			# battle, pause and back to the menu.
			_plan = [[1.5, "", "menu_title"], [1.7, "menu_accept", ""], [2.3, "move_down", ""], [2.6, "", "menu_main"],
				[2.8, "move_up", ""], [3.0, "menu_accept", ""], [3.8, "move_right", ""], [4.1, "move_down", ""],
				[4.8, "", "menu_selection"], [5.0, "menu_accept", ""], [5.4, "move_down", ""], [5.9, "", "menu_rival"],
				[6.1, "menu_accept", ""], [6.4, "move_left", ""], [6.5, "move_left", ""], [6.6, "move_left", ""], [6.7, "move_up", ""],
				[6.8, "move_right", ""], [6.9, "move_up", ""], [7.0, "move_right", ""], [7.1, "move_right", ""],
				[7.3, "", "menu_setup"], [7.5, "menu_accept", ""],
				[7.8, "", "menu_vs"], [10.7, "", "menu_battle"], [10.9, "pause", ""], [11.3, "", "menu_pause"],
				[11.5, "menu_back", ""], [12.2, "", "menu_back"]]
		"menu_moves":
			# Moves screen: Charizard's first move to Body Slam, then Air Slash into that slot
			# (it was in the second: they swap). Its own save file, which starts empty.
			Loadout.path = "user://loadouts_test.json"
			DirAccess.remove_absolute(ProjectSettings.globalize_path(Loadout.path))
			_plan = [[1.5, "", ""], [1.7, "menu_accept", ""], [2.0, "move_right", ""], [2.2, "move_down", ""], [2.4, "", ""],
				[2.6, "", "moves_main"], [2.8, "menu_accept", ""], [3.6, "move_down", ""], [3.8, "move_down", ""], [4.0, "", "moves_grid"],
				[4.2, "menu_accept", ""], [4.5, "", "moves_slots"], [4.7, "menu_accept", ""],
				[5.0, "move_down", ""], [5.2, "move_down", ""], [5.4, "move_down", ""], [5.6, "move_down", ""], [5.9, "", "moves_list"],
				[6.1, "menu_accept", ""], [6.4, "", "moves_after"], [6.6, "menu_accept", ""],
				[6.9, "move_up", ""], [7.1, "move_up", ""], [7.3, "move_up", ""], [7.6, "", "moves_swap_list"], [7.8, "menu_accept", ""],
				[8.1, "", "moves_swapped"], [8.3, "menu_info", ""], [8.6, "", "moves_details"], [8.8, "menu_info", ""],
				# Down to the ability (fifth slot), the second one; then restore: No first, then Yes.
				[9.0, "move_down", ""], [9.2, "move_down", ""], [9.4, "move_down", ""], [9.6, "move_down", ""],
				[9.8, "", "moves_ability_slot"], [10.0, "menu_accept", ""], [10.3, "move_down", ""], [10.5, "", "moves_ability_list"],
				[10.7, "menu_accept", ""], [11.0, "", "moves_ability"], [11.3, "menu_extra", ""], [11.6, "", "moves_restore_ask"],
				[11.8, "menu_accept", ""], [12.2, "menu_extra", ""], [12.4, "move_right", ""], [12.6, "menu_accept", ""],
				[13.0, "", "moves_restored"]]
		"menu_profile":
			# Profile: up from Online to the badge, in; point at another trainer (it must not
			# change yet), confirm it; up to the name, the on-screen keyboard with the pad:
			# Q, then right and W, then B deletes one; Done; back.
			_plan = [[1.5, "", ""], [1.7, "menu_accept", ""], [2.0, "move_right", ""], [2.2, "move_up", ""],
				[2.6, "", "profile_badge"], [2.8, "menu_accept", ""], [3.4, "", "profile_screen"], [3.6, "move_right", ""],
				[3.8, "move_down", ""], [4.1, "", "profile_point"], [4.3, "menu_accept", ""], [4.6, "", "profile_pick"],
				[4.8, "move_up", ""], [5.0, "move_up", ""], [5.2, "menu_accept", ""], [5.5, "menu_accept", ""],
				[5.7, "move_right", ""], [5.9, "menu_accept", ""], [6.2, "", "profile_keyboard"], [6.4, "menu_back", ""],
				[6.8, "", ""], [7.0, "menu_back", ""], [7.2, "menu_back", ""], [7.6, "", "profile_back"]]
		"menu_wheel":
			# The mouse wheel: into the options, then two notches down move two rows.
			_plan = [[1.5, "", ""], [1.7, "menu_accept", ""], [2.0, "move_right", ""], [2.2, "move_right", ""], [2.4, "move_down", ""],
				[2.9, "menu_accept", ""]]
		"menu_options":
			# Options: from the main menu, then down a few rows.
			_plan = [[1.5, "", ""], [1.7, "menu_accept", ""], [2.0, "move_right", ""], [2.2, "move_right", ""], [2.4, "move_down", ""],
				[2.6, "", ""], [2.9, "menu_accept", ""], [3.6, "", "options_top"], [3.8, "move_down", ""],
				[4.0, "move_down", ""], [4.2, "move_down", ""], [4.4, "move_down", ""], [4.6, "move_down", ""],
				[4.8, "move_down", ""], [5.0, "move_down", ""], [5.2, "move_down", ""], [5.4, "move_down", ""], [5.6, "move_down", ""],
				[6.0, "", "options_sound"]]
		"combat":
			_shots = [2.0, 4.0, 6.0, 8.0, 10.0, 12.5, 15.0, 18.0, 22.0]
		"mechanics":
			_mechanics()
		"loadouts":
			_loadouts()
		"abilities":
			_abilities()
		"status":
			_statuses()
		"status_moves":
			_status_moves()
		"stage_shots":
			_stage_shots()
		"stage_previews":
			_stage_previews()
		"result_shot":
			_result_shot()
		"deflect":
			_deflect_test()
		"clash":
			_clash_test()
		"new_moves":
			_new_moves()
		"trainers":
			_trainers_test()
		"league":
			_league_test()
		"lockon":
			_lockon_test()
		"music":
			# The tracks the game finds (in the exported build, inside its package).
			await get_tree().process_frame
			var groups := {}
			for k in main.music._tracks:
				groups[k] = main.music._tracks[k].size()
			main.music.play("night", true)
			var p: AudioStreamPlayer = main.music._players[main.music._now]
			print("MUSIC ", groups, " playing ", p.stream.resource_path if p.stream else "none")
			get_tree().quit()


## One queued menu step (see the menus' plan). From _physics_process, which runs before the
## menus' _process in a frame: a press made after them would be "just pressed" too late.
func _next_step() -> void:
	if _step_wait > 0:
		_step_wait -= 1
		return
	if _steps.is_empty():
		return
	var st: Array = _steps.pop_front()
	if st[0] == "key":
		var ev := InputEventAction.new()
		ev.action = st[1]
		ev.pressed = true
		Input.parse_input_event(ev)
		Input.action_press(st[1])
		_release_later(st[1])
		_step_wait = 4
	else:
		print("state: menu ", main.menu.is_open, " pause ", main.paused, " fighters ", main.fighters.size(), " choice ", main.menu.choice)
		_capture(st[1])


func _release_later(action: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	Input.action_release(action)


func _dir() -> String:
	return ProjectSettings.globalize_path("res://").path_join("../captures")


func _capture(n: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var img := get_viewport().get_texture().get_image()
	img.save_png(_dir().path_join(n + ".png"))
	CaptureLog.save(img, n)
	print("capture ", n)


func _physics_process(delta: float) -> void:
	t += delta
	match test_name:
		"menu", "menu_moves", "menu_options", "menu_profile", "menu_wheel":
			# Due steps go into a queue that _process plays one per few frames: after a slow
			# frame several come due at once, and two presses in one frame lose one.
			for p in _plan:
				if t >= p[0] and t - delta < p[0]:
					if p[1] != "":
						_steps.append(["key", p[1]])
					if p[2] != "":
						_steps.append(["capture", p[2]])
			_next_step()
			if test_name == "menu" and t > 12.5:
				get_tree().quit()
			if test_name == "menu_options" and t > 6.8:
				get_tree().quit()
			if test_name == "menu_wheel":
				if t >= 3.6 and t - delta < 3.6:
					_profile_trainer = str(main.options.cursor)
				for at in [3.8, 4.2]:
					if t >= at and t - delta < at:
						var w := InputEventMouseButton.new()
						w.button_index = MOUSE_BUTTON_WHEEL_DOWN
						w.pressed = true
						w.position = Vector2(800, 450)
						Input.parse_input_event(w)
				if t > 4.8:
					var moved: int = main.options.cursor - int(_profile_trainer)
					print("%s  Two wheel notches move two rows  %d" % ["OK   " if moved == 2 else "FAIL ", moved])
					get_tree().quit()
			if test_name == "menu_profile":
				# The pad drives the on-screen keyboard (the actions here come from no device).
				Controls.last_device = "xbox"
				if t >= 4.1 and t - delta < 4.1:
					_profile_trainer = main.options.trainer
				if t >= 4.6 and t - delta < 4.6:
					print("%s  Pointing does not change the trainer  %s" % ["OK   " if _profile_trainer == TrainerData.DEFAULT else "FAIL ", _profile_trainer])
					print("%s  Confirming does  %s" % ["OK   " if main.options.trainer != TrainerData.DEFAULT else "FAIL ", main.options.trainer])
				if t >= 6.8 and t - delta < 6.8:
					var n: String = main.options.player_name
					print("%s  On-screen keyboard: Q, W, delete  '%s'" % ["OK   " if n == "Q" else "FAIL ", n])
				if t > 7.9:
					get_tree().quit()
			if test_name == "menu_moves" and t >= 8.95 and t - delta < 8.95:
				# The fifth option went into the first slot, then Air Slash (second) took
				# its place: they swapped.
				var fifth: String = Loadout.moves_for("charizard")[4]
				var after: Array = Loadout.saved("charizard").moves
				var ok := after == ["airslash", fifth, "dragonclaw", "flareblitz"]
				var stored := FileAccess.get_file_as_string(Loadout.path)
				print("%s  Moves screen: change and swap saved  %s" % ["OK   " if ok else "FAIL ", after])
				print("%s  Saved to file  %s" % ["OK   " if stored.contains(fifth) else "FAIL ", Loadout.path])
			if test_name == "menu_moves" and t >= 11.2 and t - delta < 11.2:
				var ab: String = Loadout.saved("charizard").ability
				var second: String = Loadout.abilities_for("charizard")[1].id
				print("%s  Ability changed from its slot  %s" % ["OK   " if ab == second else "FAIL ", ab])
			if test_name == "menu_moves" and t >= 12.1 and t - delta < 12.1:
				print("%s  Restore, answered No, keeps it  %s" % ["OK   " if not Loadout.is_default("charizard") else "FAIL ", Loadout.saved("charizard")])
			if test_name == "menu_moves" and t > 13.2:
				print("%s  Restore, answered Yes, back to defaults  %s" % ["OK   " if Loadout.is_default("charizard") else "FAIL ", Loadout.saved("charizard")])
				get_tree().quit()
		"portraits":
			if t > 0.6:
				var strip := Image.create(28 * 3 * 2 * 4, 28 * 3 * 4, false, Image.FORMAT_RGBA8)
				for i in main.hud._portraits.size():
					var im: Image = main.hud._portraits[i].vp.get_texture().get_image()
					im.convert(Image.FORMAT_RGBA8)
					im.resize(im.get_width() * 4, im.get_height() * 4, Image.INTERPOLATE_NEAREST)
					strip.blit_rect(im, Rect2i(Vector2i.ZERO, im.get_size()), Vector2i(i * im.get_width(), 0))
				strip.save_png(_dir().path_join("portraits.png"))
				_capture("hud_portraits")
				get_tree().quit()
		"aivsai":
			_ai_vs_ai()
		"moves":
			_movs_test(delta)
		"combat":
			_fps_sum += Engine.get_frames_per_second()
			_fps_n += 1
			_fps_min = mini(_fps_min, Engine.get_frames_per_second()) if t > 2.0 else _fps_min
			if _taken < _shots.size() and t >= _shots[_taken]:
				_capture("combat_%d" % (_taken + 1))
				_taken += 1
			if _taken >= _shots.size() or t > 40.0:
				print("mean FPS %.0f · min %d · %s" % [float(_fps_sum) / _fps_n, _fps_min, RenderingServer.get_video_adapter_name()])
				get_tree().quit()


func _ai_vs_ai() -> void:
	var a: Fighter = main.fighters[0]
	var b: Fighter = main.fighters[1]
	for l in [a, b]:
		if l.flying:
			_flying[l.species] = _flying.get(l.species, 0.0) + get_physics_process_delta_time()
		if l.action and l.action.d.get("manual_aim", false) and l.action.phase == "active":
			_stream.get_or_add(l.action.id, [0.0, 0])[0] += get_physics_process_delta_time()
		# Stages with a void: what each one was doing when it went off the edge.
		if main.arena.void_y != -INF and l.global_position.y < -0.5 and not _off_edge.has(l):
			_off_edge[l] = true
			var who: AI = main.ai if l == b else main.player_ai
			print("  off the edge: %s %s %s · AI \"%s\" · pos %s vel %s input %s" % [l.species, l.state, l.action.id if l.action else "",
				who.state_text if who else "", l.global_position.snapped(Vector3.ONE * 0.1), l.velocity.snapped(Vector3.ONE * 0.1), l.ctrl.move_input])
		elif l.global_position.y > -0.1 and l.is_on_floor():
			_off_edge.erase(l)
	if t - _last_report >= 10.0:
		_last_report = t
		print("t=%3ds  %s %4d (%s)  %s %4d (%s)  hits %d  fps %d" % [int(t), a.species, a.hp, a.state, b.species, b.hp, b.state,
			_hits, Engine.get_frames_per_second()])
	if main._end_t > 1.0:
		_battles += 1
		var winner: Fighter = a if a.state != "ko" else b
		var flights := ""
		for k in _flying:
			flights += " · %s flying %.0f s" % [k, _flying[k]]
		for k in _stream:
			flights += " · %s %d hits in %.1f s firing" % [k, _stream[k][1], _stream[k][0]]
		print("BATTLE %d: %s wins in %.0f s · %d hits%s" % [_battles, winner.species, t, _hits, flights])
		main.rematch()
		await get_tree().physics_frame
		print("  after the rematch: active hits %d · projectiles %d · %s %s · %s %s" % [main.combat.hits.size(),
			main.combat.projectiles.size(), a.species, a.state, b.species, b.state])
		_hits = 0
		if _battles >= 3:
			get_tree().quit()
	if t > 300.0:
		print("timed out without a KO")
		get_tree().quit()


## Each action in the plan, with a capture in the middle of the active phase.
func _movs_test(delta: float) -> void:
	var j: Fighter = main.player
	_step_t += delta
	if _step >= _plan.size():
		if _step_t > 1.5:
			get_tree().quit()
		return
	var action: String = _plan[_step]
	if _step_t > 0.4 and _step_t - delta <= 0.4:
		if action.begins_with("move"):
			j.ctrl.press(action)
			# Held or charged moves, for a good while.
			j.ctrl.held[action] = true
		else:
			j.ctrl.press(action)
			if action == "dodge":
				j.ctrl.move_input = Vector2(1, 0)
	if _step_t > 1.6:
		j.ctrl.release(action)
		j.ctrl.move_input = Vector2.ZERO
	var move_name: String = j.data.moves[int(action.substr(3)) - 1] if action.begins_with("move") else action
	var moment := 0.4 + float(Moves.DATA.get(move_name, {}).get("startup", 0.1)) + 0.06
	if Moves.DATA.get(move_name, {}).get("chargeable", false) or Moves.DATA.get(move_name, {}).get("hold", false):
		moment = 1.2
	if action == "dodge" or action == "jump":
		moment = 0.55
	# --shot=S: the full-size capture S seconds after the press instead.
	if main._args.has("shot"):
		moment = 0.4 + float(main._args.shot)
	if _step_t > moment and _step_t - delta <= moment:
		_capture("moves_%s_%d" % [j.species, _step + 1])
	# With --sequence, also a strip of 16 frames (every 0.1 s from the press) to see how
	# the effect moves, not just one instant. --every=S and --from=S (after the press)
	# narrow it down to a quick moment, like a bolt's discharge.
	if main._args.has("sequence") and DisplayServer.get_name() != "headless":
		var every := float(main._args.get("every", "0.1"))
		var k := int(floorf((_step_t - 0.4 - float(main._args.get("from", "0"))) / every))
		if k >= 0 and k < 16 and _strip.size() == k:
			# Crop of the center (where the action happens) instead of the whole screen.
			var full := get_viewport().get_texture().get_image()
			var fw := full.get_width()
			var fh := full.get_height()
			var im := full.get_region(Rect2i(fw / 4, fh * 3 / 10, fw / 2, fh / 2))
			im.resize(fw / 3, fh / 3, Image.INTERPOLATE_BILINEAR)
			_strip.append(im)
		if k == 16 and _strip.size() == 16:
			var w: int = _strip[0].get_width()
			var h: int = _strip[0].get_height()
			var sheet := Image.create(w * 4, h * 4, false, _strip[0].get_format())
			for i in 16:
				sheet.blit_rect(_strip[i], Rect2i(0, 0, w, h), Vector2i((i % 4) * w, (i / 4) * h))
			sheet.save_png(_dir().path_join("strip_%s_%s.png" % [j.species, move_name]))
			print("strip ", move_name)
			_strip.append(null)
	if _step_t > 3.2:
		_strip.clear()
		_step += 1
		_step_t = 0.0
		j.cds.clear()
		j.energy = Fighter.ENERGY_MAX
		var b: Fighter = main.fighters[1]
		b.reset(Vector3(-3.5, 0, 0) if j.species != "snorlax" else Vector3(-4.5, 0, 0), PI * 0.5)
		j.reset(Vector3(3.0, 0, 0), -PI * 0.5)
		j.cds.clear()


# ---------------------------------------------------------------- mechanics

var _results: Array = []
var _profile_trainer := ""
var _off_edge := {}


func _setup(p1: String, p2: String, pos_a: Vector3, pos_b: Vector3) -> Array:
	main.start_battle(p1, p2, "normal")
	await get_tree().physics_frame
	var a: Fighter = main.fighters[0]
	var b: Fighter = main.fighters[1]
	main.ai.mode = "still"
	b.ctrl.move_input = Vector2.ZERO
	a.ctrl.move_input = Vector2.ZERO
	a.is_player = false
	a.reset(pos_a, atan2(pos_b.x - pos_a.x, pos_b.z - pos_a.z))
	b.reset(pos_b, atan2(pos_a.x - pos_b.x, pos_a.z - pos_b.z))
	a.locked = true
	b.locked = true
	await _wait(0.3)
	return [a, b]


func _wait(s: float) -> void:
	var end_pos := t + s
	while t < end_pos:
		await get_tree().physics_frame


func _ok(case_name: String, passes: bool, detail := "") -> void:
	_results.append([case_name, passes])
	print("%s  %s  %s" % ["OK   " if passes else "FAIL ", case_name, detail])


## Every move each Pokémon can take in the Moves menu besides its own four, used once
## against a still rival: it must run without errors and, if it attacks, hit. With a window,
## a capture of each one mid-move (loadout_<pokemon>_<move>.png).
func _loadouts() -> void:
	await get_tree().physics_frame
	var fails := 0
	var count := 0
	for sp in Roster.POKEMON:
		var own: Array = Roster.POKEMON[sp].moves
		for m in Loadout.moves_for(sp):
			if m in own:
				continue
			count += 1
			main._args.moves = ",".join([m] + own.slice(0, 3))
			var d: Dictionary = Moves.DATA[m]
			var ai: Dictionary = d.get("ai", {})
			var dist := clampf((float(ai.get("min", 0.0)) + float(ai.get("max", 3.0))) * 0.5, 1.6, 9.0)
			# Blastoise takes everything (no immunities to these moves).
			var rival := "blastoise" if sp != "blastoise" else "venusaur"
			var ab: Array = await _setup(sp, rival, Vector3(-dist, 0, 0), Vector3(0, 0, 0))
			var a: Fighter = ab[0]
			var b: Fighter = ab[1]
			var hp0: float = b.hp
			var own_hp: float = a.hp
			a.ctrl.press("mov1")
			var hold := 0.1
			if d.get("hold", false):
				hold = float(d.get("max", 1.5))
			elif d.get("chargeable", false):
				hold = float(d.get("startup_max", 1.0))
			var used := false
			var t0 := t
			var shot := false
			while t - t0 < hold + 2.5:
				await get_tree().physics_frame
				if a.action and a.action.id == m:
					used = true
				if not shot and t - t0 >= minf(hold, 0.35):
					shot = true
					_capture("loadout_%s_%s" % [sp, m])
				if t - t0 >= hold:
					a.ctrl.release("mov1")
			var kind: String = ai.get("kind", "")
			var self_move: bool = kind in ["heal", "guard", "decoy", "buff"] or d.get("cat", "") == "status"
			var hit := b.hp < hp0
			used = used or hit or a.hp != own_hp
			var passes := used and (hit or self_move)
			if not passes:
				fails += 1
			_ok("%s with %s" % [sp, m], passes, "damage %d, %s" % [int(hp0 - b.hp), "self move" if self_move else "attack"])
	main._args.erase("moves")
	print("RESULT: %d of %d" % [count - fails, count])
	get_tree().quit()


## One fighter hits the other once with "slot" from "dist" meters; returns the damage the
## target took. "ability_a" / "ability_b" set their abilities (ids) for the test.
func _one_hit(sp_a: String, sp_b: String, slot: String, dist: float, ability_a := "", ability_b := "", weather := "") -> float:
	var ab: Array = await _setup(sp_a, sp_b, Vector3(-dist, 0, 0), Vector3(0, 0, 0))
	if weather != "":
		main.weather.start(weather)
	var a: Fighter = ab[0]
	var b: Fighter = ab[1]
	if ability_a != "":
		a.data.passive = Loadout.ability(sp_a, ability_a)
	if ability_b != "":
		b.data.passive = Loadout.ability(sp_b, ability_b)
	b.status_lock = 99.0              # only the hit: no chip damage from a secondary status
	var hp0: float = b.hp
	a.ctrl.press(slot)
	await _wait(0.15)
	a.ctrl.release(slot)
	await _wait(1.6)
	return hp0 - b.hp


## Each ability does what it does in the games (adapted where real time needs it).
func _abilities() -> void:
	var ball: Dictionary = Stats.battle_data("pikachu").stats
	var plain: int = Stats.at_level(Species.DATA.pikachu.stats.spa)
	_ok("Light Ball: Ash's Pikachu has double Attack and Sp. Atk", ball.spa == plain * 2 and ball.atk == Stats.at_level(Species.DATA.pikachu.stats.atk) * 2,
		"Sp. Atk %d (plain %d)" % [ball.spa, plain])
	await get_tree().physics_frame
	# Lightning Rod: Thunder Shock does nothing and raises Sp. Atk.
	var dmg := await _one_hit("pikachu", "pikachu", "mov1", 6.0, "", "lightningrod")
	var b: Fighter = main.fighters[1]
	_ok("Lightning Rod: Electric does nothing and raises Sp. Atk", dmg == 0.0 and b.stages.spa == 1, "damage %d, Sp. Atk %+d" % [dmg, b.stages.spa])
	# Thick Fat: half from Fire (Charizard's Flare Blitz on Snorlax, with and without).
	var with_fat := await _one_hit("charizard", "snorlax", "mov4", 6.0, "", "thickfat")
	var without := await _one_hit("charizard", "snorlax", "mov4", 6.0, "", "immunity")
	_ok("Thick Fat: half damage from Fire", absf(with_fat / maxf(without, 1.0) - 0.5) < 0.05, "%d vs %d" % [with_fat, without])
	# Technician: Bullet Punch (40 power) x1.5 against Swarm.
	var tech := await _one_hit("scizor", "snorlax", "mov1", 1.6, "technician")
	var swarm := await _one_hit("scizor", "snorlax", "mov1", 1.6, "swarm")
	_ok("Technician: 60 power or less x1.5", absf(tech / maxf(swarm, 1.0) - 1.5) < 0.05, "%d vs %d" % [tech, swarm])
	# Justified: a Dark move (Night Slash) raises Lucario's Attack.
	await _one_hit("greninja", "lucario", "mov2", 1.6, "", "justified")
	b = main.fighters[1]
	_ok("Justified: a Dark move raises Attack", b.stages.atk == 1, "Attack %+d" % b.stages.atk)
	# Immunity: Sludge Bomb does not poison Snorlax.
	await _one_hit("venusaur", "snorlax", "mov3", 8.0, "", "immunity")
	b = main.fighters[1]
	await _wait(1.0)
	_ok("Immunity: cannot be poisoned", b.status == "", "status '%s'" % b.status)
	# Gluttony: at half HP it eats its berry and heals a quarter.
	var ab: Array = await _setup("charizard", "snorlax", Vector3(-6, 0, 0), Vector3(0, 0, 0))
	b = ab[1]
	b.data.passive = Loadout.ability("snorlax", "gluttony")
	b.hp = b.hp_max * 0.52
	var before: float = b.hp
	ab[0].ctrl.press("mov4")
	await _wait(0.15)
	ab[0].ctrl.release("mov4")
	await _wait(1.6)
	_ok("Gluttony: eats a Sitrus Berry at half HP", b._berry_used and b.hp > before - 0.4 * b.hp_max, "HP %d -> %d of %d" % [before, b.hp, b.hp_max])
	# Steadfast: cut short while winding up, Lucario's Speed rises.
	ab = await _setup("pikachu", "lucario", Vector3(-5.0, 0, 0), Vector3(0, 0, 0))
	var a: Fighter = ab[0]
	b = ab[1]
	b.data.passive = Loadout.ability("lucario", "steadfast")
	b.ctrl.press("mov1")              # Aura Sphere charges: long wind-up
	await _wait(0.1)
	a.ctrl.press("mov2")              # Quick Attack (medium) cuts it
	await _wait(0.15)
	a.ctrl.release("mov2")
	await _wait(1.0)
	b.ctrl.release("mov1")
	_ok("Steadfast: flinching raises Speed", b.stages.spe == 1, "Speed %+d, HP %d/%d, state %s" % [b.stages.spe, b.hp, b.hp_max, b.state])
	# Cursed Body: over many hits, about 30% disable the move (it goes on a long cooldown).
	var disabled := 0
	for i in 20:
		ab = await _setup("pikachu", "gengar", Vector3(-6, 0, 0), Vector3(0, 0, 0))
		ab[1].data.passive = Loadout.ability("gengar", "cursedbody")
		ab[0].ctrl.press("mov1")
		await _wait(0.15)
		ab[0].ctrl.release("mov1")
		await _wait(0.9)
		if ab[0].cds.get("thundershock", 0.0) > 8.0:
			disabled += 1
	_ok("Cursed Body: about 30% of hits disable the move", disabled >= 2 and disabled <= 11, "%d of 20" % disabled)
	# Weather: harsh sunlight makes Fire 1.5x and Water half; rain the other way round.
	var fire_plain := await _one_hit("charizard", "snorlax", "mov4", 6.0)
	var fire_sun := await _one_hit("charizard", "snorlax", "mov4", 6.0, "", "", "sun")
	var water_sun := await _one_hit("blastoise", "snorlax", "mov1", 6.0, "", "", "sun")
	var water_plain := await _one_hit("blastoise", "snorlax", "mov1", 6.0)
	_ok("Sun: Fire x1.5", absf(fire_sun / maxf(fire_plain, 1.0) - 1.5) < 0.05, "%d vs %d" % [fire_sun, fire_plain])
	_ok("Sun: Water x0.5", absf(water_sun / maxf(water_plain, 1.0) - 0.5) < 0.05, "%d vs %d" % [water_sun, water_plain])
	# Sandstorm: wears down Pikachu, not Garchomp (Ground), and not with Sand Veil.
	ab = await _setup("pikachu", "garchomp", Vector3(-6, 0, 0), Vector3(6, 0, 0))
	main.weather.start("sand")
	await _wait(3.3)
	_ok("Sandstorm wears down, not Ground types", ab[0].hp < ab[0].hp_max and ab[1].hp == ab[1].hp_max,
		"Pikachu %d/%d, Garchomp %d/%d" % [ab[0].hp, ab[0].hp_max, ab[1].hp, ab[1].hp_max])
	main.weather.clear()
	# Rain Dish heals in the rain.
	ab = await _setup("blastoise", "pikachu", Vector3(-6, 0, 0), Vector3(6, 0, 0))
	ab[0].data.passive = Loadout.ability("blastoise", "raindish")
	ab[0].hp = ab[0].hp_max * 0.5
	main.weather.start("rain")
	await _wait(3.3)
	_ok("Rain Dish heals in the rain", ab[0].hp > ab[0].hp_max * 0.5, "HP %d/%d" % [ab[0].hp, ab[0].hp_max])
	main.weather.clear()
	# Chlorophyll: faster in the sun.
	ab = await _setup("venusaur", "pikachu", Vector3(-6, 0, 0), Vector3(6, 0, 0))
	ab[0].data.passive = Loadout.ability("venusaur", "chlorophyll")
	var plain_k: float = ab[0].speed_stage()
	main.weather.start("sun")
	_ok("Chlorophyll: faster in the sun", ab[0].speed_stage() > plain_k * 1.4, "x%.2f vs x%.2f" % [ab[0].speed_stage(), plain_k])
	main.weather.clear()
	# Sunny Day as a move starts the sun; Solar Beam then barely charges.
	main._args.moves = "sunnyday,razorleaf,sludgebomb,solarbeam"
	ab = await _setup("venusaur", "snorlax", Vector3(-8, 0, 0), Vector3(0, 0, 0))
	main._args.erase("moves")
	ab[0].ctrl.press("mov1")
	await _wait(0.15)
	ab[0].ctrl.release("mov1")
	await _wait(1.2)
	var sunny: bool = main.weather.is_on("sun")
	ab[0].ctrl.press("mov4")
	await _wait(0.1)
	ab[0].ctrl.release("mov4")
	var short_charge: float = ab[0].action.startup_len() if ab[0].action else -1.0
	await _wait(2.0)
	_ok("Sunny Day starts the sun; Solar Beam charges fast", sunny and short_charge > 0.0 and short_charge < Moves.DATA.solarbeam.startup * 0.5,
		"sun %s, charge %.2f s of %.2f" % [sunny, short_charge, Moves.DATA.solarbeam.startup])
	main.weather.clear()
	var fails := _results.filter(func(r): return not r[1]).size()
	print("RESULT: %d of %d" % [_results.size() - fails, _results.size()])
	get_tree().quit()


## Major status conditions as in the games (Status), adapted to real time.
func _statuses() -> void:
	await get_tree().physics_frame
	# Burn: 1/16 per turn, physical moves at half power; Fire types are immune.
	var ab: Array = await _setup("pikachu", "charizard", Vector3(-6, 0, 0), Vector3(6, 0, 0))
	var a: Fighter = ab[0]
	var b: Fighter = ab[1]
	_ok("Fire types cannot be burned", not b.inflict("brn") and b.status == "", "status '%s'" % b.status)
	a.inflict("brn")
	var hp0: float = a.hp
	await _wait(Status.DURATION.brn + 0.4)
	var lost: float = (hp0 - a.hp) / a.hp_max
	_ok("Burn: its chip damage in full", absf(lost - Status.TOTAL.brn) < 0.01, "%.3f of max HP" % lost)
	_ok("Burn wears off", a.status == "", "status '%s'" % a.status)
	_ok("Just cured: no new status for a while", not a.inflict("psn"), "status '%s'" % a.status)
	await _wait(Status.IMMUNE_AFTER)
	_ok("Then it can get one again", a.inflict("psn"), "status '%s'" % a.status)
	var plain := await _one_hit("snorlax", "pikachu", "mov1", 6.0)
	ab = await _setup("snorlax", "pikachu", Vector3(-6, 0, 0), Vector3(0, 0, 0))
	ab[0].inflict("brn")
	var hp_b: float = ab[1].hp
	ab[0].ctrl.press("mov1")
	await _wait(0.15)
	ab[0].ctrl.release("mov1")
	await _wait(1.6)
	var burned_hit: float = hp_b - ab[1].hp
	_ok("Burn: physical moves hit half as hard", absf(burned_hit / maxf(plain, 1.0) - 0.5) < 0.06, "%d vs %d" % [burned_hit, plain])
	# Paralysis: half speed; Electric types are immune.
	ab = await _setup("snorlax", "pikachu", Vector3(-6, 0, 0), Vector3(6, 0, 0))
	_ok("Electric types cannot be paralyzed", not ab[1].inflict("par"), "status '%s'" % ab[1].status)
	a = ab[0]
	a.locked = false
	a.ctrl.yaw = 0.0
	a.ctrl.move_input = Vector2(0, 1)
	var z0: float = a.global_position.z
	await _wait(1.0)
	var free_run: float = absf(a.global_position.z - z0)
	a.ctrl.move_input = Vector2.ZERO
	await _wait(0.6)
	a.inflict("par")
	a._para_roll = 99.0             # no full paralysis during the measurement
	a.ctrl.move_input = Vector2(0, 1)
	z0 = a.global_position.z
	await _wait(1.0)
	a.ctrl.move_input = Vector2.ZERO
	var para_run: float = absf(a.global_position.z - z0)
	_ok("Paralysis: half speed", para_run < free_run * 0.62, "%.1f m vs %.1f m" % [para_run, free_run])
	# Badly poisoned: it gets worse every turn.
	ab = await _setup("snorlax", "pikachu", Vector3(-6, 0, 0), Vector3(6, 0, 0))
	ab[0].inflict("tox")
	hp0 = ab[0].hp
	await _wait(3.0)
	var early: float = hp0 - ab[0].hp
	await _wait(Status.DURATION.tox - 6.0)
	hp0 = ab[0].hp
	await _wait(3.0)
	var late: float = hp0 - ab[0].hp
	_ok("Badly poisoned grows as it goes on", late > early * 1.5, "%d then %d" % [early, late])
	# Poison: longer and slower than Toxic, less in all.
	ab = await _setup("snorlax", "pikachu", Vector3(-6, 0, 0), Vector3(6, 0, 0))
	ab[0].inflict("psn")
	hp0 = ab[0].hp
	await _wait(Status.DURATION.tox)
	var psn_part: float = (hp0 - ab[0].hp) / ab[0].hp_max
	_ok("Poison is slower than Toxic", psn_part < Status.TOTAL.tox * 0.5 and ab[0].status == "psn", "%.3f of max HP in %.0f s" % [psn_part, Status.DURATION.tox])
	ab = await _setup("scizor", "gengar", Vector3(-6, 0, 0), Vector3(6, 0, 0))
	_ok("Poison and Steel types cannot be poisoned", not ab[0].inflict("psn") and not ab[1].inflict("tox"), "Scizor '%s', Gengar '%s'" % [ab[0].status, ab[1].status])
	# Sleep: it cannot act.
	ab = await _setup("snorlax", "pikachu", Vector3(-6, 0, 0), Vector3(6, 0, 0))
	a = ab[0]
	a.inflict("slp")
	await _wait(0.3)
	a.ctrl.press("mov1")
	await _wait(0.3)
	a.ctrl.release("mov1")
	_ok("Asleep, it cannot act", a.action == null and a.state == "stunned", "state %s" % a.state)
	await _wait(3.2)
	_ok("It wakes up", a.status == "" and a.state != "stunned", "status '%s', state %s" % [a.status, a.state])
	# Freeze: a Fire hit thaws it out.
	ab = await _setup("charizard", "snorlax", Vector3(-5, 0, 0), Vector3(0, 0, 0))
	ab[1].inflict("frz")
	ab[1].status_t = 99.0
	ab[0].ctrl.press("mov1")
	await _wait(0.8)
	ab[0].ctrl.release("mov1")
	await _wait(0.3)
	_ok("A Fire hit thaws it out", ab[1].status == "", "status '%s'" % ab[1].status)
	# Hex and Facade: double against / with a status condition.
	var hex_plain := await _one_hit("gengar", "snorlax", "mov3", 6.0)
	ab = await _setup("gengar", "snorlax", Vector3(-6, 0, 0), Vector3(0, 0, 0))
	ab[1].inflict("par")
	ab[1]._para_roll = 99.0
	var hp_h: float = ab[1].hp
	ab[0].ctrl.press("mov3")
	await _wait(0.15)
	ab[0].ctrl.release("mov3")
	await _wait(1.6)
	var hex_double: float = hp_h - ab[1].hp
	_ok("Hex: double against a status condition", hex_double > hex_plain * 1.7, "%d vs %d" % [hex_double, hex_plain])
	# Rest cures it.
	ab = await _setup("snorlax", "pikachu", Vector3(-6, 0, 0), Vector3(6, 0, 0))
	ab[0].inflict("psn")
	ab[0].ctrl.press("mov4")
	await _wait(0.15)
	ab[0].ctrl.release("mov4")
	await _wait(1.0)
	_ok("Rest cures the status", ab[0].status == "", "status '%s'" % ab[0].status)
	var fails := _results.filter(func(r): return not r[1]).size()
	print("RESULT: %d of %d" % [_results.size() - fails, _results.size()])
	get_tree().quit()


## Status moves: each gives its status, and fails where the games say (types, powders).
func _status_moves() -> void:
	await get_tree().physics_frame
	var b := await _use("venusaur", "sleeppowder,poisonpowder,toxic,solarbeam", "snorlax", 2.5)
	_ok("Sleep Powder puts it to sleep", b.status == "slp", "status '%s'" % b.status)
	b = await _use("venusaur", "sleeppowder,poisonpowder,toxic,solarbeam", "venusaur", 2.5)
	_ok("Grass types ignore powders", b.status == "", "status '%s'" % b.status)
	b = await _use("venusaur", "poisonpowder,sleeppowder,toxic,solarbeam", "pikachu", 2.5)
	_ok("Poison Powder poisons", b.status == "psn", "status '%s'" % b.status)
	b = await _use("venusaur", "toxic,sleeppowder,poisonpowder,solarbeam", "pikachu", 8.0, 2.4)
	_ok("Toxic badly poisons", b.status == "tox", "status '%s'" % b.status)
	# Jumping as the ground bubbles avoids it: it only reaches who stands on the ground.
	main._args["moves"] = "toxic,sleeppowder,poisonpowder,solarbeam"
	var tj: Array = await _setup("venusaur", "pikachu", Vector3(-8, 0, 0), Vector3(0, 0, 0))
	main._args.erase("moves")
	tj[0].ctrl.press("mov1")
	await _wait(0.15)
	tj[0].ctrl.release("mov1")
	# The stain runs about 6 m at 13 m/s after a 0.3 s startup: the warning is on by 0.8 s.
	await _wait(0.8)
	var warned: bool = tj[1].status == ""
	tj[1].ctrl.press("jump")
	await _wait(0.1)
	tj[1].ctrl.release("jump")
	await _wait(1.0)
	_ok("Toxic: jumping on the warning avoids it", warned and tj[1].status == "", "status '%s'" % tj[1].status)
	b = await _use("charizard", "willowisp,flamethrower,airslash,dragonclaw", "snorlax", 7.0)
	_ok("Will-O-Wisp burns", b.status == "brn", "status '%s'" % b.status)
	b = await _use("pikachu", "thunderwave,nuzzle,thundershock,quickattack", "snorlax", 6.0)
	_ok("Thunder Wave paralyzes", b.status == "par", "status '%s'" % b.status)
	b = await _use("pikachu", "thunderwave,nuzzle,thundershock,quickattack", "garchomp", 6.0)
	_ok("Thunder Wave does nothing to Ground types", b.status == "", "status '%s'" % b.status)
	b = await _use("gengar", "hypnosis,shadowball,hex,substitute", "snorlax", 5.0)
	_ok("Hypnosis puts it to sleep", b.status == "slp", "status '%s'" % b.status)
	b = await _use("snorlax", "yawn,bodyslam,icepunch,rest", "pikachu", 4.0)
	_ok("Yawn makes it drowsy", b.drowsy > 0.0 and b.status == "", "drowsy %.1f, status '%s'" % [b.drowsy, b.status])
	await _wait(Status.YAWN + 0.2)
	_ok("Then it falls asleep", b.status == "slp", "status '%s'" % b.status)
	b = await _use("pikachu", "nuzzle,thunderwave,thundershock,quickattack", "snorlax", 3.0)
	_ok("Nuzzle always paralyzes", b.status == "par", "status '%s'" % b.status)
	b = await _use("pikachu", "nuzzle,thunderwave,thundershock,quickattack", "garchomp", 3.0)
	_ok("Nuzzle does not paralyze Ground types", b.status == "", "status '%s'" % b.status)
	# Just cured: it says so and nothing happens.
	main._args["moves"] = "thunderwave,nuzzle,thundershock,quickattack"
	var ab: Array = await _setup("pikachu", "snorlax", Vector3(-6, 0, 0), Vector3(0, 0, 0))
	main._args.erase("moves")
	ab[1].status_lock = 3.0
	ab[0].ctrl.press("mov1")
	await _wait(0.15)
	ab[0].ctrl.release("mov1")
	await _wait(0.7)
	var said: bool = main.vfx.texts.any(func(x): return x.s == tr("Temporary immunity"))
	_ok("Temporary immunity: no status, and it says so", said and ab[1].status == "", "status '%s'" % ab[1].status)
	var fails := _results.filter(func(r): return not r[1]).size()
	print("RESULT: %d of %d" % [_results.size() - fails, _results.size()])
	get_tree().quit()


## sp_a, with these four moves, uses the first one on sp_b standing "dist" meters away.
func _use(sp_a: String, moves: String, sp_b: String, dist: float, wait := 1.6) -> Fighter:
	main._args["moves"] = moves
	var ab: Array = await _setup(sp_a, sp_b, Vector3(-dist, 0, 0), Vector3(0, 0, 0))
	main._args.erase("moves")
	var a: Fighter = ab[0]
	if a.data.moves[0] != moves.get_slice(",", 0):
		_ok("Loadout %s" % moves, false, "got %s" % [a.data.moves])
	a.ctrl.press("mov1")
	await _wait(0.15)
	a.ctrl.release("mov1")
	await _wait(wait)
	return ab[1]


## Fixed views of the stage for checking it by eye (captures/stage_*.png): the night
## stadium's scoreboard, the camera at a corner (it must stay out of the stands) and the
## floating stadium's floor under its floodlights.
func _stage_shots() -> void:
	main.ai.mode = "still"
	await _wait(2.0)
	var a: Fighter = main.fighters[0]
	a.is_player = false
	a.hp = a.hp_max * 0.6
	await _wait(1.5)
	main.camera.set_physics_process(false)
	main.camera.global_position = Vector3(8.0, 17.0, 0.0)
	main.camera.look_at(Vector3(32.1, 21.0, 0.0))
	await _wait(0.4)
	_capture("stage_board")
	main.camera.set_physics_process(true)
	# A corner: the fighter backs into it and the camera turns toward the stands.
	a.locked = false
	a.global_position = Vector3(18.5, 0.0, 10.5)
	main.camera.yaw = deg_to_rad(-140.0)
	main.camera.pitch = 0.2
	await _wait(1.0)
	_capture("stage_corner")
	main.camera.yaw = deg_to_rad(-120.0)
	main.camera.pitch = -0.5
	await _wait(1.0)
	_capture("stage_corner_high")
	# The final blow: the strip turns the winner's color with WINNER all round.
	main.camera.yaw = deg_to_rad(-90.0)
	main.camera.pitch = -0.1
	a.global_position = Vector3(0.0, 0.0, 4.0)
	main.arena.on_ko(a)
	await _wait(1.2)
	_capture("stage_winner")
	main.arena.on_rematch()
	main.set_stage("floating")
	await _wait(1.5)
	a.global_position = Vector3(-6.0, 0.0, 0.0)
	main.camera.yaw = deg_to_rad(90.0)
	main.camera.pitch = -0.35
	await _wait(1.0)
	_capture("stage_floor")
	main.camera.pitch = -0.7
	await _wait(0.8)
	_capture("stage_floor_high")
	get_tree().quit()


## The stage pictures of the selection screen (gui/stages/<id>.png, 640 × 360): a wide
## view of each stage, no HUD or Pokémon. Run with a window; commit the result.
func _stage_previews() -> void:
	main.ai.mode = "still"
	main.hud.visible = false
	for f in main.fighters:
		f.visible = false
	main.camera.set_physics_process(false)
	var views := {"night": [Vector3(-26.0, 13.0, 22.0), Vector3(2.0, 0.0, -2.0)],
		"floating": [Vector3(-30.0, 12.0, 26.0), Vector3(0.0, -1.0, 0.0)],
		"league": [Vector3(-13.0, 10.0, 13.0), Vector3(3.0, 2.0, -8.0)]}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://gui/stages"))
	for id in Menu.STAGES:
		main.set_stage(id)
		for f in main.fighters:
			f.visible = false
		main.camera.global_position = views[id][0]
		main.camera.look_at(views[id][1])
		await _wait(2.0)
		var img := get_viewport().get_texture().get_image()
		img.resize(640, 360, Image.INTERPOLATE_LANCZOS)
		img.save_png("res://gui/stages/%s.png" % id)
		print("preview ", id)
	get_tree().quit()


## The end of a battle and the pause, captured (captures/result.png, pause.png).
func _result_shot() -> void:
	main.ai.mode = "still"
	main.player.is_player = false
	await _wait(1.5)
	main.toggle_pause()
	await _wait(0.5)
	_capture("pause")
	main.toggle_pause()
	await _wait(0.3)
	main.fighters[1]._damage_direct(99999.0)
	await _wait(main.CHOICES_AT + 0.6)
	_capture("result")
	get_tree().quit()


## Projectiles stopped by moves that deflect (Combat.deflect): a hit of that move is put in
## front of the defender, as if it swung right on time, and the rival fires into it.
func _deflect_test() -> void:
	await get_tree().physics_frame
	var cases := [["xscissor", "thundershock", "pikachu", "mov1", "Sent back: the thrower takes it, the deflector nothing"],
		["shadowclaw", "thundershock", "pikachu", "mov1", "Broken: neither takes anything"],
		["xscissor", "sludgebomb", "venusaur", "mov3", "A lobbed bomb is never sent back"]]
	for c in cases:
		var ab: Array = await _setup("scizor", c[2], Vector3(-6, 0, 0), Vector3(4, 0, 0))
		var a: Fighter = ab[0]
		var b: Fighter = ab[1]
		var g := Hit.new()
		g.user = a
		g.move_id = c[0]
		g.shape = "sphere"
		g.center = Vector3(0, 1.0, 1.2)
		g.radius = 1.8
		g.damage = 0.0
		g.lifetime = 2.0
		# The swing comes out just as the shot gets close (within its window).
		var swing := func():
			for t in 120:
				await get_tree().physics_frame
				for p in main.combat.projectiles:
					var gap: float = p.pos.distance_to(a.center())
					if p.user == b and gap < 2.0 + p.velocity.length() * 0.05:
						main.combat.add_hit(g)
						return
		swing.call()
		var hp_a: float = a.hp
		var hp_b: float = b.hp
		main.camera.set_physics_process(false)
		main.camera.global_position = Vector3(-2.5, 2.0, 6.0)
		main.camera.look_at(Vector3(-3.5, 1.0, 0.0))
		b.ctrl.press(c[3])
		await _wait(0.15)
		b.ctrl.release(c[3])
		# Pictures around the moment it meets the swing (only with a window).
		for k in 8:
			await _wait(0.04)
			_capture("deflect_%s_%s_%d" % [c[0], c[1], k])
		await _wait(1.5)
		main.camera.set_physics_process(true)
		var ok := false
		match c[0]:
			"xscissor":
				# A lobbed bomb is never sent back (it may land or break; the thrower is untouched).
				ok = (a.hp == hp_a and b.hp < hp_b) if c[1] == "thundershock" else b.hp == hp_b
			"shadowclaw":
				ok = a.hp == hp_a and b.hp == hp_b
		_ok(c[4], ok, "deflector %d/%d, thrower %d/%d" % [a.hp, hp_a, b.hp, hp_b])
	# With the real move: Scizor swings X-Scissor when the shot is this far away. A fair
	# window means several of these timings work, not just one exact frame.
	var sent := 0
	var tries := [2.5, 4.0, 5.5, 7.0, 8.5, 10.0]
	for trigger in tries:
		main._args["moves"] = "xscissor,bulletpunch,swordsdance,wingattack"
		var ab: Array = await _setup("scizor", "pikachu", Vector3(-6, 0, 0), Vector3(4, 0, 0))
		main._args.erase("moves")
		var a: Fighter = ab[0]
		var b: Fighter = ab[1]
		a.locked = true
		var hp_b: float = b.hp
		var hp_a: float = a.hp
		var swing := func():
			for t in 120:
				await get_tree().physics_frame
				for p in main.combat.projectiles:
					if p.user == b and p.pos.distance_to(a.center()) < trigger:
						a.ctrl.press("mov1")
						await get_tree().physics_frame
						a.ctrl.release("mov1")
						return
		swing.call()
		b.ctrl.press("mov1")
		await _wait(0.15)
		b.ctrl.release("mov1")
		await _wait(1.6)
		if b.hp < hp_b and a.hp == hp_a:
			sent += 1
	_ok("Real X-Scissor sends Thunder Shock back at several timings", sent >= 3, "%d of %d timings" % [sent, tries.size()])
	var fails := _results.filter(func(r): return not r[1]).size()
	print("RESULT: %d of %d" % [_results.size() - fails, _results.size()])
	get_tree().quit()


## Holds a move's button for a while (streams).
func _hold(f: Fighter, action: String, secs := 1.6) -> void:
	f.ctrl.press(action)
	f.ctrl.held[action] = true
	get_tree().create_timer(secs).timeout.connect(func():
		if is_instance_valid(f):
			f.ctrl.held[action] = false
			f.ctrl.release(action))


## Shots that meet (Combat.clash): even ones burst, a stronger one goes on weaker.
func _clash_test() -> void:
	await get_tree().physics_frame
	# Even: two Thunder Shocks head on.
	var ab: Array = await _setup("pikachu", "pikachu", Vector3(-6, 0, 0), Vector3(6, 0, 0))
	var hp := [ab[0].hp, ab[1].hp]
	for f in ab:
		f.ctrl.press("mov1")
	await _wait(0.15)
	for f in ab:
		f.ctrl.release("mov1")
	await _wait(1.2)
	_ok("Even shots burst and nobody is hit", ab[0].hp == hp[0] and ab[1].hp == hp[1], "%d/%d, %d/%d" % [ab[0].hp, hp[0], ab[1].hp, hp[1]])
	# Stronger: Shadow Ball (80) through Thunder Shock (40), half as strong after.
	var plain := await _one_hit("gengar", "pikachu", "mov1", 12.0)
	ab = await _setup("gengar", "pikachu", Vector3(-6, 0, 0), Vector3(6, 0, 0))
	hp = [ab[0].hp, ab[1].hp]
	main.camera.set_physics_process(false)
	main.camera.global_position = Vector3(0.0, 2.6, 8.5)
	main.camera.look_at(Vector3(0.0, 1.0, 0.0))
	for f in ab:
		f.ctrl.press("mov1")
	await _wait(0.15)
	for f in ab:
		f.ctrl.release("mov1")
	for k in 8:
		await _wait(0.05)
		_capture("clash_%d" % k)
	main.camera.set_physics_process(true)
	await _wait(1.2)
	var took: float = hp[1] - ab[1].hp
	_ok("The stronger shot goes on, weaker", ab[0].hp == hp[0] and took > 0.0 and took < plain * 0.75, "Pikachu took %d (plain %d), Gengar %d/%d" % [took, plain, ab[0].hp, hp[0]])
	# Streams: Hydro Pump against Flamethrower, head on. Water wins: the fire is cut where
	# they meet and never reaches Blastoise; the water reaches Charizard.
	ab = await _setup("blastoise", "charizard", Vector3(-4, 0, 0), Vector3(4, 0, 0))
	hp = [ab[0].hp, ab[1].hp]
	main.camera.set_physics_process(false)
	main.camera.global_position = Vector3(2.0, 3.5, 13.0)
	main.camera.look_at(Vector3(2.0, 1.2, 0.0))
	_hold(ab[0], "mov2", 2.4)
	await _wait(0.6)
	_hold(ab[1], "mov1")
	for k in 4:
		await _wait(0.12)
		_capture("streams_%d" % k)
	main.camera.set_physics_process(true)
	await _wait(1.0)
	_ok("Water cuts fire: only Charizard is hit", ab[0].hp == hp[0] and ab[1].hp < hp[1], "Blastoise %d/%d, Charizard %d/%d" % [ab[0].hp, hp[0], ab[1].hp, hp[1]])
	# Even streams: both cut, nobody hit.
	ab = await _setup("charizard", "charizard", Vector3(-4, 0, 0), Vector3(4, 0, 0))
	hp = [ab[0].hp, ab[1].hp]
	_hold(ab[0], "mov1")
	_hold(ab[1], "mov1")
	await _wait(1.8)
	_ok("Even streams cut each other", ab[0].hp == hp[0] and ab[1].hp == hp[1], "%d/%d, %d/%d" % [ab[0].hp, hp[0], ab[1].hp, hp[1]])
	var fails := _results.filter(func(r): return not r[1]).size()
	print("RESULT: %d of %d" % [_results.size() - fails, _results.size()])
	get_tree().quit()


## Each move added lately lands on a still Snorlax from its own distance: [user, its four
## moves (the one tried first), distance].
const NEW_MOVES := [
	["charizard", "firepunch,thunderpunch,flamethrower,airslash", 3.0],
	["charizard", "thunderpunch,firepunch,flamethrower,airslash", 2.4],
	["pikachu", "thunderbolt,quickattack,irontail,electroball", 9.0],
	["charizard", "bite,flamethrower,airslash,dragonclaw", 2.6],
	["garchomp", "crunch,dragonclaw,earthquake,stoneedge", 3.4],
	["charizard", "fireblast,flamethrower,airslash,dragonclaw", 7.0],
	["lucario", "closecombat,aurasphere,bulletpunch,extremespeed", 2.8],
	["gengar", "shadowclaw,shadowball,hex,substitute", 3.2],
	["garchomp", "rockslide,dragonclaw,earthquake,stoneedge", 8.0],
	["blastoise", "surf,hydropump,icebeam,rapidspin", 8.0],
	["gengar", "psychic,shadowball,hex,substitute", 8.0],
	["greninja", "darkpulse,watershuriken,nightslash,hydropump", 4.5],
	["venusaur", "energyball,solarbeam,sludgebomb,razorleaf", 8.0],
	["charizard", "dragonpulse,flamethrower,airslash,dragonclaw", 8.0],
	["pikachu", "thunder,quickattack,irontail,electroball", 8.0],
	["pikachu", "volttackle,quickattack,irontail,electroball", 6.0],
	["lucario", "focusblast,aurasphere,bulletpunch,extremespeed", 6.0],
	["lucario", "flashcannon,aurasphere,bulletpunch,extremespeed", 9.0],
	["garchomp", "outrage,dragonclaw,earthquake,stoneedge", 3.0],
]


func _new_moves() -> void:
	await get_tree().physics_frame
	for c in NEW_MOVES:
		var move: String = str(c[1]).get_slice(",", 0)
		main._args["moves"] = c[1]
		var dealt := await _one_hit(c[0], "snorlax", "mov1", c[2])
		main._args.erase("moves")
		_ok("%s lands from %.1f m" % [move, c[2]], dealt > 0.0, "%d damage" % dealt)
	# Thunderbolt: dodging as its ring locks avoids it.
	main._args["moves"] = "thunderbolt,quickattack,irontail,electroball"
	var ab: Array = await _setup("pikachu", "pikachu", Vector3(-5, 0, 0), Vector3(4, 0, 0))
	main._args.erase("moves")
	var hp: float = ab[1].hp
	ab[0].ctrl.press("mov1")
	await _wait(0.33)
	ab[0].ctrl.release("mov1")
	ab[1].ctrl.move_input = Vector2(0, 1)
	ab[1].ctrl.press("dodge")
	await _wait(0.1)
	ab[1].ctrl.release("dodge")
	await _wait(0.8)
	ab[1].ctrl.move_input = Vector2.ZERO
	_ok("Thunderbolt: a dodge as the ring locks avoids it", ab[1].hp == hp, "%d/%d" % [ab[1].hp, hp])
	# Outrage: after it, the user is confused and its movement is turned around.
	main._args["moves"] = "outrage,dragonclaw,earthquake,stoneedge"
	ab = await _setup("garchomp", "snorlax", Vector3(-3, 0, 0), Vector3(1, 0, 0))
	main._args.erase("moves")
	var g: Fighter = ab[0]
	var straight: Vector3 = g._world_dir(Vector2(1, 0))
	g.ctrl.press("mov1")
	await _wait(0.1)
	g.ctrl.release("mov1")
	await _wait(2.6)
	var turned: Vector3 = g._world_dir(Vector2(1, 0))
	_ok("Outrage leaves it confused, its movement turned around", g.confused > 0.0 and turned.dot(straight) < -0.9,
		"confused %.1f s, dot %.2f" % [g.confused, turned.dot(straight)])
	var fails := _results.filter(func(r): return not r[1]).size()
	print("RESULT: %d of %d" % [_results.size() - fails, _results.size()])
	get_tree().quit()


func _mechanics() -> void:
	await get_tree().physics_frame
	# 1. A projectile that is not dodged hits.
	var ab: Array = await _setup("pikachu", "charizard", Vector3(-4, 0, 0), Vector3(4, 0, 0))
	var a: Fighter = ab[0]
	var b: Fighter = ab[1]
	a.ctrl.press("mov1")
	await _wait(1.0)
	_ok("Thunder Shock without dodging hits", b.hp < b.hp_max, "HP %d/%d" % [b.hp, b.hp_max])
	# 2. Dodging it sideways with the dodge (invulnerability window).
	ab = await _setup("pikachu", "charizard", Vector3(-4, 0, 0), Vector3(4, 0, 0))
	a = ab[0]
	b = ab[1]
	a.ctrl.press("mov1")
	var dodged := false
	for i in 90:
		await get_tree().physics_frame
		for p in main.combat.projectiles:
			if not dodged and p.pos.distance_to(b.center()) < 5.0:
				dodged = true
				b.ctrl.yaw = atan2(b.global_position.x - a.global_position.x, b.global_position.z - a.global_position.z)
				b.ctrl.move_input = Vector2(1, 0)
				b.ctrl.press("dodge")
	_ok("Thunder Shock dodged with the dodge", b.hp == b.hp_max, "HP %d" % b.hp)
	# 3. Stepping aside does not shake it off at mid range: it follows (only a dodge
	# breaks the lock).
	ab = await _setup("pikachu", "charizard", Vector3(-6, 0, 0), Vector3(6, 0, 0))
	a = ab[0]
	b = ab[1]
	a.ctrl.press("mov1")
	await _wait(0.12)
	b.ctrl.yaw = 0.0
	b.ctrl.move_input = Vector2(0, 1)   # with yaw 0, "forward" is -Z: sideways to the shot
	await _wait(1.0)
	b.ctrl.move_input = Vector2.ZERO
	_ok("Thunder Shock follows a rival that steps aside", b.hp < b.hp_max, "HP %d/%d" % [b.hp, b.hp_max])
	# 3d. A dodge breaks the lock: dodging early (its invulnerability over before the shot
	# arrives) still makes it miss, because the shot flies straight from then on.
	ab = await _setup("pikachu", "charizard", Vector3(-8, 0, 0), Vector3(8, 0, 0))
	a = ab[0]
	b = ab[1]
	a.ctrl.press("mov1")
	var fired := false
	for i in 30:
		await get_tree().physics_frame
		if not fired and not main.combat.projectiles.is_empty():
			fired = true
			b.locked = false
			b.ctrl.yaw = 0.0
			b.ctrl.move_input = Vector2(0, 1)
			b.ctrl.press("dodge")
	await _wait(1.0)
	b.ctrl.move_input = Vector2.ZERO
	_ok("A dodge breaks the lock: dodging early still avoids it", fired and b.hp == b.hp_max, "HP %d" % b.hp)
	# 3b. Running in a straight line does not dodge: projectiles lead a moving target.
	ab = await _setup("pikachu", "charizard", Vector3(-6, 0, 0), Vector3(6, 0, 0))
	a = ab[0]
	b = ab[1]
	b.ctrl.yaw = 0.0
	b.ctrl.move_input = Vector2(0, 1)
	await _wait(0.6)
	a.ctrl.press("mov1")
	await _wait(0.9)
	b.ctrl.move_input = Vector2.ZERO
	_ok("Thunder Shock hits a rival running in a straight line (lead)", b.hp < b.hp_max, "HP %d/%d" % [b.hp, b.hp_max])
	# 3c. Knockback by power: a light hit barely moves the target, a heavy one sends it
	# back, a push move further; and light Pokémon fly further than heavy ones.
	var slides := {}
	# [attacker, target, slot, attacker's distance, name]
	for c in [["pikachu", "charizard", "mov1", 6.0, "thundershock"], ["pikachu", "charizard", "mov3", 1.6, "irontail"],
			["snorlax", "charizard", "mov1", 6.0, "bodyslam"], ["charizard", "pikachu", "mov4", 6.0, "flareblitz_on_pikachu"],
			["charizard", "snorlax", "mov4", 6.0, "flareblitz_on_snorlax"]]:
		ab = await _setup(c[0], c[1], Vector3(-c[3], 0, 0), Vector3(0, 0, 0))
		a = ab[0]
		b = ab[1]
		var hp0: float = b.hp
		a.ctrl.press(c[2])
		await _wait(0.15)
		a.ctrl.release(c[2])
		var t0 := t
		while b.hp >= hp0 and t - t0 < 2.5:
			await get_tree().physics_frame
		var x_hit: float = b.global_position.x
		await _wait(1.6)
		slides[c[4]] = b.global_position.x - x_hit
	print("    slides: ", slides)
	_ok("Knockback by power: light < heavy < push move", slides.thundershock < 0.8 and slides.irontail > slides.thundershock * 2.0 and slides.bodyslam > slides.irontail * 0.6,
		"Thunder Shock %.1f m, Iron Tail %.1f m, Body Slam %.1f m" % [slides.thundershock, slides.irontail, slides.bodyslam])
	_ok("Knockback by weight: Pikachu flies further than Snorlax", slides.flareblitz_on_pikachu > slides.flareblitz_on_snorlax * 2.0,
		"Flare Blitz: Pikachu %.1f m, Snorlax %.1f m" % [slides.flareblitz_on_pikachu, slides.flareblitz_on_snorlax])
	# 3e. A move that cancels into moves cannot chain into itself, and the cancelled one
	# still goes on cooldown.
	ab = await _setup("greninja", "snorlax", Vector3(-3, 0, 0), Vector3(0, 0, 0))
	a = ab[0]
	b = ab[1]
	var slashes := [0]
	b.hit_taken.connect(func(_q, info): if info.hit.move_id == "nightslash": slashes[0] += 1)
	for i in 6:
		a.ctrl.press("mov2")
		await _wait(0.12)
		a.ctrl.release("mov2")
		await _wait(0.12)
	await _wait(0.6)
	_ok("Night Slash cannot be chained into itself", slashes[0] == 1 and a.cds.get("nightslash", 0.0) > 1.5,
		"%d slashes, cooldown %.1f s" % [slashes[0], a.cds.get("nightslash", 0.0)])
	# 3f. Ice Beam travels: from afar, stepping aside as it fires gets out of its line;
	# standing still, it hits.
	for moving in [false, true]:
		ab = await _setup("blastoise", "pikachu", Vector3(-14, 0, 0), Vector3(0, 0, 0))
		a = ab[0]
		b = ab[1]
		a.ctrl.press("mov4")
		await _wait(0.15)
		a.ctrl.release("mov4")
		var shot := false
		for i in 90:
			await get_tree().physics_frame
			if not shot and a.action and a.action.phase == "active":
				shot = true
				if moving:
					b.ctrl.yaw = 0.0
					b.ctrl.move_input = Vector2(0, 1)   # yaw 0: -Z, across the beam
		b.ctrl.move_input = Vector2.ZERO
		if moving:
			_ok("Ice Beam from afar: stepping aside avoids it", b.hp == b.hp_max, "HP %d/%d" % [b.hp, b.hp_max])
		else:
			_ok("Ice Beam from afar: standing still, it hits", b.hp < b.hp_max, "HP %d/%d" % [b.hp, b.hp_max])
	# 3g. Hex's mark follows a rival that walks away, and bursts on it.
	ab = await _setup("gengar", "snorlax", Vector3(-8, 0, 0), Vector3(0, 0, 0))
	a = ab[0]
	b = ab[1]
	b.ctrl.yaw = 0.0
	b.ctrl.move_input = Vector2(1, 0)
	a.ctrl.press("mov3")
	await _wait(0.15)
	a.ctrl.release("mov3")
	await _wait(1.0)
	b.ctrl.move_input = Vector2.ZERO
	_ok("Hex follows a rival that walks away", b.hp < b.hp_max, "HP %d/%d" % [b.hp, b.hp_max])
	# 4. Earthquake without jumping hits; jumping in time, it does not.
	ab = await _setup("snorlax", "pikachu", Vector3(0, 0, 0), Vector3(6, 0, 0))
	a = ab[0]
	b = ab[1]
	a.ctrl.press("mov3")
	await _wait(2.0)
	_ok("Earthquake hits whoever does not jump", b.hp < b.hp_max, "HP %d" % b.hp)
	ab = await _setup("snorlax", "pikachu", Vector3(0, 0, 0), Vector3(6, 0, 0))
	a = ab[0]
	b = ab[1]
	a.ctrl.press("mov3")
	var jump := false
	for i in 150:
		await get_tree().physics_frame
		if a.action and a.action.id == "earthquake" and a.action.phase == "active" and not jump:
			var d: Dictionary = a.action.d
			var k: float = clampf(a.action.t / d.active, 0.0, 1.0)
			var r: float = d.r_max * (1.0 - pow(1.0 - k, 2.0))
			if r > 6.0 - 2.4:
				jump = true
				b.ctrl.press("jump")
	_ok("Earthquake jumped in time", b.hp == b.hp_max, "HP %d" % b.hp)
	# 4b. Poise: Snorlax prepares Earthquake (poise 1 + 1 for being heavy). A medium hit
	# (Thunder Shock) does not interrupt it; a heavy one (Iron Tail) does.
	for case_d in [["mov1", Vector3(-7, 0, 0), false], ["mov3", Vector3(-2.2, 0, 0), true]]:
		ab = await _setup("pikachu", "snorlax", case_d[1], Vector3(0, 0, 0))
		a = ab[0]
		b = ab[1]
		a.ctrl.press(case_d[0])
		await _wait(0.12 if case_d[0] == "mov1" else 0.0)
		b.ctrl.press("mov3")
		var cut := false
		for i in 70:
			await get_tree().physics_frame
			if b.action == null or b.action.id != "earthquake":
				cut = true
				break
			if b.action.phase == "active":
				break
		if case_d[2]:
			_ok("A heavy hit (Iron Tail) interrupts Earthquake", cut, "HP %d" % b.hp)
		else:
			_ok("A medium hit (Thunder Shock) does not interrupt Earthquake", not cut and b.hp < b.hp_max, "HP %d" % b.hp)
	# 4c. Streams without lockdown: inside a Flamethrower you can dodge out.
	ab = await _setup("charizard", "pikachu", Vector3(-3.5, 0, 0), Vector3(0, 0, 0))
	a = ab[0]
	b = ab[1]
	a.ctrl.press("mov1")
	var exits := false
	for i in 120:
		a.ctrl.held["mov1"] = true
		await get_tree().physics_frame
		if i == 50:
			b.ctrl.yaw = 0.0
			b.ctrl.move_input = Vector2(0, 1)
			b.ctrl.press("dodge")
		if i > 50 and b.state == "dodge":
			exits = true
	a.ctrl.release("mov1")
	b.ctrl.move_input = Vector2.ZERO
	_ok("Inside a Flamethrower you can dodge out", exits and b.hp < b.hp_max, "HP %d" % b.hp)
	# 4c2. Inside Flamethrower the dodge covers half: dodging backward does not leave the cone.
	ab = await _setup("charizard", "pikachu", Vector3(-3.5, 0, 0), Vector3(0, 0, 0))
	a = ab[0]
	b = ab[1]
	a.ctrl.press("mov1")
	var before_x := 0.0
	var after_x := 0.0
	for i in 110:
		a.ctrl.held["mov1"] = true
		await get_tree().physics_frame
		if i == 50:
			before_x = b.global_position.x
			b.ctrl.yaw = -PI * 0.5   # the gamepad's "forward" is +X: away from Charizard
			b.ctrl.move_input = Vector2(0, 1)
			b.ctrl.press("dodge")
		if i == 75:
			after_x = b.global_position.x
	a.ctrl.release("mov1")
	b.ctrl.move_input = Vector2.ZERO
	var traveled := absf(after_x - before_x)
	var dodge_total: float = b.data.dodge.dist
	_ok("Inside Flamethrower, dodging backward does not leave the cone",
		# The dodge covers half; the stream also pushes back a little.
		after_x > before_x and traveled < dodge_total * 0.85 and after_x - a.global_position.x < Moves.DATA.flamethrower.length,
		"travels %.1f m of %.1f; ends %.1f m away (the stream reaches %.1f)" % [traveled, dodge_total, after_x - a.global_position.x, Moves.DATA.flamethrower.length])
	# 4d. Flight: Charizard takes off (jump and air jump), stays up and falls without stamina.
	ab = await _setup("charizard", "pikachu", Vector3(-6, 0, 0), Vector3(6, 0, 0))
	a = ab[0]
	b = ab[1]
	a.ctrl.press("jump")
	await _wait(0.25)
	a.ctrl.press("jump")
	await _wait(0.1)
	var takeoff: bool = a.flying
	for i in 40:
		a.ctrl.held["jump"] = true
		await get_tree().physics_frame
	await _wait(1.0)
	var flight_height: float = a.global_position.y
	var poise_before: float = a.flight
	_ok("Flight: takes off and stays in the air", takeoff and a.flying and flight_height > 2.0, "height %.1f m, stamina %.1f" % [flight_height, poise_before])
	await _wait(a.flight + 1.5)
	_ok("Flight: without stamina it stops flying and falls", not a.flying and a.global_position.y < 0.3, "height %.1f m" % a.global_position.y)
	# 4e. Ground move in the air: Earthquake during a jump dives down and fires on landing.
	ab = await _setup("snorlax", "pikachu", Vector3(0, 0, 0), Vector3(6, 0, 0))
	a = ab[0]
	b = ab[1]
	a.ctrl.press("jump")
	await _wait(0.25)
	a.ctrl.press("mov3")
	var saw_dive := false
	var did := false
	for i in 120:
		await get_tree().physics_frame
		if a.state == "dive":
			saw_dive = true
		if a.action and a.action.id == "earthquake":
			did = true
			break
	_ok("Earthquake in the air: dives down and fires on touching the ground", saw_dive and did, "dive %s, earthquake %s" % [saw_dive, did])
	# 4f. Height assist: Blastoise's Hydro Pump reaches a flying Charizard.
	ab = await _setup("blastoise", "charizard", Vector3(-6, 0, 0), Vector3(2, 0, 0))
	a = ab[0]
	b = ab[1]
	b.global_position = Vector3(2, 4.0, 0)
	b.velocity = Vector3.ZERO
	b.reset_physics_interpolation()
	# One frame so it stops counting as grounded; then, fly.
	await get_tree().physics_frame
	await get_tree().physics_frame
	b.flying = true
	a.face_now(b.global_position)
	a.ctrl.press("mov2")
	var impact_height := -1.0
	for i in 90:
		a.ctrl.held["mov2"] = true
		await get_tree().physics_frame
		if impact_height < 0.0 and b.hp < b.hp_max:
			impact_height = b.global_position.y
	a.ctrl.release("mov2")
	_ok("Hydro Pump aims at the flyer's height on its own", impact_height > 3.0, "first impact at %.1f m" % impact_height)
	# 4g. Physical hits with vertical assist: upward, downward and a diagonal dash.
	for case_d in [["charizard", "snorlax", "mov3", Vector3(-2.2, 3.0, 0), Vector3(0, 0, 0), "Flying Charizard's Dragon Claw reaches Snorlax below"],
			["pikachu", "charizard", "mov2", Vector3(-6, 0, 0), Vector3(0, 4.0, 0), "Quick Attack from the ground reaches Charizard in the air"]]:
		ab = await _setup(case_d[0], case_d[1], case_d[3], Vector3(case_d[4].x, 0, 0))
		a = ab[0]
		b = ab[1]
		for l in [a, b]:
			var pos: Vector3 = case_d[3] if l == a else case_d[4]
			l.global_position = pos
			l.velocity = Vector3.ZERO
			l.reset_physics_interpolation()
		await get_tree().physics_frame
		await get_tree().physics_frame
		for l in [a, b]:
			if l.global_position.y > 0.5 and l.data.has("flight"):
				l.flying = true
		a.face_now(b.global_position)
		a.ctrl.press(case_d[2])
		var hit_at := -1.0
		for i in 60:
			await get_tree().physics_frame
			if hit_at < 0.0 and b.hp < b.hp_max:
				hit_at = b.global_position.y - a.global_position.y
		_ok(case_d[5], hit_at != -1.0, "HP %d, height difference on hit %.1f m" % [b.hp, hit_at])
	# 4g2. If the target dodges a dash rising toward it, the attacker does not shoot into the sky.
	ab = await _setup("pikachu", "charizard", Vector3(-2.5, 0, 0), Vector3(0, 0, 0))
	a = ab[0]
	b = ab[1]
	b.global_position = Vector3(0, 4.0, 0)
	b.velocity = Vector3.ZERO
	b.reset_physics_interpolation()
	await get_tree().physics_frame
	await get_tree().physics_frame
	b.flying = true
	a.face_now(b.global_position)
	a.ctrl.press("mov2")
	var ceiling := 0.0
	for i in 70:
		b.invulnerable = 0.1
		await get_tree().physics_frame
		ceiling = maxf(ceiling, a.global_position.y)
	_ok("Dodged dash: does not shoot over the rival", ceiling < b.center().y + 0.5, "max height %.1f m (rival's center at %.1f)" % [ceiling, b.center().y])
	# 4g3. A ground Pokémon does not "fly" chasing a high Charizard: Lucario's Extreme
	# Speed against a rival 8 m up and 9 m away (before the fix it rose to 47 m from
	# inertia) rises at most to its ceiling.
	ab = await _setup("lucario", "charizard", Vector3(-9, 0, 0), Vector3(0, 0, 0))
	a = ab[0]
	b = ab[1]
	b.global_position = Vector3(0, 8.0, 0)
	b.velocity = Vector3.ZERO
	b.reset_physics_interpolation()
	await get_tree().physics_frame
	await get_tree().physics_frame
	b.flying = true
	a.face_now(b.global_position)
	a.ctrl.press("mov3")
	var ceiling_l := 0.0
	for i in 70:
		b.invulnerable = 0.1
		b.velocity = Vector3.ZERO
		b.global_position.y = 8.0
		await get_tree().physics_frame
		ceiling_l = maxf(ceiling_l, a.global_position.y)
	_ok("A ground Pokémon does not fly after a high rival", ceiling_l < a.attack_ceiling() + 0.5, "max height %.1f m (ceiling %.1f, rival at 8)" % [ceiling_l, a.attack_ceiling()])
	# 4h. Flying, attacking makes it stop (it does not carry the movement's inertia).
	ab = await _setup("charizard", "pikachu", Vector3(-6, 3.0, 0), Vector3(6, 0, 0))
	a = ab[0]
	b = ab[1]
	await get_tree().physics_frame
	await get_tree().physics_frame
	a.flying = true
	a.velocity = Vector3(0, 0, 7.0)
	a.ctrl.press("mov1")
	await _wait(0.3)
	var before_z: float = a.global_position.z
	for i in 40:
		a.ctrl.held["mov1"] = true
		await get_tree().physics_frame
	a.ctrl.release("mov1")
	_ok("Flying, Flamethrower does not carry inertia", absf(a.global_position.z - before_z) < 0.6, "moved %.2f m" % absf(a.global_position.z - before_z))
	# 4i. Body Slam lands on a rival that stands still.
	ab = await _setup("snorlax", "pikachu", Vector3(0, 0, 0), Vector3(7, 0, 0))
	a = ab[0]
	b = ab[1]
	a.ctrl.press("mov1")
	await _wait(0.1)
	a.ctrl.release("mov1")
	await _wait(1.6)
	_ok("Body Slam hits a rival that stands still", b.hp < b.hp_max, "HP %d/%d" % [b.hp, b.hp_max])
	# 5. Punishing Body Slam's recovery (0.7 s lying down).
	ab = await _setup("snorlax", "pikachu", Vector3(0, 0, 0), Vector3(9, 0, 0))
	a = ab[0]
	b = ab[1]
	b.invulnerable = 1.6   # so the fall does not knock it down: this tests the punish
	a.ctrl.press("mov1")
	while not (a.action and a.action.id == "bodyslam" and a.action.phase == "recovery"):
		await get_tree().physics_frame
		if t > 30.0:
			break
	b.global_position = a.global_position + Vector3(2.0, 0, 0)
	b.reset_physics_interpolation()
	b.face_now(a.global_position)
	var before := a.hp
	b.ctrl.press("mov2")      # Pikachu's Quick Attack
	await _wait(0.35)
	_ok("Punish during Body Slam's recovery", a.hp < before, "HP %d -> %d" % [before, a.hp])
	# 6. Hitstop and combo limit (the fifth hit knocks down).
	ab = await _setup("pikachu", "snorlax", Vector3(-1.4, 0, 0), Vector3(0.0, 0, 0))
	a = ab[0]
	b = ab[1]
	var pause := false
	var count := [0]
	var lockout := 0.0
	var worst := 0.0
	b.hit_taken.connect(func(_q, _i): count[0] += 1)
	for i in 360:
		# No cooldowns or cost: Thunder Shock and Iron Tail nonstop, the worst case.
		a.cds.clear()
		a.energy = Fighter.ENERGY_MAX
		if i % 6 == 0:
			a.ctrl.press("mov1" if (i / 6) % 2 == 0 else "mov3")
		# The attacker chases to try to combo forever.
		var toward := b.global_position - a.global_position
		a.ctrl.yaw = atan2(-toward.x, -toward.z)
		a.ctrl.move_input = Vector2(0, 1) if toward.length() > 1.6 else Vector2.ZERO
		await get_tree().physics_frame
		if a.frozen():
			pause = true
		if b.state in ["stunned", "knocked_down", "lying"]:
			lockout += get_physics_process_delta_time()
			worst = maxf(worst, lockout)
		else:
			lockout = 0.0
	_ok("Hitstop on hit", pause)
	_ok("No infinite chains: the longest lockdown is short", worst < 3.0 and count[0] > 3, "%d hits, max lockdown %.1f s" % [count[0], worst])
	# 7. After a KO nothing stays active.
	b.hp = 1.0
	a.ctrl.press("mov1")
	await _wait(2.0)
	main.rematch()
	await get_tree().physics_frame
	_ok("After KO and rematch no hits or projectiles remain", main.combat.hits.is_empty() and main.combat.projectiles.is_empty(),
		"hits %d projectiles %d" % [main.combat.hits.size(), main.combat.projectiles.size()])
	# 8. Floating stadium: standing on the platform holds; a push move by the edge sends
	# the rival into the void and that is a KO (ring-out).
	var stage_before: String = main.arena.stage
	main.set_stage("floating")
	ab = await _setup("snorlax", "pikachu", Vector3(11, 0, 0), Vector3(19, 0, 0))
	a = ab[0]
	b = ab[1]
	await _wait(0.5)
	var y_on: float = b.global_position.y
	var stands: bool = absf(y_on) < 0.2 and main.arena.inside(b.global_position)
	a.ctrl.press("mov1")
	await _wait(0.15)
	a.ctrl.release("mov1")
	await _wait(3.5)
	_ok("Floating stadium: the platform holds the fighters", stands, "y %.2f" % y_on)
	_ok("Floating stadium: knocked off the edge is a KO", b.state == "ko" and b.global_position.y < 0.0,
		"state %s, position %s" % [b.state, b.global_position])
	# 9. A move never carries its user off (Extreme Speed toward the edge stops at it), but
	# dodging out or walking out does fall.
	ab = await _setup("lucario", "snorlax", Vector3(14, 0, 0), Vector3(21, 0, 0))
	a = ab[0]
	a.ctrl.press("mov3")
	await _wait(0.15)
	a.ctrl.release("mov3")
	await _wait(2.0)
	_ok("Floating stadium: Extreme Speed toward the edge stops at it", a.state != "ko" and a.global_position.y > -0.5,
		"state %s, position %s" % [a.state, a.global_position.snapped(Vector3.ONE * 0.1)])
	ab = await _setup("pikachu", "snorlax", Vector3(22, 0, 0), Vector3(0, 0, 0))
	a = ab[0]
	a.locked = false
	a.ctrl.yaw = -PI * 0.5           # facing +X, toward the edge
	a.ctrl.move_input = Vector2(0, 1)
	a.ctrl.press("dodge")
	await _wait(2.5)
	a.ctrl.move_input = Vector2.ZERO
	_ok("Floating stadium: dodging out of the edge falls", a.state == "ko", "state %s" % a.state)
	ab = await _setup("snorlax", "pikachu", Vector3(21, 0, 0), Vector3(0, 0, 0))
	a = ab[0]
	a.locked = false
	a.ctrl.yaw = -PI * 0.5
	a.ctrl.move_input = Vector2(0, 1)
	await _wait(3.0)
	a.ctrl.move_input = Vector2.ZERO
	_ok("Floating stadium: walking out of the edge falls", a.state == "ko", "state %s" % a.state)
	# 10. Flyers knocked off fly back (the AI recovers): Charizard and Gengar.
	for flyer in ["charizard", "gengar"]:
		ab = await _setup("snorlax", flyer, Vector3(14.5, 0, 0), Vector3(22.5, 0, 0))
		a = ab[0]
		b = ab[1]
		a.ctrl.press("mov1")
		await _wait(0.15)
		a.ctrl.release("mov1")
		var went_off := false
		var t0 := t
		while t - t0 < 1.5:
			await get_tree().physics_frame
			if not main.arena.inside(b.global_position, 0.0):
				went_off = true
		main.ai.mode = "active"          # from now on the AI plays it: it has to fly back
		await _wait(6.0)
		var back: bool = b.state != "ko" and b.global_position.y > -0.5 and main.arena.inside(b.global_position, -0.5)
		_ok("Floating stadium: %s knocked off flies back" % flyer, went_off and back,
			"off %s, state %s, position %s" % [went_off, b.state, b.global_position.snapped(Vector3.ONE * 0.1)])
		main.ai.mode = "still"
	main.set_stage(stage_before)
	var fails := _results.filter(func(r): return not r[1]).size()
	print("RESULT: %d of %d" % [_results.size() - fails, _results.size()])
	get_tree().quit()


# ---------------------------------------------------------------- trainers

## Trainers on both stages: the opening (throws, the Pokémon coming out), a wide shot with
## both trainers, your own from behind your Pokémon, their reactions and the end. Checks
## that they stand out of reach, that nobody moves during the opening and that both
## Pokémon are out when it ends. Rendered (not headless) for the pictures.
func _trainers_test() -> void:
	await get_tree().physics_frame
	main._args["intro"] = "1"
	for stage in ["night", "floating"]:
		main.set_stage(stage)
		main.start_battle("pikachu", "charizard", "normal")
		var a: Fighter = main.fighters[0]
		var b: Fighter = main.fighters[1]
		main.ai.mode = "still"
		a.is_player = false
		var b_start := b.global_position
		var strip: Array = []
		var times := [0.15, 0.4, 0.6, 0.8, 1.05, 1.3, 1.6, 2.1]
		var t0 := t
		for tt in times:
			await _wait(t0 + tt - t)
			if DisplayServer.get_name() != "headless":
				var im := get_viewport().get_texture().get_image()
				im.resize(im.get_width() / 2, im.get_height() / 2, Image.INTERPOLATE_BILINEAR)
				strip.append(im)
		_ok("%s: nobody moves during the opening" % stage, b.global_position.distance_to(b_start) < 0.2, "%.2f m" % b.global_position.distance_to(b_start))
		await _wait(main.INTRO + 0.25 - (t - t0))
		_capture("trainers_%s_start" % stage)
		_ok("%s: both Pokémon are out after the opening" % stage, a.appear >= 1.0 and b.appear >= 1.0 and main.intro_t <= 0.0, "%.2f %.2f" % [a.appear, b.appear])
		var limit := 19.5 if stage == "night" else FloatingStadium.PLAT_X + 2.0
		_ok("%s: trainers stand out of reach" % stage, main.trainers.size() == 2 and main.trainers.all(func(tr): return absf(tr.global_position.x) > limit), str(main.trainers.map(func(tr): return tr.global_position.x)))
		if strip.size() == 8:
			var w: int = strip[0].get_width()
			var h: int = strip[0].get_height()
			var sheet := Image.create(w * 4, h * 2, false, strip[0].get_format())
			for i in 8:
				sheet.blit_rect(strip[i], Rect2i(0, 0, w, h), Vector2i((i % 4) * w, (i / 4) * h))
			sheet.save_png(_dir().path_join("trainers_%s_intro.png" % stage))
		# Wide: both trainers and the field, from the side.
		main.camera.target = null
		main.camera.global_position = Vector3(0, 11, 14)
		main.camera.look_at(Vector3(0, 0, -2), Vector3.UP)
		await _wait(0.3)
		_capture("trainers_%s_wide" % stage)
		# Your own trainer, seen from your Pokémon's side of the field.
		main.camera.global_position = a.global_position + Vector3(-4.0 * signf(a.global_position.x), 3.0, 4.0)
		main.camera.look_at(main.trainers[0].global_position + Vector3.UP * 1.0, Vector3.UP)
		await _wait(0.3)
		_capture("trainers_%s_mine" % stage)
		# Reactions: your Pokémon hits (your trainer cheers, theirs flinches), then KOs.
		main.camera.target = a
		a.locked = true
		b.hp = 1.0
		a.ctrl.press("mov1")
		await _wait(0.1)
		a.ctrl.release("mov1")
		await _wait(2.0)
		main.camera.target = null
		main.camera.global_position = Vector3(0, 11, 14)
		main.camera.look_at(Vector3(0, 0, -2), Vector3.UP)
		await _wait(0.3)
		_capture("trainers_%s_end" % stage)
		main.camera.target = a
		Engine.time_scale = 1.0
	var fails := _results.filter(func(r): return not r[1]).size()
	print("RESULT: %d of %d" % [_results.size() - fails, _results.size()])
	get_tree().quit()


# ---------------------------------------------------------------- League stadium

## The League stadium: pictures (wide, from behind the player, the field closing in) and
## the closing field's rules: its radius over time, damage outside and none inside.
func _league_test() -> void:
	await get_tree().physics_frame
	var stage_id := "league"
	main.set_stage(stage_id)
	main.start_battle("pikachu", "charizard", "normal")
	var a: Fighter = main.fighters[0]
	var b: Fighter = main.fighters[1]
	main.ai.mode = "still"
	a.is_player = false
	var st: LeagueStadium = main.arena
	_ok("Field radius over time", is_equal_approx(LeagueStadium.radius_at(0.0), 16.0) and is_equal_approx(LeagueStadium.radius_at(40.0), 12.5)
		and is_equal_approx(LeagueStadium.radius_at(300.0), 5.0) and LeagueStadium.radius_at(32.5) < 16.0 and LeagueStadium.radius_at(32.5) > 12.5,
		"%.1f %.1f %.1f" % [LeagueStadium.radius_at(0.0), LeagueStadium.radius_at(32.5), LeagueStadium.radius_at(40.0)])
	await _wait(1.0)
	_capture(stage_id + "_battle")
	main.camera.target = null
	main.camera.global_position = Vector3(-13.0, 10.0, 13.0)
	main.camera.look_at(Vector3(3.0, 2.0, -8.0), Vector3.UP)
	await _wait(0.5)
	_capture(stage_id + "_wide")
	main.camera.global_position = Vector3(0.0, 4.0, 14.0)
	main.camera.look_at(Vector3(0.0, 10.0, -26.0), Vector3.UP)
	await _wait(0.4)
	_capture(stage_id + "_statues")
	main.camera.global_position = Vector3(-6.0, 9.0, 8.0)
	main.camera.look_at(Vector3(-24.0, 13.0, 12.0), Vector3.UP)
	await _wait(0.4)
	_capture(stage_id + "_sails")
	main.camera.global_position = Vector3(0.0, 16.0, 26.0)
	main.camera.look_at(Vector3(0.0, 4.0, -10.0), Vector3.UP)
	await _wait(0.4)
	_capture(stage_id + "_canopy")
	# The next ring announced, then closing.
	st.zone_t = 27.5
	main.camera.global_position = Vector3(-13.0, 10.0, 13.0)
	main.camera.look_at(Vector3(2.0, 0.0, -2.0), Vector3.UP)
	await _wait(0.6)
	_capture(stage_id + "_warning")
	st.zone_t = 33.0
	await _wait(0.6)
	_capture(stage_id + "_closing")
	st.zone_t = 60.0
	await _wait(0.3)
	# The wall: whoever is past it is put back inside, with no damage.
	a.global_position = Vector3(0.0, 0.0, 3.0)
	b.global_position = Vector3(14.0, 0.0, 0.0)
	var hb := b.hp
	await _wait(0.5)
	var rb := Vector2(b.global_position.x, b.global_position.z).length()
	_ok("The wall keeps it inside", rb <= st.zone_r + 0.05, "%.2f m, ring %.2f m" % [rb, st.zone_r])
	_ok("The wall does no damage", b.hp == hb, "%d -> %d" % [hb, b.hp])
	# After the final blow the field stops closing.
	var frozen := st.zone_t
	st._win_t = 0.0
	await _wait(0.5)
	_ok("The field stops closing after the battle", is_equal_approx(st.zone_t, frozen), "%.2f -> %.2f" % [frozen, st.zone_t])
	st._win_t = -1.0
	_capture(stage_id + "_outside")
	# Playing near the closed edge: the camera behind you, out past the aurora.
	main.camera.target = a
	a.locked = true
	a.global_position = Vector3(0.0, 0.0, 7.5)
	b.global_position = Vector3(0.0, 0.0, -3.0)
	await _wait(1.2)
	_capture(stage_id + "_camera_out")
	main.camera.target = null
	main.camera.global_position = Vector3(0.0, 2.2, 15.5)
	main.camera.look_at(Vector3(0.0, 1.0, 0.0), Vector3.UP)
	await _wait(0.3)
	_capture(stage_id + "_aurora")
	main.camera.target = a
	var fails := _results.filter(func(r): return not r[1]).size()
	print("RESULT: %d of %d" % [_results.size() - fails, _results.size()])
	get_tree().quit()


# ---------------------------------------------------------------- lock-on and free aim

## Substitute locks the rival on the doll; a flick switches to the real one and back; when
## the doll goes, the camera is free. Free, a shot leaves where the camera looks and still
## follows its target. Locking on picks what the camera looks at.
func _lockon_test() -> void:
	await get_tree().physics_frame
	var ab: Array = await _setup("pikachu", "gengar", Vector3(-5, 0, 0), Vector3(3, 0, 0))
	var a: Fighter = ab[0]
	var b: Fighter = ab[1]
	a.locked = true
	a.ctrl.yaw = atan2(-(b.global_position - a.global_position).x, -(b.global_position - a.global_position).z)
	b.ctrl.press("mov4")
	await _wait(0.1)
	b.ctrl.release("mov4")
	await _wait(0.5)
	var decoy: Node3D = a.aim_target()
	_ok("Substitute locks the rival on its doll", decoy is Decoy, str(decoy))
	a.switch_target(1)
	var after_right: Node3D = a.aim_target()
	a.switch_target(-1)
	var after_left: Node3D = a.aim_target()
	_ok("A flick switches between the doll and the real one", (after_right == b) != (after_left == b) or after_right == b or after_left == b,
		"right %s, left %s" % [after_right, after_left])
	# Back on the doll, then it goes: the camera is free.
	if a.aim_target() == b:
		a.switch_target(1)
		if a.aim_target() == b:
			a.switch_target(-1)
	if is_instance_valid(decoy):
		decoy.undo()
	await _wait(0.2)
	_ok("When the doll goes, the lock goes", not a.locked, "locked %s" % a.locked)
	# Free aim: looking 90 degrees off the rival, the shot leaves where the camera looks.
	ab = await _setup("pikachu", "snorlax", Vector3(-5, 0, 0), Vector3(3, 0, 0))
	a = ab[0]
	b = ab[1]
	a.locked = false
	var toward: Vector3 = (b.global_position - a.global_position).normalized()
	var side := Vector3(-toward.z, 0.0, toward.x)
	a.ctrl.yaw = atan2(-side.x, -side.z)
	await _wait(0.3)
	a.ctrl.press("mov1")
	await _wait(0.05)
	a.ctrl.release("mov1")
	var shot_dir := Vector3.ZERO
	var follows := false
	for k in 40:
		await get_tree().physics_frame
		for p in main.combat.projectiles:
			if p.user == a:
				shot_dir = p.velocity.normalized()
				follows = p.target == b
		if shot_dir != Vector3.ZERO:
			break
	_ok("Free camera: the shot leaves where the camera looks and still follows", shot_dir.dot(side) > 0.7 and follows,
		"dot %.2f, follows %s" % [shot_dir.dot(side), follows])
	# Locking on picks what the camera looks at.
	a.ctrl.yaw = atan2(-toward.x, -toward.z)
	a.lock_on_looked()
	_ok("Locking on picks what the camera looks at", a.locked and a.aim_target() == b, str(a.aim_target()))
	var fails := _results.filter(func(r): return not r[1]).size()
	print("RESULT: %d of %d" % [_results.size() - fails, _results.size()])
	get_tree().quit()
