class_name Fighter
extends CharacterBody3D
## A Pokémon in battle. Player and AI use this same class: what changes is who fills
## in its Intent.
##
## States:
##   free          moves, jumps, dodges and can start actions
##   action        an attack or move in progress (Action: startup, active, recovery)
##   dodge         start, a dash with invulnerability and a punishable recovery
##   stunned       took a hit: cannot act until it wears off
##   knocked_down  launched or knocked over; then lying, then get_up with a moment of
##                 invulnerability
##   dive          a ground move used in the air: drops down and fires it on landing
##   ko            defeated
##
## Rules against lockdowns: stun gets shorter with each hit of the same combo and the
## fifth one knocks it down (it leaves the combo and gets up invulnerable).

signal defeated(who: Fighter)
signal hit_taken(who: Fighter, info: Dictionary)

const BUFFER := 0.15                 # how long a press waits to be executed
const ENERGY_MAX := 100.0
const ENERGY_REGEN := 9.0           # per second
const COMBO_MAX := 5
const DODGE_DELAY := 1.1        # s from the start of a dodge until charges start refilling again
const RECOIL := 0.85               # speed when backing away from the locked-on rival

var main: Node
var species := "pikachu"
var data: Dictionary
var types: Array = []
var team := 0
var rival: Fighter
var ctrl := Intent.new()
var is_player := false
var is_remote := false               # online: the rival's copy, moved by the network
var net_state := {}                 # last real state received from the rival
var net_lead := 0                # frames to fast-forward whatever starts (the ping)
var start_pos := Vector3.ZERO       # where each battle starts (rematch)
var start_yaw := 0.0

var hp := 100.0
var hp_max := 100.0
var energy := ENERGY_MAX
var charges := 3.0                    # dodges available
var flight := 0.0                     # flight stamina left (seconds)
var flying := false
var _ground_t := 0.0                  # time on the ground (flight recharge waits a bit)
var _dive_move := ""                # move waiting to touch the ground (Earthquake in the air)
var _dive_button := ""
var cds := {}                        # move -> seconds of cooldown left
var uses := {}                       # moves with limited uses (Rest)
var state := "free"
var action: Action = null
var locked := true
var face_yaw := 0.0                  # where it faces (the +Z of its frame)
var slow := 1.0                     # Ice, Static...
## Confused (Outrage's rage wearing off, and moves to come): seconds left with its movement
## turned around, as with an inverted stick: left goes right, forward goes back. It sits
## alongside a status (burned and confused at once is possible). Stars circle its head.
var confused := 0.0
var _locked_decoy := false            # locked on a decoy (when it goes, the lock goes)
var ai_driven := false                # its moves come from the AI (it never unlocks)
var _confuse_fx := 0.0
var _slow_t := 0.0
var static_mark := 0.0
var burned := 0.0
var poisoned := 0.0
var wet := 0.0                    # Rain Dish (Blastoise)
var chlorophyll := 0.0                 # Chlorophyll (Venusaur)
var steadfast_t := 0.0                 # Steadfast (Lucario)
## Stat stages, as in the games: each +1 is x1.5 (+2 x2...), each -1 x2/3; -6 to +6. They
## last the whole battle. Attack and Sp. Atk change damage, Defense and Sp. Def what it
## takes, Speed how fast it moves.
var stages := {"atk": 0, "def": 0, "spa": 0, "spd": 0, "spe": 0}
var _berry_used := false             # Gluttony (Snorlax)
## Major status condition (Status): "", "brn", "par", "psn", "tox", "slp", "frz".
var status := ""
var status_t := 0.0                  # seconds left
var status_lock := 0.0               # just cured: no new status yet
var shots := 0                       # projectiles fired this battle (Combat numbers them)
var drowsy := 0.0                    # Yawn: seconds before it falls asleep
var _status_age := 0.0
var _status_tick := 0.0
var _status_dealt := 0.0
var _para_roll := 0.0
var _status_fx := 0.0
var translucent := 0.0               # Substitute (Gengar)
var _skin_t := 0.0
var fooled_by: Node3D = null         # decoy it is locked on (the AI falls for it; a player picks it)
var ai_aim = null                    # AI only: where it thinks the rival is (delayed, with error)
var aim_lead := 1.0                  # how much projectiles lead a moving target (the AI uses less)
var _hit_ms := -100000               # when it was last hit (Time ms), for the ring-out log
var _left_as := ""                   # what it was doing when it went off the edge (same log)
var head_pitch := 0.0                   # tilt of hits toward the target's height (rad)
var air_jumps := 0                 # jumps left in the air (Greninja: double jump)
var boosted_hits := 0                        # hits boosted by Swords Dance
var _boost_t := 0.0                  # seconds left on the Swords Dance boost
var _passive_t := 0.0
var invulnerable := 0.0
var vulnerable := 1.0                # >1 takes more damage (Rest)

var _buffer := {}                    # action -> seconds left
var _frozen := 0.0
var _state_t := 0.0
var _stunned := 0.0
var _combo := 0
var _combo_clear := 0.0
var _dodge_dir := Vector3.ZERO
var _last_dodge := -10.0
var _dodge_fatigue := false
var _dodge_reach := 1.0              # slowness (streams, ice) shortens the dodge
var _energy_pause := 0.0
var _was_grounded := true
var _time := 0.0
var _rumble_ok := true

# Visual
var pivot: Node3D                   # receives the procedural pose
## Only for show: how far it has come out of its Poké Ball (0 inside, 1 out) and how white
## it still glows from it (the battle's opening, main.gd).
var appear := 1.0
var appear_glow := 0.0
var model: PokeModel
var _scale := 1.0
var _pose := {"tilt": 0.0, "side": 0.0, "turn": 0.0, "stretch": 1.0, "height": 0.0, "spin": 0.0}
var _flash := 0.0
var _afterimage_t := 0.0
var _cheer := ""
var _feet: Array = []                # lowest bones of the model (so it does not sink)
var _above_ground := 0.0              # how much the body is raised if the feet sink


## "loadout": its moves and ability (Loadout); empty, the roster's defaults.
func setup(m: Node, sp: String, eq: int, loadout := {}) -> void:
	main = m
	species = sp
	team = eq
	data = Stats.battle_data(sp)
	if not loadout.is_empty():
		data.moves = loadout.moves.duplicate()
		data.passive = Loadout.ability(sp, loadout.ability)
	if data.passive.id == "lightmetal":
		# Half its weight: it dodges a little further (weight counts on a log scale) and is
		# knocked further (speed goes with 1/mass; tamed to x1.25 here).
		data.weight_kg = float(data.get("weight_kg", 100.0)) * 0.5
		data.dodge.dist = snappedf(float(data.dodge.dist) + 0.085 * log(2.0), 0.1)
		data.knockback = float(data.knockback) * 1.25
	types = data.types
	hp_max = data.hp
	hp = hp_max
	charges = data.dodge.charges
	flight = _flight_max()
	collision_layer = 2
	collision_mask = 1 | 4
	floor_snap_length = 0.3
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = minf(data.radius, 0.6)
	cap.height = maxf(data.height * 0.9, cap.radius * 2.0 + 0.05)
	col.shape = cap
	col.position.y = cap.height * 0.5
	add_child(col)
	pivot = Node3D.new()
	add_child(pivot)
	model = PokeModel.new()
	model.setup(sp)
	var box: AABB = model._res.mesh.get_aabb()
	_scale = data.height / maxf(box.size.y, 0.05)
	model.scale = Vector3.ONE * _scale
	model.rotation.y = PI
	pivot.add_child(model)
	_animate_base(0.0)


# ---------------------------------------------------------------- what combat asks

## Frame for hits: faces face_yaw and, when attacking, tilts toward the target's height
## (pitch), rotating around the center of the body.
func body_basis() -> Transform3D:
	var b := Basis(Vector3.UP, face_yaw)
	if absf(head_pitch) < 0.001:
		return Transform3D(b, global_position)
	b = b * Basis(Vector3.RIGHT, -head_pitch)
	var half: Vector3 = Vector3.UP * data.height * 0.5
	return Transform3D(b, global_position + half - b * half)


## Where a hit goes: forward, tilted toward the target's height.
func attack_dir() -> Vector3:
	return body_basis().basis.z


## Vertical aim assist for hits: if the target is in front and at another height (or
## it attacks from the air), hits and their lunges tilt toward it.
func _update_head_pitch() -> void:
	head_pitch = 0.0
	if state != "action" and state != "dive":
		return
	var b := aim_target()
	if b == null or not is_instance_valid(b) or (b is Fighter and b.state == "ko"):
		return
	var toward: Vector3 = target_center() - center()
	var plane := Vector2(toward.x, toward.z).length()
	if plane > 9.0 or plane < 0.05 or Vector3(toward.x, 0, toward.z).normalized().dot(forward()) < 0.3:
		return
	if is_on_floor() and absf(toward.y) < 1.2:
		return
	head_pitch = clampf(atan2(toward.y, maxf(plane, 0.5)), -1.1, 1.1)


