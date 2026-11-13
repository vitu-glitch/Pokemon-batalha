class_name Hit
extends RefCounted
## An active hit volume. It is the only thing that deals damage: if its shape does not
## touch the rival's body (a capsule), there is no hit, whatever the effects look like.
##   sphere   center, radius
##   capsule  a, b, radius (a segment with thickness: sweeps, streams)
##   cone     origin, dir, length, angle (Flamethrower)
##   ring     center, r_in, r_out, only hits whoever touches the ground (Earthquake: jump it)
## With "local", positions are in the user's space (x right, y up, z forward) and
## follow its body; otherwise they are in world space.

var user: Node            # Fighter
var shape := "sphere"
var local := true
var center := Vector3.ZERO
var a := Vector3.ZERO
var b := Vector3.ZERO
var radius := 0.5
var dir := Vector3.FORWARD
var length := 4.0
var angle := 0.4
var r_in := 0.0
var r_out := 1.0
var ground_only := false

var damage := 50.0
var type := "normal"
var cat := "physical"
var contact := true            # close-range hit (passives like Static)
var knock := -1.0              # meters it slides the target (-1: from Knockback, by strength)
var push := 0.0                # m/s along "push_dir" (pulls like Vine Whip's); unused without it
var push_dir := Vector3.ZERO   # if not zero, in the user's space
var lift := 0.0                # upward speed: launches the target
var stun := 0.3                # time unable to act
var knocks_down := false       # falls to the ground and gets up (with invulnerability)
var hitstop := 0.06            # impact pause (hitstop) on both fighters
var strength := 1              # 0 light, 1 medium, 2 heavy: sound, rumble, effects
var effect := ""               # paralyze, freeze, burn...
var interval := 0.0            # repeated hits on the same target every so often (0: only one)
var lifetime := -1.0           # seconds it lasts (-1: until removed)
var active := true
var hit_list := {}             # target id -> time of the last hit
var on_strike := Callable()    # callback(target, result)
var move_id := ""
var source: Node                # whose stats the damage uses, if not the user's (sent back)
var bonus := 1.0               # damage multiplier (a projectile sent back hits harder)
var born := 0.0                # Combat's clock when it came out (deflect timing)
var quiet := false             # a follow-up blow of a flurry: the effectiveness is not told again
var cut := 0.0                 # a stream stopped short by another (m from its origin; 0: not cut)


## What share of its move one hit is worth (Aura Sphere's charge; 1 otherwise).
func hit_share() -> float:
	var d: Dictionary = Moves.DATA.get(move_id, {})
	if d.has("power_at"):
		return clampf(damage / maxf(float(d.power_at), 0.01), 0.2, 2.0)
	return 1.0


## A fresh copy of this hit (same shape and numbers, nothing hit yet).
func copy() -> Hit:
	var h := Hit.new()
	for k in ["user", "shape", "local", "center", "a", "b", "radius", "dir", "length", "angle", "r_in", "r_out",
			"ground_only", "damage", "type", "cat", "contact", "knock", "push", "push_dir", "lift", "stun",
			"knocks_down", "hitstop", "strength", "effect", "interval", "lifetime", "move_id", "source", "bonus", "quiet"]:
		h.set(k, get(k))
	return h


## Shape in world space, according to where the user is now.
func base() -> Transform3D:
	if not local or user == null:
		return Transform3D.IDENTITY
	return user.body_basis()
