class_name Stats
extends RefCounted
## Turns each species' real base stats (data/species.gd) into battle numbers.
## Everything is computed at level 50 with 31 IVs, no EVs and a neutral nature, so the
## differences between Pokémon are exactly the ones in the games. The formulas are the same
## for everyone: tune them here, never a single Pokémon. Design notes: docs/roster-plan.md.
## What stats do not cover (size, jump, flight, dodge style, passive, moves) stays in
## data/roster.gd. Launch with --hand-stats to use roster.gd's hand-tuned numbers.

const LEVEL := 50
## Health = HP at level 50 × this. Battles take about this many times more hits than in the
## games, so they are not over in a few seconds.
const HP_MULT := 6.5
## Held items that change stats, as in the games (roster "item"). The Light Ball doubles
## Pikachu's Attack and Sp. Atk.
const ITEMS := {"lightball": {"atk": 2.0, "spa": 2.0}}


## A stat at level 50 (31 IVs, no EVs, neutral nature), with the games' formula.
static func at_level(base: int, is_hp := false) -> int:
	var core := int((2 * base + 31) * LEVEL / 100.0)
	return core + LEVEL + 10 if is_hp else core + 5


## The Pokémon's roster data with its real stats applied. A copy: Roster.POKEMON is untouched.
static func battle_data(species: String) -> Dictionary:
	var d: Dictionary = Roster.POKEMON[species].duplicate(true)
	if not Species.DATA.has(species) or OS.get_cmdline_user_args().has("--hand-stats"):
		return d
	var sp: Dictionary = Species.DATA[species]
	var s := {}
	for k in sp.stats:
		s[k] = at_level(sp.stats[k], k == "hp")
	for k in ITEMS.get(d.get("item", ""), {}):
		s[k] = int(s[k] * ITEMS[d.item][k])
	var kg: float = sp.weight_kg
	d.stats = s
	d.weight_kg = kg
	d.hp = snappedf(s.hp * HP_MULT, 10.0)
	# Speed: movement, and how many dodges, how far and how fast they come back.
	d.speed = snappedf(4.0 + 0.032 * s.spe, 0.1)
	d.dodge.charges = clampi(1 + int(s.spe / 45.0), 1, 3)
	d.dodge.recharge = snappedf(2.2 - 0.009 * s.spe, 0.1)
	# Heavy Pokémon dodge shorter: weight counts on a log scale (6 kg to 460 kg).
	d.dodge.dist = snappedf(3.2 + 0.0225 * s.spe - 0.085 * log(kg), 0.1)
	return d
