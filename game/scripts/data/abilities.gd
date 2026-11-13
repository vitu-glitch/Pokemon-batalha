class_name Abilities
extends RefCounted
## Abilities beyond each Pokémon's default one (Roster.POKEMON[...].passive), by Showdown id.
## An ability listed here becomes selectable in the Moves menu for every Pokémon that has it
## in the games (Species.DATA[...].abilities). Its effect lives in fighter.gd, by id.
##   display_name, text          player-facing, in English (translated when drawn)

const DATA := {
	"lightningrod": {"display_name": "Lightning Rod",
		"text": "Electric moves do nothing to it and raise its Sp. Atk one stage (x1.5 for the battle)."},
	"immunity": {"display_name": "Immunity",
		"text": "It cannot be poisoned: puddles and poison do not hurt it."},
	"gluttony": {"display_name": "Gluttony",
		"text": "No items yet: it holds a Sitrus Berry and, being a glutton, eats it at half HP instead of a quarter. It heals a quarter of its HP, once per battle."},
	"torrent": {"display_name": "Torrent",
		"text": "At a third of its HP or less, its Water moves hit 1.5 times as hard."},
	"overgrow": {"display_name": "Overgrow",
		"text": "At a third of its HP or less, its Grass moves hit 1.5 times as hard."},
	"swarm": {"display_name": "Swarm",
		"text": "At a third of its HP or less, its Bug moves hit 1.5 times as hard."},
	"innerfocus": {"display_name": "Inner Focus",
		"text": "It does not flinch: its moves need one more step of strength to be cut short."},
	"justified": {"display_name": "Justified",
		"text": "Each Dark move that hits it raises its Attack one stage (x1.5 for the battle)."},
	"cursedbody": {"display_name": "Cursed Body",
		"text": "Each hit it takes has a 30% chance of disabling that move of the rival for 12 s."},
	"raindish": {"display_name": "Rain Dish",
		"text": "In the rain it heals 1/16 of its max HP every turn (3 s)."},
	"chlorophyll": {"display_name": "Chlorophyll",
		"text": "In harsh sunlight its Speed doubles."},
	"solarpower": {"display_name": "Solar Power",
		"text": "In harsh sunlight its Sp. Atk is 1.5 times higher, but it loses 1/8 of its max HP every turn (3 s)."},
	"sandveil": {"display_name": "Sand Veil",
		"text": "The sandstorm does not hurt it, and in it projectiles follow it worse."},
	"lightmetal": {"display_name": "Light Metal",
		"text": "Half its weight: it dodges a little further, but hits send it further too."},
}