func forward() -> Vector3:
	return Vector3(sin(face_yaw), 0.0, cos(face_yaw))


func body() -> Array:
	var r := radius()
	var a := global_position + Vector3.UP * r
	var b := global_position + Vector3.UP * maxf(r, data.height - r)
	return [a, b]


func radius() -> float:
	return data.radius


func center() -> Vector3:
	return global_position + Vector3.UP * data.height * 0.5


## A body point from Cobblemon's locators (mouth, hands, tail...).
func point(locator: String) -> Vector3:
	if model and model.skel.find_bone(locator) >= 0:
		return model.bone_world(locator)
	return center() + forward() * data.radius


func hittable() -> bool:
	return state != "ko"


func on_floor() -> bool:
	if data.get("levitates", false):
		return false
	return is_on_floor() or global_position.y < main.ground_y + 0.15


## What it looks at and aims at: the rival, or a decoy it is locked on (the AI falls for
## one; Substitute locks its rival on its doll; a player can pick one, see switch_target).
func aim_target() -> Node3D:
	if fooled_by and is_instance_valid(fooled_by) and not fooled_by.is_queued_for_deletion():
		return fooled_by
	return rival


## Not locked on: its moves go where the camera looks (Action.aim), not at the rival. Only
## players unlock; the AI is always locked on.
func free_aim() -> bool:
	return not locked


## Where the camera looks, flat (free aim).
func camera_forward() -> Vector3:
	return Vector3(-sin(ctrl.yaw), 0.0, -cos(ctrl.yaw))


## What it can lock on: the rival and the rival's decoys (Substitute's doll, Double Team's
## clones): it cannot always tell the real one.
func lock_candidates() -> Array:
	var out: Array = []
	if rival and is_instance_valid(rival) and rival.state != "ko":
		out.append(rival)
	for o in main.combat.targets:
		if o is Decoy and is_instance_valid(o) and o.user == rival and not o.is_queued_for_deletion():
			out.append(o)
	return out


## Locks on whatever is closest to where the camera looks (the real one or not).
func lock_on_looked() -> void:
	locked = true
	var best: Node3D = rival
	var best_a := INF
	var look := camera_forward()
	for o in lock_candidates():
		var to: Vector3 = o.global_position - global_position
		to.y = 0.0
		if to.length() < 0.1:
			continue
		var a := look.angle_to(to.normalized())
		if a < best_a:
			best_a = a
			best = o
	fooled_by = null if best == rival else best


## Souls style: the next target to the right (side 1) or the left (-1) of the current one
## on screen, among the rival and its decoys.
func switch_target(side: int) -> void:
	var cur: Node3D = aim_target()
	if cur == null:
		return
	var right := Vector3(cos(ctrl.yaw), 0.0, -sin(ctrl.yaw))
	var here: float = right.dot(cur.global_position - global_position)
	var best: Node3D = null
	var best_d := INF
	for o in lock_candidates():
		if o == cur:
			continue
		var d: float = (right.dot(o.global_position - global_position) - here) * side
		if d > 0.05 and d < best_d:
			best_d = d
			best = o
	if best:
		fooled_by = null if best == rival else best


## How high the feet can rise with hits and dashes that go upward: its jump height
## plus one meter. Flyers have no ceiling. This way a ground Pokémon does not "fly"
## chasing a Charizard in the air.
func attack_ceiling() -> float:
	if data.has("flight") or flying:
		return INF
	var g: float = maxf(float(data.gravity), 1.0)
	return main.ground_y + float(data.jump) * float(data.jump) / (2.0 * g) + 1.0


func target_center() -> Vector3:
	var b := aim_target()
	return b.center() if b else center() + forward() * 3.0


## A major status condition (for Hex and Facade).
func has_status() -> bool:
	return status != ""


## Gives it a major status condition if it can get it (types, ability, none already), as
## in the games. Online, on the rival's copy, it is sent to the rival, who decides.
## Confusion for "secs" seconds (longer wins), said over its head.
func confuse(secs: float) -> void:
	if state == "ko":
		return
	if confused <= 0.0:
		main.vfx.text(center() + Vector3.UP * 1.0, tr("Confused!"), Color(0.85, 0.7, 1.0))
	confused = maxf(confused, secs)


func inflict(kind: String) -> bool:
	if state == "ko" or status != "" or status_lock > 0.0 or not Status.can_get(kind, types, data.passive.id):
		return false
	if is_remote:
		main.net.send_event({"t": "effect", "type": "status", "v": 0.0, "move": kind})
		return true
	status = kind
	status_t = Status.DURATION.get(kind, 0.0)
	_status_age = 0.0
	_status_tick = Status.TICK
	_status_dealt = 0.0
	_para_roll = Status.PARA_ROLL
	main.vfx.text(center() + Vector3.UP * 0.9, Status.text(kind), Status.COLOR[kind])
	main.hud.log_entry(tr("%s: %s") % [tr(data.display_name), Status.text(kind)])
	match kind:
		"slp":
			status_t = randf_range(Status.SLEEP.x, Status.SLEEP.y)
			stun_target(status_t)
		"frz":
			status_t = randf_range(Status.FREEZE.x, Status.FREEZE.y)
			stun_target(status_t)
	return true


## Cures it; for a while it cannot get another one (IMMUNE_AFTER).
func cure_status(lock := true) -> void:
	if status != "" and lock:
		status_lock = Status.IMMUNE_AFTER
	status = ""
	status_t = 0.0
	_status_age = 0.0


## Per frame: the chip damage, paralysis, and wearing off (each copy decides its own
## Pokémon; online the rival's HP comes with its state), and the look of it.
func _status_process(delta: float) -> void:
	status_lock = maxf(0.0, status_lock - delta)
	if drowsy > 0.0 and state != "ko":
		drowsy -= delta
		_status_fx -= delta
		if _status_fx <= 0.0:
			_status_fx = 0.9
			main.fx.anim("generic/status/sleep_zzz.png", global_position + Vector3(0.3, data.height + 0.3, 0), 0.5, 16, 0.9)
		if drowsy <= 0.0 and not is_remote:
			inflict("slp")
	if status == "" or state == "ko":
		return
	if not is_remote:
		_status_age += delta
		var chip := hp_max * Status.rate(status, _status_age) * delta
		if chip > 0.0:
			_damage_direct(chip)
			_status_dealt += chip
		_status_tick -= delta
		if _status_tick <= 0.0:
			_status_tick += Status.TICK
			if _status_dealt > 0.5:
				main.vfx.number(center(), _status_dealt, 1.0)
			_status_dealt = 0.0
		if status == "par":
			_para_roll -= delta
			if _para_roll <= 0.0:
				_para_roll = Status.PARA_ROLL
				if randf() < Status.PARA_CHANCE and state in ["free", "action"]:
					stun_target(Status.PARA_T)
					main.vfx.text(center() + Vector3.UP * 0.9, tr("Fully paralyzed!"), Status.COLOR.par)
		status_t -= delta
		if status_t <= 0.0:
			main.vfx.text(center() + Vector3.UP * 0.9, Status.cured_text(status), Status.COLOR[status])
			cure_status()
			return
	# The look of it: Cobblemon's status sprites and the types' particles.
	_status_fx -= delta
	if _status_fx <= 0.0:
		match status:
			"par":
				_status_fx = 0.5
				main.fx.anim("generic/status/paralysis_spark.png", center() + Vector3(randf_range(-0.4, 0.4), randf_range(0.0, 0.5), 0), 0.5, 10, 0.4)
			"slp":
				_status_fx = 0.7
				main.fx.anim("generic/status/sleep_zzz.png", global_position + Vector3(0.3, data.height + 0.35, 0), 0.7, 16, 1.0)
			"brn":
				_status_fx = 0.35
				main.vfx.burst("fire_fx", center() + Vector3.UP * 0.2, Vector3.UP, Color(0, 0, 0, 0), 0.25)
			"psn", "tox":
				_status_fx = 0.4
				main.vfx.burst("shadow", center(), Vector3.UP, Status.COLOR[status], 0.25)
			"frz":
				_status_fx = 0.25
				main.vfx.burst("ice_fx", center(), Vector3.UP, Color(0, 0, 0, 0), 0.35)


