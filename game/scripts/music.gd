class_name Music
extends Node
## Background music, quiet on purpose, in three groups by file name in game/music/ (see its
## README): "menu_*" for the menus, "select_*" for the selection and the moves editor,
## "battle_*" for the battles. Each time the group changes (and at every new battle) a track
## of it is picked at random, not the one just heard; it loops. Changing crossfades in a
## second; with no files the game is just silent. Battles play lower than the menus so the
## moves and the crowd come first. It plays on the "Music" bus, whose volume is the player's
## (Settings.music). Online each copy picks its own battle track.

const DIR := "res://music/"
const BASE_DB := -14.0               # menus
const BATTLE_DB := -19.0             # battles
const FADE := 1.0
const GROUP := {"menu": "menu_", "selection": "select_", "moves": "select_", "vs": "select_"}

var _players: Array = []
var _now := 0
var _group := ""
var _last := {}                      # group prefix -> the last track played
var _tracks := {}                    # group prefix -> its file names
var _volume := 0.5


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Audio.buses()
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		p.volume_db = -80.0
		add_child(p)
		_players.append(p)
	_scan()


## The files there are (exported, each is listed by its .import).
func _scan() -> void:
	var dir := DirAccess.open(DIR)
	if dir == null:
		return
	for f in dir.get_files():
		var clean := f.trim_suffix(".import").trim_suffix(".remap")
		if not (clean.ends_with(".mp3") or clean.ends_with(".ogg")):
			continue
		for prefix in ["menu_", "select_", "battle_"]:
			if clean.begins_with(prefix):
				var list: Array = _tracks.get(prefix, [])
				if not list.has(clean):
					list.append(clean)
				_tracks[prefix] = list


func set_volume(v: float) -> void:
	_volume = v


## Plays the group of "place" ("menu", "selection", "moves" or a stage id: a battle),
## crossfading. A battle always starts a new track ("fresh").
func play(place: String, fresh := false) -> void:
	var prefix: String = GROUP.get(place, "battle_")
	if prefix == _group and not fresh:
		return
	_group = prefix
	var stream := _pick(prefix)
	_now = 1 - _now
	var p: AudioStreamPlayer = _players[_now]
	p.stream = stream
	if stream:
		p.volume_db = -80.0
		p.play()
	else:
		p.stop()


func _pick(prefix: String) -> AudioStream:
	var list: Array = _tracks.get(prefix, []).duplicate()
	if list.is_empty():
		return null
	if list.size() > 1:
		list.erase(_last.get(prefix, ""))
	var file: String = list.pick_random()
	_last[prefix] = file
	var s: AudioStream = load(DIR + file)
	if s is AudioStreamOggVorbis or s is AudioStreamMP3:
		s.loop = true
	return s


func _process(delta: float) -> void:
	var target := BATTLE_DB if _group == "battle_" else BASE_DB
	for i in 2:
		var p: AudioStreamPlayer = _players[i]
		if not p.playing:
			continue
		var want := target if i == _now else -80.0
		p.volume_db = move_toward(p.volume_db, want, delta * 60.0 / FADE)
		if i != _now and p.volume_db <= -79.0:
			p.stop()
