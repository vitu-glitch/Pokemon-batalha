extends Node3D
## Main battle scene. Builds the stage, both fighters, the camera, the HUD, effects,
## sound and the AI, and runs the battle: start, KO, rematch, pause and training.
##
## Launch: godot --path game -- [--p1=pikachu] [--p2=snorlax] [--diff=normal]
##         [--stage=night|floating] [--training] [--aivsai] [--test=name] [--lang=en|es]
## Online:  --host [--p1=species]            hosts a game (port 7777)
##          --join=IP [--p1=species]         joins someone else's
##          --bot (the AI plays your own Pokémon), --lag=ms --jitter=ms --loss=%

var options: Settings
var music: Music
var ground_y := 0.0
var mode := "combat"            # combat, training
var paused := false

var arena: Arena
var vfx: Vfx
var weather: Weather
var fx: Fx
var audio: Audio
var combat: Combat
var camera: BattleCamera
var hud: Hud
var menu: Menu
var ai: AI
var player_ai: AI               # only with --aivsai (tests)
var net: Net                     # online only
var fighters: Array = []
var trainers: Array = []          # Trainer of each fighter, same order (only for show)
## The opening: each trainer throws their Poké Ball and their Pokémon comes out; nobody
## moves until it ends. Tests skip it (unless --intro).
const INTRO := 2.5
var intro_t := 0.0
var start_t := -1.0               # seconds since the opening ended ("START"); -1 without one
var player: Fighter
var _fonts := {}
var _end_t := -1.0
## Online, on the result screen: who wants a rematch (Net.me ids). The host keeps the count
## and starts it once everyone is in ("rematch"); everyone sees "votes" as they come.
var rematch_votes := {}
var rematch_of := 0
## After the final blow: the result shows up once the stadium has had its moment (the
## strip's WINNER), and its options a little later; only then do A and B work.
const RESULT_AT := 2.4
const CHOICES_AT := 3.2
## With nobody choosing, the result screen goes on by itself this long after its options
## show: to the selection screen (online, both, still connected: the room). The stage stops
## then instead of running on behind.
const AUTO_LEAVE := 15.0
var _no_input := 0.0          # at the start, so the menu's A press does not make it jump
var _args := {}
var session: SessionLog


func _ready() -> void:
	session = SessionLog.new()
	session.main = self
	add_child(session)
	Controls.configure()
	# Less input lag: "mailbox" VSync does not wait on the frame queue and does not
	# tear. If the system does not support it, the normal mode stays.
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_MAILBOX)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var parts := a.substr(2).split("=")
			_args[parts[0]] = parts[1] if parts.size() > 1 else "1"
	# The language follows the system; --lang=en or --lang=es forces one.
	if _args.has("lang"):
		TranslationServer.set_locale(_args.lang)
	process_physics_priority = -20
	set_stage(_args.get("stage", "night"))
	combat = Combat.new()
	combat.main = self
	combat.process_physics_priority = 10
	add_child(combat)
	vfx = Vfx.new()
	vfx.main = self
	add_child(vfx)
	weather = Weather.new()
	weather.main = self
	add_child(weather)
	fx = Fx.new()
	fx.main = self
	add_child(fx)
	audio = Audio.new()
	audio.main = self
	add_child(audio)
	music = Music.new()
	add_child(music)
	options = Settings.new()
	options.main = self
	add_child(options)
	options.load_saved()
	if _args.has("lang"):
		TranslationServer.set_locale(_args.lang)
	camera = BattleCamera.new()
	camera.main = self
	camera.fov = 62.0
	add_child(camera)
	camera.current = true
	hud = Hud.new()
	hud.main = self
	add_child(hud)
	menu = Menu.new()
	menu.main = self
	menu.choice.stage = arena.stage
	add_child(menu)
	if _args.has("training"):
		mode = "training"
		menu.choice.mode = "training"
	# With --p1, --test or --aivsai it goes straight into battle; otherwise, to the menu.
	if _args.has("host") or _args.has("join"):
		var err := start_net(_args.has("host"), _args.get("join", ""), _args.get("p1", "pikachu"))
		if err != "":
			push_error(err)
	elif _args.has("p1") or _args.has("aivsai") or (_args.has("test") and not _args.test.begins_with("menu")):
		start_battle(_args.get("p1", "pikachu"), _args.get("p2", "snorlax"), _args.get("diff", "normal"))
	else:
		menu.open_menu()
	if _args.has("test"):
		var p: Node = preload("res://scripts/tests.gd").new()
		p.main = self
		p.test_name = _args.test
		add_child(p)
	elif not menu.is_open and net == null:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func font(bold := true) -> Font:
	var k := "n" if bold else "r"
	if not _fonts.has(k):
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Arial"])
		f.font_weight = 700 if bold else 500
		_fonts[k] = f
	return _fonts[k]


