class_name Menu
extends Node
## Menus: white and clean like Sword and Shield's, laid out like Smash Ultimate's. The
## stage is not behind them: it is only built when the battle starts. Screens:
##   title       the logo; A to enter
##   main        Battle, Online, Training, Moves, Options, Quit
##   online      Host game, Join, Back
##   waiting     host waiting: its IPs and whether the router opened the port
##   join        type the IP (keyboard, or digit by digit with the gamepad)
##   connecting  trying to join someone else's game
##   selection   Pokémon grid on top, each side's pick below with its moves, and the
##               battle's options (stage, difficulty, edit moves, fight). Online: each
##               picks their own and the host picks the stage
##   moves       each Pokémon's four moves and ability, its stats sheet and each move's
##               details (also opened from the selection, for last-minute changes)
##   options     controls, sound, screen and language (Options)
##   vs          both face to face before the battle
## Logic and input live here; MenuDraw draws. Visible text is English and goes through tr()
## when drawn (game/i18n).

const DIFFICULTIES := ["easy", "normal", "hard"]
const DIFFICULTY_NAME := {"easy": "Easy", "normal": "Normal", "hard": "Hard"}
const STAGES := ["night", "floating", "league"]
const STAGE_NAME := {"night": "Night Stadium", "floating": "Floating Stadium", "league": "League Stadium"}
const STAGE_TEXT := {"night": "A Galar stadium at night, packed and walled all round: nobody falls off.",
	"floating": "A platform over the void. Whoever is pushed off the edge is out.",
	"league": "The League's coliseum. The field closes in bit by bit: outside it you lose HP."}
const COLUMNS := 5
const MAIN_MENU := [["combat", "Battle", "Against the AI. Pick your Pokémon, the rival and the difficulty."],
	["online", "Online", "1 vs 1 with a friend over the internet."],
	["training", "Training", "Still or active rival, no rush. R resets, T stops or frees the rival."],
	["moves", "Moves", "Pick each Pokémon's four moves and its ability, and see what each one does."],
	["options", "Options", "Controls, sound, screen and language."],
	["quit", "Quit", "Close the game."],
	["profile", "Profile", "Your trainer and your name. Online, your rival sees them."]]
const ONLINE := [["create", "Host game", "Your friend joins with your IP. Port 7777 (UDP)."],
	["join", "Join", "Type the IP of whoever hosted the game."],
	["back", "Back", ""]]
const IP_CHARS := "0123456789."
## The profile's name: up to NAME_MAX of these (with the pad, each letter goes round them).
const NAME_MAX := 12
const NAME_CHARS := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 -_."
const PROFILE_COLUMNS := 3
## The on-screen keyboard for the name (pad and mouse; the real keyboard types directly):
## four rows of ten keys and a row of four wide ones.
const NAME_KEYS := [["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"], ["A", "S", "D", "F", "G", "H", "J", "K", "L", "Ñ"],
	["Z", "X", "C", "V", "B", "N", "M", "-", "_", "."], ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
	["shift", "space", "del", "done"]]
## The main and online menus are tiles of different sizes (MenuDraw): where each arrow goes
## from each one ([up, down, left, right], -1 stays).
const MAIN_NAV := [[-1, -1, -1, 1], [6, 3, 0, 2], [6, 4, 1, -1], [1, -1, 0, 4], [2, 5, 3, -1], [4, -1, 3, -1], [-1, 2, 1, -1]]
const ONLINE_NAV := [[-1, -1, -1, 1], [-1, 2, 0, -1], [1, -1, 0, -1]]

var main: Node
var is_open := false
var screen := "title"
var cursor := 0
var choice := {"p1": "pikachu", "p2": "snorlax", "diff": "normal", "mode": "combat", "stage": "night"}
var online := false
var sel_phase := "p1"             # p1, p2 (the rival against the AI), setup (options and start)
var setup_cursor := 0
var me_ready := false
var rival_choice_id := ""
var rival_loadout := {}          # the online rival's moves and ability (sent with its choice)
var rival_trainer := ""          # and its trainer
var rival_ready := false
var message := ""                # notices (connection errors, disconnects), already translated
var ip := ""
var confirm := {}                # a yes/no question on top: {text, yes (Callable), on (0 no, 1 yes)}
var portraits := {}               # species -> Texture2D (grid icons)
var enter_t := 0.0               # time on this screen (entry animations)
var draw: MenuDraw
var _key := Vector2i.ZERO        # selected key of the on-screen keypad (column, row)
var _t := 0.0
var _vs_t := -1.0
var _vs := []                    # [mine, theirs] on the VS screen
var _renders := {}               # slot -> {vp, model, species}: live 3D renders on the menus
var _generating := false
# Moves screen: pokemon (list), slots (its 4 + ability), list (options for the slot)
var edit_phase := "pokemon"
var edit_sp := ""
var edit_slot := 0               # 0-3: moves, 4: ability
var edit_cursor := 0             # highlighted option in the list
var edit_top := 0                # first option shown (the list scrolls)
var details := false             # the details panel of the highlighted move
var _edit_return := "main"       # where B leaves the Moves screen to
var rival_name := ""             # the online rival's name
var rival_version := ""          # the online rival's game version ("" until it says)
# Profile screen: -1 is the name, 0.. the trainers' grid.
var profile_cursor := 0
var name_edit := false           # typing the name
var name_key := Vector2i.ZERO    # the on-screen keyboard's key (column 0-9, row 0-4)
var name_lower := false          # its letters in lowercase
var _clicked := false            # a left click on what the pointer is over: accepts, this frame
var _back_click := false         # a right click: back, this frame


