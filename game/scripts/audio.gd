class_name Audio
extends Node
## Battle sound. Move and impact sounds come from Cobblemon (game/sounds/moves/,
## MPL 2.0); the cries, from each Pokémon. What Cobblemon does not have (dodge,
## footsteps, falls, armor, charges) is synthesized here in code and is marked as
## placeholder in the README.
## Players are reused: never created on every hit.

const DIR := "res://sounds/moves/"

## Key -> Cobblemon folder and file prefix (one is picked at random).
const COBBLEMON := {
	"thundershock": ["thundershock", "thundershock_actor"], "thundershock_hit": ["thundershock", "thundershock_target"],
	"bolt": ["thunderbolt", "thunderbolt_actor"], "thunderbolt": ["thunderbolt", "thunderbolt_target"], "bolt_hit": ["thunderbolt", "thunderbolt_target"],
	"quickattack": ["quickattack", "quickattack_actor"], "quickattack_hit": ["quickattack", "quickattack_target"],
	"flamethrower": ["flamethrower", "flamethrower_actor"], "flamethrower_hit": ["flamethrower", "flamethrower_target"],
	"bodyslam": ["bodyslam", "bodyslam_actor"], "bodyslam_hit": ["bodyslam", "bodyslam_target"],
	"icepunch": ["icepunch", "icepunch_target"], "firepunch": ["firepunch", "firepunch_target"], "fireblast": ["fireblast", "fireblast_actor"], "fireblast_hit": ["fireblast", "fireblast_target"], "closecombat": ["closecombat", "closecombat_target"], "shadowclaw": ["shadowball", "shadowball_target"], "rockslide": ["rockthrow", "rockthrow_actor"], "rockslide_hit": ["rockthrow", "rockthrow_target"], "surf": ["waterpulse", "waterpulse_actor"], "surf_hit": ["waterpulse", "waterpulse_target"], "psychic": ["psychic", "psychic_actor"], "psychic_hit": ["psychic", "psychic_target"], "darkpulse": ["shadowball", "shadowball_actor"], "darkpulse_hit": ["shadowball", "shadowball_target"], "ball_throw": ["poke_ball", "poke_ball_throw_"], "ball_send": ["poke_ball", "poke_ball_send_out"], "ball_open": ["poke_ball", "poke_ball_open"], "thunder_up": ["thunder", "thunder_actor"], "thunder": ["thunder", "thunder_target"], "volttackle": ["thunderbolt", "thunderbolt_actor"], "focusblast": ["closecombat", "closecombat_actor"], "focusblast_hit": ["eruption", "eruption_target"], "flashcannon": ["aurorabeam", "aurorabeam_actor"], "flashcannon_hit": ["bulletpunch", "bulletpunch_target"], "outrage_cry": ["dragonclaw", "dragonclaw_actor"], "outrage": ["closecombat", "closecombat_actor"], "outrage_hit": ["dragonclaw", "dragonclaw_target"], "dragonpulse_charge": ["aurorabeam", "aurorabeam_actor"], "dragonpulse": ["dracometeor", "dracometeor_actor"], "dragonpulse_hit": ["dracometeor", "dracometeor_target"], "energyball": ["shadowball", "shadowball_actor"], "energyball_hit": ["shadowball", "shadowball_target"], "bite": ["bite", "bite_target"], "crunch": ["crunch", "crunch_target"], "thunderpunch": ["thundershock", "thundershock_target"], "dragonclaw": ["dragonclaw", "dragonclaw_actor"],
	"dragonclaw_hit": ["dragonclaw", "dragonclaw_target"], "airslash": ["aerialace", "aerialace_actor"],
	"airslash_hit": ["aerialace", "aerialace_target"], "earthquake": ["bulldoze", "bulldoze_actor"],
	"earthquake_hit": ["bulldoze", "bulldoze_target"], "flareblitz": ["flamewheel", "flamewheel_actor"],
	"flareblitz_hit": ["flamecharge", "flamecharge_target"], "electroball": ["thunderwave", "thunderwave"],
	"electroball_burst": ["thunder", "thunder"], "irontail": ["bulletpunch", "bulletpunch_target"],
	"rest": ["sing", "sing"], "electric_charge": ["thunderwave", "thunderwave"],
	"protection": ["protect", "protect_actor"], "dance": ["swordsdance", "swordsdance_actor"],
	"aquajet": ["watergun", "watergun_actor"], "hydropump": ["hydropump", "hydropump_actor"],
	"hydropump_hit": ["hydropump", "hydropump_target"], "rapidspin": ["withdraw", "withdraw_actor"],
	"icebeam": ["icebeam", "icebeam_actor"], "icebeam_hit": ["icebeam", "icebeam_target"],
	"vinewhip": ["razorleaf", "razorleaf_target"], "razorleaf": ["razorleaf", "razorleaf_actor"],
	"sludgebomb": ["sludgebomb", "sludgebomb_actor"], "sludgebomb_hit": ["sludgebomb", "sludgebomb_target"],
	"solarbeam_charge": ["leafstorm", "leafstorm_actor"], "solarbeam": ["leafstorm", "leafstorm_target"],
	"aurasphere": ["confusion", "confusion_actor"], "aurasphere_hit": ["confusion", "confusion_target"],
	"meteormash": ["bulletpunch", "bulletpunch_target"], "extremespeed": ["quickattack", "quickattack_actor"],
	"detect": ["protect", "protect_actor"], "shadowball": ["shadowball", "shadowball_actor"],
	"shadowball_hit": ["shadowball", "shadowball_target"], "hex": ["confusion", "confusion_target"],
	"substitute": ["protect", "protect_actor"], "dig": ["bulldoze", "bulldoze_actor"],
	"dig_emerge": ["bulldoze", "bulldoze_target"], "stoneedge": ["rockthrow", "rockthrow_actor"],
	"stoneedge_hit": ["rockthrow", "rockthrow_target"],
	"watershuriken": ["watergun", "watergun_actor"], "nightslash": ["aerialace", "aerialace_actor"],
	"doubleteam": ["doubleteam", "doubleteam"], "xscissor": ["aerialace", "aerialace_target"],
	"swordsdance": ["swordsdance", "swordsdance"], "wingattack": ["gust", "gust"],
	"takedown": ["bodyslam", "bodyslam_actor"], "doubleedge": ["closecombat", "closecombat_actor"],
	"gigaimpact": ["eruption", "eruption_actor"], "headbutt": ["seismictoss", "seismictoss_target"],
	"strength": ["bulldoze", "bulldoze_actor"], "rocksmash": ["rockthrow", "rockthrow_target"],
	"facade": ["superfang", "superfang_actor"], "megapunch": ["closecombat", "closecombat_target"],
	"megakick": ["seismictoss", "seismictoss_actor"], "brickbreak": ["crunch", "crunch_target"],
	"focuspunch_hit": ["closecombat", "closecombat_target"], "hyperbeam_charge": ["aurorabeam", "aurorabeam_actor"],
	"hyperbeam": ["dracometeor", "dracometeor_target"],
	"toxic": ["acid", "acid_actor"], "toxic_hit": ["acid", "acid_target"],
	"willowisp": ["willowisp", "willowisp_actor"], "willowisp_hit": ["willowisp", "willowisp_target"],
	"thunderwave": ["thunderwave", "thunderwave_actor"], "thunderwave_hit": ["thunderwave", "thunderwave_target"],
	"hypnosis": ["kinesis", "kinesis_actor"], "hypnosis_hit": ["kinesis", "kinesis_target"],
	"yawn": ["bubble", "bubble_actor"], "yawn_hit": ["bubble", "bubble_target"],
	"sleeppowder": ["sleeppowder", "sleeppowder_actor"], "sleeppowder_hit": ["sleeppowder", "sleeppowder_target"],
	"poisonpowder": ["poisonpowder", "poisonpowder_actor"], "poisonpowder_hit": ["poisonpowder", "poisonpowder_target"],
	"nuzzle": ["thundershock", "thundershock_actor"],
}