## Effect on this fighter caused by the rival (Rough Skin, Static, Detect). If this is
## an online rival's copy, it is sent to the rival, who is in charge of its own
## Pokémon.
func effect(type: String, value: float, move := "") -> void:
	if is_remote:
		main.net.send_event({"t": "effect", "type": type, "v": value, "move": move})
		return
	match type:
		"damage":
			_damage_direct(value)
		"static_charge":
			static_mark = value
		"stun":
			stun_target(value)
		"status":
			inflict(move)
		"self_boost":
			if stages.has(move):
				boost(move, int(value))
		"disable":
			# Disable: that move cannot be used for a while.
			if Moves.DATA.has(move):
				cds[move] = maxf(cds.get(move, 0.0), value)
				main.vfx.text(center() + Vector3.UP * 0.9, tr("%s is disabled!") % tr(Moves.DATA[move].display_name), Color(0.75, 0.6, 1.0))


## Online copy: moves toward the rival's real state (position extrapolated with the
## ping, HP, resources and hits taken there, which the rival decides).
func _net_correct(delta: float) -> void:
	if main.net == null:
		net_state = {}
		return
	var s := net_state
	hp = s.hp
	energy = s.energy
	charges = s.charges
	flight = s.flight
	flying = s.flying
	slow = s.slow
	_slow_t = s.slow_t
	var had := status
	status = Net.STATUSES[clampi(int(s.burned), 0, Net.STATUSES.size() - 1)]
	if had != "" and status == "":
		status_lock = Status.IMMUNE_AFTER
	status_t = s.poisoned
	_status_age = s.static_mark
	steadfast_t = s.steadfast_t
	translucent = s.translucent
	invulnerable = s.invulnerable
	boosted_hits = s.boosted_hits
	types = s.types
	if state != "ko" and s.state == "ko":
		_die({})
		return
	if s.state in ["stunned", "knocked_down", "lying", "get_up"] and state != s.state and state != "ko":
		if action:
			action.finish(true)
			action = null
		_switch_state(s.state)
		_stunned = s.stunned
		if s.state in ["stunned", "knocked_down"] and model.has_anim("recoil"):
			model.play("recoil", 0.03, true)
	var age_t: float = s.outbound + (main.net._t - s.received)
	var target: Vector3 = s.pos + s.speed * clampf(age_t, 0.0, 0.3)
	var error := target - global_position
	if error.length() > 2.5:
		global_position = target
		reset_physics_interpolation()
	else:
		global_position += error * (1.0 - exp(-12.0 * delta))
	face_yaw = lerp_angle(face_yaw, s.yaw, 1.0 - exp(-14.0 * delta))


## Stunned from outside (Detect): drops whatever it was doing.
func stun_target(t: float) -> void:
	if state == "ko":
		return
	if action:
		_cut_cooldown()
		action.finish(true)
		action = null
	_switch_state("stunned")
	_stunned = t
	velocity = Vector3(0, minf(velocity.y, 0.0), 0)


func frozen() -> bool:
	return _frozen > 0.0


func freeze(t: float) -> void:
	_frozen = maxf(_frozen, t)


func rumble_pad(weak: float, strong: float, dur: float) -> void:
	if is_player and main.options.rumble:
		Input.start_joy_vibration(0, weak, strong, dur)


func cd(move: String) -> float:
	return cds.get(move, 0.0)


func ready(move: String) -> bool:
	var d: Dictionary = Moves.DATA[move]
	return cd(move) <= 0.0 and energy >= d.get("cost", 0.0) and uses.get(move, 1) > 0


# ---------------------------------------------------------------- step

func _physics_process(delta: float) -> void:
	_time += delta
	# Each copy decides its own Pokémon's fall (online, the rival's copy just follows).
	if not is_remote and state != "ko" and global_position.y < main.arena.void_y:
		_ring_out()
		return
	if main.arena.void_y != -INF and _left_as == "" and global_position.y < -0.5:
		_left_as = state + (" " + action.id if action else "")
	if _frozen > 0.0:
		# Hitstop: everything frozen, the animation too.
		_frozen -= delta
		model.speed = 0.0
		ctrl.clear()
		return
	_update_head_pitch()
	_timers(delta)
	_read_buffer(delta)
	_state_t += delta
	var on_ground := is_on_floor()
	match state:
		"free":
			_move_free(delta, on_ground)
			_try_actions(on_ground)
		"action":
			_step_action(delta, on_ground)
		"dodge":
			_step_dodge(delta)
		"stunned":
			# Slides back with ground friction (Knockback.FRICTION) and stays stunned until
			# the slide ends. Asleep or frozen, it stays put until that wears off.
			_brake(delta, Knockback.FRICTION / 3.0 if on_ground else 2.0)
			if status in ["slp", "frz"]:
				_stunned = maxf(_stunned, status_t)
			_stunned -= delta
			if _stunned <= 0.0 and on_ground and Vector2(velocity.x, velocity.z).length() < 0.8:
				_to_free()
			elif _stunned <= -0.6:
				_to_free()
		"knocked_down":
			_brake(delta, Knockback.FRICTION / 3.0 if on_ground else 0.5)
			if on_ground and _state_t > 0.25 and velocity.y <= 0.0:
				_switch_state("lying")
				main.vfx.dust(global_position, data.radius * 1.6)
				main.audio.play_sound("fall", global_position, -4.0)
			# Knocked off into a void it would never land: after a moment it regains
			# control in the air, so a flyer can fly back (and anyone can steer).
			elif not on_ground and _state_t > 0.6 and main.arena.void_y != -INF and global_position.y < -1.0:
				_to_free()
		"lying":
			_brake(delta, 14.0)
			if _state_t >= 0.55:
				_switch_state("get_up")
				invulnerable = 0.45
		"get_up":
			_brake(delta, 14.0)
			if _state_t >= 0.3:
				_to_free()
		"ko":
			_brake(delta, 6.0)
		"dive":
			_brake(delta, 1.0)
			_afterimage_t -= delta
			if _afterimage_t <= 0.0:
				_afterimage_t = 0.05
				main.vfx.afterimage(self, Color(1.0, 0.9, 0.7))
			if on_ground:
				main.vfx.dust(global_position, data.radius * 1.5)
				_to_free()
				if ready(_dive_move):
					start(_dive_move, _dive_button)
					main.hud.log_entry(tr("%s used %s!") % [tr(data.display_name), tr(Moves.DATA[_dive_move].display_name)])
	if flying and state in ["free", "action", "dodge"]:
		_flight_control(delta)
	elif state != "action" or not action or not action.no_gravity:
		velocity.y -= data.gravity * delta * (2.2 if state == "dive" else 1.0)
	_separate()
	var before := global_position
	move_and_slide()
	_edge_stop(before)
	if is_remote and not net_state.is_empty():
		_net_correct(delta)
	if on_ground and not _was_grounded and state in ["free", "action"]:
		_land()
	_was_grounded = is_on_floor()
	ctrl.clear()


## On stages with a void, a move never carries its user off the edge (a Quick Attack or an
## Extreme Speed stops at it): only being knocked off, dodging out or walking out are falls.
func _edge_stop(before: Vector3) -> void:
	if main.arena.void_y == -INF or is_remote or state not in ["action", "dive"]:
		return
	var p := global_position
	if main.arena.inside(p, 0.2):
		return
	# Already outside (pushed close to the edge): only stop moving further out.
	if Vector2(p.x, p.z).length() <= Vector2(before.x, before.z).length():
		return
	global_position = Vector3(before.x, p.y, before.z)
	velocity.x = 0.0
	velocity.z = 0.0


## A move's secondary effect as in the games ("secondary": {"chance", and "status", "boost"
## on the target or "self" on the user}). A stream's ticks share the chance of one use.
## A status move that touched it (Toxic, Will-O-Wisp, the powders...): no damage or stun,
## only its status, if it can get it. As in the games, the type chart stops some ("respects_
## types": Thunder Wave does nothing to Ground types) and Grass types and Overcoat ignore
## powders.
func _status_move(md: Dictionary, info: Dictionary) -> String:
	var kind: String = md.get("inflicts", "")
	# Why it fails, as the games tell it: the type (or the ability), a status it already
	# has, or the few seconds after one wears off.
	var why := ""
	if (md.get("respects_types", false) and Roster.immune(info.hit.type, types)) \
			or (md.get("powder", false) and ("grass" in types or data.passive.id == "overcoat")) \
			or not Status.can_get("slp" if kind == "drowsy" else kind, types, data.passive.id):
		why = tr("No effect")
	elif status != "" or drowsy > 0.0:
		why = tr("Already has a status")
	elif status_lock > 0.0:
		why = tr("Temporary immunity")
	elif kind == "drowsy":
		drowsy = Status.YAWN
		main.vfx.text(center() + Vector3.UP * 0.9, tr("Drowsy..."), Status.COLOR.slp)
	else:
		inflict(kind)
	if why != "":
		main.vfx.text(center() + Vector3.UP * 0.9, why, Color(0.75, 0.77, 0.85))
		return "status"
	var at: Fighter = info.attacker if info.attacker is Fighter else null
	for piece in md.get("fx_hit", []):
		main.vfx.cobble(piece, center(), at.center() if at else null, data.height)
	main.audio.play_sound(info.hit.move_id + "_hit", center(), -3.0)
	return "status"