func _ready() -> void:
	var saved := _load_ip()
	ip = saved if saved != "" else "192.168.1."
	draw = MenuDraw.new()
	draw.m = self


## Only those with all their moves done (the rest are half finished).
func pokemon_list() -> Array:
	var list: Array = []
	for sp in Roster.POKEMON:
		var data: Dictionary = Roster.POKEMON[sp]
		var ready := true
		for move in data.moves:
			if not Moves.DATA.has(move) or not ResourceLoader.exists(Moves.DATA[move].script):
				ready = false
		if ready:
			list.append(sp)
	return list


# ---------------------------------------------------------------- open and close

func open_menu(en := "") -> void:
	is_open = true
	_t = 0.0
	_vs_t = -1.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	main.camera.target = null
	if main.arena:
		main.arena.visible = false
		# Nothing to show behind the menus: the stage stops (crowd, clocks, the League's field).
		main.arena.process_mode = Node.PROCESS_MODE_DISABLED
	if en == "":
		en = "main" if screen != "title" else "title"
	_go(en)
	if portraits.is_empty() and not _generating:
		_generate_portraits()


func close() -> void:
	is_open = false
	confirm = {}
	_free_renders()
	if main.arena:
		main.arena.visible = true
		main.arena.process_mode = Node.PROCESS_MODE_INHERIT


func _go(p: String) -> void:
	screen = p
	main.music.play(p if p in ["selection", "vs", "moves"] else "menu")
	cursor = 0
	enter_t = 0.0
	details = false
	confirm = {}
	if p == "selection":
		me_ready = false
		sel_phase = "p1"
		cursor = maxi(pokemon_list().find(choice.p1), 0)
		if online:
			if rival_choice_id != "":
				choice.p2 = rival_choice_id
			_send_choice()
	elif p == "profile":
		name_edit = false
		profile_cursor = TrainerData.ids().find(main.options.trainer)
	elif p == "moves":
		edit_phase = "pokemon"
		var list := pokemon_list()
		cursor = maxi(list.find(choice.p1), 0)
		edit_sp = list[cursor]
	elif p != "vs":
		_free_renders()


## Online: once connected, both go on to pick.
func online_connected() -> void:
	online = true
	rival_choice_id = ""
	rival_version = ""
	rival_ready = false
	message = ""
	if not is_open:
		open_menu("selection")
	else:
		_go("selection")


func disconnected(reason: String) -> void:
	online = false
	message = reason
	open_menu("online")


# ---------------------------------------------------------------- input

func _pressed(a: String) -> bool:
	# When the menu opens, the press that opened it (B after an online battle) does
	# not count here: otherwise it would leave the selection right after entering.
	if a == "menu_back" and _back_click:
		return true
	return _t > 0.15 and Input.is_action_just_pressed(a)


func _accept() -> bool:
	return _clicked or _pressed("menu_accept") or _pressed("jump")


func _process(delta: float) -> void:
	_menu_frame(delta)
	_clicked = false
	_back_click = false


func _menu_frame(delta: float) -> void:
	if not is_open:
		return
	_t += delta
	enter_t += delta
	if draw:
		draw.step(delta)
	if _vs_t >= 0.0:
		_vs_t += delta
		if _vs_t > 2.2:
			_vs_t = -1.0
			var vs := _vs.duplicate()
			close()
			if not online:
				main.set_stage(choice.stage)
			main.start_battle(vs[0], vs[1], choice.diff, rival_loadout if online else {}, rival_trainer if online else "")
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	if not confirm.is_empty():
		_confirm_input()
		return
	match screen:
		"title":
			if _accept():
				_sound("ok")
				_go("main")
		"main":
			_move_nav(MAIN_NAV)
			if _accept():
				_sound("ok")
				match MAIN_MENU[cursor][0]:
					"combat", "training":
						online = false
						choice.mode = MAIN_MENU[cursor][0]
						main.mode = choice.mode
						_go("selection")
					"online":
						message = ""
						_go("online")
					"moves":
						_edit_return = "main"
						_go("moves")
					"options":
						_go("options")
					"profile":
						_go("profile")
					"quit":
						get_tree().quit()
			elif _pressed("menu_back"):
				_sound("back")
				_go("title")
		"online":
			_move_nav(ONLINE_NAV)
			if _accept():
				_sound("ok")
				match ONLINE[cursor][0]:
					"create":
						var err: String = main.start_net(true, "")
						message = err
						if err == "":
							_go("waiting")
					"join":
						_go("join")
						_key = Vector2i.ZERO
					"back":
						_go("main")
			elif _pressed("menu_back"):
				_sound("back")
				_go("main")
		"waiting", "connecting":
			if _pressed("menu_back"):
				_sound("back")
				main.close_net()
				_go("online")
		"join":
			_edit_ip_pad()
		"selection":
			_selection()
		"moves":
			_edit_moves()
		"options":
			main.options.menu_input(self)
		"profile":
			_profile_input()


