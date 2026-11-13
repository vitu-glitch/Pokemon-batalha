class_name Status
extends RefCounted
## Major status conditions, as in the games (Showdown), adapted to an action game. One at a
## time, the same effects and immunities as there, but none lasts the whole battle: in real
## time a lasting poison rewards running away while it wears the rival down. So each one
## lasts a fixed DURATION and does its chip damage (TOTAL, a share of max HP) within that
## time; once cured it cannot get another one for IMMUNE_AFTER seconds.
##   brn  chip damage; its physical moves hit half as hard (not Facade). Fire types cannot
##        be burned.
##   par  moves at half speed; every PARA_ROLL seconds, a 25% chance of being fully
##        paralyzed for a moment. Electric types cannot be paralyzed.
##   psn  long and slow: little damage over a long time.
##   tox  badly poisoned: short and fast, more damage in less time, and growing as it goes
##        on (1/16, 2/16, 3/16... per turn there). Poison and Steel types (and Immunity)
##        cannot be poisoned.
##   slp  asleep SLEEP seconds (random): it cannot act or move; hits do not wake it.
##   frz  frozen solid FREEZE seconds: a Fire hit thaws it. Ice types cannot be frozen.
## The Fighter keeps it (Fighter.inflict); the HUD shows Cobblemon's status tab and the
## time left under it.

const DURATION := {"brn": 8.0, "par": 8.0, "psn": 12.0, "tox": 6.0}
const TOTAL := {"brn": 0.08, "psn": 0.10, "tox": 0.16}
const TICK := 2.0                      # a damage number every TICK seconds
const YAWN := 2.5                      # drowsy: seconds before it falls asleep
const IMMUNE_AFTER := 5.0
const PARA_ROLL := 2.0
const PARA_CHANCE := 0.25
const PARA_T := 0.6
const SLEEP := Vector2(1.5, 3.0)
const FREEZE := Vector2(1.5, 3.0)
const IMMUNE := {"brn": ["fire"], "par": ["electric"], "psn": ["poison", "steel"], "tox": ["poison", "steel"],
	"frz": ["ice"], "slp": []}
const COLOR := {"brn": Color(1.0, 0.45, 0.2), "par": Color(1.0, 0.85, 0.2), "psn": Color(0.7, 0.35, 0.85),
	"tox": Color(0.6, 0.2, 0.75), "slp": Color(0.75, 0.75, 0.8), "frz": Color(0.55, 0.85, 1.0)}


## Whether a Pokémon of these types and this ability can get "kind".
static func can_get(kind: String, types: Array, ability: String) -> bool:
	if not IMMUNE.has(kind):
		return false
	for t in types:
		if t in IMMUNE[kind]:
			return false
	if kind in ["psn", "tox"] and ability == "immunity":
		return false
	return true


## Seconds it lasts at most (for the HUD's bar).
static func length(kind: String) -> float:
	match kind:
		"slp": return SLEEP.y
		"frz": return FREEZE.y
	return DURATION.get(kind, 1.0)


## Chip damage per second, as a share of max HP, "age" seconds after it started. Badly
## poisoned goes from 0.4 to 1.6 times the average, so TOTAL is still the whole of it.
static func rate(kind: String, age: float) -> float:
	if not TOTAL.has(kind):
		return 0.0
	var per_s: float = TOTAL[kind] / DURATION[kind]
	if kind == "tox":
		per_s *= 0.4 + 1.2 * clampf(age / DURATION[kind], 0.0, 1.0)
	return per_s


## Text when it wears off.
static func cured_text(kind: String) -> String:
	match kind:
		"brn": return TranslationServer.translate("Burn healed!")
		"par": return TranslationServer.translate("Paralysis cured!")
		"psn", "tox": return TranslationServer.translate("Poison cured!")
		"slp": return TranslationServer.translate("Woke up!")
		"frz": return TranslationServer.translate("Thawed out!")
	return ""


## What a move with it does to the target, for the menus ("30%: burns").
static func verb(kind: String) -> String:
	match kind:
		"brn": return TranslationServer.translate("burns")
		"par": return TranslationServer.translate("paralyzes")
		"psn": return TranslationServer.translate("poisons")
		"tox": return TranslationServer.translate("badly poisons")
		"slp": return TranslationServer.translate("puts to sleep")
		"frz": return TranslationServer.translate("freezes")
	return ""


## Text when it happens, as in the games' battle log.
static func text(kind: String) -> String:
	match kind:
		"brn": return TranslationServer.translate("Burned!")
		"par": return TranslationServer.translate("Paralyzed!")
		"psn": return TranslationServer.translate("Poisoned!")
		"tox": return TranslationServer.translate("Badly poisoned!")
		"slp": return TranslationServer.translate("Fell asleep!")
		"frz": return TranslationServer.translate("Frozen solid!")
	return ""
