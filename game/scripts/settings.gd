class_name Settings
extends Node
## The player's options, saved in user://settings.cfg and applied when loaded and on every
## change: the battle controls (each action on keyboard and on gamepad), music and effects
## volume, window mode, vertical sync and frame cap, camera shake, rumble and language.
## The Options screen (Menu, drawn by MenuDraw) works through items(), menu_input() and
## menu_event(). Tests start from the defaults and never save, so a player's settings
## never change what a test sees.

const PATH := "user://settings.cfg"
const ROWS := 12                     # rows shown at once on the screen (it scrolls)
const BINDABLE := ["jump", "dodge", "lock_on", "mov1", "mov2", "mov3", "mov4", "descend", "pause"]
const FPS_CAPS := [0, 60, 120, 144, 240]
const LANGUAGES := ["", "en", "es"]

var main: Node
var rumble := true
var shake := 1.0
var music := 0.5
var sfx := 1.0
var fullscreen := true
var vsync := true
var fps_cap := 0
var language := ""
var trainer := TrainerData.DEFAULT     # the profile: which trainer you are
var player_name := ""                  # and your name (empty: the trainer's)
var bindings := {}                   # action -> {"kb": data, "pad": data} (Controls.to_data)
var cursor := 1
var top := 0
var waiting := ""                    # the action waiting for a key or button
var _guard := 0.0
var _saving := true


func load_saved() -> void:
	if main._args.has("test") or main._args.has("aivsai"):
		_saving = false
		Audio.set_bus_volume("SFX", sfx)
		Audio.set_bus_volume("Music", music)
		return
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		# No saved options yet: the defaults, volumes included, still go into effect.
		Audio.set_bus_volume("SFX", sfx)
		Audio.set_bus_volume("Music", music)
		return
	rumble = cf.get_value("game", "rumble", rumble)
	shake = cf.get_value("game", "shake", shake)
	language = cf.get_value("game", "language", language)
	trainer = TrainerData.valid(cf.get_value("profile", "trainer", trainer))
	player_name = str(cf.get_value("profile", "name", player_name)).substr(0, Menu.NAME_MAX)
	music = cf.get_value("sound", "music", music)
	sfx = cf.get_value("sound", "sfx", sfx)
	fullscreen = cf.get_value("screen", "fullscreen", fullscreen)
	vsync = cf.get_value("screen", "vsync", vsync)
	fps_cap = cf.get_value("screen", "fps_cap", fps_cap)
	bindings = cf.get_value("controls", "bindings", {})
	apply(true)


func save() -> void:
	if not _saving:
		return
	var cf := ConfigFile.new()
	cf.set_value("game", "rumble", rumble)
	cf.set_value("game", "shake", shake)
	cf.set_value("game", "language", language)
	cf.set_value("profile", "trainer", trainer)
	cf.set_value("profile", "name", player_name)
	cf.set_value("sound", "music", music)
	cf.set_value("sound", "sfx", sfx)
	cf.set_value("screen", "fullscreen", fullscreen)
	cf.set_value("screen", "vsync", vsync)
	cf.set_value("screen", "fps_cap", fps_cap)
	cf.set_value("controls", "bindings", bindings)
	cf.save(PATH)


## Puts everything into effect. "screen" also sets the window (only when loading or when
## the player changes it: the command line's window stays otherwise).
func apply(screen := false) -> void:
	Audio.set_bus_volume("SFX", sfx)
	Audio.set_bus_volume("Music", music)
	if screen and DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
		# "Mailbox" when on: it does not wait on the frame queue (less input lag) and does not tear.
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_MAILBOX if vsync else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = fps_cap
	if language != "":
		TranslationServer.set_locale(language)
	Controls.configure()
	for action in bindings:
		for kind in ["kb", "pad"]:
			var ev := Controls.from_data(bindings[action].get(kind, []))
			if ev:
				Controls.rebind(action, ev)


# ---------------------------------------------------------------- the Options screen

## Rows of the screen: {id, kind (header, bind, slider, toggle, choice, action), label,
## value (already translated), help}.
func items() -> Array:
	var out: Array = []
	out.append({"id": "h_controls", "kind": "header", "label": tr("Controls")})
	for a in BINDABLE:
		var kb := ""
		var pad := ""
		for ev in InputMap.action_get_events(a):
			if Controls.is_pad(ev):
				pad = Controls.event_name(ev, "playstation" if Controls.last_device == "playstation" else "xbox")
			else:
				kb = Controls.event_name(ev)
		out.append({"id": a, "kind": "bind", "label": _action_name(a), "value": "%s  /  %s" % [kb, pad],
			"help": tr("Press to change it, then press the new key or button: a key changes the keyboard's, a button the gamepad's. Esc cancels.")})
	out.append({"id": "reset_controls", "kind": "action", "label": tr("Default controls"), "value": "",
		"help": tr("Puts every action back on its usual key and button.")})
	out.append({"id": "h_sound", "kind": "header", "label": tr("Sound")})
	out.append({"id": "music", "kind": "slider", "label": tr("Music"), "value": "%d%%" % roundi(music * 100.0),
		"help": tr("Volume of the music in the menus and battles.")})
	out.append({"id": "sfx", "kind": "slider", "label": tr("Effects"), "value": "%d%%" % roundi(sfx * 100.0),
		"help": tr("Volume of moves, hits, cries and the crowd.")})
	out.append({"id": "h_screen", "kind": "header", "label": tr("Screen")})
	out.append({"id": "fullscreen", "kind": "toggle", "label": tr("Full screen"),
		"value": tr("On") if fullscreen else tr("Off"), "help": tr("Full screen or a window.")})
	out.append({"id": "vsync", "kind": "toggle", "label": tr("Vertical sync"),
		"value": tr("On") if vsync else tr("Off"), "help": tr("Stops tearing; off can lower the delay a little.")})
	out.append({"id": "fps_cap", "kind": "choice", "label": tr("Frame limit"),
		"value": tr("None") if fps_cap == 0 else "%d" % fps_cap, "help": tr("Highest frames per second.")})
	out.append({"id": "h_game", "kind": "header", "label": tr("Game")})
	out.append({"id": "shake", "kind": "slider", "label": tr("Camera shake"), "value": "%d%%" % roundi(shake * 100.0),
		"help": tr("How much the camera shakes on hits.")})
	out.append({"id": "rumble", "kind": "toggle", "label": tr("Rumble"),
		"value": tr("On") if rumble else tr("Off"), "help": tr("The gamepad rumbles on hits.")})
	out.append({"id": "language", "kind": "choice", "label": tr("Language"),
		"value": {"": tr("System"), "en": "English", "es": "Español"}[language], "help": tr("The game's language.")})
	return out