func _secondary(md: Dictionary, info: Dictionary, at: Fighter) -> void:
	if not md.has("secondary") or Roster.immune(info.hit.type, types):
		return
	var sec: Dictionary = md.secondary
	var chance: float = float(sec.get("chance", 1.0)) / float(md.get("split", 1))
	if randf() >= chance:
		return
	if sec.has("status"):
		inflict(sec.status)
	for stat in sec.get("boost", {}):
		boost(stat, int(sec.boost[stat]))
	if at and is_instance_valid(at):
		for stat in sec.get("self", {}):
			at.effect("self_boost", float(sec.self[stat]), stat)


## A move cut short by a hit or a stun: if it had already gone off (past its startup) it
## was used and goes on cooldown; cut while winding up, it was not (as a flinch in the
## games: the move never happens).
func _cut_cooldown() -> void:
	if action and action.phase != "startup":
		_start_cooldown(action.id)


## A used move goes on cooldown (keeping a longer one already set, like a Disable).
func _start_cooldown(move: String) -> void:
	var c: float = Moves.cooldown(move)
	if c > 0.0:
		cds[move] = maxf(cds.get(move, 0.0), c)


func _timers(delta: float) -> void:
	for k in cds.keys():
		cds[k] = maxf(0.0, cds[k] - delta)
	invulnerable = maxf(0.0, invulnerable - delta)
	static_mark = maxf(0.0, static_mark - delta)
	if confused > 0.0:
		confused = maxf(0.0, confused - delta)
		_confuse_fx -= delta
		if _confuse_fx <= 0.0:
			_confuse_fx = 0.2
			var a := _time * 4.0
			var head: Vector3 = global_position + Vector3.UP * (data.height + 0.35)
			main.vfx.burst("stars", head + Vector3(cos(a), 0.0, sin(a)) * (data.radius * 0.8 + 0.2), Vector3.UP, Color(0, 0, 0, 0), 0.3)
	_flash = maxf(0.0, _flash - delta * 6.0)

	_slow_t -= delta
	if _slow_t <= 0.0:
		slow = 1.0
	_energy_pause -= delta
	if _energy_pause <= 0.0 and state != "ko":
		energy = minf(ENERGY_MAX, energy + ENERGY_REGEN * delta)
	var dodge_cfg: Dictionary = data.dodge
	# Like stamina in Elden Ring: after dodging, charges do not start coming back
	# until a while later (use it well, not recklessly).
	if charges < dodge_cfg.charges and state != "dodge" and _time - _last_dodge > float(dodge_cfg.get("delay", DODGE_DELAY)):
		charges = minf(dodge_cfg.charges, charges + delta / dodge_cfg.recharge)
	_flight_timers(delta)
	_status_process(delta)
	_passive_t -= delta
	if wet > 0.0:
		wet -= delta
		if state != "ko":
			heal(hp_max * 0.009 * delta)
		if _passive_t <= 0.0:
			_passive_t = 0.22
			main.vfx.burst("water_fx", global_position + Vector3.UP * data.height, Vector3.DOWN, Color(0, 0, 0, 0), 0.3)
	if steadfast_t > 0.0:
		steadfast_t -= delta
		if _passive_t <= 0.0:
			_passive_t = 0.12
			main.vfx.burst("stars", center(), Vector3.UP, Color(0.45, 0.65, 1.0), 0.3)
	# Substitute: invisible for the rival; a faint ghost for whoever plays it.
	if translucent > 0.0:
		translucent -= delta
		var hidden := translucent > 0.0
		var sees_self: bool = is_player or (main.net != null and not is_remote)
		model.visible = not hidden or sees_self
		model.mesh_instance.transparency = 0.85 if hidden and sees_self else 0.0
		model.mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if hidden else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_skin_t -= delta
	if boosted_hits > 0:
		_boost_t -= delta
		if _boost_t <= 0.0:
			boosted_hits = 0
		elif int(_time * 20.0) % 4 == 0:
			main.vfx.burst("stars", point("locator_hand_primary"), Vector3.UP, Color(1.0, 0.85, 0.5), 0.2)
	if chlorophyll > 0.0:
		chlorophyll -= delta
		if _passive_t <= 0.0:
			_passive_t = 0.18
			main.vfx.burst("leaves", center(), Vector3.UP, Color(0, 0, 0, 0), 0.25)
	if state in ["free"]:
		_combo_clear += delta
		if _combo_clear > 0.5:
			_combo = 0


func _read_buffer(delta: float) -> void:
	for k in _buffer.keys():
		_buffer[k] -= delta
		if _buffer[k] <= 0.0:
			_buffer.erase(k)
	for k in ctrl.pressed:
		_buffer[k] = BUFFER
	if ctrl.pressed.has("lock_on"):
		# Locking on picks what the camera looks at (a decoy, maybe).
		if locked:
			locked = false
			fooled_by = null
		else:
			lock_on_looked()
		_buffer.erase("lock_on")
	# The decoy it was locked on is gone: the camera is free; lock on again to find the real
	# one (the AI just goes back to the rival).
	if _locked_decoy and not (fooled_by and is_instance_valid(fooled_by) and not fooled_by.is_queued_for_deletion()):
		_locked_decoy = false
		fooled_by = null
		if not ai_driven:
			locked = false
	elif fooled_by and is_instance_valid(fooled_by):
		_locked_decoy = true


func _wants(a: String) -> bool:
	return _buffer.has(a)


func _consume(a: String) -> void:
	_buffer.erase(a)


# ---------------------------------------------------------------- movement

func _world_dir(v: Vector2) -> Vector3:
	if confused > 0.0:
		v = -v
	var yaw := ctrl.yaw
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var d := right * v.x + fwd * v.y
	return d.limit_length(1.0)


func _move_free(delta: float, on_ground: bool, mult := 1.0) -> void:
	var extra := (1.35 if translucent > 0.0 else 1.0) * speed_stage() * (0.5 if status == "par" else 1.0)
	var wants: Vector3 = _world_dir(ctrl.move_input) * data.speed * slow * mult * extra
	# Backing away (moving away from the locked-on rival) is 15% slower.
	if locked and rival and is_instance_valid(rival) and wants.length() > 0.1:
		var to_rival := Vector3(rival.global_position.x - global_position.x, 0, rival.global_position.z - global_position.z).normalized()
		if wants.normalized().dot(to_rival) < -0.5:
			wants *= RECOIL
	if flying:
		wants *= float(data.flight.get("speed", 1.0))
	var accel: float = data.accel * (1.0 if on_ground or flying else data.air_control * 0.6)
	var h := Vector3(velocity.x, 0, velocity.z).move_toward(Vector3(wants.x, 0, wants.z), accel * delta)
	velocity.x = h.x
	velocity.z = h.z
	# Facing: the rival if locked on; otherwise, where it moves.
	if locked and rival and is_instance_valid(rival) and rival.state != "ko":
		turn_toward(aim_target().global_position, delta)
	elif wants.length() > 0.5:
		turn_toward(global_position + wants, delta)


func turn_toward(p: Vector3, delta: float, mult := 1.0) -> void:
	var v := p - global_position
	if Vector2(v.x, v.z).length() < 0.05:
		return
	var target := atan2(v.x, v.z)
	var d := wrapf(target - face_yaw, -PI, PI)
	var step: float = data.turn * mult * delta
	face_yaw += clampf(d, -step, step)


func face_now(p: Vector3) -> void:
	var v := p - global_position
	if Vector2(v.x, v.z).length() > 0.05:
		face_yaw = atan2(v.x, v.z)


func _brake(delta: float, f: float) -> void:
	var h := Vector3(velocity.x, 0, velocity.z).move_toward(Vector3.ZERO, f * delta * 3.0)
	velocity.x = h.x
	velocity.z = h.z


# ---------------------------------------------------------------- flight

func _flight_max() -> float:
	return float(data.flight.stamina) if data.has("flight") else 0.0


## Takes off (jump again in the air) if it has stamina left.
func _take_off() -> bool:
	if not data.has("flight") or flying or flight < 0.4:
		return false
	flying = true
	velocity.y = maxf(velocity.y, 2.0)
	main.vfx.burst("wind", global_position, Vector3.DOWN, Color(0, 0, 0, 0), 1.0)
	main.audio.play_sound("jump", global_position, -6.0, 0.8)
	return true