## Builds the stage: "night" (the night stadium, the default) or "floating" (a platform
## over a void: falling off is a KO). It can be
## changed in the menu (online, the host picks it); it is rebuilt from scratch.
func set_stage(stage_id: String) -> void:
	if arena and arena.stage == stage_id:
		return
	if arena:
		arena.queue_free()
		remove_child(arena)
	match stage_id:
		"floating": arena = FloatingStadium.new()
		"league": arena = LeagueStadium.new()
		_:
			arena = NightStadium.new()
			stage_id = "night"
	arena.stage = stage_id
	arena.main = self
	add_child(arena)
	move_child(arena, 0)
	arena.build()
	_put_trainers()
	if hud and fighters.size() == 2:
		portraits(fighters[0].species, fighters[1].species)


## My Pokémon's moves and ability: what I saved in the Moves menu. Tests and AI against AI
## use the defaults (or --moves=a,b,c,d for p1), so they always play the same.
func my_loadout(sp: String) -> Dictionary:
	if _args.has("moves"):
		return Loadout.valid(sp, {"moves": Array(str(_args.moves).split(",")), "ability": Roster.POKEMON[sp].passive.id})
	if _args.has("test") or _args.has("aivsai"):
		return Loadout.default_for(sp)
	return Loadout.saved(sp)


## "rival_loadout": what the online rival sent with its choice (against the AI, its defaults).
## "rival_trainer": the online rival's trainer (against the AI, one from TrainerData).
func start_battle(p1: String, p2: String, diff: String, rival_loadout := {}, rival_trainer := "") -> void:
	music.play(arena.stage, true)
	vfx.clear()
	weather.clear()
	for l in fighters:
		l.queue_free()
	fighters.clear()
	combat.clear()
	if ai:
		ai.queue_free()
	if player_ai:
		player_ai.queue_free()
	var side := 1.0 if net and not net.host else -1.0
	var a := _create(p1, 0, Vector3(7 * side, 0, 0), -PI * 0.5 * side, my_loadout(p1))
	var b := _create(p2, 1, Vector3(-7 * side, 0, 0), PI * 0.5 * side,
		Loadout.valid(p2, rival_loadout) if net else Loadout.default_for(p2))
	a.rival = b
	b.rival = a
	player = a
	a.is_player = true
	ai = null
	if net:
		_setup_net(a, b)
	else:
		_setup_ai(a, b, diff)
	combat.targets = fighters.duplicate()
	camera.target = a
	camera.yaw = -PI * 0.5 * -side
	_end_t = -1.0
	_no_input = 0.25
	Engine.time_scale = 1.0
	portraits(p1, p2)
	var mine: String = options.trainer
	_place_trainers([mine, rival_trainer if net and rival_trainer != "" else TrainerData.rival_for(mine, p2)])
	_introduce()
	session.battle_started(p1, p2, arena.stage, net != null, ("host" if net.host else "guest") if net else mode)
	if _args.has("weather"):
		weather.start(_args.weather)          # tests: --weather=sun|rain|sand|snow


func _setup_ai(a: Fighter, b: Fighter, diff: String) -> void:
	ai = AI.new()
	ai.main = self
	ai.me = b
	ai.rival = a
	ai.difficulty = diff
	ai.process_physics_priority = -10
	add_child(ai)
	if _args.has("aivsai"):
		player_ai = AI.new()
		player_ai.main = self
		player_ai.me = a
		player_ai.rival = b
		player_ai.difficulty = diff
		player_ai.process_physics_priority = -10
		add_child(player_ai)
		a.is_player = false


func _introduce() -> void:
	var a: Fighter = fighters[0]
	var b: Fighter = fighters[1]
	hud.clear_log()
	arena.on_rematch()
	_opening()
	if trainers.size() == 2:
		hud.log_entry(tr("%s sends out %s!") % [trainers[0].display_name, tr(a.data.display_name)])
		hud.log_entry(tr("%s sends out %s!") % [trainers[1].display_name, tr(b.data.display_name)])
	else:
		hud.log_entry(tr("Go, %s!") % tr(a.data.display_name))
		hud.log_entry(tr("%s jumps onto the field!") % tr(b.data.display_name))
	if mode == "training":
		hud.log_entry(tr("Training. R resets, T stops or frees the rival, F3 shows the hitboxes."))


