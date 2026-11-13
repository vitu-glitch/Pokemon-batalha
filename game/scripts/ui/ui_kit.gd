class_name UiKit
extends RefCounted
## Drawing kit of the menus, in Smash Ultimate's dark look: a charcoal floor with wide
## diagonal hatching, slanted blocks of solid color, heavy condensed italic names and
## little text. Flat shapes only (no gradients or shadows). Everything is placed in a
## 1920 × 1080 design space, scaled to the window's height and centered (wider screens
## just show more floor). Text that could run long is fitted to its box (text_fit).

const W := 1920.0
const H := 1080.0
const FLOOR := Color("1d1d21")
const HATCH := Color("242429")
const PANEL := Color("2b2b31")
const PANEL_HI := Color("36363e")
const LINE := Color("45454f")
const INK := Color("f4f4f6")
const SOFT := Color("9c9ca8")
const DARK := Color("121214")
const RED := Color("e0262f")
const YELLOW := Color("ffd21f")
const BLUE := Color("2f6fe0")
const GREEN := Color("1fae54")
const ORANGE := Color("f08a1c")
const GREY := Color("6b6d75")
const SLANT := 0.21                # tan(12°): every slanted shape leans the same way
const TALL := 0.06                 # tall panels lean less, so their text stays inside
const TYPE_ORDER := ["normal", "fire", "water", "grass", "electric", "ice", "fighting", "poison", "ground",
	"flying", "psychic", "bug", "rock", "ghost", "dragon", "dark", "steel", "fairy"]

var c: Control
var k := 1.0
var o := Vector2.ZERO
var heavy: SystemFont
var bold: SystemFont
var body: SystemFont
var _types: Texture2D


func _init() -> void:
	heavy = _font(700, 75)
	bold = _font(600, 87)
	body = _font(400, 100)
	_types = load("res://gui/cobblemon/types.png")


func _font(weight: int, stretch: int) -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Arial"])
	f.font_weight = weight
	f.font_stretch = stretch
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	return f


func begin(canvas: Control) -> void:
	c = canvas
	k = canvas.size.y / H
	o = Vector2((canvas.size.x - W * k) * 0.5, 0.0)


## A point of the design space on screen.
func p(x: float, y: float) -> Vector2:
	return o + Vector2(x, y) * k


## Left and right edges of the window in design units (beyond 0-1920 on wide screens).
func left() -> float:
	return -o.x / k


func right() -> float:
	return (c.size.x - o.x) / k


# ---------------------------------------------------------------- shapes

func full(col: Color) -> void:
	c.draw_rect(Rect2(Vector2.ZERO, c.size), col)


## The floor: charcoal with wide diagonal strokes, sliding very slowly.
func floor_hatch(t: float) -> void:
	full(FLOOR)
	var x := left() - 1200.0 + fmod(t * 6.0, 90.0)
	while x < right():
		c.draw_colored_polygon(PackedVector2Array([p(x, H), p(x + 30.0, H), p(x + 30.0 + H * 0.6, 0.0), p(x + H * 0.6, 0.0)]), HATCH)
		x += 90.0


func rect(x: float, y: float, w: float, h: float, col: Color) -> void:
	c.draw_rect(Rect2(p(x, y), Vector2(w, h) * k), col)


## Parallelogram leaning right (its top edge shifted by h × lean).
func slant(x: float, y: float, w: float, h: float, col: Color, lean := SLANT) -> void:
	c.draw_colored_polygon(PackedVector2Array([p(x + h * lean, y), p(x + w + h * lean, y), p(x + w, y + h), p(x, y + h)]), col)


## Where the left edge of a slant(x, y, _, h) block is at height at_y: what goes inside
## starts from here, so text follows the diagonal instead of sticking out at the top.
func edge(x: float, y: float, h: float, at_y: float, lean := SLANT) -> float:
	return x + (y + h - clampf(at_y, y, y + h)) * lean