func _move_nav(nav: Array) -> void:
	var to := -1
	for i in 4:
		if _pressed(["move_up", "move_down", "move_left", "move_right"][i]):
			to = nav[cursor][i]
	if to >= 0 and to != cursor:
		cursor = to
		_sound("move")


## Menu sounds: soft and short (move, ok, back).
func _sound(kind := "move") -> void:
	main.audio.ui(kind)


## A yes/no question on top of the screen (leaving an online room...). B or "No" closes it.
func ask(text: String, yes: Callable) -> void:
	confirm = {"text": text, "yes": yes, "on": 0, "t": 0.0}


func _confirm_input() -> void:
	confirm.t += get_process_delta_time()
	if _pressed("move_left") or _pressed("move_right") or _pressed("move_up") or _pressed("move_down"):
		confirm.on = 1 - int(confirm.on)
		_sound("move")
	if _accept():
		var yes: Callable = confirm.yes
		var take: bool = confirm.on == 1
		confirm = {}
		if take:
			_sound("ok")
			yes.call()
		else:
			_sound("back")
	elif _pressed("menu_back"):
		_sound("back")
		confirm = {}


# ---------------------------------------------------------------- IP

## On-screen keypad for the IP. With the gamepad: move between keys, A presses, B deletes
## (and goes back when the IP is empty). With the keyboard: type it, Enter connects,
## Ctrl+V pastes, Esc goes back. Both work at any time.
const KEYPAD := [["1", "2", "3", "del"], ["4", "5", "6", "paste"], ["7", "8", "9", "clear"], [".", "0", "connect", "connect"]]


func _edit_ip_pad() -> void:
	var before := _key
	if _pressed("move_left"):
		_key.x = (_key.x + 3) % 4
	elif _pressed("move_right"):
		_key.x = (_key.x + 1) % 4
	elif _pressed("move_up"):
		_key.y = (_key.y + 3) % 4
	elif _pressed("move_down"):
		_key.y = (_key.y + 1) % 4
	# "Connect" spans two keys: landing on its right half moves to its left half.
	if _key.y == 3 and _key.x == 3:
		_key.x = 2
	if _key != before:
		_sound("move")
	if Controls.last_device != "keyboard":
		if _accept():
			_sound("ok")
			_press_key(KEYPAD[_key.y][_key.x])
		elif _pressed("menu_back"):
			if ip.is_empty():
				_sound("back")
				_go("online")
			else:
				ip = ip.substr(0, ip.length() - 1)


func key_label(k: String) -> String:
	match k:
		"del":
			return "<-"
		"paste":
			return tr("Paste")
		"clear":
			return tr("Clear")
		"connect":
			return tr("Connect")
	return k


func key_on() -> Vector2i:
	return _key


func _press_key(k: String) -> void:
	match k:
		"del":
			ip = ip.substr(0, ip.length() - 1)
		"clear":
			ip = ""
		"paste":
			_paste()
		"connect":
			_connect_peer()
		_:
			if ip.length() < 15:
				ip += k


func _paste() -> void:
	var clean := ""
	for ch in DisplayServer.clipboard_get().strip_edges():
		if IP_CHARS.contains(ch):
			clean += ch
	ip = clean.substr(0, 15)


func _unhandled_input(ev: InputEvent) -> void:
	# (The tests drive the menus with actions: the real pointer resting over their window
	# must not move the cursor.)
	if is_open and (ev is InputEventMouseMotion or ev is InputEventMouseButton) and confirm.is_empty() and _vs_t < 0.0 			and not (ev is InputEventMouseMotion and main._args.has("test")):
		_mouse(ev)
	if is_open and screen == "options":
		main.options.menu_event(self, ev)
		return
	if is_open and screen == "profile" and name_edit and ev is InputEventKey and ev.pressed:
		_type_name(ev)
		get_viewport().set_input_as_handled()
		return
	if not is_open or screen != "join" or not (ev is InputEventKey) or not ev.pressed:
		return
	var k: InputEventKey = ev
	if k.keycode == KEY_BACKSPACE:
		ip = ip.substr(0, ip.length() - 1)
	elif k.keycode == KEY_ESCAPE:
		_go("online")
	elif k.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		_connect_peer()
	elif k.keycode == KEY_V and k.ctrl_pressed:
		_paste()
	elif k.unicode > 0 and IP_CHARS.contains(char(k.unicode)) and ip.length() < 15:
		ip += char(k.unicode)
	else:
		return
	get_viewport().set_input_as_handled()