# ---------------------------------------------------------------- trainers and the opening

## A trainer for each fighter, in their side's trainer area of the stage.
func _place_trainers(ids: Array) -> void:
	for t in trainers:
		t.queue_free()
	trainers.clear()
	for i in fighters.size():
		var t := Trainer.new()
		add_child(t)
		t.setup(self, ids[i], fighters[i])
		t.display_name = tr(TrainerData.LIST[t.id].name)
		trainers.append(t)
	trainers[0].display_name = options.shown_name()
	if net and menu.rival_name != "" and trainers.size() > 1:
		trainers[1].display_name = menu.rival_name
	_put_trainers()


func _clear_trainers() -> void:
	for t in trainers:
		if is_instance_valid(t):
			t.queue_free()
	trainers.clear()


func _put_trainers() -> void:
	for t in trainers:
		# Back in the menus the fighters may be gone already: nothing to place then.
		if not is_instance_valid(t) or not is_instance_valid(t.fighter):
			continue
		var f: Fighter = t.fighter
		t.global_position = arena.trainer_spot(signf(f.start_pos.x) if f.start_pos.x != 0.0 else 1.0)


## Visual reactions of a fighter's trainer: "command" (it used a move), "cheer" (it landed a
## hit), "flinch" (it took a heavy one).
func trainer_react(f: Node, kind: String) -> void:
	for t in trainers:
		if t.fighter == f and is_instance_valid(t):
			t.call(kind)


func _opening() -> void:
	for t in trainers:
		t.reset()
	var play := not (_args.has("test") or _args.has("aivsai")) or _args.has("intro")
	start_t = -1.0
	if not play:
		intro_t = 0.0
		for f in fighters:
			f.appear = 1.0
			f.appear_glow = 0.0
		audio.cry(fighters[0].species, fighters[0].global_position)
		return
	intro_t = INTRO
	_no_input = INTRO
	for i in fighters.size():
		var f: Fighter = fighters[i]
		f.appear = 0.0
		f.appear_glow = 0.0
		var t: Trainer = trainers[i]
		var wait := 0.2 + 0.25 * i
		get_tree().create_timer(wait, false).timeout.connect(func():
			if is_instance_valid(t):
				t.throw())
		get_tree().create_timer(wait + 0.25, false).timeout.connect(func():
			if is_instance_valid(t) and is_instance_valid(f):
				_throw_ball(t, f))


## The ball flies in an arc from the trainer's hand to where the Pokémon stands, spinning,
## and opens there in a burst of light; the Pokémon grows out of it, white, and cries.
func _throw_ball(t: Trainer, f: Fighter) -> void:
	var from := t.hand()
	var to := f.global_position + Vector3.UP * 0.7
	var flight := 0.75
	var top := 0.8 + from.distance_to(to) * 0.06
	var ball := vfx.pixel_ball("pokeball", 4, 0.5, Color.WHITE, 14.0, false)
	ball.global_position = from
	audio.play_sound("ball_throw", from, -2.0)
	vfx.live(ball, flight, func(k: float):
		ball.global_position = from.lerp(to, k) + Vector3.UP * sin(k * PI) * top)
	get_tree().create_timer(flight, false).timeout.connect(func():
		if not is_instance_valid(f):
			return
		audio.play_sound("ball_open", to, 0.0)
		audio.play_sound("ball_send", to, -4.0)
		vfx.light(to, Color.WHITE, 6.0, 6.0, 0.4)
		vfx.burst("stars", to, Vector3.UP, Color(0, 0, 0, 0), 1.2)
		vfx.wave(Vector3(to.x, ground_y, to.z), 2.2, 0.35, Color(1.0, 0.95, 0.9), 0.08)
		vfx.live(Node3D.new(), 0.4, func(k: float):
			if is_instance_valid(f):
				f.appear = k
				f.appear_glow = 1.0 - k)
		get_tree().create_timer(0.3, false).timeout.connect(func():
			if is_instance_valid(f):
				audio.cry(f.species, f.global_position)))