func _flight_control(delta: float) -> void:
	var v: Dictionary = data.flight
	var target := 0.0
	if state == "free":
		var altitude: float = global_position.y - main.ground_y
		if ctrl.keeps("jump") and altitude < float(v.ceiling):
			target = float(v.climb)
		elif ctrl.keeps("descend"):
			target = -float(v.climb) * 1.3
		else:
			target = sin(_time * 2.2) * 0.25
		if altitude > float(v.ceiling):
			target = minf(target, -1.0)
	elif state == "action" and action and action.no_gravity:
		return
	velocity.y = move_toward(velocity.y, target, 26.0 * delta)


func _flight_timers(delta: float) -> void:
	if not data.has("flight"):
		return
	if is_on_floor():
		if flying:
			flying = false
		_ground_t += delta
		if _ground_t > 0.5:
			flight = minf(_flight_max(), flight + _flight_max() / float(data.flight.recharge) * delta)
		return
	_ground_t = 0.0
	if not flying:
		return
	var spend := 1.0
	if ctrl.keeps("jump") and state == "free":
		spend += 0.8
	if Vector2(velocity.x, velocity.z).length() > data.speed * 0.6:
		spend += 0.3
	if state == "dodge":
		spend += 2.0
	flight = maxf(0.0, flight - spend * delta)
	if flight <= 0.0:
		flying = false
		main.vfx.text(center() + Vector3.UP * 0.9, tr("Out of stamina"), Color(1.0, 0.7, 0.4))


func _separate() -> void:
	if rival == null or not is_instance_valid(rival) or rival.state == "ko":
		return
	if (action and action.d.get("pierces", false)) or (rival.action and rival.action.d.get("pierces", false)):
		return
	var d := global_position - rival.global_position
	d.y = 0.0
	var min_d: float = radius() + rival.radius()
	var l := d.length()
	if l < min_d and l > 0.001 and absf(global_position.y - rival.global_position.y) < data.height:
		# Position correction (not velocity: otherwise it accumulates and they slide away).
		# Each one moves its share; the heavier one, less.
		var part: float = data.knockback / (data.knockback + rival.data.knockback)
		var corr: Vector3 = d / l * (min_d - l) * part * 0.5
		global_position += Vector3(corr.x, 0, corr.z)


func _land() -> void:
	main.vfx.dust(global_position, data.radius * (1.0 if data.height < 1.5 else 1.8))
	main.audio.play_sound("footstep", global_position, -10.0 + data.height * 2.0, 0.9 / maxf(0.6, data.height * 0.6))
	_pose.stretch = 0.8


# ---------------------------------------------------------------- actions

func _try_actions(on_ground: bool) -> void:
	if _wants("dodge") and charges >= 1.0:
		_consume("dodge")
		_start_dodge()
		return
	if on_ground:
		air_jumps = int(data.get("jumps", 1)) - 1
	if _wants("jump") and not on_ground and _take_off():
		_consume("jump")
		return
	if _wants("jump") and (on_ground or air_jumps > 0):
		_consume("jump")
		if not on_ground:
			air_jumps -= 1
			main.vfx.burst("wind", global_position, Vector3.DOWN, Color(0, 0, 0, 0), 0.6)
			_pose.turn = 0.0
		velocity.y = data.jump
		main.vfx.dust(global_position, data.radius)
		main.audio.play_sound("jump", global_position, -8.0)
		_pose.stretch = 1.25
		return
	for i in 4:
		var b := "mov%d" % (i + 1)
		if _wants(b):
			var move: String = data.moves[i]
			if ready(move) and not on_ground and Moves.DATA[move].get("needs_ground", false):
				_consume(b)
				_start_dive(move, b)
				return
			if ready(move):
				_consume(b)
				start(move, b)
				main.hud.log_entry(tr("%s used %s!") % [tr(data.display_name), tr(Moves.DATA[move].display_name)])
				return
			elif not ready(move):
				_consume(b)
				if is_player:
					main.hud.warn_not_ready(i)


## Moves that need the ground used in the air: dives down and does it on landing.
func _start_dive(move: String, b: String) -> void:
	flying = false
	_dive_move = move
	_dive_button = b
	_switch_state("dive")
	velocity = Vector3(velocity.x * 0.3, minf(velocity.y, 0.0) - 14.0, velocity.z * 0.3)
	main.vfx.burst("wind", center(), Vector3.UP, Color(0, 0, 0, 0), 0.8)


func start(move: String, button: String, extra := {}) -> void:
	var d: Dictionary = Moves.DATA[move]
	# Attacking reveals it (Substitute).
	if translucent > 0.0 and d.cat != "status":
		translucent = 0.001
		main.vfx.burst("shadow", center(), Vector3.UP, Color(0, 0, 0, 0), 1.0)
	var a: Action = load(d.script).new()
	a.l = self
	a.id = move
	a.d = d
	a.button = button
	a.extra = extra
	if action:
		_cut_cooldown()
		action.finish(true)
	action = a
	_switch_state("action")
	main.trainer_react(self, "command")
	if d.get("cost", 0.0) > 0.0:
		energy -= d.cost
		_energy_pause = 0.8
	if d.has("uses"):
		uses[move] = uses.get(move, d.uses) - 1
	_update_head_pitch()
	# Every move starts from the idle pose: if the base had another one (sleeping
	# after Rest), it would stay on in moves without their own animation.
	_animate_base(0.12)
	# Online copy: whatever starts is fast-forwarded by how long it took to arrive.
	var lead := mini(net_lead, 12)
	net_lead = 0
	# Passives that turn on when using a move of their type.
	if data.passive.id == "protean" and d.cat != "status" and types != [d.type]:
		types = [d.type]
		main.vfx.text(center() + Vector3.UP * 0.9, tr(Roster.TYPE_NAME[d.type]), Roster.TYPE_COLOR[d.type])
	a.start()
	for i in lead:
		if a.finished or action != a:
			break
		a.step(1.0 / 60.0)


func _step_action(delta: float, on_ground: bool) -> void:
	if action == null:
		_to_free()
		return
	action.step(delta)
	if action.moves_freely:
		_move_free(delta, on_ground, action.move_mult)
	elif not action.no_brake:
		# Flying it brakes like on the ground: when attacking it stops, without carrying inertia.
		_brake(delta, 6.0 if on_ground or flying else 0.6)
	if action.d.get("manual_aim", false) and is_player:
		if ctrl.move_input.length() > 0.3:
			turn_toward(global_position + _world_dir(ctrl.move_input), delta, action.d.get("manual_turn", 0.5))
	elif action.d.get("manual_aim", false) and ai_aim != null:
		# The AI turns its stream as slowly as a player and toward where it thinks the
		# rival is, not where it really is: strafing gets you out, like against a person.
		turn_toward(ai_aim, delta, action.d.get("manual_turn", 0.5))
	elif action.faces_rival and free_aim():
		# Not locked on: the move goes where the camera looks.
		turn_toward(global_position + camera_forward(), delta, action.turn_mult)
	elif action.faces_rival and rival and is_instance_valid(rival):
		turn_toward(aim_target().global_position, delta, action.turn_mult)
	# Cancels allowed by the action itself. The cancelled move still goes on cooldown (it was
	# used): otherwise a move that cancels into moves could chain into itself forever.
	if action.can_cancel():
		if _wants("dodge") and charges >= 1.0 and action.cancels_dodge():
			_consume("dodge")
			_start_cooldown(action.id)
			action.finish(true)
			action = null
			_start_dodge()
			return
		for i in 4:
			var b := "mov%d" % (i + 1)
			var move: String = data.moves[i]
			if _wants(b) and move != action.id and action.cancels_into(move) and ready(move):
				_consume(b)
				_start_cooldown(action.id)
				start(move, b)
				main.hud.log_entry(tr("%s used %s!") % [tr(data.display_name), tr(Moves.DATA[move].display_name)])
				return
		if _wants("jump") and on_ground and action.cancels_jump():
			_consume("jump")
			_start_cooldown(action.id)
			action.finish(true)
			action = null
			_to_free()
			velocity.y = data.jump
			return
	if action and action.finished:
		_start_cooldown(action.id)
		action = null
		_to_free()


func _start_dodge() -> void:
	var dodge_cfg: Dictionary = data.dodge
	charges -= 1.0
	var d := _world_dir(ctrl.move_input)
	if d.length() < 0.3:
		d = -forward()
	_dodge_dir = d.normalized()
	# Repeating it back to back is tiring: recovery gets longer and can be punished.
	_dodge_fatigue = _time - _last_dodge < 0.75
	# Slowed (inside a stream, chilled, charged): the dodge covers less ground, in the
	# same proportion. It lasts the same and its invulnerability does not change.
	_dodge_reach = slow
	_last_dodge = _time
	_switch_state("dodge")
	main.audio.play_sound("dodge", global_position, -6.0)
	if dodge_cfg.get("teleport", false):
		main.vfx.burst("shadow", center(), Vector3.UP, Color(0, 0, 0, 0), 1.2)
	else:
		main.vfx.dust(global_position, data.radius * 0.8)