func _connect_peer() -> void:
	if ip.count(".") != 3:
		message = tr("The IP has four numbers separated by dots.")
		return
	_save_ip(ip)
	var err: String = main.start_net(false, ip)
	message = err
	if err == "":
		_go("connecting")


func _load_ip() -> String:
	var f := FileAccess.open("user://last_ip.txt", FileAccess.READ)
	return f.get_as_text().strip_edges() if f else ""


func _save_ip(text: String) -> void:
	var f := FileAccess.open("user://last_ip.txt", FileAccess.WRITE)
	if f:
		f.store_string(text)


# ---------------------------------------------------------------- selection

## The options under the picks, in order. Online the guest cannot change the stage.
func setup_items() -> Array:
	if online:
		return ["stage", "build", "ready"]
	if choice.mode == "training":
		return ["stage", "build", "fight"]
	return ["stage", "diff", "build", "fight"]


func _selection() -> void:
	var list := pokemon_list()
	var n := list.size()
	var host: bool = online and main.net != null and main.net.host
	# Online, the host can also change the stage from the grid (RB / E).
	if host and sel_phase != "setup" and _pressed("mov2"):
		_cycle_stage(1)
	if sel_phase == "setup":
		_setup_input(list)
		return
	var to := cursor
	if _pressed("move_right"):
		to = mini(cursor + 1, n - 1)
	elif _pressed("move_left"):
		to = maxi(cursor - 1, 0)
	elif _pressed("move_down"):
		to = mini(cursor + COLUMNS, n - 1)
	elif _pressed("move_up"):
		to = maxi(cursor - COLUMNS, 0)
	if to != cursor:
		_pick_on_wall(to)
	if _accept():
		_sound("ok")
		choice[sel_phase] = list[cursor]
		if sel_phase == "p1" and not online:
			sel_phase = "p2"
			cursor = maxi(list.find(choice.p2), 0)
		else:
			_to_setup()
	elif _pressed("menu_back"):
		_sound("back")
		if online:
			ask(tr("Leave the room? You will be disconnected."), func():
				main.close_net()
				online = false
				_go("online"))
		elif sel_phase == "p2":
			sel_phase = "p1"
			cursor = maxi(list.find(choice.p1), 0)
		else:
			_go("main")


func _to_setup() -> void:
	sel_phase = "setup"
	var items := setup_items()
	setup_cursor = items.size() - 1          # straight on Fight / Ready
	if online:
		_send_choice()


func _setup_input(list: Array) -> void:
	var items := setup_items()
	var item: String = items[setup_cursor]
	var host: bool = not online or (main.net != null and main.net.host)
	if online and me_ready:
		if _pressed("menu_back"):
			_sound("back")
			me_ready = false
			_send_choice()
		return
	# The options sit side by side: left and right go through them, up and down change them.
	if _pressed("move_left"):
		setup_cursor = (setup_cursor + items.size() - 1) % items.size()
		_sound("move")
	elif _pressed("move_right"):
		setup_cursor = (setup_cursor + 1) % items.size()
		_sound("move")
	elif _pressed("move_up") or _pressed("move_down"):
		var step := 1 if _pressed("move_up") else -1
		match item:
			"stage":
				if host:
					_cycle_stage(step)
			"diff":
				var i := DIFFICULTIES.find(choice.diff)
				choice.diff = DIFFICULTIES[(i + step + 3) % 3]
				_sound("move")
	if _accept():
		match item:
			"stage":
				if host:
					_cycle_stage(1)
			"diff":
				var i := DIFFICULTIES.find(choice.diff)
				choice.diff = DIFFICULTIES[(i + 1) % 3]
				_sound("move")
			"build":
				_sound("ok")
				_edit_return = "selection"
				var keep := sel_phase
				_go("moves")
				edit_sp = choice.p1
				cursor = maxi(list.find(edit_sp), 0)
				edit_slot = 0
				edit_phase = "slots"
				sel_phase = keep
			"fight":
				_sound("ok")
				_start_vs(choice.p1, choice.p2)
			"ready":
				_sound("ok")
				me_ready = true
				_send_choice()
				main.check_start()
	elif _pressed("menu_back"):
		_sound("back")
		sel_phase = "p1" if online else "p2"
		cursor = maxi(list.find(choice[sel_phase]), 0)


# ---------------------------------------------------------------- profile