func _create(sp: String, eq: int, pos: Vector3, yaw: float, loadout := {}) -> Fighter:
	var l := Fighter.new()
	add_child(l)
	l.setup(self, sp, eq, loadout)
	l.global_position = pos
	l.face_yaw = yaw
	l.start_pos = pos
	l.start_yaw = yaw
	l.reset_physics_interpolation()
	l.defeated.connect(_on_defeat)
	fighters.append(l)
	return l


func rematch() -> void:
	session.event("rematch")
	rematch_votes.clear()
	var a: Fighter = fighters[0]
	var b: Fighter = fighters[1]
	weather.clear()
	combat.clear()
	vfx.clear()
	a.reset(a.start_pos, a.start_yaw)
	b.reset(b.start_pos, b.start_yaw)
	camera.yaw = a.start_yaw + PI
	_end_t = -1.0
	Engine.time_scale = 1.0
	_introduce()


func _on_defeat(who: Fighter) -> void:
	if _end_t >= 0.0:
		return
	_end_t = 0.0
	# Brief slow motion: the last hit is visible, without taking control away. Not
	# online: time has to run the same on both machines.
	if net == null:
		Engine.time_scale = 0.35
	var winner: Fighter = who.rival
	hud.log_entry(tr("%s fainted!") % tr(who.data.display_name))
	hud.log_entry(tr("%s wins.") % tr(winner.data.display_name))
	audio.play_sound("ko", who.global_position, -2.0)
	arena.on_ko(winner)
	trainer_react(winner, "win")
	trainer_react(who, "lose")
	session.battle_ended(winner.species + (" (me)" if winner == player else ""), [int(fighters[0].hp), int(fighters[1].hp)])


# ---------------------------------------------------------------- online

## Hosts a game or joins someone else's. Returns an error or "".
## With "species" (a shortcut for arguments and tests) it is picked and marked ready on
## connecting; without it, once connected both go to the menu's selection.
func start_net(as_host: bool, ip: String, species := "") -> String:
	close_net()
	net = Net.new()
	net.main = self
	net.lag_sim = float(_args.get("lag", "0")) / 1000.0
	net.jitter_sim = float(_args.get("jitter", "0")) / 1000.0
	net.loss_sim = float(_args.get("loss", "0"))
	add_child(net)
	menu.rival_choice_id = ""
	menu.rival_version = ""
	menu.rival_ready = false
	net.connected.connect(func():
		if species != "":
			menu.online = true
			menu.choice.p1 = species
			menu.me_ready = true
			net.send_event({"t": "choice", "species": species, "ready": true, "loadout": my_loadout(species), "trainer": options.trainer, "name": options.shown_name(), "ver": Menu.version()})
			check_start()
		else:
			menu.online_connected())
	net.event.connect(_net_event)
	net.disconnected.connect(_disconnection)
	var err := net.create() if as_host else net.join(ip)
	session.event("net_start", {"role": "host" if as_host else "guest", "error": err})
	net.connected.connect(func(): session.event("connected"))
	return err


func close_net() -> void:
	if net:
		net.close()
		net.queue_free()
		net = null


## The host starts the battle when both are ready.
func check_start() -> void:
	if net == null or not net.host or not menu.me_ready or not menu.rival_ready or menu.rival_choice_id == "":
		return
	if menu.version_mismatch():
		return
	var mine: String = menu.choice.p1
	var theirs: String = menu.rival_choice_id
	menu.me_ready = false
	menu.rival_ready = false
	net.send_event({"t": "start", "host": mine, "guest": theirs, "stage": menu.choice.stage})
	set_stage(menu.choice.stage)
	_start_online(mine, theirs)


func _setup_net(a: Fighter, b: Fighter) -> void:
	b.is_remote = true
	b.is_player = false
	net.local = a
	net.remote = b
	# net.frame counts the whole connection: reset, the rival would drop a second
	# battle's packets as old.
	net.in_battle = true
	if _args.has("bot"):
		ai = AI.new()
		ai.main = self
		ai.me = a
		ai.rival = b
		ai.difficulty = _args.get("diff", "normal")
		ai.process_physics_priority = -10
		add_child(ai)
		a.is_player = false