func _step_dodge(delta: float) -> void:
	var dodge_cfg: Dictionary = data.dodge
	var t := _state_t
	var start_t := 0.04
	var end_move: float = start_t + dodge_cfg.dur
	var recovery: float = dodge_cfg.recovery * (2.2 if _dodge_fatigue else 1.0)
	invulnerable = 0.02 if t >= dodge_cfg.iframes[0] and t <= dodge_cfg.iframes[1] else invulnerable
	if t < start_t:
		_brake(delta, 12.0)
	elif t < end_move:
		var v: Vector3 = _dodge_dir * dodge_cfg.dist * _dodge_reach / dodge_cfg.dur
		velocity.x = v.x
		velocity.z = v.z
		if dodge_cfg.get("teleport", false):
			model.visible = false
		else:
			_afterimage_t -= delta
			if _afterimage_t <= 0.0:
				_afterimage_t = 0.05
				main.vfx.afterimage(self)
	elif t < end_move + recovery:
		if dodge_cfg.get("teleport", false) and not model.visible:
			model.visible = true
			main.vfx.burst("shadow", center(), Vector3.UP, Color(0, 0, 0, 0), 1.2)
		_brake(delta, 16.0)
	else:
		model.visible = true
		_to_free()


func _switch_state(e: String) -> void:
	state = e
	_state_t = 0.0


func _to_free() -> void:
	_switch_state("free")
	_combo_clear = 0.0


# ---------------------------------------------------------------- hits

## Damage adjustments from passives (of the attacker).
func outgoing_mod(g: Hit, target: Fighter) -> float:
	var k := 1.0
	# Technician: moves of 60 power or less hit 1.5 times as hard.
	var power := Damage.power_of(Moves.DATA.get(g.move_id, {}), self, target)
	if data.passive.id == "technician" and power > 0.0 and power <= 60.0:
		k *= 1.5
	if boosted_hits > 0 and g.cat == "physical":
		k *= 1.5
		boosted_hits -= 1
		main.vfx.burst("sparks_metal", target.center(), Vector3.UP, Color(0, 0, 0, 0), 1.0)
	# Blaze, Torrent, Overgrow, Swarm: at a third of its HP or less, moves of that type
	# hit 1.5 times as hard.
	if PINCH.get(data.passive.id, "") == g.type and hp <= hp_max / 3.0:
		k *= 1.5
	return k


const PINCH := {"blaze": "fire", "torrent": "water", "overgrow": "grass", "swarm": "bug"}
## Flinching (Headbutt...), adapted: this much longer stunned instead of a lost turn.
const FLINCH_T := 0.35
## Paralysis (Static), adapted to real time: half speed this long, no lost turns.
const PARALYSIS_T := 5.0


## Multiplier of a stat stage (see "stages").
func stage_mult(stat: String) -> float:
	var n: int = stages.get(stat, 0)
	return (2.0 + n) / 2.0 if n >= 0 else 2.0 / (2.0 - n)


## Movement from the Speed stage: the Speed stat is multiplied and the movement speed
## follows the same formula as in Stats (4 + 0.032 x Speed).
func speed_stage() -> float:
	var k := stage_mult("spe")
	# Chlorophyll: Speed doubles in harsh sunlight.
	if data.passive.id == "chlorophyll" and main.weather and main.weather.is_on("sun"):
		k *= 2.0
	if k == 1.0 or not data.has("stats"):
		return 1.0
	var spe: float = data.stats.spe
	return (4.0 + 0.032 * spe * k) / (4.0 + 0.032 * spe)


## Raises (or lowers) a stat stage, with its text. Online the rival's copy of this Pokémon
## gets it too (it needs it to work out damage).
func boost(stat: String, n: int, source := "") -> void:
	var before: int = stages[stat]
	stages[stat] = clampi(before + n, -6, 6)
	if stages[stat] == before:
		return
	var names := {"atk": tr("Attack"), "def": tr("Defense"), "spa": tr("Sp. Atk"), "spd": tr("Sp. Def"), "spe": tr("Speed")}
	var text: String = names[stat] + (" +%d" % (stages[stat] - before) if n > 0 else " %d" % (stages[stat] - before))
	if source != "":
		text = tr(source) + ": " + text
	main.vfx.text(center() + Vector3.UP * 1.0, text, Color(1.0, 0.85, 0.4) if n > 0 else Color(0.6, 0.75, 1.0))
	if not is_remote and main.net and main.net.linked:
		main.net.send_event({"t": "boost", "stat": stat, "stages": stages[stat]})


