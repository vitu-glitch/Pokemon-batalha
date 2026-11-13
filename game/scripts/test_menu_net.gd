extends Node
## Online test through the menu (two copies at once):
##   godot --path game -- --test=menu_net --role=host --bot
##   godot --headless --path game -- --test=menu_net --role=guest --bot
## Each copy presses the buttons like a player: title, Online, Host game or Join
## (types 127.0.0.1 on the keyboard), picks a Pokémon, ready, VS, battle. After the
## first KO the host goes back to selection; both pick another, the host picks the floating
## stage (the guest must get it too), another battle, and at
## the end the host leaves: the guest must return to the online menu with the notice.
## Prints a MENU_NET_FINAL line to compare both copies.

const CHOOSES := {"host": ["charizard", "gengar"], "guest": ["lucario", "pikachu"]}

var main: Node
var role := "host"
var _t := 0.0
var _wait_t := 0.0
var _round := 0                  # 0: first pick, 1: second
var _combat_t := -1.0
var _typed := false
var _captures := {}
var _steps: Array = []
var _battles: Array = []
var _end := ""
var _states_at_start := 0     # net.states_applied when the battle started
var _last := {}                # HP and state of the last battle frame


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	role = main._args.get("role", "host")


func _step(text: String) -> void:
	if _steps.is_empty() or _steps.back() != text:
		_steps.append(text)
		print("MENU_NET %s t=%.1f %s" % [role, _t, text])


