class_name SessionLog
extends Node
## Session log for bug reports: one JSON object per line in user://logs/, one file per
## session (the newest 20 are kept), next to Godot's own log with errors and warnings.
## Nothing is sent anywhere: players open the folder with F9 and send the files. No IP
## addresses are written.
##
## Besides the events main.gd reports (battles, KOs, online, pause...), it samples the
## battle every 5 s (FPS, ping, rival states received) and warns when an online battle
## stops receiving the rival's state.

const KEEP := 20
const SAMPLE_EVERY := 5.0

var main: Node
var _file: FileAccess
var _t := 0.0
var _sample_t := 0.0
var _fps_min := 9999
var _fps_sum := 0.0
var _fps_n := 0
var _last_states := 0
var _no_states_t := 0.0
var _warned_states := false
var battle := {}          # running counts for the battle in progress
var _battle_start := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute("user://logs")
	_prune()
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	_file = FileAccess.open("user://logs/pokebrawl_%s.jsonl" % stamp, FileAccess.WRITE)
	event("session", {"version": ProjectSettings.get_setting("application/config/version", "dev"),
		"os": OS.get_name() + " " + OS.get_version(), "gpu": RenderingServer.get_video_adapter_name(),
		"locale": TranslationServer.get_locale(), "screen": str(DisplayServer.screen_get_size()),
		"args": " ".join(OS.get_cmdline_user_args())})


## Writes one line: {"t": seconds since start, "e": kind, ...data}.
func event(kind: String, data := {}) -> void:
	if _file == null:
		return
	var line := {"t": snappedf(_t, 0.01), "e": kind}
	line.merge(data)
	_file.store_line(JSON.stringify(line))
	_file.flush()


## Opens the log folder in the system's file explorer.
func open_folder() -> void:
	OS.shell_open(ProjectSettings.globalize_path("user://logs"))


func battle_started(p1: String, p2: String, stage: String, online: bool, role: String) -> void:
	battle = {"hits": [0, 0], "damage": [0.0, 0.0], "dodges": [0, 0]}
	_fps_min = 9999
	_fps_sum = 0.0
	_fps_n = 0
	_warned_states = false
	_no_states_t = 0.0
	_last_states = main.net.states_applied if main.net else 0
	_battle_start = _t
	event("battle_start", {"p1": p1, "p2": p2, "stage": stage, "online": online, "role": role})


## A hit landed on "target" (index 0 or 1 in main.fighters).
func hit(target: int, damage: float) -> void:
	if battle.is_empty():
		return
	battle.hits[1 - target] += 1
	battle.damage[1 - target] += damage


func dodge(who: int) -> void:
	if not battle.is_empty():
		battle.dodges[who] += 1


func battle_ended(winner: String, hp: Array) -> void:
	var data := {"winner": winner, "duration": snappedf(_t - _battle_start, 0.1), "hp": hp,
		"fps_mean": int(_fps_sum / maxf(_fps_n, 1.0)), "fps_min": _fps_min}
	data.merge(battle)
	event("ko", data)
	battle = {}


func _process(delta: float) -> void:
	_t += delta
	if main == null or main.fighters.size() < 2:
		return
	var fps := Engine.get_frames_per_second()
	_fps_min = mini(_fps_min, fps)
	_fps_sum += fps
	_fps_n += 1
	var net: Net = main.net
	# Online watchdog: the rival's state should arrive every frame or so.
	if net and net.in_battle:
		if net.states_applied != _last_states:
			_last_states = net.states_applied
			_no_states_t = 0.0
			_warned_states = false
		else:
			_no_states_t += delta
			if _no_states_t > 2.0 and not _warned_states:
				_warned_states = true
				event("warning", {"what": "no rival state for 2 s", "linked": net.linked, "ping_ms": net.ping_ms()})
	_sample_t += delta
	if _sample_t >= SAMPLE_EVERY:
		_sample_t = 0.0
		var s := {"fps": fps, "hp": [int(main.fighters[0].hp), int(main.fighters[1].hp)]}
		if net:
			s.ping_ms = net.ping_ms()
			s.rival_states = net.states_applied
		event("sample", s)


## Keeps the newest KEEP session files.
func _prune() -> void:
	var files: Array = []
	for f in DirAccess.get_files_at("user://logs"):
		if f.begins_with("pokebrawl_") and f.ends_with(".jsonl"):
			files.append(f)
	files.sort()
	while files.size() >= KEEP:
		DirAccess.remove_absolute("user://logs/" + files.pop_front())