var main: Node
var _pool: Array = []
var _cache := {}
var _synth := {}
var volume := 1.0
var _ui: AudioStreamPlayer


## Every sound goes through one of two buses under Master: "SFX" (effects, cries, the
## menus' clicks) and "Music"; the options set their volumes (Settings.apply). Made here,
## so the project needs no bus layout file.
static func buses() -> void:
	for name in ["SFX", "Music"]:
		if AudioServer.get_bus_index(name) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, name)
			AudioServer.set_bus_send(i, "Master")


static func set_bus_volume(name: String, v: float) -> void:
	buses()
	var i := AudioServer.get_bus_index(name)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.001)))
	AudioServer.set_bus_mute(i, v <= 0.001)


func _ready() -> void:
	buses()
	for i in 24:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 10.0
		p.max_distance = 70.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)
	_synth["dodge"] = _whistle(0.22, 900.0, 3200.0, 0.55)
	_synth["jump"] = _whistle(0.14, 500.0, 1400.0, 0.35)
	_synth["footstep"] = _thud(0.12, 140.0, 0.6)
	_synth["fall"] = _thud(0.32, 90.0, 0.9)
	_synth["armor"] = _metal(0.35, 520.0)
	_synth["charge"] = _hum(0.6, 180.0, 520.0)
	_synth["light_hit"] = _thud(0.08, 260.0, 0.6)
	_synth["heavy_hit"] = _thud(0.25, 110.0, 1.0)
	_synth["ko"] = _whistle(0.9, 1600.0, 200.0, 0.4)
	_synth["ui_move"] = _notes([1320.0], 0.035)
	_synth["ui_ok"] = _notes([880.0, 1320.0], 0.055)
	_synth["ui_back"] = _notes([990.0, 660.0], 0.05)