func _press(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	Input.action_press(action)
	get_tree().create_timer(0.05, true, false, true).timeout.connect(func(): Input.action_release(action))
	_wait_t = 0.3


func _key(source: Key, text := "") -> void:
	var ev := InputEventKey.new()
	ev.keycode = source
	ev.physical_keycode = source
	ev.unicode = text.unicode_at(0) if text != "" else 0
	ev.pressed = true
	Input.parse_input_event(ev)


func _capture(n: String) -> void:
	if _captures.has(n) or DisplayServer.get_name() == "headless":
		return
	_captures[n] = true
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://").path_join("../captures/net_%s_%s.png" % [role, n]))


func _physics_process(delta: float) -> void:
	_t += delta
	if _t > 150.0:
		_finish("timed out at: " + str(_steps.back() if not _steps.is_empty() else "start"))
		return
	_wait_t -= delta
	if _wait_t > 0.0:
		return
	var m: Menu = main.menu
	if m.is_open:
		_menu(m)
	else:
		_combat(delta)


func _menu(m: Menu) -> void:
	match m.screen:
		"title":
			_step("title")
			_press("menu_accept")
		"main":
			_step("main")
			_go_to(m, m.MAIN_MENU, "online")
		"online":
			if _combat_t >= 0.0:
				_round_end()
			if _round >= 2:
				# After the disconnect: the notice must be on screen.
				_step("back in Online: \"%s\"" % m.message)
				_capture("disconnection")
				_finish("" if m.message != "" else "no disconnect notice")
				return
			_step("online")
			_go_to(m, m.ONLINE, "create" if role == "host" else "join")
		"waiting":
			_step("waiting for the guest")
			if m._t > 6.0:
				_capture("waiting")
		"join":
			_step("join")
			if not _typed:
				_typed = true
				for i in 20:
					_key(KEY_BACKSPACE)
				for ch in "127.0.0.1":
					_key(KEY_PERIOD if ch == "." else (KEY_0 + int(ch)) as Key, ch)
				_wait_t = 0.4
				return
			_capture("join")
			_key(KEY_ENTER)
			_wait_t = 0.5
		"connecting":
			_step("connecting")
		"selection":
			if _combat_t >= 0.0:
				# The other one went back to selection before the end was seen here.
				_round_end()
				return
			if _round >= 2:
				return
			# Second battle: the host changes the stage (mov2) to the floating one.
			if role == "host" and _round == 1 and m.choice.stage != "floating":
				_press("mov2")
				return
			# Picked: on the options, Ready is already highlighted.
			if m.sel_phase == "setup":
				if not m.me_ready:
					_press("menu_accept")
				elif m.rival_choice_id != "":
					_capture("selection_%d" % (_round + 1))
				return
			var want: String = CHOOSES[role][_round]
			_step("selection %d: want %s" % [_round + 1, want])
			if m.me_ready:
				if m.rival_choice_id != "":
					_capture("selection_%d" % (_round + 1))
				return
			var list := m.pokemon_list()
			var target := list.find(want)
			if m.cursor == target:
				_press("menu_accept")
			elif target / m.COLUMNS > m.cursor / m.COLUMNS:
				_press("move_down")
			elif target / m.COLUMNS < m.cursor / m.COLUMNS:
				_press("move_up")
			else:
				_press("move_right" if target > m.cursor else "move_left")
		"vs":
			_step("VS %s vs %s" % m._vs)
			_capture("vs_%d" % (_round + 1))


func _go_to(m: Menu, list: Array, id: String) -> void:
	var i := list.map(func(e): return e[0]).find(id)
	if m.cursor == i:
		_press("menu_accept")
	else:
		_press("move_right")          # Online and Join are to the right of the first tile


func _combat(delta: float) -> void:
	var net: Net = main.net
	if net == null:
		if _round >= 2 and role == "host":
			_finish("")
		return
	if not net.in_battle or net.local == null or not is_instance_valid(net.remote):
		return
	var l: Fighter = net.local
	var r: Fighter = net.remote
	if _combat_t < 0.0:
		_combat_t = 0.0
		_step("battle %d: me %s, rival %s, ping %d ms" % [_round + 1, l.species, r.species, net.ping_ms()])
		_states_at_start = net.states_applied
		var expected: Array = [CHOOSES[role][_round], CHOOSES["guest" if role == "host" else "host"][_round]]
		if [l.species, r.species] != expected:
			_finish("species swapped: %s, expected %s" % [[l.species, r.species], expected])
			return
		# Both play on the stage the host picked.
		var want_stage := "floating" if _round == 1 else "night"
		_step("stage %s" % main.arena.stage)
		# Each side's moves: the rival's must be what it saved (it sends them with its choice).
		_step("moves: me %s, rival %s" % [",".join(l.data.moves), ",".join(r.data.moves)])
		if main.arena.stage != want_stage:
			_finish("battle %d on stage %s, expected %s" % [_round + 1, main.arena.stage, want_stage])
			return
	_combat_t += delta
	_last = {"me_ko": l.state == "ko", "my_hp": int(l.hp), "rival_hp": int(r.hp)}
	if _combat_t > 3.0:
		_capture("combat_%d" % (_round + 1))
	# To avoid waiting for a whole battle: at 10 s each side drops itself to 1 HP
	# (each copy controls its own); the next hit ends it.
	if _combat_t > 10.0 and _combat_t - delta <= 10.0:
		l.hp = minf(l.hp, 1.0)
	# In sync: the rival's states keep arriving during the battle, also after "pick another".
	if _combat_t > 8.0 and _combat_t - delta <= 8.0 and net.states_applied - _states_at_start < 120:
		_finish("battle %d out of sync: only %d rival states applied in 8 s" % [_round + 1, net.states_applied - _states_at_start])
		return
	if main._end_t > main.CHOICES_AT + 0.3:
		_round_end()
		if role == "host":
			if _round == 1:
				_press("menu_back")          # both go back to pick
			else:
				main.back_to_menu()           # leaves: the other gets the disconnect
				_finish("")
		else:
			_wait_t = 1.0
	elif _combat_t > 60.0:
		_finish("battle %d does not end" % (_round + 1))


func _round_end() -> void:
	var winner := "rival" if _last.get("me_ko", false) else "me"
	_battles.append({"round": _round + 1, "winner": winner, "my_hp": _last.get("my_hp", -1), "rival_hp": _last.get("rival_hp", -1)})
	_step("KO in battle %d: %s wins (my HP %d, rival HP %d)" % [_round + 1, winner, _last.get("my_hp", -1), _last.get("rival_hp", -1)])
	_capture("ko_%d" % (_round + 1))
	_combat_t = -1.0
	_round += 1


func _finish(error: String) -> void:
	if _end != "":
		return
	_end = "ok" if error == "" else error
	var data := {"role": role, "result": _end, "battles": _battles, "steps": _steps.size()}
	print("MENU_NET_FINAL ", JSON.stringify(data))
	get_tree().create_timer(0.5, true, false, true).timeout.connect(func(): get_tree().quit())