func _net_event(d: Dictionary) -> void:
	match d.t:
		"choice":
			if d.has("stage") and menu.STAGES.has(d.stage):
				menu.choice.stage = d.stage
			menu.rival_choice(d.species, d.ready, d.get("loadout", {}), str(d.get("trainer", "")), str(d.get("name", "")), str(d.get("ver", "")))
			check_start()
		"start":
			menu.me_ready = false
			menu.rival_ready = false
			menu.choice.stage = d.get("stage", menu.choice.stage)
			set_stage(menu.choice.stage)
			_start_online(d.guest, d.host)
		"stage":
			# The host changed the stage in the selection (it is built when the battle starts).
			if menu.STAGES.has(d.id):
				menu.choice.stage = d.id
		"to_selection":
			_to_selection(false)
		"hit":
			# Confirmation from the rival: my hit landed. Number and type, like offline.
			if fighters.size() > 1 and d.damage > 0.5:
				vfx.number(d.point, d.damage, d.affinity)
				if d.affinity > 1.05:
					hud.log_entry(tr("It's super effective!"))
				elif d.affinity < 0.95:
					hud.log_entry(tr("It's not very effective..."))
		"effect":
			if net.local:
				net.local.effect(d.type, d.v, d.get("move", ""))
		"clash":
			# The host saw two shots meet: the same here ("h" is the host's shot, "g" mine).
			if net.local and net.remote:
				var mine = null
				var theirs = null
				for p in combat.projectiles:
					if p.get("shooter") == net.local and p.get("seq", -2) == int(d.g):
						mine = p
					elif p.get("shooter") == net.remote and p.get("seq", -2) == int(d.h):
						theirs = p
				if mine != null and theirs != null:
					combat.clash(theirs, mine)
		"deflect":
			# The rival deflected one of my projectiles: the same here.
			if net.local and net.remote:
				for p in combat.projectiles:
					if p.get("shooter") == net.local and p.get("seq", -2) == int(d.seq):
						combat.deflect(p, net.remote, int(d.level))
						break
		"boost":
			# The rival's Pokémon changed a stat stage: its copy here needs it for damage.
			if net.remote and net.remote.stages.has(d.stat):
				net.remote.stages[d.stat] = int(d.stages)
		"rematch":
			rematch()
		"asks_rematch":
			if net.host and _end_t > 1.0:
				_vote_rematch(str(d.get("id", "guest")))
		"votes":
			rematch_votes = {}
			for id in d.get("ids", []):
				rematch_votes[str(id)] = true
			rematch_of = int(d.get("of", 2))


func _start_online(mine: String, theirs: String) -> void:
	# From the menu, with the VS screen; from arguments (tests), straight in.
	if menu.is_open:
		menu.show_vs(mine, theirs)
		return
	start_battle(mine, theirs, "normal", menu.rival_loadout, menu.rival_trainer)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if not _args.has("test") else Input.MOUSE_MODE_VISIBLE


## Online rematch vote: everyone must ask for it. A guest's vote goes to the host; the host
## counts, tells everyone how many are in, and starts the rematch for all when the last one
## asks. Until then nobody's battle starts.
func _vote_rematch(id: String) -> void:
	if net == null or _end_t < 0.0:
		return
	if not net.host:
		if rematch_votes.has(id):
			return
		rematch_votes[id] = true
		net.send_event({"t": "asks_rematch", "id": id})
		return
	rematch_votes[id] = true
	rematch_of = net.players()
	net.send_event({"t": "votes", "ids": rematch_votes.keys(), "of": rematch_of})
	if rematch_votes.size() >= rematch_of:
		net.send_event({"t": "rematch"})
		rematch()


## Online, after a battle: both pick again without dropping the connection.
func _to_selection(warn: bool) -> void:
	if net == null:
		return
	session.event("to_selection", {"asked_by_me": warn})
	rematch_votes.clear()
	if warn:
		net.send_event({"t": "to_selection"})
	net.in_battle = false
	net.local = null
	net.remote = null
	for l in fighters:
		l.queue_free()
	fighters.clear()
	player = null
	combat.clear()
	combat.targets = []
	vfx.clear()
	if ai:
		ai.queue_free()
		ai = null
	_end_t = -1.0
	_clear_trainers()
	hud.clear_log()
	menu.online = true
	menu.open_menu("selection")


func _disconnection(reason: String) -> void:
	session.event("disconnected", {"reason": reason})
	hud.log_entry(reason)
	push_warning(reason)
	if net:
		net.queue_free()
		net = null
	if _args.get("test", "") == "net":
		return
	back_to_menu()
	menu.disconnected(reason)


## For the Cobblemon particle interpreter: ground height under a point.
func ground_at(_p: Vector3, _from: float) -> float:
	return ground_y


