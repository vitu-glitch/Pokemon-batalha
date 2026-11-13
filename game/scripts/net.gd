class_name Net
extends Node
## 1 vs 1 online play over IP (ENet over UDP).
##
## Authority: each player is in charge of their own Pokémon. Their presses run instantly
## on their screen; they reach the other player with the ping and move a copy there (the
## "remote"), which is also corrected with the real state. Whoever takes a hit decides
## whether it landed (if they dodged on their screen, it did not) and tells the attacker.
##
## Custom packets, no RPC, to keep them small:
##   channel 0, unreliable, every frame: input + state of your own Pokémon
##   channel 1, reliable: start, confirmed hits, effects, KO, rematch...
## Presses travel as per-action counters: even if a packet is lost, the next one carries
## them.
##
## Testing: --lag=ms (round trip), --jitter=ms and --loss=% simulate a bad network.

signal connected
signal disconnected(reason: String)
signal event(data: Dictionary)

const PORT := 7777
const ACTIONS := ["jump", "dodge", "lock_on", "mov1", "mov2", "mov3", "mov4", "descend"]
const STATES := ["free", "action", "dodge", "stunned", "knocked_down", "lying", "get_up", "ko", "dive"]
const STATUSES := ["", "brn", "par", "psn", "tox", "slp", "frz"]
const TYPES := ["normal", "fire", "water", "grass", "electric", "ice", "fighting", "poison", "ground",
	"flying", "psychic", "bug", "rock", "ghost", "dragon", "dark", "steel", "fairy"]
const P_STATE := 1
const P_EVENT := 2

var main: Node
var peer: ENetMultiplayerPeer
var host := false
var linked := false              # connected to the other player
## This copy's own id in shared decisions (votes): random per session, the same for the
## whole connection.
var me := ""
var in_battle := false
var local: Fighter              # your own Pokémon
var remote: Fighter             # the rival's copy
var frame := 0
var rtt := 0.0                   # round trip, in seconds (measured)
var lag_sim := 0.0               # simulated round-trip delay (s)
var jitter_sim := 0.0
var loss_sim := 0.0
var upnp_ok := false
var public_ip := ""

var _counters := {}            # own presses per action
var _seen_list := {}                # last counters received from the other player
var _last_frame_other := -1
var states_applied := 0       # rival states actually applied (tests and the session log)
var _exit_t: Array = []          # [time, channel, bytes] (simulated network)
var _ping_t := 0.0
var _pings := {}                 # id -> send time
var _ping_id := 0
var _last_packet := 0.0
var _t := 0.0
var _upnp: UPNP
var upnp_testing := false


func _ready() -> void:
	me = "%08x" % (randi() & 0x7fffffff)
	process_physics_priority = -15
	for a in ACTIONS:
		_counters[a] = 0
		_seen_list[a] = 0


# ---------------------------------------------------------------- connection

func create(port := PORT) -> String:
	close()
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(port, 1, 2)
	if err != OK:
		return tr("Could not open port %d (is another program using it?)") % port
	host = true
	_setup_peer()
	_open_router_port.call_deferred(port)
	return ""


func join(ip: String, port := PORT) -> String:
	close()
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(ip.strip_edges(), port, 2)
	if err != OK:
		return tr("Invalid address")
	host = false
	_setup_peer()
	return ""


func _setup_peer() -> void:
	peer.peer_connected.connect(func(_id):
		linked = true
		_last_packet = _t
		# No compression and no waiting: small packets, sent as soon as they are made.
		connected.emit())
	# Never close the connection inside its own callback (it hangs): do it afterwards.
	peer.peer_disconnected.connect(func(_id): _lost.call_deferred(tr("The other player disconnected")))
	_t = 0.0
	frame = 0
	for a in ACTIONS:
		_counters[a] = 0
		_seen_list[a] = 0
	_last_frame_other = -1


func close() -> void:
	if peer:
		peer.close()
	peer = null
	linked = false
	in_battle = false
	local = null
	remote = null
	_exit_t.clear()
	if _upnp and upnp_ok:
		# Removing the port from the router takes a while: in the background, without stalling the game.
		var u := _upnp
		WorkerThreadPool.add_task(func(): u.delete_port_mapping(PORT, "UDP"))
	upnp_ok = false


func _lost(reason: String) -> void:
	if not linked and peer == null:
		return
	close()
	disconnected.emit(reason)


