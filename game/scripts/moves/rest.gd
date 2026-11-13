extends Action
## Rest: falls asleep and slowly recovers HP. Asleep it cannot be interrupted, but it
## takes 35% more damage and cannot do anything: that is the rival's window. Two uses.

var _zz := 0.0
var _healed := 0.0


func on_start() -> void:
	faces_rival = false
	play_sound("rest", -2.0)


func on_active() -> void:
	l.cure_status()
	l.vulnerable = d.vulnerable
	if l.model.has_anim("sleep_intro"):
		l.model.play("sleep_intro", 0.2)


func in_active(delta: float) -> void:
	var total_heal: float = l.hp_max * d.heal
	var amount: float = total_heal * delta / d.active
	l.heal(amount)
	_healed += amount
	_zz -= delta
	if _zz <= 0.0:
		_zz = 0.6
		# Cobblemon's sleep status Zs, not floating text.
		l.main.fx.anim("generic/status/sleep_zzz.png", l.global_position + Vector3(0.3, l.data.height + 0.35, 0), 0.7, 16, 1.0)


## Asleep it does not wake up from hits (but it takes more damage).
func armor() -> float:
	return 99999.0 if phase == "active" else 0.0


func on_recovery() -> void:
	l.vulnerable = 1.0


func on_end(_interrupted: bool) -> void:
	l.vulnerable = 1.0


func pose() -> Dictionary:
	if phase == "active":
		var a := "sleep" if l.model.has_anim("sleep") and t > 0.6 else ""
		return {"tilt": 0.0, "stretch": 0.92 + 0.03 * sin(total * 2.5), "anim": a}
	if phase == "startup":
		return {"stretch": 0.9}
	return {"stretch": 1.05}