## Profile: your name on top, your trainers below. Moving over the trainers only points
## at them; A (or a click) makes the one pointed at yours (saved). A on the name starts
## editing it: the real keyboard types straight into it (Enter ends), and an on-screen
## keyboard comes up for the pad and the mouse (Done ends; B deletes a letter).
func _profile_input() -> void:
	var list := TrainerData.ids()
	if name_edit:
		_name_keyboard()
		return
	var before := profile_cursor
	if profile_cursor < 0:
		if _pressed("move_down"):
			profile_cursor = 0
	else:
		if _pressed("move_right"):
			profile_cursor = mini(profile_cursor + 1, list.size() - 1)
		elif _pressed("move_left"):
			profile_cursor = maxi(profile_cursor - 1, 0)
		elif _pressed("move_down"):
			profile_cursor = mini(profile_cursor + PROFILE_COLUMNS, list.size() - 1)
		elif _pressed("move_up"):
			profile_cursor = profile_cursor - PROFILE_COLUMNS if profile_cursor >= PROFILE_COLUMNS else -1
	if profile_cursor != before:
		_sound("move")
	if _accept():
		_sound("ok")
		if profile_cursor < 0:
			name_edit = true
			name_key = Vector2i.ZERO
		else:
			main.options.trainer = list[profile_cursor]
			main.options.save()
	elif _pressed("menu_back"):
		_sound("back")
		_go("main")
		cursor = 6


## The on-screen keyboard with the pad (the real keyboard's keys are typing then, so they
## do not move it; the mouse presses its keys in _mouse).
func _name_keyboard() -> void:
	if Controls.last_device == "keyboard":
		if _back_click:
			_end_name()
		return
	var before := name_key
	if _pressed("move_right"):
		name_key.x = (name_key.x + (3 if name_key.y == 4 else 1)) % 10
	elif _pressed("move_left"):
		name_key.x = (name_key.x + 10 - (3 if name_key.y == 4 else 1)) % 10
	elif _pressed("move_down"):
		name_key.y = (name_key.y + 1) % 5
	elif _pressed("move_up"):
		name_key.y = (name_key.y + 4) % 5
	if name_key != before:
		_sound("move")
	if _accept():
		_press_name_key()
	elif _pressed("menu_back"):
		var n: String = main.options.player_name
		if n == "":
			_end_name()
		else:
			main.options.player_name = n.substr(0, n.length() - 1)
			_sound("back")


## The key under the on-screen keyboard's cursor (the last row's four keys are 2.5 columns
## wide each).
func name_key_id() -> String:
	if name_key.y == 4:
		return NAME_KEYS[4][mini(int(name_key.x / 2.5), 3)]
	return NAME_KEYS[name_key.y][name_key.x]


func _press_name_key() -> void:
	var k := name_key_id()
	var n: String = main.options.player_name
	match k:
		"shift":
			name_lower = not name_lower
		"space":
			if n.length() < NAME_MAX and n != "":
				n += " "
		"del":
			n = n.substr(0, n.length() - 1)
		"done":
			_end_name()
			return
		_:
			if n.length() < NAME_MAX:
				n += k.to_lower() if name_lower else k
	main.options.player_name = n
	_sound("ok" if k == "done" else "move")


func _type_name(k: InputEventKey) -> void:
	var n: String = main.options.player_name
	if k.keycode == KEY_BACKSPACE:
		n = n.substr(0, n.length() - 1)
	elif k.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE]:
		_end_name()
		return
	elif k.unicode > 0 and n.length() < NAME_MAX and (NAME_CHARS.contains(char(k.unicode)) or "ÁÉÍÓÚÑÜáéíóúñü".contains(char(k.unicode))):
		n += char(k.unicode)
	main.options.player_name = n


func _end_name() -> void:
	name_edit = false
	main.options.player_name = main.options.player_name.strip_edges()
	main.options.save()
	_sound("ok")


func _cycle_stage(step: int) -> void:
	var e := STAGES.find(choice.stage)
	choice.stage = STAGES[(e + step + STAGES.size()) % STAGES.size()]
	_sound("move")
	if online and main.net and main.net.host:
		main.net.send_event({"t": "stage", "id": choice.stage})


# ---------------------------------------------------------------- Moves screen

const EDIT_ROWS := 8             # options shown at once in the list