## Outline of thickness t around a slant(x, y, w, h) block, following its lean.
func slant_frame(x: float, y: float, w: float, h: float, t: float, col: Color, lean := SLANT) -> void:
	slant(x + h * lean - t, y - t, w + 2.0 * t, t, col, lean)
	slant(x - t - t * lean, y + h, w + 2.0 * t, t, col, lean)
	slant(x - t, y, t, h, col, lean)
	slant(x + w, y, t, h, col, lean)


## Diagonal stripes inside a slanted block (texture for big tiles).
func stripes(x: float, y: float, w: float, h: float, col: Color, step := 36.0) -> void:
	var sx := x
	while sx < x + w - 10.0:
		var sw := minf(12.0, x + w - sx)
		slant(sx, y, sw, h, col, SLANT * 2.5)
		sx += step


func line(x0: float, y0: float, x1: float, y1: float, col: Color, w := 2.0) -> void:
	c.draw_line(p(x0, y0), p(x1, y1), col, w * k)


func tex(t: Texture2D, x: float, y: float, w: float, h: float, mod := Color.WHITE) -> void:
	if t:
		c.draw_texture_rect(t, Rect2(p(x, y), Vector2(w, h) * k), false, mod)


## A region of a texture (in its pixels) drawn into a rectangle.
func tex_region(t: Texture2D, x: float, y: float, w: float, h: float, region: Rect2, mod := Color.WHITE) -> void:
	if t:
		c.draw_texture_rect_region(t, Rect2(p(x, y), Vector2(w, h) * k), region, mod)


## Cobblemon's type symbol (the round one), size × size.
func type_icon(type: String, x: float, y: float, size: float, a := 1.0) -> void:
	var i := TYPE_ORDER.find(type)
	if i < 0 or _types == null:
		return
	c.draw_texture_rect_region(_types, Rect2(p(x, y), Vector2(size, size) * k), Rect2(i * 36, 0, 36, 36), Color(1, 1, 1, a))


## Segmented meter (stats, details): "v" from 0 to 1 over "segs" blocks.
func meter(x: float, y: float, w: float, h: float, v: float, col: Color, segs := 10) -> void:
	var gap := 3.0
	var sw := (w - gap * (segs - 1)) / segs
	var lit := v * segs
	for i in segs:
		var bx := x + i * (sw + gap)
		slant(bx, y, sw, h, LINE)
		var f := clampf(lit - i, 0.0, 1.0)
		if f > 0.0:
			slant(bx, y, sw * f, h, col)


# ---------------------------------------------------------------- text

## Text with its top-left (or top-center / top-right with align 0 / 1) at (x, y).
func text(x: float, y: float, s: String, size: float, col: Color, font: Font = null, align := -1) -> void:
	var f: Font = font if font else bold
	var px := int(round(size * k))
	if px < 4 or s == "":
		return
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var at := p(x, y)
	if align == 0:
		at.x -= w * 0.5
	elif align == 1:
		at.x -= w
	at.y += f.get_ascent(px)
	c.draw_string(f, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)


## The size at which "s" fits in max_w (never under 55% of "size").
func fit(s: String, max_w: float, size: float, font: Font = null) -> float:
	var w := width(s, size, font)
	if w <= max_w or w <= 0.0:
		return size
	return maxf(size * max_w / w, size * 0.55)


## Text shrunk to fit max_w, kept on the same baseline.
func text_fit(x: float, y: float, s: String, max_w: float, size: float, col: Color, font: Font = null, align := -1) -> void:
	var f := fit(s, max_w, size, font)
	var f_font: Font = font if font else bold
	var dy := (f_font.get_ascent(int(round(size * k))) - f_font.get_ascent(int(round(f * k)))) / k
	text(x, y + dy, s, f, col, font, align)