func shake_camera(k: float, pos: Vector3) -> void:
	var d := camera.global_position.distance_to(pos)
	camera.shake_camera(k * clampf(1.4 - d / 25.0, 0.3, 1.0))


# ---------------------------------------------------------------- player input

func _physics_process(delta: float) -> void:
	if intro_t > 0.0:
		intro_t -= delta
		if intro_t <= 0.0:
			start_t = 0.0
	elif start_t >= 0.0:
		start_t += delta
	if _end_t >= 0.0:
		_end_t += delta / maxf(Engine.time_scale, 0.01)
		if _end_t > 0.9:
			Engine.time_scale = 1.0
		if _end_t > CHOICES_AT + AUTO_LEAVE and not paused and not _args.has("test") and not _args.has("aivsai"):
			_leave_result()
	if _no_input > 0.0:
		_no_input -= delta
		if player:
			player.ctrl.clear()
		return
	if player == null or not player.is_player:
		return
	if paused:
		# Online the battle goes on under the pause menu: your Pokémon just stands still.
		player.ctrl.clear()
		return
	var c := player.ctrl
	c.move_input = Input.get_vector("move_left", "move_right", "move_down", "move_up")
	c.yaw = camera.yaw
	for a in ["jump", "dodge", "lock_on", "mov1", "mov2", "mov3", "mov4", "descend"]:
		if Input.is_action_just_pressed(a):
			c.press(a)
		elif Input.is_action_pressed(a):
			c.held[a] = true
		else:
			c.release(a)


func _unhandled_input(ev: InputEvent) -> void:
	Controls.notice(ev)
	if ev is InputEventKey and ev.pressed and not ev.echo and ev.physical_keycode == KEY_F9:
		session.open_folder()
	if ev.is_action_pressed("debug"):
		hud.debug = not hud.debug
	if fighters.size() < 2:
		return
	if ev.is_action_pressed("reset") and net == null and (mode == "training" or _end_t > 1.0):
		rematch()
	if ev is InputEventKey and ev.pressed and ev.physical_keycode == KEY_T and mode == "training" and ai:
		ai.mode = "still" if ai.mode == "active" else "active"
		ai.me.ctrl.move_input = Vector2.ZERO
	if _end_t > CHOICES_AT and ev.is_action_pressed("jump"):
		if net == null:
			rematch()
		else:
			_vote_rematch(net.me)
	elif _end_t > CHOICES_AT and ev.is_action_pressed("menu_back"):
		if net:
			_to_selection(true)
		else:
			back_to_menu()
	if ev is InputEventMouseButton and ev.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not paused and not menu.is_open and not _args.has("test"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## HUD and jumbotron portraits for this matchup.
func portraits(p1: String, p2: String) -> void:
	hud.prepare_portraits([p1, p2])
	arena.screens(hud._portraits[0].vp.get_texture(), hud._portraits[1].vp.get_texture(),
		Roster.TYPE_COLOR[Roster.POKEMON[p1].types[0]], Roster.TYPE_COLOR[Roster.POKEMON[p2].types[0]])


## Nobody chose on the result screen: back to the selection (online the host takes both,
## still connected; the guest waits for it).
func _leave_result() -> void:
	if net:
		if net.host:
			_to_selection(true)
		return
	back_to_menu("selection")


## Leaves the battle and returns to the menu with the last picks ("screen": which one).
func back_to_menu(screen := "") -> void:
	session.event("back_to_menu", {"online": net != null, "battle_over": _end_t >= 0.0})
	if net:
		net.close()
		net.queue_free()
		net = null
	if paused:
		paused = false
		get_tree().paused = false
	vfx.clear()
	for l in fighters:
		l.queue_free()
	fighters.clear()
	player = null
	combat.clear()
	combat.targets = []
	if ai:
		ai.queue_free()
		ai = null
	if player_ai:
		player_ai.queue_free()
		player_ai = null
	_end_t = -1.0
	Engine.time_scale = 1.0
	_clear_trainers()
	hud.clear_log()
	menu.open_menu(screen)


func toggle_pause() -> void:
	paused = not paused
	session.event("pause" if paused else "resume", {"online": net != null})
	# Online the game cannot stop (the rival keeps playing): the menu opens on top so you
	# can leave, and the battle goes on.
	if net == null:
		get_tree().paused = paused
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if paused else Input.MOUSE_MODE_CAPTURED