## Moves screen: pick a Pokémon in the list, then one of its four moves (or its ability),
## then what goes there. Every change is saved at once (Loadout). Y / X shows or hides
## the details of the highlighted move; X / R restores the defaults (see ask_restore).
func _edit_moves() -> void:
	var list := pokemon_list()
	var n := list.size()
	if _pressed("menu_info") and edit_phase != "pokemon":
		details = not details
		_sound("move")
	if _pressed("menu_extra"):
		ask_restore()
		return
	match edit_phase:
		"pokemon":
			var before := cursor
			cursor = _cycle(cursor, n)
			if cursor != before:
				edit_sp = list[cursor]
				main.audio.cry(edit_sp, main.camera.global_position, 1.0, -22.0)
			if _accept():
				_sound("ok")
				edit_sp = list[cursor]
				edit_slot = 0
				edit_phase = "slots"
			elif _pressed("menu_back"):
				_sound("back")
				_leave_moves()
		"slots":
			edit_slot = _cycle(edit_slot, 5)
			if _accept():
				_sound("ok")
				var options := edit_options()
				var lo := Loadout.saved(edit_sp)
				edit_cursor = maxi(options.find(lo.moves[edit_slot] if edit_slot < 4 else lo.ability), 0)
				edit_top = clampi(edit_cursor - EDIT_ROWS / 2, 0, maxi(options.size() - EDIT_ROWS, 0))
				edit_phase = "list"
			elif _pressed("menu_back"):
				_sound("back")
				if _edit_return == "selection":
					_leave_moves()
				else:
					edit_phase = "pokemon"
		"list":
			var options := edit_options()
			edit_cursor = _cycle(edit_cursor, options.size())
			edit_top = clampi(edit_top, edit_cursor - EDIT_ROWS + 1, edit_cursor)
			if _accept():
				_sound("ok")
				var lo := Loadout.saved(edit_sp)
				var pick: String = options[edit_cursor]
				if edit_slot < 4:
					# Already in another slot: they swap places.
					var other: int = lo.moves.find(pick)
					if other >= 0:
						lo.moves[other] = lo.moves[edit_slot]
					lo.moves[edit_slot] = pick
				else:
					lo.ability = pick
				Loadout.store(edit_sp, lo)
				edit_phase = "slots"
			elif _pressed("menu_back"):
				_sound("back")
				edit_phase = "slots"


## Restores the default moves and ability, after asking: every Pokémon's from the list of
## Pokémon, the one being edited from its slots or a slot's options.
func ask_restore() -> void:
	if restore_all():
		if pokemon_list().all(Loadout.is_default):
			_sound("back")
			return
		ask(tr("Restore every Pokémon's default moves and abilities?"), func(): Loadout.restore())
	else:
		if Loadout.is_default(edit_sp):
			_sound("back")
			return
		var sp := edit_sp
		ask(tr("Restore %s's default moves and ability?") % tr(Roster.POKEMON[sp].display_name), func():
			Loadout.restore(sp)
			edit_phase = "slots")


func restore_all() -> bool:
	return edit_phase == "pokemon"


func _leave_moves() -> void:
	if _edit_return == "selection":
		var keep := choice.duplicate()
		screen = "selection"
		enter_t = 0.0
		details = false
		choice = keep
		sel_phase = "setup"
		setup_cursor = setup_items().find("build")
		cursor = maxi(pokemon_list().find(choice.p1), 0)
		if online:
			_send_choice()
	else:
		_go("main")


## Up and down through n rows, wrapping around.
func _cycle(i: int, n: int) -> int:
	if n <= 0:
		return 0
	if _pressed("move_up"):
		_sound("move")
		return (i + n - 1) % n
	if _pressed("move_down"):
		_sound("move")
		return (i + 1) % n
	return i


## What can go in the slot being edited: move ids, or ability ids for slot 4.
func edit_options() -> Array:
	if edit_slot < 4:
		return Loadout.moves_for(edit_sp)
	return Loadout.abilities_for(edit_sp).map(func(a): return a.id)


## The move whose details are shown: the highlighted option, or the highlighted slot's.
func shown_move() -> String:
	if edit_phase == "list" and edit_slot < 4:
		var options := edit_options()
		return options[edit_cursor] if not options.is_empty() else ""
	if edit_phase == "slots" and edit_slot < 4:
		return Loadout.saved(edit_sp).moves[edit_slot]
	return ""


# ---------------------------------------------------------------- online

func _send_choice() -> void:
	if main.net:
		var d := {"t": "choice", "species": choice.p1, "ready": me_ready, "loadout": main.my_loadout(choice.p1), "trainer": main.options.trainer, "name": main.options.shown_name(),
			"ver": Menu.version()}
		if main.net.host:
			d.stage = choice.stage            # so the rival sees the stage from the start
		main.net.send_event(d)


## The online rival changes Pokémon or gets ready.
## The game's version (project settings), sent online so both can tell they match.
static func version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", ""))


## Online: whether the rival plays another version (then the battle does not start).
func version_mismatch() -> bool:
	return rival_version != "" and rival_version != Menu.version()


func rival_choice(sp: String, ready: bool, loadout := {}, trainer := "", rival := "", ver := "") -> void:
	if not Roster.POKEMON.has(sp):
		return
	rival_version = ver if ver != "" else "?"
	rival_name = rival.substr(0, NAME_MAX)
	rival_trainer = TrainerData.valid(trainer) if trainer != "" else ""
	rival_choice_id = sp
	rival_loadout = Loadout.valid(sp, loadout)
	rival_ready = ready
	if is_open and screen == "selection":
		choice.p2 = sp