## Heading in heavy italic (sheared like the blocks), fitted to max_w when given.
func title(x: float, y: float, s: String, size: float, col: Color, align := -1, max_w := 0.0) -> void:
	var sz := fit(s, max_w, size, heavy) if max_w > 0.0 else size
	var y2 := y + (size - sz) * 0.8
	var pivot := p(x, y2 + sz)
	c.draw_set_transform_matrix(Transform2D(Vector2(1, 0), Vector2(-SLANT, 1), pivot) * Transform2D(0.0, -pivot))
	text(x, y2, s, sz, col, heavy, align)
	c.draw_set_transform_matrix(Transform2D.IDENTITY)


func width(s: String, size: float, font: Font = null) -> float:
	var f: Font = font if font else bold
	var px := maxi(1, int(round(size * k)))
	return f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x / k


## Splits a text into lines no wider than w.
func wrap_lines(s: String, w: float, size: float, font: Font = null) -> Array:
	var out: Array = []
	for part in s.split("\n"):
		var current := ""
		for word in part.split(" "):
			var test := word if current == "" else current + " " + word
			if width(test, size, font) > w and current != "":
				out.append(current)
				current = word
			else:
				current = test
		out.append(current)
	return out


## Wrapped paragraph in at most max_lines (the last one ends in "..." if it is cut);
## returns the y after it.
func para(x: float, y: float, s: String, w: float, size: float, col: Color, font: Font = null, gap := 1.3, max_lines := 99) -> float:
	var f: Font = font if font else body
	var lines := wrap_lines(s, w, size, f)
	for i in mini(lines.size(), max_lines):
		var ln: String = lines[i]
		if i == max_lines - 1 and lines.size() > max_lines:
			while ln.length() > 1 and width(ln + "...", size, f) > w:
				ln = ln.substr(0, ln.length() - 1)
			ln += "..."
		text(x, y, ln, size, col, f)
		y += size * gap
	return y


# ---------------------------------------------------------------- pieces

## Small button hints in the bottom-right corner: [[glyph, label]...], right to left.
func hints(items: Array) -> void:
	var x := 1860.0
	for i in range(items.size() - 1, -1, -1):
		var it: Array = items[i]
		var lw := width(it[1], 22.0, bold)
		var gw := maxf(width(it[0], 20.0, heavy) + 16.0, 30.0)
		text(x, 1030.0, it[1], 22.0, SOFT, bold, 1)
		x -= lw + 10.0
		rect(x - gw, 1030.0, gw, 28.0, PANEL_HI)
		text(x - gw * 0.5, 1033.0, it[0], 20.0, INK, heavy, 0)
		x -= gw + 30.0


## A type's color tag with its symbol and name.
func type_tag(x: float, y: float, type: String, size := 22.0) -> float:
	var name: String = TranslationServer.translate(Roster.TYPE_NAME.get(type, type)).to_upper()
	var h := size + 14.0
	var w := width(name, size, heavy) + h + 24.0 + size * SLANT
	slant(x, y, w, h, Roster.TYPE_COLOR.get(type, GREY))
	type_icon(type, x + 6.0 + h * SLANT * 0.5, y + 3.0, h - 6.0)
	# The name leans like the tag, and stays inside it.
	title(x + h + 10.0, y + 6.0, name, size, INK, -1, w - h - 22.0)
	return x + w + 10.0


## Dodge charges as the HUD shows them: a row of diamonds.
func diamonds(x: float, y: float, n: int, size: float, col: Color) -> void:
	for i in n:
		var cx := x + size * 0.5 + i * (size + 8.0)
		var cy := y + size * 0.5
		c.draw_colored_polygon(PackedVector2Array([p(cx, cy - size * 0.5), p(cx + size * 0.5, cy), p(cx, cy + size * 0.5), p(cx - size * 0.5, cy)]), col)


static func ease(t: float) -> float:
	var v := clampf(t, 0.0, 1.0)
	return 1.0 - pow(1.0 - v, 3.0)
