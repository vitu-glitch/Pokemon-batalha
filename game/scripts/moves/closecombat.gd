extends Action
## Close Combat: it crouches, gathering its aura, then rushes in throwing "blows" hits one
## after another, hands in turn, each with its trail; where each lands a fist or a foot pops
## over the rival, like in the DS games (Cobblemon's fist and foot, many, popping in and
## out). The first
## ones keep the rival stunned and the last one sends it flying. Blows after the first count
## as a combo (less each), so each is worth more to make the whole flurry its "damage". As in the games, if it
## lands it lowers the user's own Defense and Sp. Def, once. The flurry breaks shots it
## meets ("deflects" 1).

## What the six blows add up to with the combo falloff (Fighter.receive: 1, 0.88, 0.76,
## 0.64, 0.52, 0.45).
const COMBO_SUM := 4.25

var _done := 0
var _aura := 0.0


func on_start() -> void:
	turn_mult = 2.5
	_done = 0


func in_startup(delta: float) -> void:
	tint_col = Roster.TYPE_COLOR.fighting
	tint_k = 0.3 * clampf(t / maxf(startup_len(), 0.01), 0.0, 1.0)
	_aura -= delta
	if _aura <= 0.0:
		_aura = 0.05
		var c := l.center()
		var from_pos: Vector3 = c + Vector3(randf_range(-1, 1), randf_range(-0.5, 1), randf_range(-1, 1)).normalized() * l.data.height * 0.8
		l.main.vfx.burst("stars", from_pos, (c - from_pos).normalized(), Roster.TYPE_COLOR.fighting, 0.25)


func in_active(_delta: float) -> void:
	var blows: int = d.blows
	var due := mini(int(t / (d.active / blows)) + 1, blows)
	while _done < due:
		_blow(_done, _done == blows - 1)
		_done += 1


func _blow(i: int, last: bool) -> void:
	tint_k = 0.0
	advance_by(d.advance / d.active * 0.6)
	var hand := "locator_hand_primary" if i % 2 == 0 else "locator_hand_secondary"
	var height: float = l.data.height * (0.65 if i % 3 != 2 else 0.35)       # every third one low, like a kick
	var side: float = (0.35 if i % 2 == 0 else -0.35) * l.data.radius
	var g := hit({"shape": "sphere", "center": Vector3(side, height, l.data.radius + d.reach * 0.5), "radius": d.radius,
		"lifetime": 0.07, "damage": d.damage / COMBO_SUM, "quiet": i > 0, "stun": d.stun if not last else d.stun_last,
		"strength": 1 if not last else 2, "lift": 0.0 if not last else d.lift, "hitstop": 0.04 if not last else 0.12})
	var vfx: Vfx = l.main.vfx
	var me := l
	var struck := {"done": false}
	g.on_strike = func(o: Node, _res: String):
		struck.done = true
		# On the rival's surface facing the user (inside its body it would be hidden).
		var c: Vector3 = (o as Node3D).center() if o.has_method("center") else me.center() + me.forward()
		var toward := Vector3(me.global_position.x - c.x, 0.0, me.global_position.z - c.z).normalized()
		var r: float = o.radius() if o.has_method("radius") else 0.5
		_fists(c + toward * (r + 0.35), i, last)
	# A miss throws them too, in the air where the blow lands.
	var miss_at: Vector3 = l.center() + l.forward() * (l.data.radius + d.reach * 0.7) + Vector3.UP * (height - l.data.height * 0.5)
	l.get_tree().create_timer(0.05, false, true).timeout.connect(func():
		if not struck.done and is_instance_valid(me):
			_fists(miss_at, i, last))
	# The blow's trail from the body, and a faint blur of others around it.
	vfx.ribbon(func(): return [l.center(), l.point(hand)], Roster.TYPE_COLOR.fighting, 0.12, 0.16)
	var front: Vector3 = l.center() + l.forward() * (l.data.radius + d.reach * 0.6)
	vfx.burst("stars", front + Vector3(randf_range(-0.5, 0.5), randf_range(-0.4, 0.4), 0.0), l.forward(), Roster.TYPE_COLOR.fighting, 0.3)
	l.main.audio.play_sound("dodge", l.global_position, -8.0, 1.1 + 0.05 * i)
	if last:
		l.main.shake_camera(0.2, front)


## Like the DS games: many small fists (a foot here and there for the low blows), Cobblemon's
## own, popping in and out round "at", staggered, in the fighting type's dark orange; the
## last blow, more and a little bigger.
func _fists(at: Vector3, i: int, last: bool) -> void:
	var vfx: Vfx = l.main.vfx
	at += Vector3(randf_range(-0.8, 0.8), randf_range(-0.5, 0.6), randf_range(-0.8, 0.8))
	var count := 8 if last else 4
	for n in count:
		var spot: Vector3 = at + Vector3(randf_range(-0.7, 0.7), randf_range(-0.5, 0.6), randf_range(-0.7, 0.7))
		var size: float = randf_range(0.8, 1.1) if last else randf_range(0.5, 0.9)
		var foot: bool = i % 3 == 2 and n % 2 == 0
		var show := func(): vfx.pop("res://fx/tex/generic/foot.png" if foot else "res://fx/tex/generic/fist.png", 5, 3, spot, size,
			randf_range(0.16, 0.24), Color(0.85, 0.32, 0.08), true)
		if n == 0:
			show.call()
		else:
			l.get_tree().create_timer(n * 0.03, false, true).timeout.connect(show)


func on_recovery() -> void:
	tint_k = 0.0
	if landed:
		play_sound(id, 0.0)
		# The price, as in the games: its own guard drops.
		l.boost("def", -1)
		l.boost("spd", -1)


func pose() -> Dictionary:
	match phase:
		"startup":
			return {"tilt": -0.2, "stretch": 0.88}
		"active":
			# Leaning in and shaking with each blow.
			var k := float(_done % 2)
			return {"tilt": 0.3 + 0.08 * k, "stretch": 1.04 + 0.05 * k, "anim": "physical"}
	return {"tilt": 0.2 * (1.0 - t / maxf(float(d.recovery), 0.01))}
