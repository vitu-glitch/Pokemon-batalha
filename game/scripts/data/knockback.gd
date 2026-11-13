class_name Knockback
extends RefCounted
## How far a hit sends its target, in one place so every move (present or future) follows
## the same rule.
##
## The target slides backward while stunned and friction slows it down: a hit gives it a
## starting speed and the slide ends where friction stops it. The distance depends on the
## power of the hit:
##   light (strength 0) 0.3 m · medium (1) 1 m · heavy (2) 2.5 m
## Push moves (Body Slam, Flare Blitz, Solar Beam...) set their own distance with "knock"
## (meters) in Moves.DATA. A new move needs nothing: its strength is enough.
## Distances are for a Pokémon of average weight. Speed is divided by mass, as in real
## physics: the target's "knockback" in Roster.POKEMON (light ones above 1, heavy ones
## below) multiplies the starting speed, so the distance goes with its square: Pikachu
## (1.25) slides 1.56 times as far and Snorlax (0.45) a fifth as far.

const DISTANCE := [0.3, 1.0, 2.5]
## Deceleration while sliding on the ground (m/s²).
const FRICTION := 10.0
## Stream hits (Flamethrower, Hydro Pump) push every tick: this share of a full push.
const STREAM_SHARE := 0.3


## Meters the hit sends a target of average weight.
static func distance(g: Hit) -> float:
	if g.knock >= 0.0:
		return g.knock
	var d: Dictionary = Moves.DATA.get(g.move_id, {})
	if d.has("knock"):
		return d.knock
	return DISTANCE[clampi(g.strength, 0, 2)]


## Starting speed (m/s) that slides "meters" on the ground under FRICTION.
static func launch_speed(meters: float) -> float:
	return sqrt(2.0 * FRICTION * maxf(meters, 0.0))