func receive(info: Dictionary) -> String:
	if state == "ko":
		return ""
	var g: Hit = info.hit
	var at: Fighter = info.attacker
	var underground: bool = action != null and action.id == "dig" and action.phase == "active"
	if underground and g.move_id == "earthquake":
		invulnerable = 0.0
		main.vfx.text(center() + Vector3.UP * 0.5, tr("Underground!"), Color(0.95, 0.75, 0.4))
	elif invulnerable > 0.0:
		main.vfx.text(center() + Vector3.UP * 0.5, tr("Dodged"), Color(0.85, 0.9, 1.0))
		if state == "dodge":
			main.arena.on_dodge(self)
			main.session.dodge(team)
		return "dodged"
	if action and action.has_method("intercept"):
		var r: String = action.intercept(info)
		if r != "":
			return r
	var md: Dictionary = Moves.DATA.get(g.move_id, {})
	# Flinch ("flinch": chance, as in the games): a longer stun. Inner Focus does not flinch;
	# Steadfast speeds up when it does.
	var flinched: bool = not info.get("flow", false) and randf() < float(md.get("flinch", 0.0)) and data.passive.id != "innerfocus"
	# Lightning Rod: Electric moves do nothing to it and raise its Sp. Atk.
	if data.passive.id == "lightningrod" and g.type == "electric" and g.move_id != "":
		if not info.get("flow", false):
			boost("spa", 1, "Lightning Rod")
		return "absorbed"
	if g.cat == "status":
		return _status_move(md, info)
	# A Fire hit thaws it out, as in the games.
	if status == "frz" and g.type == "fire":
		main.vfx.text(center() + Vector3.UP * 0.9, tr("Thawed out!"), Status.COLOR.frz)
		cure_status()
		_stunned = minf(_stunned, 0.2)
	var damage: float = Damage.dealt(g, at if at and is_instance_valid(at) else null, self, info.affinity) * vulnerable * (2.0 if underground and g.move_id == "earthquake" else 1.0)
	if at and is_instance_valid(at):
		damage *= at.outgoing_mod(g, self)
	if data.passive.id == "thickfat" and g.type in ["fire", "ice"]:
		damage *= 0.5
		main.vfx.text(center() + Vector3.UP * 0.9, tr("Thick Fat"), Color(0.95, 0.9, 0.8))
	# Static: a contact hit has a 30% chance of paralyzing whoever made it.
	if data.passive.id == "static" and g.contact and at and is_instance_valid(at) and randf() < 0.3:
		at.inflict("par")
		main.vfx.text(at.center() + Vector3.UP * 0.7, tr("Static"), Roster.TYPE_COLOR.electric)
	# Justified: a Dark move raises its Attack.
	if data.passive.id == "justified" and g.type == "dark" and not info.get("flow", false):
		boost("atk", 1, "Justified")
	# Cursed Body: 30% chance of disabling the move that hit it (4 turns: 12 s).
	if data.passive.id == "cursedbody" and at and is_instance_valid(at) and g.move_id != "" and not info.get("flow", false) and randf() < 0.3:
		at.effect("disable", 12.0, g.move_id)
		main.vfx.text(at.center() + Vector3.UP * 0.7, tr("Cursed Body"), Roster.TYPE_COLOR.ghost)
	# Moves that lower the target's stats ("target_boost", with "boost_chance").
	if md.has("target_boost") and not info.get("flow", false) and randf() < float(md.get("boost_chance", 1.0)):
		for stat in md.target_boost:
			boost(stat, int(md.target_boost[stat]))
	# Rough Skin: a contact hit costs whoever made it 1/8 of its max HP.
	if data.passive.id == "roughskin" and g.contact and at and is_instance_valid(at):
		at.effect("damage", at.hp_max / 8.0)
		main.vfx.burst("sparks_metal", at.center(), Vector3.UP, Color(0, 0, 0, 0), 0.6)
		if _skin_t <= 0.0:
			_skin_t = 1.5
			main.vfx.text(at.center() + Vector3.UP * 0.7, tr("Rough Skin"), Color(0.85, 0.8, 0.7))
	# Flow: consecutive impacts from a stream (Flamethrower, Hydro Pump). The first one
	# stuns like any hit; the next ones only deal damage, push a little and slow,
	# without locking: you can dodge or walk out, even if it is hard.
	var flow: bool = info.get("flow", false)
	var in_combo := state in ["stunned", "knocked_down"] and not flow
	if flow:
		pass
	elif in_combo:
		_combo += 1
		damage *= maxf(0.45, 1.0 - 0.12 * _combo)
	else:
		_combo = 0
	hp -= damage
	_flash = 1.0
	# Gluttony: no items yet, so it holds a Sitrus Berry and, being a glutton, eats it at
	# half HP instead of a quarter: it heals a quarter of its HP, once per battle.
	if data.passive.id == "gluttony" and not _berry_used and hp > 0.0 and hp <= hp_max * 0.5:
		_berry_used = true
		hp = minf(hp_max, hp + hp_max * 0.25)
		main.vfx.text(center() + Vector3.UP * 1.0, tr("Gluttony: Sitrus Berry"), Color(1.0, 0.85, 0.4))
	main.vfx.number(info.point, damage, info.affinity)
	hit_taken.emit(self, info)
	main.arena.on_hit(info.attacker, self, damage)
	main.trainer_react(info.attacker, "cheer")
	if g.strength >= 2 or damage > hp_max * 0.12:
		main.trainer_react(self, "flinch")
	main.session.hit(team, damage)
	if at and is_instance_valid(at) and not at.is_remote:
		at.energy = minf(ENERGY_MAX, at.energy + 3.0)
	energy = minf(ENERGY_MAX, energy + 2.0)
	if hp <= 0.0:
		_die(info)
		return "hit"
	if flow:
		var far: Vector3 = global_position - (at.global_position if at and is_instance_valid(at) else info.point)
		far.y = 0.0
		if far.length() > 0.01 and state in ["free", "action"]:
			var push: Vector3 = far.normalized() * Knockback.launch_speed(Knockback.distance(g)) * Knockback.STREAM_SHARE * data.knockback
			velocity.x += push.x
			velocity.z += push.z
		slow_down(0.5, 0.3)
		return "hit"
	var threshold := action.armor() if action else 0.0
	if threshold > 0.0 and damage < threshold:
		main.vfx.armor(self)
		return "armor"
	# Poise: while preparing or executing a move, it is only interrupted by hits with
	# strength (0 light, 1 medium, 2 heavy) equal to or greater than the move's poise
	# plus the Pokémon's. It takes the damage anyway.
	# Inner Focus: it does not flinch, so one more step of strength is needed to cut its moves.
	if action and action.phase in ["startup", "active"]:
		var level: int = int(action.d.get("poise", 0)) + int(data.get("poise", 0)) + (1 if data.passive.id == "innerfocus" else 0)
		if g.strength < level:
			main.vfx.armor(self)
			return "armor"
	var was_acting := action != null and action.phase in ["startup", "active"]
	if action:
		_cut_cooldown()
		action.finish(true)
		action = null
	flying = false
	# Steadfast: flinching (its move cut short by a hit) raises its Speed.
	if data.passive.id == "steadfast" and was_acting:
		boost("spe", 1, "Steadfast")
	var outside: Vector3 = global_position - (at.global_position if at and is_instance_valid(at) else info.point)
	outside.y = 0.0
	var dir: Vector3 = outside.normalized() if outside.length() > 0.01 else -forward()
	if g.push_dir != Vector3.ZERO:
		dir = (g.base().basis * g.push_dir).normalized()
	# Knockback by the power of the hit (see Knockback): a starting speed backward that
	# friction stops while it is stunned. Light Pokémon fly further (speed ∝ 1/mass).
	var knockback: float = data.knockback
	var speed := g.push if g.push_dir != Vector3.ZERO else Knockback.launch_speed(Knockback.distance(g))
	velocity = dir * speed * knockback + Vector3.UP * g.lift * knockback
	_apply_effect(g.effect)
	_secondary(md, info, at)
	if g.knocks_down or g.lift * knockback > 5.0 or _combo >= COMBO_MAX:
		_switch_state("knocked_down")
		if velocity.y < 3.0:
			velocity.y = 3.0
		_combo = 0
	else:
		_switch_state("stunned")
		_stunned = g.stun * maxf(0.35, 1.0 - 0.15 * _combo)
		if flinched:
			_stunned += FLINCH_T
			main.vfx.text(center() + Vector3.UP * 1.0, tr("Flinched!"), Color(1.0, 0.9, 0.6))
			if data.passive.id == "steadfast":
				boost("spe", 1, "Steadfast")
	_hit_ms = Time.get_ticks_msec()
	if model.has_anim("recoil"):
		model.play("recoil", 0.03, true)
		_cheer = "recoil"
	return "hit"


func _apply_effect(e: String) -> void:
	if e in ["brn", "par", "psn", "tox", "slp", "frz"]:
		inflict(e)


## Sludge Bomb puddle: stepping in it poisons (the status, as in the games).
func poison_target(_t: float) -> void:
	inflict("psn")


func slow_down(f: float, t: float) -> void:
	slow = minf(slow, f)
	_slow_t = maxf(_slow_t, t)


func _damage_direct(d: float) -> void:
	if state == "ko":
		return
	hp -= d
	if hp <= 0.0:
		_die({})


func heal(c: float) -> void:
	hp = minf(hp_max, hp + c)


func on_strike(o: Node, g: Hit, res: String) -> void:
	if action:
		action.landed = true
	# Recoil, as in the games: a share of the damage dealt ("recoil" in the move data).
	var d: Dictionary = Moves.DATA.get(g.move_id, {})
	if res == "hit" and d.has("recoil") and o is Fighter and not is_remote:
		_damage_direct(Damage.dealt(g, self, o, Roster.affinity(g.type, o.types)) * float(d.recoil))
		main.vfx.text(center() + Vector3.UP * 0.6, tr("Recoil"), Color(1.0, 0.6, 0.4), 0.8)


func _die(_info: Dictionary) -> void:
	hp = 0.0
	if action:
		action.finish(true)
		action = null
	main.combat.remove_from(self)
	_switch_state("ko")
	velocity.y = maxf(velocity.y, 3.0)
	# No faint animation (Charizard, Snorlax, Venusaur): the sleep one, lying down.
	# That way it is not left lying on the ground with whatever it had (running).
	if model.has_anim("faint"):
		model.play("faint", 0.05)
	elif model.has_anim("sleep"):
		model.play("sleep", 0.2)
	else:
		_animate_base(0.1)
	main.audio.cry(species, global_position, 0.8)
	defeated.emit(self)


## Fell into the stage's void (only stages with one: Arena.void_y): KO.
func _ring_out() -> void:
	main.vfx.text(global_position + Vector3.UP * 4.0, tr("Out!"), Color(1.0, 0.55, 0.3))
	# "since_hit": seconds since it was last hit (a long time: it walked off on its own).
	main.session.event("ring_out", {"species": species, "team": team, "state": state, "left_as": _left_as,
		"since_hit": snappedf((Time.get_ticks_msec() - _hit_ms) / 1000.0, 0.1)})
	_die({})


## On restarting the battle.
func reset(pos: Vector3, yaw: float) -> void:
	net_state = {}
	_left_as = ""
	if action:
		action.finish(true)
		action = null
	global_position = pos
	face_yaw = yaw
	velocity = Vector3.ZERO
	hp = hp_max
	energy = ENERGY_MAX
	charges = data.dodge.charges
	flight = _flight_max()
	flying = false
	# The procedural pose snaps back into place (otherwise it rises from wherever it
	# was: for example, from underground with Dig).
	_pose = {"tilt": 0.0, "side": 0.0, "turn": 0.0, "stretch": 1.0, "height": 0.0, "spin": 0.0}
	_above_ground = 0.0
	cds.clear()
	uses.clear()
	slow = 1.0
	confused = 0.0
	burned = 0.0
	poisoned = 0.0
	steadfast_t = 0.0
	translucent = 0.0
	boosted_hits = 0
	stages = {"atk": 0, "def": 0, "spa": 0, "spd": 0, "spe": 0}
	_berry_used = false
	cure_status(false)
	status_lock = 0.0
	shots = 0
	drowsy = 0.0
	types = data.types
	model.mesh_instance.transparency = 0.0
	model.visible = true
	wet = 0.0
	chlorophyll = 0.0
	static_mark = 0.0
	invulnerable = 0.0
	vulnerable = 1.0
	_combo = 0
	_buffer.clear()
	_switch_state("free")
	reset_physics_interpolation()
	_animate_base(0.0)
	model.rotation = Vector3(0, PI, 0)
	pivot.transform = Transform3D.IDENTITY


# ---------------------------------------------------------------- animation

