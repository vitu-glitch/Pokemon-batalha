class_name Scoreboard
extends Control
## The night stadium's big screens: each Pokémon's live portrait in a frame of its side's
## color, its name and its HP bar, drawn in the HUD's pixel font on a small canvas
## (SIZE) that the screens show as chunky LEDs. Still: only the HP bars move, sliding to
## the new value after a hit. Slot 0 is the pink side (left), 1 the cyan one.

const SIZE := Vector2i(192, 84)
const BG := Color(0.02, 0.03, 0.06)
const INK := Color(0.95, 0.96, 1.0)

var colors := [Color.WHITE, Color.WHITE]
var portraits: Array = [null, null]
var names := ["", ""]
var hp := [1.0, 1.0]
var _shown := [1.0, 1.0]
var _font: Font


func _ready() -> void:
	_font = load("res://gui/font/pixel.fnt")
	size = Vector2(SIZE)


func set_hp(left: float, right: float) -> void:
	hp = [left, right]


func _process(delta: float) -> void:
	var moved := false
	for i in 2:
		if absf(_shown[i] - hp[i]) > 0.0005:
			_shown[i] = move_toward(_shown[i], hp[i], delta * 0.6)
			moved = true
	if moved:
		queue_redraw()


func refresh() -> void:
	_shown = hp.duplicate()
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(SIZE)), BG)
	for i in 2:
		var right := i == 1
		var col: Color = colors[i]
		var x0 := 120.0 if right else 8.0
		# Portrait in a frame of its color.
		draw_rect(Rect2(x0 - 2.0, 6.0, 68.0, 52.0), col)
		draw_rect(Rect2(x0, 8.0, 64.0, 48.0), Color(0.06, 0.08, 0.13))
		if portraits[i]:
			draw_texture_rect(portraits[i], Rect2(x0, 8.0, 64.0, 48.0), false)
		# Name under it.
		var s: String = names[i]
		var w := _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		var tx := x0 + 64.0 - w if right else x0
		draw_string(_font, Vector2(roundf(tx) + 1.0, 70.0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0, 0, 0, 0.8))
		draw_string(_font, Vector2(roundf(tx), 69.0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, INK)
		# HP bar: it empties toward the outside.
		var bw := 80.0
		var bx := 104.0 if right else 8.0
		draw_rect(Rect2(bx, 74.0, bw, 5.0), col.darkened(0.75))
		var fw := roundf(bw * clampf(_shown[i], 0.0, 1.0))
		draw_rect(Rect2(bx if right else bx + bw - fw, 74.0, fw, 5.0), col)
	# VS in the middle.
	var vs := "VS"
	var vw := _font.get_string_size(vs, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
	draw_string(_font, Vector2(roundf(96.0 - vw * 0.5) + 1.0, 42.0), vs, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(0, 0, 0, 0.8))
	draw_string(_font, Vector2(roundf(96.0 - vw * 0.5), 41.0), vs, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, INK)
