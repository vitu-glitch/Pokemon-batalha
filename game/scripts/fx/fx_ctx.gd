class_name FxCtx
extends RefCounted
## Evaluation context for the translated Molang (see tools/convert_particles.py).
## Expressions call these methods: V("name") reads a variable or curve,
## msin/mcos work in degrees like Bedrock, mif(c, a, b) is "c ? a : b".

var p: Dictionary = {}       # particle variables
var e: Dictionary = {}       # emitter variables
var curves: Dictionary = {}  # effect curves


func V(n: String) -> float:
	if p.has(n):
		return p[n]
	if e.has(n):
		return e[n]
	if curves.has(n):
		return _curve(curves[n])
	return 0.0


func ev(x) -> float:
	if x is float or x is int:
		return float(x)
	if x is Expression:
		var r = x.execute([], self)
		return float(r) if (r is float or r is int or r is bool) else 0.0
	return 0.0


func _curve(c: Dictionary) -> float:
	var nodes: Array = c.nodes
	if nodes.is_empty():
		return 0.0
	var span := ev(c.range)
	var t := ev(c.input) / span if span != 0.0 else 0.0
	t = clampf(t, 0.0, 1.0)
	var list := nodes
	if c.type == "catmull_rom" and nodes.size() > 3:
		list = nodes.slice(1, nodes.size() - 1)
	var n := list.size()
	if n == 1:
		return float(list[0])
	var f := t * (n - 1)
	var i := mini(int(f), n - 2)
	return lerpf(float(list[i]), float(list[i + 1]), f - i)


# --- Molang functions (math.*) ---
func msin(x: float) -> float: return sin(deg_to_rad(x))
func mcos(x: float) -> float: return cos(deg_to_rad(x))
func masin(x: float) -> float: return rad_to_deg(asin(x))
func macos(x: float) -> float: return rad_to_deg(acos(x))
func matan(x: float) -> float: return rad_to_deg(atan(x))
func matan2(y: float, x: float) -> float: return rad_to_deg(atan2(y, x))
func mrand(a: float = 0.0, b: float = 1.0) -> float: return randf_range(a, b)
func mrandi(a: float, b: float) -> float: return float(randi_range(int(a), int(b)))
func mdie(n: float, lo: float, hi: float) -> float:
	var s := 0.0
	for i in int(n):
		s += randf_range(lo, hi)
	return s
func mclamp(x: float, a: float, b: float) -> float: return clampf(x, a, b)
func mround(x: float) -> float: return round(x)
func mfloor(x: float) -> float: return floor(x)
func mceil(x: float) -> float: return ceil(x)
func mtrunc(x: float) -> float: return float(int(x))
func mabs(x: float) -> float: return absf(x)
func mmin(a: float, b: float) -> float: return minf(a, b)
func mmax(a: float, b: float) -> float: return maxf(a, b)
func mpow(a: float, b: float) -> float: return pow(a, b)
func msqrt(x: float) -> float: return sqrt(maxf(x, 0.0))
func mmod(a: float, b: float) -> float: return fmod(a, b) if b != 0.0 else 0.0
func mlerp(a: float, b: float, t: float) -> float: return lerpf(a, b, t)
func mexp(x: float) -> float: return exp(x)
func mln(x: float) -> float: return log(maxf(x, 1e-6))
func mhermite(t: float) -> float: return 3.0 * t * t - 2.0 * t * t * t
func mzero(_a = 0.0, _b = 0.0, _c = 0.0) -> float: return 0.0
func mif(c, a, b) -> float: return float(a) if mt(c) else float(b)
func mb(c) -> float: return 1.0 if c else 0.0
func mt(c) -> bool: return (c is bool and c) or ((c is float or c is int) and c != 0)