## Tries to open the port on the router (UPnP) so others can join from outside.
func _open_router_port(port: int) -> void:
	# On the thread pool: if the game is closed halfway, the task finishes on its own
	# without leaving a dangling thread.
	var u := UPNP.new()
	_upnp = u
	upnp_testing = true
	var r := [false, ""]
	var task := WorkerThreadPool.add_task(func():
		if u.discover(2000, 2, "InternetGatewayDevice") == UPNP.UPNP_RESULT_SUCCESS and u.get_gateway() and u.get_gateway().is_valid_gateway():
			r[0] = u.add_port_mapping(port, port, "PokeBrawl", "UDP") == UPNP.UPNP_RESULT_SUCCESS
			r[1] = u.query_external_address())
	while not WorkerThreadPool.is_task_completed(task):
		await get_tree().process_frame
		if not is_inside_tree():
			return
	WorkerThreadPool.wait_for_task_completion(task)
	upnp_testing = false
	if peer == null:
		# It was closed in the meantime: the open port is not needed.
		if r[0]:
			WorkerThreadPool.add_task(func(): u.delete_port_mapping(port, "UDP"))
		return
	upnp_ok = r[0]
	public_ip = r[1]


## This computer's local IPs (for LAN or VPNs like Radmin/ZeroTier).
static func local_ips() -> Array:
	var out: Array = []
	for ip in IP.get_local_addresses():
		if ip.contains(".") and not ip.begins_with("127.") and not ip.begins_with("169.254."):
			out.append(ip)
	return out


# ---------------------------------------------------------------- sending

func _send(channel: int, data: PackedByteArray) -> void:
	if peer == null:
		return
	if lag_sim > 0.0 or loss_sim > 0.0:
		if channel == 0 and randf() * 100.0 < loss_sim:
			return
		var outbound := lag_sim * 0.5 + randf_range(-jitter_sim, jitter_sim) * 0.5
		_exit_t.append([_t + maxf(outbound, 0.0), channel, data])
		return
	_put_on(channel, data)


func _put_on(channel: int, data: PackedByteArray) -> void:
	if peer == null or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	peer.transfer_channel = channel
	peer.transfer_mode = MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED if channel == 0 else MultiplayerPeer.TRANSFER_MODE_RELIABLE
	peer.set_target_peer(MultiplayerPeer.TARGET_PEER_BROADCAST)
	peer.put_packet(data)
	# Send it now, not on the next poll (that would add 16 ms each way).
	if peer.host:
		peer.host.flush()


## How many players share this session (themselves included). 1 vs 1 for now: the votes
## (rematch) count against this, so more players only need it to grow.
func players() -> int:
	return 2 if linked else 1


## Reliable event (start, confirmed hit, effect, KO, rematch, pick...).
func send_event(data: Dictionary) -> void:
	var b := StreamPeerBuffer.new()
	b.put_u8(P_EVENT)
	b.put_var(data)
	_send(1, b.data_array)


# ---------------------------------------------------------------- loop

func _physics_process(delta: float) -> void:
	_t += delta
	if peer == null:
		return
	peer.poll()
	# Simulated delayed output.
	var i := 0
	while i < _exit_t.size():
		if _exit_t[i][0] <= _t:
			_put_on(_exit_t[i][1], _exit_t[i][2])
			_exit_t.remove_at(i)
		else:
			i += 1
	while peer and peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED and peer.get_available_packet_count() > 0:
		var pkt := peer.get_packet()
		_last_packet = _t
		_receive(pkt)
	if peer == null:
		return
	if linked and _t - _last_packet > 5.0:
		_lost.call_deferred(tr("No response from the other player"))
		linked = false
		return
	# Own ping every half second (includes the simulated network).
	_ping_t -= delta
	if linked and _ping_t <= 0.0:
		_ping_t = 0.5
		_ping_id += 1
		_pings[_ping_id] = _t
		send_event({"t": "ping", "id": _ping_id})
	if in_battle and local:
		frame += 1
		_send(0, _pack())


func _receive(pkt: PackedByteArray) -> void:
	var b := StreamPeerBuffer.new()
	b.data_array = pkt
	match b.get_u8():
		P_STATE:
			_read_state(b)
		P_EVENT:
			var d = b.get_var()
			if typeof(d) != TYPE_DICTIONARY:
				return
			match d.get("t", ""):
				"ping":
					send_event({"t": "pong", "id": d.id})
				"pong":
					if _pings.has(d.id):
						var measured: float = _t - _pings[d.id]
						rtt = measured if rtt <= 0.0 else lerpf(rtt, measured, 0.3)
						_pings.erase(d.id)
				_:
					event.emit(d)