func _start_vs(mine: String, theirs: String) -> void:
	_vs = [mine, theirs]
	_vs_t = 0.0
	screen = "vs"
	enter_t = 0.0
	main.portraits(mine, theirs)
	main.audio.cry(mine, main.camera.global_position, 1.0, -12.0)


func vs_pair() -> Array:
	return _vs


func vs_time() -> float:
	return _vs_t


## From main, online: both are ready.
func show_vs(mine: String, theirs: String) -> void:
	if not is_open:
		open_menu("selection")
	_start_vs(mine, theirs)


# ---------------------------------------------------------------- 3D renders

## A live render of a Pokémon (animated, turning a little) for a slot of the screen.
func render(slot: String, sp: String, px: Vector2i, turn := 0.45) -> Texture2D:
	var r: Dictionary = _renders.get(slot, {})
	if r.is_empty():
		var vp := SubViewport.new()
		vp.own_world_3d = true
		vp.transparent_bg = true
		vp.msaa_3d = Viewport.MSAA_4X
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(vp)
		r = {"vp": vp, "model": null, "species": "", "turn": turn}
		_renders[slot] = r
	var vp: SubViewport = r.vp
	if vp.size != px:
		vp.size = px
	if sp != r.species:
		r.species = sp
		for ch in vp.get_children():
			ch.queue_free()
		var data := _setup_portrait(vp, sp, turn)
		r.model = data.model
		_frame_portrait(data, true, float(px.x) / maxf(px.y, 1.0))
	if r.model:
		r.model.rotation.y = PI + r.turn + sin(_t * 0.6) * 0.2
	return vp.get_texture()


func _free_renders() -> void:
	for slot in _renders:
		_renders[slot].vp.queue_free()
	_renders.clear()


# ---------------------------------------------------------------- portraits

## Grid icons: each Pokémon rendered once to a texture.
func _generate_portraits() -> void:
	_generating = true
	for sp in pokemon_list():
		var vp := SubViewport.new()
		vp.own_world_3d = true
		vp.transparent_bg = true
		vp.size = Vector2i(128, 128)
		vp.msaa_3d = Viewport.MSAA_4X
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(vp)
		var data := _setup_portrait(vp, sp, 0.5)
		# Wait for the animation to place the skeleton: before that, the locators are in
		# the rest pose and the framing ends up on the belly.
		for i in 18:
			await get_tree().process_frame
		_frame_portrait(data)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		if DisplayServer.get_name() != "headless":
			var img := vp.get_texture().get_image()
			portraits[sp] = ImageTexture.create_from_image(img)
		vp.queue_free()
	_generating = false


func _setup_portrait(vp: SubViewport, sp: String, turn: float) -> Dictionary:
	var m := PokeModel.new()
	m.setup(sp)
	var box: AABB = m._res.mesh.get_aabb()
	m.scale = Vector3.ONE * Roster.POKEMON[sp].height / maxf(box.size.y, 0.05)
	m.rotation.y = PI + turn
	vp.add_child(m)
	m.play("battle_idle" if m.has_anim("battle_idle") else "ground_idle", 0.0)
	var cam := Camera3D.new()
	cam.fov = 30.0
	# With physics interpolation the camera would only move on the next physics step,
	# and the picture would be taken from inside the model.
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	m.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	vp.add_child(cam)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.7, 0.5, 0.0)
	sun.light_energy = 1.25
	vp.add_child(sun)
	var amb := WorldEnvironment.new()
	amb.environment = Environment.new()
	amb.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	amb.environment.ambient_light_color = Color(0.85, 0.87, 0.95)
	amb.environment.ambient_light_energy = 0.75
	amb.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	vp.add_child(amb)
	return {"model": m, "cam": cam, "height": Roster.POKEMON[sp].height}


func _frame_portrait(r: Dictionary, body := false, aspect := 1.0) -> void:
	var m: PokeModel = r.model
	if body:
		# The whole body, wings and tails included: far enough for its height and for its
		# width (seen from any side as it turns) in a frame of this aspect.
		var box: AABB = m._res.mesh.get_aabb()
		var k: float = m.scale.x
		var half_w: float = maxf(box.size.x, box.size.z) * 0.5 * k
		var half_h: float = r.height * 0.5
		var t := tan(deg_to_rad(15.0))
		var dist: float = maxf(half_h / t, half_w / (t * aspect)) * 1.06
		var center := Vector3(0, half_h, 0)
		r.cam.position = center + Vector3(0, r.height * 0.1, dist)
		r.cam.look_at(center)
		return
	var points: Array = []
	for bone in ["locator_face", "locator_head", "head"]:
		if m.skel.find_bone(bone) >= 0:
			points.append(m.bone_world(bone))
	var face := Vector3(0, r.height * 0.75, 0)
	if points.size() >= 2:
		face = (points[0] + points[1]) * 0.5
	elif points.size() == 1:
		face = points[0]
	var box_height: float = clampf(r.height * 0.6, 0.6, 1.4)
	var dist := box_height * 0.5 / tan(deg_to_rad(15.0))
	var looks := face - Vector3(0, box_height * 0.08, 0)
	r.cam.position = looks + Vector3(0, box_height * 0.1, dist)
	r.cam.look_at(looks)