func _action_name(a: String) -> String:
	match a:
		"jump": return tr("Jump")
		"dodge": return tr("Dodge")
		"lock_on": return tr("Lock on")
		"mov1": return tr("Move 1")
		"mov2": return tr("Move 2")
		"mov3": return tr("Move 3")
		"mov4": return tr("Move 4")
		"descend": return tr("Descend (flying)")
		"pause": return tr("Pause")
	return a


func menu_input(menu: Menu) -> void:
	_guard = maxf(0.0, _guard - get_process_delta_time())
	if waiting != "" or _guard > 0.0:
		return
	var list := items()
	var n := list.size()
	var before := cursor
	if menu._pressed("move_up"):
		cursor = _next(list, cursor, -1)
	elif menu._pressed("move_down"):
		cursor = _next(list, cursor, 1)
	if cursor != before:
		menu._sound("move")
		top = clampi(top, cursor - ROWS + 1, cursor)
		if cursor == 1:
			top = 0
	var it: Dictionary = list[cursor]
	var step := 0
	if menu._pressed("move_left"):
		step = -1
	elif menu._pressed("move_right"):
		step = 1
	if step != 0 and it.kind in ["slider", "choice", "toggle"]:
		_change(it.id, step)
		menu._sound("move")
	if menu._accept():
		match it.kind:
			"bind":
				waiting = it.id
				menu._sound("ok")
			"action":
				bindings.clear()
				apply()
				save()
				menu._sound("ok")
			"slider", "choice", "toggle":
				_change(it.id, 1)
				menu._sound("move")
	elif menu._pressed("menu_back"):
		menu._sound("back")
		save()
		menu._go("main")
	if n == 0:
		return


func _next(list: Array, i: int, step: int) -> int:
	var j := i
	for k in list.size():
		j = (j + step + list.size()) % list.size()
		if list[j].kind != "header":
			return j
	return i


func _change(id: String, step: int) -> void:
	match id:
		"music":
			music = clampf(snappedf(music + 0.1 * step, 0.1), 0.0, 1.0)
		"sfx":
			sfx = clampf(snappedf(sfx + 0.1 * step, 0.1), 0.0, 1.0)
		"shake":
			shake = clampf(snappedf(shake + 0.25 * step, 0.25), 0.0, 1.0)
		"rumble":
			rumble = not rumble
		"fullscreen":
			fullscreen = not fullscreen
			apply(true)
		"vsync":
			vsync = not vsync
			apply(true)
		"fps_cap":
			fps_cap = FPS_CAPS[(FPS_CAPS.find(fps_cap) + step + FPS_CAPS.size()) % FPS_CAPS.size()]
		"language":
			language = LANGUAGES[(LANGUAGES.find(language) + step + LANGUAGES.size()) % LANGUAGES.size()]
			TranslationServer.set_locale(language if language != "" else OS.get_locale_language())
	apply()
	save()


## While waiting for a binding: the next key, mouse button, gamepad button or trigger.
func menu_event(menu: Menu, ev: InputEvent) -> void:
	if waiting == "":
		return
	var take: InputEvent = null
	if ev is InputEventKey and ev.pressed and not ev.echo:
		if ev.physical_keycode == KEY_ESCAPE:
			waiting = ""
			_guard = 0.2
			menu.get_viewport().set_input_as_handled()
			return
		take = ev
	elif ev is InputEventMouseButton and ev.pressed and ev.button_index not in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		take = ev
	elif ev is InputEventJoypadButton and ev.pressed:
		take = ev
	elif ev is InputEventJoypadMotion and ev.axis in [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT] and absf(ev.axis_value) > 0.6:
		take = ev
	if take == null:
		return
	Controls.rebind(waiting, take)
	var b: Dictionary = bindings.get(waiting, {})
	b["pad" if Controls.is_pad(take) else "kb"] = Controls.to_data(take)
	bindings[waiting] = b
	waiting = ""
	_guard = 0.3
	save()
	menu._sound("ok")
	menu.get_viewport().set_input_as_handled()


## The name shown for you: the one you typed, or your trainer's.
func shown_name() -> String:
	return player_name if player_name.strip_edges() != "" else tr(TrainerData.LIST[trainer].name)