func _process(delta: float) -> void:
	if model == null:
		return
	if _frozen > 0.0:
		return
	var h := Vector3(velocity.x, 0, velocity.z)
	var speed := h.length()
	var obj := {"tilt": 0.0, "side": 0.0, "turn": 0.0, "stretch": 1.0, "height": 0.0, "spin": 0.0}
	match state:
		"free":
			if not is_on_floor():
				obj.stretch = 1.08 if velocity.y > 0.0 else 0.95
				obj.tilt = clampf(-velocity.y * 0.02, -0.15, 0.15)
				if flying:
					var moving: bool = Vector2(velocity.x, velocity.z).length() > 1.5
					_set_anim("air_fly" if moving or velocity.y > 1.0 else "air_idle", 1.0)
					var local_vel := Basis(Vector3.UP, face_yaw).inverse() * h
					obj.tilt = clampf(local_vel.z / data.speed, -1.0, 1.0) * 0.25
					obj.side = clampf(-local_vel.x / data.speed, -1.0, 1.0) * 0.3
					obj.stretch = 1.0
				else:
					_animate_base(0.15)
			elif speed > 0.6 and data.get("levitates", false) and model.has_anim("air_fly"):
				_set_anim("air_fly", clampf(speed / data.speed, 0.6, 1.6))
				var local_l := Basis(Vector3.UP, face_yaw).inverse() * h
				obj.tilt = clampf(local_l.z / data.speed, -1.0, 1.0) * 0.18
				obj.side = clampf(-local_l.x / data.speed, -1.0, 1.0) * 0.2
			elif speed > 0.6:
				var local := Basis(Vector3.UP, face_yaw).inverse() * h
				# Backward (facing away from where it goes): the walk played in reverse and slower.
				# Cobblemon has no backing animation; running in reverse looks odd.
				var backwards: bool = local.z < -speed * 0.5 and model.has_anim("ground_walk")
				var run: bool = not backwards and speed > data.speed * 0.6 and model.has_anim("ground_run") and not "ground_run" in data.get("no_anims", [])
				var pace := clampf(speed / (data.speed * (0.85 if run else 0.45)), 0.6, 2.2)
				if backwards:
					_set_anim("ground_walk", -pace * 0.75)
				else:
					_set_anim("ground_run" if run else "ground_walk", pace)
				# Leans toward where it accelerates, sideways when strafing while locked on.
				obj.tilt = clampf(local.z / data.speed, -1.0, 1.0) * 0.12
				obj.side = clampf(-local.x / data.speed, -1.0, 1.0) * 0.14
				obj.height = absf(sin(_time * speed * 2.2)) * 0.03 * data.height if not model.has_anim("ground_walk") else 0.0
			else:
				_animate_base(0.2)
		"action":
			if action:
				var p: Dictionary = action.pose()
				for k in p:
					if obj.has(k):
						obj[k] = p[k]
				obj.tilt -= head_pitch * 0.6
				if p.has("anim") and p.anim != "" and model.has_anim(p.anim):
					_set_anim(p.anim, p.get("anim_speed", 1.0), p.get("reset", false))
		"dodge":
			var local := Basis(Vector3.UP, face_yaw).inverse() * _dodge_dir
			obj.tilt = local.z * 0.35
			obj.side = -local.x * 0.45
			obj.stretch = 0.85
			# Small ones do a roll; big ones just crouch and launch themselves.
			if data.height < 1.3:
				obj.turn = clampf(_state_t / (0.04 + data.dodge.dur), 0.0, 1.0) * TAU * signf(local.x if absf(local.x) > 0.3 else 1.0)
		"dive":
			obj.tilt = 0.6
			obj.stretch = 1.12
		"stunned":
			obj.tilt = -0.25
			obj.stretch = 0.92
			if status == "slp":
				obj.tilt = -0.05
				if model.has_anim("sleep"):
					_set_anim("sleep", 1.0)
			elif status == "frz":
				obj.tilt = 0.0
				obj.stretch = 1.0
				model.speed = 0.0
		"knocked_down", "lying":
			obj.tilt = -1.2 if state == "lying" else -0.6
			obj.height = 0.0
		"get_up":
			obj.tilt = lerpf(-1.0, 0.0, clampf(_state_t / 0.3, 0.0, 1.0))
		"ko":
			if not model.has_anim("faint") and not model.has_anim("sleep"):
				obj.tilt = -1.45
			obj.stretch = 1.0
	# Pose smoothing and application to the pivot.
	for k in _pose:
		var quickness := 18.0 if k in ["turn"] else 12.0
		_pose[k] = lerpf(_pose[k], obj[k], 1.0 - exp(-quickness * delta))
	if state == "dodge" and data.height < 1.3:
		_pose.turn = obj.turn
	# Spinning in place (Rapid Spin): unsmoothed, since it is a continuous turn.
	_pose.spin = obj.spin
	var e: float = _pose.stretch
	var b := Basis(Vector3.UP, face_yaw + _pose.spin) * Basis(Vector3.RIGHT, _pose.tilt) * Basis(Vector3.BACK, _pose.side)
	if absf(_pose.turn) > 0.001:
		b = b * Basis(Vector3.RIGHT, _pose.turn)
	pivot.global_basis = b.scaled(Vector3(1.0 / sqrt(e), e, 1.0 / sqrt(e)))
	# The pivot is at the feet. The roll rotates around the body's center (otherwise
	# the head goes through the floor): it shifts as needed so the center stays still.
	# Lying on its back, it rises a little.
	var half: float = data.height * 0.5
	var g: float = _pose.turn
	var fixed_center := Basis(Vector3.UP, face_yaw + _pose.spin) * Vector3(0.0, half - half * cos(g), -half * sin(g))
	var rises: float = clampf(-_pose.tilt - 0.3, 0.0, 1.2) * data.radius * 0.75
	if data.get("levitates", false) and state != "ko":
		rises += 0.35 + 0.08 * sin(_time * 2.4)
	pivot.position = Vector3(0, _pose.height + rises, 0) + (fixed_center if absf(g) > 0.001 else Vector3.ZERO)
	# Feet on the ground: some Cobblemon animations lower the body without accounting
	# for the ground (Greninja). If the feet sink while standing, it rises just enough.
	var sunk := 0.0
	if is_on_floor() and model.visible and not (action and action.id == "dig"):
		if _feet.is_empty():
			_find_feet()
		# Fainted, lying down: any bone counts (hands, tail...).
		var bones: Array = _feet if state != "ko" else range(model.skel.get_bone_count()).map(func(b): return model.skel.get_bone_name(b))
		for p in bones:
			if state == "ko" and (p.begins_with("locator") or p == species):
				continue
			sunk = maxf(sunk, global_position.y - model.bone_world(p).y)
	_above_ground = lerpf(_above_ground, maxf(sunk - 0.04, 0.0), 1.0 - exp(-20.0 * delta))
	pivot.position.y += _above_ground
	if _cheer != "recoil" or model.finished():
		# After hitstop (speed 0). Negative is walking backward: it is respected.
		model.speed = model.speed if model.speed != 0.0 else 1.0
	model.set_param("flash", _flash * 0.7)
	var tint_col := Vector3.ZERO
	if action and action.tint_col != Color.BLACK:
		var c := action.tint_col
		tint_col = Vector3(c.r, c.g, c.b) * action.tint_k
	if slow < 1.0:
		tint_col += Vector3(0.1, 0.25, 0.35)
	if static_mark > 0.0 and fmod(_time, 0.5) < 0.25:
		tint_col += Vector3(0.25, 0.22, 0.0)
	tint_col += Vector3.ONE * appear_glow * 1.4
	model.set_param("tint", tint_col)
	model.visible = appear > 0.01
	model.scale = Vector3.ONE * _scale * clampf(appear, 0.05, 1.0)


## The lowest bones in the idle pose: feet, toes and whatever brushes the ground.
func _find_feet() -> void:
	var sk := model.skel
	var list: Array = []
	for b in sk.get_bone_count():
		var n := sk.get_bone_name(b)
		if n.begins_with("locator") or n == species:
			continue
		list.append([model.bone_world(n).y - global_position.y, n])
	list.sort_custom(func(a, c): return a[0] < c[0])
	for i in mini(6, list.size()):
		if list[i][0] < data.height * 0.2:
			_feet.append(list[i][1])


func _animate_base(fade: float) -> void:
	var a := "battle_idle" if model.has_anim("battle_idle") else "ground_idle"
	if data.get("levitates", false) and model.has_anim("air_idle"):
		a = "air_idle"
	if flying and model.has_anim("air_idle"):
		a = "air_idle"
	_set_anim(a, 1.0, false, fade)


func _set_anim(a: String, speed := 1.0, reset := false, fade := 0.12) -> void:
	if not model.has_anim(a):
		a = "ground_idle"
	model.play(a, fade, reset)
	model.speed = speed
	_cheer = a