# ---------------------------------------------------------------- drawing

func draw_ui(h: Hud) -> void:
	draw.draw(h)


# ---------------------------------------------------------------- mouse

## The mouse works everywhere the keys do: over something (MenuDraw's zones) it moves the
## cursor there, a left click accepts it, a right click goes back. Keys on the on-screen
## keyboards are pressed straight away.
func _mouse(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT:
		_back_click = true
		return
	# The wheel scrolls like the arrows: up and down (lists, options, the setup tab under
	# the pointer), left and right along the selection's row of Pokémon.
	if ev is InputEventMouseButton and ev.pressed and ev.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var up: bool = ev.button_index == MOUSE_BUTTON_WHEEL_UP
		var along := screen == "selection" and sel_phase != "setup"
		_tap(("move_left" if up else "move_right") if along else ("move_up" if up else "move_down"))
		return
	if draw == null:
		return
	var z: Dictionary = draw.zone_at(ev.position)
	if z.is_empty():
		return
	# A question on top: only its answers count.
	if not confirm.is_empty() and z.kind != "confirm":
		return
	_hover(z)
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		match z.kind:
			"key":
				_sound("ok")
				_press_key(KEYPAD[_key.y][_key.x])
			"nkey":
				_press_name_key()
			"confirm":
				_clicked = z.i >= 0
			"restore":
				ask_restore()
			"mvp":
				_click_moves_pokemon(z.i)
			"slot":
				# From the list of Pokémon, straight to that slot of the highlighted one.
				if edit_phase == "pokemon":
					_sound("ok")
					edit_sp = pokemon_list()[cursor]
					edit_slot = z.i
					edit_phase = "slots"
				else:
					_clicked = edit_phase == "slots"
			"opt":
				_clicked = edit_phase == "list"
			_:
				_clicked = true


## A click on a Pokémon of the Moves screen: picks it, or from its slots or options
## changes to it (not when it came from the selection, which is for one Pokémon).
func _click_moves_pokemon(i: int) -> void:
	if edit_phase == "pokemon":
		_clicked = true
	elif _edit_return != "selection" and pokemon_list()[i] != edit_sp:
		_sound("ok")
		cursor = i
		edit_sp = pokemon_list()[i]
		edit_slot = 0
		edit_phase = "slots"
		details = false
		main.audio.cry(edit_sp, main.camera.global_position, 1.0, -22.0)


## Presses an action for one frame, as if a key had been tapped.
func _tap(action: String) -> void:
	Input.action_press(action)
	await get_tree().process_frame
	await get_tree().process_frame
	Input.action_release(action)


func _hover(z: Dictionary) -> void:
	var before := [cursor, profile_cursor, setup_cursor, _key, name_key, edit_slot, edit_cursor, confirm.get("on")]
	match z.kind:
		"confirm":
			if z.i >= 0:
				confirm.on = z.i
		"mvp":
			if screen == "moves" and edit_phase == "pokemon" and z.i != cursor:
				cursor = z.i
				edit_sp = pokemon_list()[cursor]
				main.audio.cry(edit_sp, main.camera.global_position, 1.0, -22.0)
		"slot":
			if edit_phase == "slots":
				edit_slot = z.i
		"opt":
			if edit_phase == "list":
				edit_cursor = z.i
		"main", "online":
			if screen == z.kind:
				cursor = z.i
		"pf":
			if not name_edit:
				profile_cursor = z.i
		"wall":
			if screen == "selection" and sel_phase != "setup" and z.i != cursor:
				_pick_on_wall(z.i)
				return
		"tab":
			if screen == "selection" and sel_phase == "setup" and not (online and me_ready):
				setup_cursor = z.i
		"key":
			_key = Vector2i(z.i % 4, z.i / 4)
		"nkey":
			name_key = Vector2i(z.i % 10, z.i / 10)
	if [cursor, profile_cursor, setup_cursor, _key, name_key, edit_slot, edit_cursor, confirm.get("on")] != before:
		_sound("move")


## The selection's cursor onto Pokémon "i" (keys and mouse alike).
func _pick_on_wall(i: int) -> void:
	var list := pokemon_list()
	cursor = clampi(i, 0, list.size() - 1)
	_sound("move")
	choice[sel_phase] = list[cursor]
	main.audio.cry(choice[sel_phase], main.camera.global_position, 1.0, -22.0)
	if online:
		_send_choice()