# ---------------------------------------------------------------- state

func _pack() -> PackedByteArray:
	var l := local
	var c := l.ctrl
	var b := StreamPeerBuffer.new()
	b.put_u8(P_STATE)
	b.put_u32(frame)
	# Input: what the copy needs to do the same.
	b.put_float(c.move_input.x)
	b.put_float(c.move_input.y)
	b.put_float(c.yaw)
	var mask := 0
	for k in ACTIONS.size():
		if c.keeps(ACTIONS[k]):
			mask |= 1 << k
	b.put_u16(mask)
	for a in ACTIONS:
		b.put_u8(int(c.counter.get(a, 0)))
	# Real state, to correct the copy.
	for v in [l.global_position, l.velocity]:
		b.put_float(v.x)
		b.put_float(v.y)
		b.put_float(v.z)
	b.put_float(l.face_yaw)
	b.put_u8(maxi(STATES.find(l.state), 0))
	b.put_float(l._stunned)
	var code := 0
	if l.action:
		code = l.data.moves.find(l.action.id) + 1
	b.put_u8(code)
	b.put_u8(["startup", "active", "recovery"].find(l.action.phase) if l.action else 0)
	b.put_float(l.action.t if l.action else 0.0)
	# The status: code, time left, toxic turns.
	for v in [l.hp, l.energy, l.charges, l.flight, l.slow, l._slow_t, float(STATUSES.find(l.status)), l.status_t, l._status_age,
			l.steadfast_t, l.translucent, l.invulnerable]:
		b.put_float(v)
	b.put_u8((1 if l.flying else 0) | (2 if l.model.visible else 0))
	b.put_u8(l.boosted_hits)
	b.put_u8(maxi(TYPES.find(l.types[0]), 0))
	b.put_u8(TYPES.find(l.types[1]) + 1 if l.types.size() > 1 else 0)
	return b.data_array


func _read_state(b: StreamPeerBuffer) -> void:
	var f := b.get_u32()
	if f <= _last_frame_other and _last_frame_other - f < 1000000:
		return   # old or repeated
	_last_frame_other = f
	if remote == null or not is_instance_valid(remote):
		return
	states_applied += 1
	var r := remote
	var c := r.ctrl
	c.move_input = Vector2(b.get_float(), b.get_float())
	c.yaw = b.get_float()
	var mask := b.get_u16()
	# Estimated one-way delay, in frames: whatever starts is fast-forwarded by it.
	var lead := int(round(_outbound() * 60.0))
	for k in ACTIONS.size():
		var a: String = ACTIONS[k]
		var n := b.get_u8()
		var new_ones := (n - int(_seen_list[a]) + 256) % 256
		_seen_list[a] = n
		if new_ones > 0 and new_ones < 30:
			c.press(a)
			r.net_lead = lead
		elif mask & (1 << k):
			c.held[a] = true
		else:
			c.release(a)
	var s := {}
	s.pos = Vector3(b.get_float(), b.get_float(), b.get_float())
	s.speed = Vector3(b.get_float(), b.get_float(), b.get_float())
	s.yaw = b.get_float()
	s.state = STATES[clampi(b.get_u8(), 0, STATES.size() - 1)]
	s.stunned = b.get_float()
	s.action = b.get_u8()
	s.phase = b.get_u8()
	s.action_t = b.get_float()
	for k in ["hp", "energy", "charges", "flight", "slow", "slow_t", "burned", "poisoned", "static_mark",
			"steadfast_t", "translucent", "invulnerable"]:
		s[k] = b.get_float()
	var flags := b.get_u8()
	s.flying = flags & 1 != 0
	s.visible = flags & 2 != 0
	s.boosted_hits = b.get_u8()
	var t1 := b.get_u8()
	var t2 := b.get_u8()
	s.types = [TYPES[clampi(t1, 0, TYPES.size() - 1)]] + ([TYPES[t2 - 1]] if t2 > 0 and t2 <= TYPES.size() else [])
	s.outbound = _outbound()
	s.received = _t
	r.net_state = s


## Estimated one-way delay (s).
func _outbound() -> float:
	return maxf(rtt, 0.0) * 0.5


func ping_ms() -> int:
	return int(round(rtt * 1000.0))