func _player() -> AudioStreamPlayer3D:
	for p in _pool:
		if not p.playing:
			return p
	return _pool[0]


func _files(folder: String, prefix: String) -> Array:
	var k := folder + "/" + prefix
	if not _cache.has(k):
		var list := []
		for f in DirAccess.get_files_at(DIR + folder):
			var clean := f.replace(".import", "").replace(".remap", "")
			if clean.ends_with(".ogg") and clean.begins_with(prefix) and not list.has(clean):
				list.append(clean)
		_cache[k] = list
	return _cache[k]


## Plays a key: Cobblemon sounds first, then the synthesized ones.
func play_sound(key: String, pos: Vector3, vol := 0.0, tone := 1.0) -> void:
	var stream: AudioStream = null
	if COBBLEMON.has(key):
		var c: Array = COBBLEMON[key]
		var list := _files(c[0], c[1])
		if not list.is_empty():
			stream = load(DIR + c[0] + "/" + list.pick_random())
	elif _synth.has(key):
		stream = _synth[key]
	if stream == null:
		return
	_touch(stream, pos, vol, tone * randf_range(0.95, 1.05))


func impact(type: String, strength: int, pos: Vector3) -> void:
	var list := _files("impact_generic", "impact_generic_%s_" % type)
	if list.is_empty():
		list = _files("impact_generic", "impact_generic_normal_")
	if not list.is_empty():
		_touch(load(DIR + "impact_generic/" + list.pick_random()), pos, -2.0 + strength * 2.0, randf_range(0.95, 1.05) * (1.1 - strength * 0.08))
	_touch(_synth["heavy_hit" if strength >= 2 else "light_hit"], pos, -6.0 + strength * 2.0, 1.0)


func cry(species: String, pos: Vector3, tone := 1.0, vol := -2.0) -> void:
	var file_path := "res://pokemon/%s/cry.ogg" % species
	if ResourceLoader.exists(file_path):
		_touch(load(file_path), pos, vol, tone)


