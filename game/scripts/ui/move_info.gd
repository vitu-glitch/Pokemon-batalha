class_name MoveInfo
extends RefCounted
## A move's numbers as the menus show them: the games' data (power, accuracy, PP) and
## ours (cooldown, energy, timings, knockback, poise...), each with a bar from 0 to 1 and
## the exact figure. Everything comes from Moves.DATA, so a change there shows here.

## [label, bar 0-1 (or -1: no bar), figure] rows.
static func rows(id: String) -> Array:
	var d: Dictionary = Moves.DATA[id]
	var out: Array = []
	var power: float = d.get("power", 0)
	if power > 0.0:
		var shown := "%d" % power
		if int(d.get("split", 1)) > 1:
			shown += "  " + TranslationServer.translate("(in %d hits)") % int(d.split)
		out.append([TranslationServer.translate("Power"), clampf(power / 150.0, 0.0, 1.0), shown])
	var acc: float = d.get("accuracy", 0)
	out.append([TranslationServer.translate("Tracking"), 1.0 if acc <= 0.0 else pow(acc / 100.0, 2.5),
		TranslationServer.translate("Never misses") if acc <= 0.0 else "%d%%" % acc])
	var cd := Moves.cooldown(id)
	out.append([TranslationServer.translate("Cooldown"), clampf(cd / 14.0, 0.0, 1.0), "%.1f s" % cd])
	out.append([TranslationServer.translate("Energy"), clampf(float(d.get("cost", 0.0)) / 40.0, 0.0, 1.0), "%d" % int(d.get("cost", 0.0))])
	var startup: float = d.get("startup", 0.0)
	out.append([TranslationServer.translate("Wind-up"), clampf(startup / 1.4, 0.0, 1.0), "%.2f s" % startup])
	out.append([TranslationServer.translate("Recovery"), clampf(float(d.get("recovery", 0.0)) / 1.0, 0.0, 1.0), "%.2f s" % float(d.get("recovery", 0.0))])
	if d.get("cat", "") != "status":
		var meters: float = d.get("knock", Knockback.DISTANCE[clampi(int(d.get("strength", 1)), 0, 2)])
		out.append([TranslationServer.translate("Knockback"), clampf(meters / 4.0, 0.0, 1.0), "%.1f m" % meters])
		var strength := int(d.get("strength", 1))
		out.append([TranslationServer.translate("Breaks poise"), (strength + 1) / 3.0, [TranslationServer.translate("Light"), TranslationServer.translate("Medium"), TranslationServer.translate("Heavy")][clampi(strength, 0, 2)]])
	var poise := int(d.get("poise", 0))
	out.append([TranslationServer.translate("Poise"), poise / 2.0, [TranslationServer.translate("None"), TranslationServer.translate("Medium"), TranslationServer.translate("High")][clampi(poise, 0, 2)]])
	return out


## Short facts without a bar: category, priority, cancels, secondary effect.
static func facts(id: String) -> Array:
	var d: Dictionary = Moves.DATA[id]
	var out: Array = []
	match d.get("cat", ""):
		"physical": out.append(TranslationServer.translate("Physical"))
		"special": out.append(TranslationServer.translate("Special"))
		"status": out.append(TranslationServer.translate("Status"))
	if int(d.get("priority", 0)) > 0:
		out.append(TranslationServer.translate("Priority +%d") % int(d.priority))
	if d.get("cancels_dodge", false):
		out.append(TranslationServer.translate("Cancels into a dodge"))
	if d.get("cancels_into_moves", false):
		out.append(TranslationServer.translate("Chains into moves on hit"))
	match int(d.get("deflects", 0)):
		1: out.append(TranslationServer.translate("Breaks projectiles"))
		2: out.append(TranslationServer.translate("Sends projectiles back"))
	if d.get("knocks_down", false):
		out.append(TranslationServer.translate("Knocks down"))
	if d.has("secondary"):
		var sec: Dictionary = d.secondary
		var what := ""
		if sec.has("status"):
			what = Status.verb(sec.status)
		elif sec.has("boost"):
			what = TranslationServer.translate("Lowers the rival's stats")
		elif sec.has("self"):
			what = TranslationServer.translate("Raises its own stats")
		out.append("%d%%: %s" % [int(round(float(sec.get("chance", 1.0)) * 100.0)), what])
	if d.has("flinch"):
		out.append(TranslationServer.translate("%d%% flinch") % int(round(float(d.flinch) * 100.0)))
	return out


## The Pokémon's sheet: the numbers it fights with here (HP and stats at level 50, with
## its held item), as [label, bar 0-1, bar 0-1 without the item, figure]. Where they come
## from is in the documentation.
const HP_TOP := 1600.0               # bar scales: about the highest in the roster
const STAT_TOP := 200.0


static func stat_rows(sp: String) -> Array:
	var d := Stats.battle_data(sp)
	var out: Array = []
	if not d.has("stats"):
		return out
	out.append([TranslationServer.translate("HP"), clampf(float(d.hp) / HP_TOP, 0.0, 1.0), -1.0, "%d" % int(d.hp)])
	var item: Dictionary = Stats.ITEMS.get(d.get("item", ""), {})
	for k in [["atk", "Attack"], ["def", "Defense"], ["spa", "Sp. Atk"], ["spd", "Sp. Def"], ["spe", "Speed"]]:
		var v: int = d.stats.get(k[0], 0)
		var plain: float = v / float(item.get(k[0], 1.0))
		out.append([TranslationServer.translate(k[1]), clampf(v / STAT_TOP, 0.0, 1.0),
			clampf(plain / STAT_TOP, 0.0, 1.0) if item.has(k[0]) else -1.0, "%d" % v])
	return out


## What the stats do not say: weight and how far hits send it (one goes with the other),
## dodges, and whether it flies or levitates.
static func body(sp: String) -> Dictionary:
	var d := Stats.battle_data(sp)
	return {"kg": float(d.get("weight_kg", 0.0)), "knockback": float(d.knockback), "dodges": int(d.dodge.charges),
		"air": "levitates" if d.get("levitates", false) else ("flies" if d.has("flight") else "")}
