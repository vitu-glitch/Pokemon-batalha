class_name Damage
extends RefCounted
## How much a hit takes off, with the games' formula at level 50 so every move does to every
## Pokémon the same share of its health as in the games:
##   (22 × power × Attack / Defense) / 50 + 2
## times STAB (×1.5 if the move is of one of the user's types), type effectiveness (our
## softened table, Roster.affinity) and the average of the games' random roll (×0.925).
## Physical moves use Attack and Defense; special ones, Sp. Atk and Sp. Def, each with its
## stage (Fighter.stages: +1 is x1.5).
## Health is HP × Stats.HP_MULT, so damage is scaled the same way and then divided by
## BATTLE_LENGTH: battles take that many times more hits than in the games.
## A hit that is only part of a use (a stream tick, one of two swipes) deals its share
## (Moves.DATA "split", "power_at"). The weather changes it too (Weather: sun, rain, sand,
## snow; Solar Power).

const BATTLE_LENGTH := 4.2
const STAB := 1.5
const ROLL := 0.925


## Damage of hit "g" from "attacker" to "target" ("affinity": type effectiveness). Without
## stats (--hand-stats) or power, the hit's own hand-tuned damage.
static func dealt(g: Hit, attacker: Fighter, target: Fighter, affinity: float) -> float:
	# A projectile sent back still hits with whoever threw it (its stats, its STAB).
	if g.source is Fighter and is_instance_valid(g.source):
		attacker = g.source
	var d: Dictionary = Moves.DATA.get(g.move_id, {})
	var power := power_of(d, attacker, target)
	if power <= 0.0 or attacker == null or not attacker.data.has("stats") or not target.data.has("stats"):
		return g.damage * affinity * g.bonus
	var physical := g.cat == "physical"
	var atk: float = (attacker.data.stats.atk if physical else attacker.data.stats.spa) * attacker.stage_mult("atk" if physical else "spa")
	var def: float = (target.data.stats.def if physical else target.data.stats.spd) * target.stage_mult("def" if physical else "spd")
	# A burn halves physical moves (not Facade), as in the games.
	if physical and attacker.status == "brn" and d.get("power_by", "") != "status":
		atk *= 0.5
	var w: Weather = attacker.main.weather
	if w:
		def *= w.defense_mult(target.types, physical)
		if not physical and w.is_on("sun") and attacker.data.passive.id == "solarpower":
			atk *= 1.5
	var base := (22.0 * power * atk / def) / 50.0 + 2.0
	if d.type in attacker.types:
		base *= STAB
	var share: float = g.damage / maxf(float(d.get("power_at", d.get("damage", g.damage))), 0.01)
	if w:
		base *= w.type_mult(d.type)
	return base * affinity * ROLL * Stats.HP_MULT / BATTLE_LENGTH / float(d.get("split", 1)) * share * g.bonus


## The move's power in the games; Electro Ball's depends on how much faster the user is.
static func power_of(d: Dictionary, attacker: Fighter, target: Fighter) -> float:
	if d.get("power_by", "") == "speed" and attacker and target and attacker.data.has("stats"):
		var ratio: float = float(attacker.data.stats.spe) / maxf(float(target.data.stats.spe), 1.0)
		if ratio >= 4.0:
			return 150.0
		if ratio >= 3.0:
			return 120.0
		if ratio >= 2.0:
			return 80.0
		if ratio >= 1.0:
			return 60.0
		return 40.0
	# Facade: twice the power while the user is burned, poisoned or paralyzed.
	if d.get("power_by", "") == "status" and attacker and attacker.has_status():
		return float(d.get("power", 0)) * 2.0
	return float(d.get("power", 0))