## Menu sounds, not placed in the world: "move" (cursor, Cobblemon's soft click a little
## higher), "ok" (two quick rising notes) and "back" (two falling ones). Quiet and short.
func ui(kind: String) -> void:
	if _ui == null:
		_ui = AudioStreamPlayer.new()
		_ui.bus = "SFX"
		_ui.max_polyphony = 4
		add_child(_ui)
	var s: AudioStream = null
	var vol := -16.0
	var pitch := 1.0
	match kind:
		"move":
			s = load("res://sounds/gui/click.ogg") if ResourceLoader.exists("res://sounds/gui/click.ogg") else _synth.get("ui_move")
			vol = -20.0
			pitch = randf_range(1.15, 1.22)
		"ok":
			s = _synth.get("ui_ok")
			vol = -15.0
		"back":
			s = _synth.get("ui_back")
			vol = -16.0
	if s == null:
		return
	_ui.stream = s
	_ui.volume_db = vol
	_ui.pitch_scale = pitch
	_ui.play()


func _touch(s: AudioStream, pos: Vector3, vol: float, tone: float) -> void:
	var p := _player()
	p.stream = s
	p.volume_db = vol
	p.pitch_scale = tone
	p.global_position = pos
	p.play()


# ---------------------------------------------------------------- synthesis (placeholder)

func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = 22050
	w.stereo = false
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	w.data = bytes
	return w


## Filtered noise sweeping from one frequency to another (dodges, jumps).
func _whistle(dur: float, f0: float, f1: float, vol: float) -> AudioStreamWAV:
	var n := int(22050 * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var y := 0.0
	for i in n:
		var k := float(i) / n
		var f := lerpf(f0, f1, k)
		var a := clampf(f / 22050.0 * 6.0, 0.01, 0.9)
		y += (randf_range(-1, 1) - y) * a
		var env := sin(k * PI) * (1.0 - k * 0.3)
		out[i] = y * env * vol * 2.0
	return _wav(out)


## Thud: a low falling sine plus a click of noise.
func _thud(dur: float, f: float, vol: float) -> AudioStreamWAV:
	var n := int(22050 * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var k := float(i) / n
		phase += TAU * f * (1.0 - k * 0.6) / 22050.0
		var env := exp(-k * 7.0)
		out[i] = (sin(phase) * 0.8 + randf_range(-1, 1) * exp(-k * 40.0) * 0.5) * env * vol
	return _wav(out)


func _metal(dur: float, f: float) -> AudioStreamWAV:
	var n := int(22050 * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var k := float(i) / n
		var t := float(i) / 22050.0
		var s := sin(TAU * f * t) + 0.6 * sin(TAU * f * 2.76 * t) + 0.4 * sin(TAU * f * 5.4 * t)
		out[i] = s * exp(-k * 9.0) * 0.35 + randf_range(-1, 1) * exp(-k * 60.0) * 0.4
	return _wav(out)


## Soft notes one after another (menu sounds): a sine with a quick attack and decay and a
## touch of its octave, like a small chime.
func _notes(freqs: Array, each: float) -> AudioStreamWAV:
	var n := int(22050 * each)
	var out := PackedFloat32Array()
	out.resize(n * freqs.size())
	for j in freqs.size():
		var f: float = freqs[j]
		for i in n:
			var t := float(i) / 22050.0
			var env := minf(1.0, t / 0.004) * exp(-t / each * 3.0)
			out[j * n + i] = (sin(TAU * f * t) * 0.8 + sin(TAU * f * 2.0 * t) * 0.15) * env * 0.5
	return _wav(out)


func _hum(dur: float, f0: float, f1: float) -> AudioStreamWAV:
	var n := int(22050 * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var k := float(i) / n
		phase += TAU * lerpf(f0, f1, k) / 22050.0
		out[i] = (sin(phase) * 0.5 + sin(phase * 2.01) * 0.25 + randf_range(-1, 1) * 0.08) * sin(k * PI) * 0.6
	return _wav(out)
