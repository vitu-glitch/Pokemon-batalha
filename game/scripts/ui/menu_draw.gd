class_name MenuDraw
extends RefCounted
## Draws the menus (Menu keeps the logic) in Smash Ultimate's dark look (UiKit): a
## hatched charcoal floor, solid slanted blocks, big italic names and very little text.
## Each screen weighs differently: the main menu is a wall of tiles of different sizes,
## the selection a row of portraits over two big player cards, the Moves screen a list
## with a sheet. Highlights ease in and out; text that could run long is fitted to its
## block so nothing spills out.

const ITEM_COLOR := {"combat": UiKit.RED, "online": UiKit.GREEN, "training": UiKit.ORANGE, "moves": UiKit.BLUE,
	"options": UiKit.GREY, "quit": Color("3a3a42"), "profile": Color("6a4bb8"), "create": UiKit.GREEN, "join": UiKit.BLUE, "back": UiKit.GREY}
## Tiles of the main menu and the online menu: [x, y, w, h] in the 1920 × 1080 space.
## Tiles of the main menu and the online menu: [x, y, w, h] in the 1920 × 1080 space, x
## measured on the wall's base line (TILE_BASE). All their sides lean on that same line, so
## the gaps between tiles stay the same from top to bottom whatever their height.
const TILE_BASE := 840.0
const MAIN_TILES := [[70, 150, 760, 690], [870, 150, 520, 330], [1430, 150, 300, 330],
	[870, 510, 520, 330], [1430, 510, 300, 150], [1430, 690, 300, 150]]
const ONLINE_TILES := [[70, 150, 760, 690], [870, 150, 860, 500], [870, 690, 860, 150]]
## Credits at the bottom of the main menu, small. Cobblemon's assets are CC BY-NC 3.0:
## the team, the license and the non-profit nature are named.
const CREDITS := ["Created by xjoje6. Made with Godot Engine.",
	"Models, animations, effects, sounds and battle UI: the Cobblemon team (CC BY-NC 3.0, adapted)",
	"Music: Pokémon arrangements by The Noble Demon, used with credit as permitted by the artist. Original compositions by GAME FREAK.",
	"Trainer sprites from the Pokémon games, via Pokémon Showdown. Full credits in CREDITS.txt.",
	"Non-profit fan project. Pokémon belongs to Nintendo, Creatures Inc., GAME FREAK and The Pokémon Company."]

var m: Menu
var u := UiKit.new()
## What the mouse can point at, gathered while drawing: {kind, i, rect} in screen pixels,
## the last drawn on top.
var zones: Array = []
var _on := {}                    # eased highlight of each element (0 to 1)
var _want := {}                  # where each one is going
var _t := 0.0
var _stage_tex := {}


func step(delta: float) -> void:
	_t += delta
	for key in _on.keys():
		_on[key] = move_toward(_on[key], _want.get(key, 0.0), delta * 7.0)


## Eased highlight: "want" is where it is going; returns where it is now.
func on(key: String, want: bool) -> float:
	_want[key] = 1.0 if want else 0.0
	if not _on.has(key):
		_on[key] = 1.0 if want else 0.0
	return _on[key]


func _stage_picture(id: String) -> Texture2D:
	if not _stage_tex.has(id):
		var path := "res://gui/stages/%s.png" % id
		_stage_tex[id] = load(path) if ResourceLoader.exists(path) else null
	return _stage_tex[id]


# ---------------------------------------------------------------- frame

func draw(h: Hud) -> void:
	u.begin(h._c)
	zones.clear()
	u.floor_hatch(_t)
	match m.screen:
		"title":
			_title()
		"main":
			_header(tr("Menu"), ITEM_COLOR.get(Menu.MAIN_MENU[m.cursor][0], UiKit.RED))
			_tiles(Menu.MAIN_MENU, MAIN_TILES)
			_profile_badge()
			_credits()
			u.hints([[Controls.glyph("jump"), tr("Choose")], [Controls.glyph("menu_back"), tr("Back")]])
		"online":
			_header(tr("Online"), UiKit.GREEN)
			_tiles(Menu.ONLINE, ONLINE_TILES)
			u.hints([[Controls.glyph("jump"), tr("Select")], [Controls.glyph("menu_back"), tr("Back")]])
		"waiting":
			_waiting()
		"connecting":
			_header(tr("Connecting"), UiKit.GREEN)
			_card(160.0, 220.0, 1000.0, [tr("Joining %s:7777") % m.ip + ".".repeat(int(_t * 2.0) % 4)], UiKit.GREEN)
			u.hints([[Controls.glyph("menu_back"), tr("Cancel")]])
		"join":
			_join()
		"selection":
			_selection()
		"moves":
			_moves()
		"options":
			_options()
		"profile":
			_profile()
		"vs":
			_vs()
	if not m.confirm.is_empty():
		_confirm()


## Black slanted block with the screen's name, a color edge sliding in with it.
func _header(text: String, col: Color) -> void:
	var k := UiKit.ease(m.enter_t / 0.3)
	var x := lerpf(-900.0, -80.0, k)
	u.slant(x, 30.0, 840.0, 92.0, UiKit.DARK)
	u.slant(x + 840.0, 30.0, 16.0, 92.0, col)
	u.title(x + 170.0, 42.0, text.to_upper(), 64.0, UiKit.INK, -1, 600.0)


# ---------------------------------------------------------------- title

func _title() -> void:
	var k := UiKit.ease(m.enter_t / 0.6)
	u.slant(lerpf(-1600.0, -300.0, k), 330.0, 1500.0, 190.0, UiKit.RED)
	u.slant(lerpf(-1800.0, -300.0, k), 532.0, 1260.0, 26.0, UiKit.YELLOW)
	u.title(150.0, 336.0, "POKEBRAWL", 176.0, UiKit.INK)
	if Menu.version().begins_with("demo"):
		u.title(156.0, 574.0, "DEMO", 40.0, UiKit.YELLOW)
	u.tex(m.render("title", m.choice.p1, Vector2i(760, 820), 0.6), 1080.0, 160.0, 760.0, 820.0)
	var a := 0.7 + 0.3 * sin(_t * TAU * 0.5)
	u.text(156.0, 800.0, tr("%s to start") % Controls.glyph("jump"), 34.0, Color(UiKit.YELLOW, a), u.heavy)
	# The demo says so under the name; a numbered version, in the corner.
	if not Menu.version().begins_with("demo"):
		u.text(1860.0, 1030.0, "v" + Menu.version(), 22.0, UiKit.SOFT, u.body, 1)


# ---------------------------------------------------------------- tile menus

## A wall of tiles of different sizes in their own colors, Smash style. The highlighted one
## grows a little and gets a white frame; the others darken. Under them, what it does.
func _tiles(list: Array, tiles: Array) -> void:
	for i in mini(list.size(), tiles.size()):
		var id: String = list[i][0]
		var r: Array = tiles[i]
		var delay := UiKit.ease((m.enter_t - i * 0.05) / 0.3)
		var x: float = r[0] + (1.0 - delay) * 120.0
		var y: float = r[1]
		var w: float = r[2]
		var hgt: float = r[3]
		var o := on(m.screen + id, i == m.cursor)
		var col: Color = ITEM_COLOR.get(id, UiKit.GREY)
		var grow := 10.0 * o
		if o > 0.01:
			_tile(x, y, w, hgt, grow + 6.0 * o, UiKit.INK)
		_tile(x, y, w, hgt, grow, col.darkened(0.45 * (1.0 - o)))
		_tile_art(id, x, y, w, hgt, o)
		zone(m.screen, i, _tile_x(x, y + hgt), y, w + (y + hgt - y) * UiKit.SLANT, hgt)
		var size := 92.0 if hgt > 500.0 else (64.0 if hgt > 200.0 else 44.0)
		u.title(_tile_x(x, y + hgt - 30.0) + 36.0, y + hgt - size - 30.0, tr(list[i][1]).to_upper(), size, UiKit.INK, -1, w - 90.0)
	# What the highlighted tile does, under the wall.
	var desc: String = list[m.cursor][2]
	if desc != "":
		u.text_fit(70.0, 880.0, tr(desc), 1780.0, 30.0, UiKit.INK, u.bold)
	if m.message != "":
		var mw := minf(u.width(m.message, 26.0, u.bold), 1700.0)
		u.slant(70.0, 926.0, mw + 60.0, 48.0, UiKit.RED)
		u.text_fit(100.0, 936.0, m.message, 1700.0, 26.0, UiKit.INK, u.bold)


## A tile whose sides lean on the wall's base line, "grow" bigger on every side.
func _tile(x: float, y: float, w: float, hgt: float, grow: float, col: Color) -> void:
	var y0 := y - grow
	var y1 := y + hgt + grow
	u.c.draw_colored_polygon(PackedVector2Array([u.p(_tile_x(x, y0) - grow, y0), u.p(_tile_x(x, y0) + w + grow, y0),
		u.p(_tile_x(x, y1) + w + grow, y1), u.p(_tile_x(x, y1) - grow, y1)]), col)


## The left side of a tile at height at_y.
func _tile_x(x: float, at_y: float) -> float:
	return x + (TILE_BASE - at_y) * UiKit.SLANT


## What each tile shows besides its name.
func _tile_art(id: String, x: float, y: float, w: float, _hgt: float, o: float) -> void:
	match id:
		"combat":
			u.tex(m.render("menu_b", m.choice.p2, Vector2i(300, 340), -0.5), _tile_x(x, y + 230.0) + 10.0, y + 60.0, 300.0, 340.0, Color(1, 1, 1, 0.35 + 0.65 * o))
			u.tex(m.render("menu_a", m.choice.p1, Vector2i(420, 470), 0.5), _tile_x(x, y + 300.0) + w - 430.0, y + 10.0, 420.0, 470.0)
		"online":
			u.title(_tile_x(x, y + 120.0) + w - 50.0, y + 20.0, "1 VS 1", 110.0, Color(1, 1, 1, 0.14), 1)
		"moves":
			var lo := Loadout.saved(m.choice.p1)
			var ix := _tile_x(x, y + 90.0) + w - 70.0
			for mv in lo.moves:
				u.type_icon(Moves.DATA[mv].type, ix - 10.0, y + 30.0, 56.0, 0.5 + 0.5 * o)
				ix -= 66.0
		"create":
			u.title(_tile_x(x, y + 150.0) + w - 50.0, y + 30.0, "7777", 120.0, Color(1, 1, 1, 0.12), 1)
		"join":
			u.title(_tile_x(x, y + 120.0) + w - 50.0, y + 30.0, m.ip, 90.0, Color(1, 1, 1, 0.14), 1, w - 120.0)


func _credits() -> void:
	var y := 1034.0 - CREDITS.size() * 24.0
	for i in CREDITS.size():
		u.text(70.0, y, tr(CREDITS[i]), 17.0, Color(UiKit.INK, 0.6 if i == 0 else 0.4), u.body)
		y += 24.0


## A dark block of text lines ("!" in front marks a warning, in red).
func _card(x: float, y: float, w: float, lines: Array, col: Color) -> void:
	var hgt := 50.0
	for ln in lines:
		hgt += u.wrap_lines(str(ln).trim_prefix("!"), w - 110.0, 30.0, u.bold).size() * 39.0 + 10.0
	u.slant(x, y, w, hgt, UiKit.PANEL, UiKit.TALL)
	u.slant(x, y, 14.0, hgt, col, UiKit.TALL)
	var ly := y + 26.0
	for ln in lines:
		var text: String = ln
		var c := UiKit.INK
		if text.begins_with("!"):
			text = text.substr(1)
			c = UiKit.RED.lightened(0.25)
		ly = u.para(u.edge(x, y, hgt, ly, UiKit.TALL) + 50.0, ly, text, w - 110.0, 30.0, c, u.bold) + 10.0


func _waiting() -> void:
	_header(tr("Waiting for rival"), UiKit.GREEN)
	var lines: Array = [tr("Give your friend one of these IPs:")]
	var net: Net = m.main.net
	if net and net.public_ip != "":
		lines.append(tr("Over the internet: %s") % net.public_ip)
	for loc in Net.local_ips():
		lines.append(tr("Local network or VPN: %s") % loc)
	if net and net.upnp_testing:
		lines.append(tr("Opening port 7777 on the router") + ".".repeat(int(_t * 2.0) % 4))
	elif net and net.upnp_ok:
		lines.append(tr("Port 7777 open on the router."))
	else:
		lines.append("!" + tr("The router did not open the port: open it (UDP 7777) or use Radmin VPN or ZeroTier."))
	_card(160.0, 200.0, 1200.0, lines, UiKit.GREEN)
	u.hints([[Controls.glyph("menu_back"), tr("Back")]])


func _join() -> void:
	_header(tr("Join"), UiKit.BLUE)
	u.slant(150.0, 180.0, 920.0, 150.0, UiKit.PANEL)
	u.slant(150.0, 180.0, 14.0, 150.0, UiKit.BLUE)
	u.text(u.edge(150.0, 180.0, 150.0, 196.0) + 40.0, 196.0, tr("Game IP:"), 26.0, UiKit.SOFT, u.bold)
	u.title(u.edge(150.0, 180.0, 150.0, 280.0) + 50.0, 232.0, m.ip, 70.0, UiKit.INK, -1, 780.0)
	var w := minf(u.width(m.ip, 70.0, u.heavy), 780.0)
	u.rect(u.edge(150.0, 180.0, 150.0, 280.0) + 66.0 + w, 300.0, 34.0, 8.0, Color(UiKit.YELLOW, 0.6 + 0.4 * sin(_t * TAU * 0.9)))
	var pad: bool = Controls.last_device != "keyboard"
	var key_on := m.key_on()
	for row in 4:
		for col in 4:
			var key: String = Menu.KEYPAD[row][col]
			if key == "connect" and col == 3:
				continue
			var cw := 420.0 if key == "connect" else 200.0
			var cx := 150.0 + col * 220.0
			var cy := 370.0 + row * 120.0
			var o := on("key%d%d" % [col, row], Vector2i(col, row) == key_on)
			u.slant(cx, cy, cw, 100.0, UiKit.PANEL.lerp(UiKit.BLUE, o))
			zone("key", row * 4 + col, cx, cy, cw, 100.0)
			u.text_fit(cx + cw * 0.5 + 10.0, cy + 28.0, m.key_label(key), cw - 40.0, 40.0, UiKit.INK, u.heavy, 0)
	if m.message != "":
		_card(1150.0, 180.0, 700.0, ["!" + m.message], UiKit.RED)
	if pad:
		u.hints([[Controls.glyph("jump"), tr("Press")], [Controls.glyph("menu_back"), tr("Delete")]])
	else:
		u.hints([[tr("Enter"), tr("Connect")], [tr("Esc"), tr("Back")]])


# ---------------------------------------------------------------- selection

func _side_color(side: int) -> Color:
	if side == 0:
		return UiKit.RED
	return UiKit.BLUE if m.online else UiKit.GREY


func _selection() -> void:
	var list := m.pokemon_list()
	var title := tr("Pick your Pokémon")
	if m.sel_phase == "p2":
		title = tr("Pick the rival")
	elif m.sel_phase == "setup":
		title = tr("Get ready")
	_header(title, _side_color(1 if m.sel_phase == "p2" else 0))
	# The stage, always at hand: its picture and name, top right.
	var st: String = m.choice.stage
	u.slant(1500.0, 30.0, 360.0, 92.0, UiKit.DARK)
	u.tex(_stage_picture(st), 1530.0, 38.0, 136.0, 76.0)
	u.text(1676.0, 44.0, tr("Stage"), 20.0, UiKit.SOFT, u.bold)
	u.text_fit(1676.0, 70.0, tr(Menu.STAGE_NAME[st]), 170.0, 30.0, UiKit.INK, u.heavy)
	var setup := on("setup_view", m.sel_phase == "setup")
	if setup < 0.999:
		_wall(list, setup)
	if setup > 0.001:
		_setup_bar(setup)
	for side in 2:
		_player_card(side)
	var items: Array = []
	if m.sel_phase == "setup":
		items = [[Controls.glyph("menu_back"), tr("Change")]] if m.online and m.me_ready \
			else [[Controls.glyph("jump"), tr("Choose")], [Controls.glyph("menu_back"), tr("Back")]]
	else:
		items = [[Controls.glyph("jump"), tr("Pick")], [Controls.glyph("menu_back"), tr("Leave") if m.online else tr("Back")]]
		if m.online and m.main.net and m.main.net.host:
			items.push_front([Controls.glyph("mov2"), tr("Stage")])
	if m.online and m.main.net:
		u.text(70.0, 1030.0, "Ping %d ms" % m.main.net.ping_ms(), 22.0, UiKit.SOFT, u.bold)
	if m.online and m.version_mismatch():
		var warn := tr("Your rival has another version (%s, yours %s): use the same package to play.") % [
			m.rival_version if m.rival_version != "?" else tr("an old one"), Menu.version()]
		var ww := minf(u.width(warn, 26.0, u.bold), 1300.0)
		u.slant(70.0, 960.0, ww + 60.0, 48.0, UiKit.RED)
		u.text_fit(100.0, 970.0, warn, 1300.0, 26.0, UiKit.INK, u.bold)
	u.hints(items)


## The wall of portraits: one row of ten, no gaps. The highlighted one lights up in the
## color of whoever is picking; tokens mark what each side has.
func _wall(list: Array, setup: float) -> void:
	var tw := 1780.0 / list.size()
	var lift := -340.0 * UiKit.ease(setup)
	var picker := _side_color(1 if m.sel_phase == "p2" else 0)
	for i in list.size():
		var sp: String = list[i]
		var data: Dictionary = Roster.POKEMON[sp]
		var x := 70.0 + i * tw
		var y := 150.0 + lift
		var o := on("wall" + sp, i == m.cursor and m.sel_phase != "setup")
		if setup < 0.5:
			zone("wall", i, x, y, tw - 3.0, 200.0)
		u.rect(x, y, tw - 3.0, 200.0, UiKit.PANEL.lerp(UiKit.PANEL_HI, o))
		u.rect(x, y, tw - 3.0, 124.0, Color(Roster.TYPE_COLOR.get(data.types[0], UiKit.GREY), 0.22 + 0.2 * o))
		if m.portraits.has(sp):
			u.tex(m.portraits[sp], x + (tw - 3.0) * 0.5 - 76.0, y + 4.0 - 6.0 * o, 152.0, 152.0)
		for t in data.types.size():
			u.type_icon(data.types[t], x + tw - 34.0 - t * 28.0, y + 6.0, 26.0)
		u.rect(x, y + 160.0, tw - 3.0, 40.0, UiKit.DARK.lerp(picker, o))
		u.title(x + 12.0, y + 166.0, tr(data.display_name).to_upper(), 26.0, UiKit.INK, -1, tw - 30.0)
		if o > 0.01:
			u.rect(x - 4.0, y - 6.0 * o, tw + 5.0, 6.0 * o, picker)
		var tx := x + 6.0
		if sp == m.choice.p1 and (m.sel_phase != "p1" or m.me_ready):
			tx = _token(tx, y + 8.0, "1P", UiKit.RED)
		if not m.online and sp == m.choice.p2 and m.sel_phase == "setup":
			_token(tx, y + 8.0, "CPU", UiKit.GREY)
		if m.online and sp == m.rival_choice_id:
			_token(tx, y + 8.0, "2P", UiKit.BLUE)


func _token(x: float, y: float, label: String, col: Color) -> float:
	var w := u.width(label, 22.0, u.heavy) + 22.0
	u.slant(x, y, w, 34.0, col)
	u.text(x + 14.0, y + 5.0, label, 22.0, UiKit.INK, u.heavy)
	return x + w + 4.0


## The battle's options, in place of the wall once both are picked: the stage's picture
## with a line about it, and the options as tabs (stage, difficulty, edit moves, fight).
func _setup_bar(setup: float) -> void:
	var y := lerpf(-260.0, 150.0, UiKit.ease(setup))
	var st: String = m.choice.stage
	u.rect(70.0, y, 400.0, 200.0, UiKit.DARK)
	u.tex(_stage_picture(st), 82.0, y + 12.0, 376.0, 176.0)
	u.rect(70.0, y + 194.0, 400.0, 6.0, UiKit.RED)
	var items := m.setup_items()
	var host: bool = not m.online or (m.main.net != null and m.main.net.host)
	var x := 510.0
	var tw := (1850.0 - x - (items.size() - 1) * 20.0) / items.size()
	for i in items.size():
		var it: String = items[i]
		var o := on("tab" + it, i == m.setup_cursor and not (m.online and m.me_ready))
		var go := it in ["fight", "ready"]
		var col := UiKit.YELLOW if go else UiKit.RED
		if it == "ready" and m.me_ready:
			o = 1.0
		var bx := x + i * (tw + 20.0)
		u.slant(bx, y, tw, 200.0, UiKit.PANEL.lerp(col, o))
		zone("tab", i, bx, y, tw + 200.0 * UiKit.SLANT, 200.0)
		var ink := UiKit.DARK if go and o > 0.5 else UiKit.INK
		var label := ""
		var sub := ""
		match it:
			"stage":
				sub = tr("Stage") if host else tr("Stage (the host picks)")
				label = tr(Menu.STAGE_NAME[st])
			"diff":
				sub = tr("Difficulty")
				label = tr(Menu.DIFFICULTY_NAME[m.choice.diff])
			"build":
				sub = tr("Moves and ability")
				label = tr("Edit Pokémon")
			"fight":
				label = tr("Fight!")
			"ready":
				label = tr("Waiting for the rival") if m.me_ready else tr("Ready!")
		if sub != "":
			u.text_fit(u.edge(bx, y, 200.0, y + 44.0) + 24.0, y + 24.0, sub.to_upper(), tw - 70.0, 20.0, Color(ink, 0.7), u.bold)
		if go:
			# Fight / Ready: alone in its tab, centered both ways (the center follows the slant).
			var size := 72.0
			var cy := y + 100.0 - size * 0.62
			u.title(u.edge(bx, y, 200.0, y + 100.0) + tw * 0.5, cy, label.to_upper(), size, ink, 0, tw - 80.0)
		else:
			var ly := y + 64.0
			u.title(u.edge(bx, y, 200.0, ly + 50.0) + 20.0, ly, label.to_upper(), 46.0, ink, -1, tw - 80.0)
		if it == "stage":
			u.para(u.edge(bx, y, 200.0, y + 180.0) + 22.0, y + 128.0, tr(Menu.STAGE_TEXT[st]), tw - 90.0, 19.0, Color(ink, 0.75), u.body, 1.2, 3)
		if it in ["stage", "diff"] and (host or it == "diff") and o > 0.01:
			u.text(u.edge(bx, y, 200.0, y + 30.0) + tw - 30.0, y + 18.0, "^", 24.0, Color(ink, o), u.heavy, 1)
			u.text(u.edge(bx, y, 200.0, y + 190.0) + tw - 30.0, y + 160.0, "v", 24.0, Color(ink, o), u.heavy, 1)


## Each side's pick in a big card, Smash style: its color, the Pokémon in 3D spilling a
## little over the top, the name huge at the bottom, its ability and its four moves with
## their type symbol on the right. Online the rival's card says whether it is ready.
func _player_card(side: int) -> void:
	var left := side == 0
	var col := _side_color(side)
	var k := UiKit.ease((m.enter_t - 0.08 * side) / 0.4)
	var x := (70.0 if left else 990.0) + (1.0 - k) * (-900.0 if left else 900.0)
	var y := 400.0
	var w := 860.0
	var hgt := 600.0
	u.slant(x, y, w, hgt, col)
	u.slant(x + 16.0, y + 16.0, w - 32.0, hgt - 32.0, col.darkened(0.3))
	u.stripes(x + 30.0, y + 16.0, w - 60.0, hgt - 32.0, Color(1, 1, 1, 0.035), 44.0)
	var tag := "1P" if left else ("2P" if m.online else "CPU")
	if not left and m.online and m.rival_choice_id == "":
		u.title(u.edge(x, y, hgt, y + 90.0) + 30.0, y + 26.0, tag, 64.0, Color(UiKit.INK, 0.9))
		u.title(u.edge(x, y, hgt, y + 330.0) + 30.0, y + 250.0, tr("Choosing...").to_upper(), 80.0, Color(UiKit.INK, 0.6), -1, w - 120.0)
		return
	var sp: String = m.choice.p1 if left else m.choice.p2
	var data: Dictionary = Roster.POKEMON[sp]
	# The Pokémon, on the left half, a little over the card's top edge.
	u.tex(m.render("card%d" % side, sp, Vector2i(440, 520), 0.5 if left else -0.5), u.edge(x, y, hgt, y + 300.0) + 10.0, y - 60.0, 440.0, 520.0)
	var tag_x := u.edge(x, y, hgt, y + 92.0) + 20.0
	u.slant(tag_x, y + 22.0, u.width(tag, 56.0, u.heavy) + 44.0, 70.0, UiKit.DARK)
	u.title(tag_x + 22.0, y + 28.0, tag, 56.0, UiKit.INK)
	# Right half: ability and moves, each in its own strip, stepping along the diagonal.
	var rw := 300.0
	var lo := _loadout(side)
	var ab: Dictionary = Loadout.ability(sp, lo.ability)
	var ax := u.edge(x, y, hgt, y + 92.0) + 430.0
	u.text(ax, y + 40.0, tr("Ability").to_upper(), 18.0, Color(UiKit.INK, 0.6), u.bold)
	u.text_fit(ax, y + 62.0, tr(ab.display_name), rw, 30.0, UiKit.INK, u.heavy)
	for i in lo.moves.size():
		var d: Dictionary = Moves.DATA[lo.moves[i]]
		var my: float = y + 116.0 + i * 64.0
		var rx := u.edge(x, y, hgt, my + 54.0) + 430.0
		u.slant(rx - 12.0, my, rw + 12.0, 54.0, Color(0, 0, 0, 0.28))
		u.type_icon(d.type, rx + 4.0, my + 7.0, 40.0)
		u.text_fit(rx + 54.0, my + 12.0, tr(d.display_name), rw - 70.0, 28.0, UiKit.INK, u.bold)
	# Name and types at the bottom, across the card.
	var tx := u.edge(x, y, hgt, y + hgt - 164.0) + 30.0
	for t in data.types:
		tx = u.type_tag(tx, y + hgt - 196.0, t, 20.0)
	u.title(u.edge(x, y, hgt, y + hgt - 40.0) + 24.0, y + hgt - 150.0, tr(data.display_name).to_upper(), 110.0, UiKit.INK, -1, w - 110.0)
	if not left and m.online and m.rival_ready:
		u.slant(x + w - 240.0, y + 30.0, 190.0, 54.0, UiKit.YELLOW)
		u.title(x + w - 214.0, y + 36.0, tr("Ready").to_upper(), 38.0, UiKit.DARK, -1, 150.0)


func _loadout(side: int) -> Dictionary:
	var sp: String = m.choice.p1 if side == 0 else m.choice.p2
	if side == 0:
		return m.main.my_loadout(sp)
	if m.online and not m.rival_loadout.is_empty():
		return m.rival_loadout
	return Loadout.default_for(sp)


# ---------------------------------------------------------------- moves

const RX := 930.0                # the right column of the Moves screen
const RW := 920.0


func _moves() -> void:
	_header(tr("Moves"), UiKit.BLUE)
	var list := m.pokemon_list()
	var sp := m.edit_sp
	var picking := m.edit_phase == "pokemon"
	# Left: the Pokémon, a column of strips.
	for i in list.size():
		var s: String = list[i]
		var o := on("mv" + s, s == sp)
		var y := 150.0 + i * 84.0
		var lit := o if picking else o * 0.45
		u.slant(60.0 + 18.0 * o, y, 330.0, 74.0, UiKit.PANEL.lerp(UiKit.BLUE, lit))
		zone("mvp", i, 60.0, y, 330.0 + 74.0 * UiKit.SLANT, 74.0)
		if m.portraits.has(s):
			u.tex(m.portraits[s], 70.0 + 18.0 * o, y - 2.0, 76.0, 76.0)
		u.title(156.0 + 18.0 * o, y + 20.0, tr(Roster.POKEMON[s].display_name).to_upper(), 32.0, UiKit.INK, -1, 210.0)
	# Middle: the Pokémon and its sheet.
	var data: Dictionary = Roster.POKEMON[sp]
	u.slant(430.0, 150.0, 460.0, 840.0, UiKit.PANEL, UiKit.TALL)
	u.tex(m.render("moves", sp, Vector2i(400, 380), 0.45), 450.0, 190.0, 400.0, 380.0)
	u.title(460.0, 160.0, tr(data.display_name).to_upper(), 56.0, UiKit.INK, -1, 400.0)
	var tx := 466.0
	for t in data.types:
		tx = u.type_tag(tx, 230.0, t, 18.0)
	var ry := 596.0
	for r in MoveInfo.stat_rows(sp):
		u.text_fit(466.0, ry, r[0], 120.0, 22.0, UiKit.SOFT, u.bold)
		u.meter(596.0, ry + 4.0, 200.0, 16.0, r[1], UiKit.ORANGE if r[2] >= 0.0 else UiKit.YELLOW, 10)
		if r[2] >= 0.0:
			# Its held item's share, in another color: what it would have without it.
			u.meter(596.0, ry + 4.0, 200.0, 16.0, r[2], UiKit.YELLOW, 10)
		u.text(860.0, ry, r[3], 24.0, UiKit.INK, u.heavy, 1)
		ry += 36.0
	# What the stats do not say.
	var b := MoveInfo.body(sp)
	ry += 14.0
	u.text(466.0, ry, tr("Weight"), 22.0, UiKit.SOFT, u.bold)
	u.text(860.0, ry, "%.1f kg" % b.kg, 24.0, UiKit.INK, u.heavy, 1)
	u.text_fit(466.0, ry + 28.0, tr("Hits send it ×%.2f as far") % b.knockback, 394.0, 20.0, Color(UiKit.INK, 0.75), u.body)
	ry += 66.0
	u.text(466.0, ry, tr("Dodges"), 22.0, UiKit.SOFT, u.bold)
	u.diamonds(860.0 - b.dodges * 26.0 + 8.0, ry + 4.0, b.dodges, 18.0, UiKit.INK)
	if b.air != "":
		ry += 36.0
		u.text(466.0, ry, tr("In the air"), 22.0, UiKit.SOFT, u.bold)
		u.text(860.0, ry, tr("Flies") if b.air == "flies" else tr("Levitates"), 24.0, UiKit.INK, u.heavy, 1)
	# Right: its moves and ability, or the options for a slot, or a move's details.
	var lo := Loadout.saved(sp)
	if m.details and m.shown_move() != "":
		_details(m.shown_move())
	elif m.edit_phase == "list":
		_choices(lo)
	else:
		_slots(lo)
	_restore_button()
	var items: Array = []
	match m.edit_phase:
		"pokemon":
			items = [[Controls.glyph("jump"), tr("Edit")], [Controls.glyph("menu_back"), tr("Back")]]
		"slots":
			items = [[Controls.glyph("jump"), tr("Change")], [Controls.glyph("menu_info"), tr("Details")], [Controls.glyph("menu_back"), tr("Back")]]
		"list":
			items = [[Controls.glyph("jump"), tr("Choose")], [Controls.glyph("menu_info"), tr("Details")], [Controls.glyph("menu_back"), tr("Back")]]
	u.hints(items)


## Top right of the Moves screen: back to the defaults, every Pokémon's from the list of
## Pokémon, the one being edited from its slots. Dimmed when there is nothing to restore.
func _restore_button() -> void:
	var all: bool = m.restore_all()
	var changed: bool = not (m.pokemon_list().all(Loadout.is_default) if all else Loadout.is_default(m.edit_sp))
	var w := 560.0
	var hgt := 84.0
	var x := RX + RW - w - hgt * UiKit.SLANT
	var y := 34.0
	var o := on("restore", changed)
	u.slant(x, y, w, hgt, UiKit.DARK.lerp(UiKit.PANEL_HI, o))
	u.slant(x, y, 12.0, hgt, Color(UiKit.ORANGE, 0.35 + 0.65 * o))
	zone("restore", 0, x, y, w + hgt * UiKit.SLANT, hgt)
	var ink := Color(UiKit.INK, 0.4 + 0.6 * o)
	var g := Controls.glyph("menu_extra")
	var gw := maxf(u.width(g, 22.0, u.heavy) + 18.0, 36.0)
	u.rect(x + 40.0, y + 24.0, gw, 34.0, UiKit.PANEL if o > 0.5 else UiKit.DARK)
	u.text(x + 40.0 + gw * 0.5, y + 28.0, g, 22.0, ink, u.heavy, 0)
	u.text_fit(x + 60.0 + gw, y + 12.0, tr("Restore defaults").to_upper(), w - gw - 110.0, 28.0, ink, u.heavy)
	var whose := tr("Every Pokémon") if all else tr(Roster.POKEMON[m.edit_sp].display_name)
	u.text_fit(x + 60.0 + gw, y + 48.0, whose, w - gw - 110.0, 20.0, Color(ink, ink.a * 0.7), u.bold)


func _slots(lo: Dictionary) -> void:
	for i in 5:
		var o := on("slot%d" % i, m.edit_phase != "pokemon" and i == m.edit_slot)
		var y := 150.0 + i * 150.0
		var x := RX + 18.0 * o
		zone("slot", i, RX, y, RW + 240.0 * UiKit.TALL, 132.0 if i < 4 else 240.0)
		if i < 4:
			var id: String = lo.moves[i]
			var d: Dictionary = Moves.DATA[id]
			var tc: Color = Roster.TYPE_COLOR.get(d.type, UiKit.GREY)
			u.slant(x, y, RW, 132.0, UiKit.PANEL.lerp(tc.darkened(0.2), o))
			u.slant(x, y, 16.0, 132.0, tc)
			u.type_icon(d.type, x + 40.0, y + 22.0, 64.0)
			u.title(x + 124.0, y + 18.0, tr(d.display_name).to_upper(), 46.0, UiKit.INK, -1, RW - 340.0)
			u.text_fit(x + 128.0, y + 82.0, ", ".join(MoveInfo.facts(id).slice(0, 3)), RW - 340.0, 22.0, Color(UiKit.INK, 0.75), u.body)
			# Right edge: power and cooldown, big figures.
			var pw: String = "%d" % d.power if d.get("power", 0) > 0 else "-"
			u.text(x + RW - 180.0, y + 22.0, pw, 46.0, UiKit.INK, u.heavy, 1)
			u.text(x + RW - 180.0, y + 78.0, tr("Power"), 18.0, Color(UiKit.INK, 0.6), u.bold, 1)
			u.text(x + RW - 50.0, y + 22.0, "%.1f" % Moves.cooldown(id), 46.0, UiKit.INK, u.heavy, 1)
			u.text(x + RW - 50.0, y + 78.0, tr("Cooldown"), 18.0, Color(UiKit.INK, 0.6), u.bold, 1)
		else:
			var ab: Dictionary = Loadout.ability(m.edit_sp, lo.ability)
			u.slant(x, y, RW, 240.0, UiKit.PANEL.lerp(UiKit.BLUE.darkened(0.2), o), UiKit.TALL)
			u.slant(x, y, 16.0, 240.0, UiKit.BLUE, UiKit.TALL)
			u.text(x + 46.0, y + 22.0, tr("Ability").to_upper(), 20.0, Color(UiKit.INK, 0.6), u.bold)
			u.title(x + 44.0, y + 50.0, tr(ab.display_name).to_upper(), 46.0, UiKit.INK, -1, RW - 100.0)
			u.para(x + 48.0, y + 118.0, tr(ab.text), RW - 110.0, 24.0, Color(UiKit.INK, 0.85), u.body, 1.25, 4)


## The options for a slot: a scrolling list, the equipped ones dimmed, and what the
## highlighted one does under it.
func _choices(lo: Dictionary) -> void:
	var options := m.edit_options()
	u.slant(RX, 150.0, RW, 840.0, UiKit.PANEL, UiKit.TALL)
	var head := (tr("Move %d") % (m.edit_slot + 1)) if m.edit_slot < 4 else tr("Ability")
	u.text(RX + 50.0, 166.0, head.to_upper(), 22.0, UiKit.SOFT, u.bold)
	if options.size() > Menu.EDIT_ROWS:
		u.text(RX + RW - 40.0, 166.0, "%d / %d" % [m.edit_cursor + 1, options.size()], 22.0, UiKit.SOFT, u.bold, 1)
	for k in range(m.edit_top, mini(m.edit_top + Menu.EDIT_ROWS, options.size())):
		var id: String = options[k]
		var y := 204.0 + (k - m.edit_top) * 72.0
		var sel := k == m.edit_cursor
		zone("opt", k, RX + 30.0, y, RW - 70.0 + 62.0 * UiKit.SLANT, 62.0)
		if m.edit_slot < 4:
			var d: Dictionary = Moves.DATA[id]
			var tc: Color = Roster.TYPE_COLOR.get(d.type, UiKit.GREY)
			var equipped: bool = id in lo.moves
			u.slant(RX + 30.0, y, RW - 70.0, 62.0, tc.darkened(0.15) if sel else UiKit.PANEL_HI)
			u.type_icon(d.type, RX + 46.0, y + 9.0, 44.0, 1.0 if not equipped or sel else 0.45)
			var ink := UiKit.INK if (sel or not equipped) else Color(UiKit.INK, 0.4)
			u.text_fit(RX + 104.0, y + 14.0, tr(d.display_name), RW - 380.0, 30.0, ink, u.heavy)
			if equipped and not sel:
				u.text(RX + RW - 160.0, y + 20.0, tr("Equipped"), 20.0, UiKit.SOFT, u.bold, 1)
			var pw: String = "%d" % d.power if d.get("power", 0) > 0 else "-"
			u.text(RX + RW - 60.0, y + 14.0, pw, 30.0, ink, u.heavy, 1)
		else:
			var ab: Dictionary = Loadout.ability(m.edit_sp, id)
			u.slant(RX + 30.0, y, RW - 70.0, 62.0, UiKit.BLUE if sel else UiKit.PANEL_HI)
			u.text_fit(RX + 60.0, y + 14.0, tr(ab.display_name), RW - 140.0, 30.0, UiKit.INK, u.heavy)
	var shown: String = options[m.edit_cursor] if not options.is_empty() else ""
	if shown != "":
		var text := tr(Moves.DATA[shown].desc) if m.edit_slot < 4 else tr(Loadout.ability(m.edit_sp, shown).text)
		u.para(RX + 50.0, 204.0 + Menu.EDIT_ROWS * 72.0 + 18.0, text, RW - 110.0, 24.0, UiKit.INK, u.body, 1.25, 3)


## A move's details: its games' numbers and ours, each as a meter in its type's color with
## the exact figure, then what it does and how to face it.
func _details(id: String) -> void:
	var d: Dictionary = Moves.DATA[id]
	var tc: Color = Roster.TYPE_COLOR.get(d.type, UiKit.GREY)
	u.slant(RX, 150.0, RW, 840.0, UiKit.PANEL, UiKit.TALL)
	var hx := u.edge(RX, 150.0, 840.0, 254.0, UiKit.TALL) + 16.0
	u.slant(hx, 166.0, RW - 60.0, 104.0, tc.darkened(0.15))
	u.type_icon(d.type, u.edge(hx, 166.0, 104.0, 226.0) + 26.0, 182.0, 72.0)
	u.title(u.edge(hx, 166.0, 104.0, 230.0) + 116.0, 178.0, tr(d.display_name).to_upper(), 54.0, UiKit.INK, -1, RW - 260.0)
	u.text_fit(u.edge(hx, 166.0, 104.0, 250.0) + 120.0, 236.0, ", ".join(MoveInfo.facts(id).slice(0, 2)), RW - 260.0, 20.0, Color(UiKit.INK, 0.85), u.bold)
	var y := 296.0
	for r in MoveInfo.rows(id):
		u.text_fit(RX + 50.0, y, r[0], 230.0, 24.0, UiKit.SOFT, u.bold)
		if r[1] >= 0.0:
			u.meter(RX + 300.0, y + 5.0, 360.0, 18.0, r[1], tc, 12)
		u.text_fit(RX + RW - 50.0, y, r[2], 190.0, 26.0, UiKit.INK, u.heavy, 1)
		y += 42.0
	var extra := MoveInfo.facts(id).slice(2)
	if not extra.is_empty():
		y = u.para(RX + 50.0, y + 8.0, ", ".join(extra), RW - 110.0, 22.0, UiKit.YELLOW, u.bold, 1.25, 2) + 6.0
	u.para(RX + 50.0, y + 4.0, tr(d.desc), RW - 110.0, 24.0, UiKit.INK, u.body, 1.3, 4)


# ---------------------------------------------------------------- options

func _options() -> void:
	var opts = m.main.options
	_header(tr("Options"), UiKit.GREY)
	var items: Array = opts.items()
	var y := 150.0
	var shown := 0
	for i in range(opts.top, items.size()):
		if shown >= opts.ROWS:
			break
		shown += 1
		var it: Dictionary = items[i]
		if it.kind == "header":
			u.title(84.0, y + 18.0, it.label.to_upper(), 34.0, UiKit.YELLOW)
			y += 66.0
			continue
		var o := on("opt" + it.id, i == opts.cursor)
		u.slant(70.0 + 16.0 * o, y, 1100.0, 60.0, UiKit.PANEL.lerp(UiKit.RED, o))
		u.text_fit(110.0 + 16.0 * o, y + 14.0, it.label, 560.0, 28.0, UiKit.INK, u.bold)
		var value: String = it.value
		if opts.waiting == it.id:
			value = tr("Press a key or button...")
		if it.kind == "slider" and opts.waiting != it.id:
			var v: float = float(value.trim_suffix("%")) / 100.0
			u.meter(720.0 + 16.0 * o, y + 22.0, 300.0, 16.0, v, UiKit.YELLOW if o < 0.5 else UiKit.INK, 10)
		u.text_fit(1150.0 + 16.0 * o, y + 14.0, value, 400.0 if it.kind != "slider" else 110.0, 28.0, UiKit.INK, u.heavy, 1)
		y += 68.0
	var cur: Dictionary = items[opts.cursor]
	u.slant(1260.0, 150.0, 600.0, 330.0, UiKit.PANEL, UiKit.TALL)
	u.slant(1260.0, 150.0, 14.0, 330.0, UiKit.RED, UiKit.TALL)
	u.para(1320.0, 186.0, cur.get("help", ""), 500.0, 26.0, UiKit.INK, u.bold, 1.3, 8)
	u.hints([[Controls.glyph("jump"), tr("Change")], [tr("< >"), tr("Adjust")], [Controls.glyph("menu_back"), tr("Back")]])


# ---------------------------------------------------------------- VS

func _vs() -> void:
	var pair: Array = m.vs_pair()
	var t := m.vs_time()
	var k := UiKit.ease(t / 0.4)
	u.full(UiKit.DARK)
	u.slant(lerpf(-1700.0, -560.0, k), 0.0, 1560.0, 1080.0, UiKit.RED, 0.25)
	u.slant(lerpf(2400.0, 980.0, k), 0.0, 1500.0, 1080.0, _side_color(1), 0.25)
	for i in 2:
		var sp: String = pair[i]
		var x := 470.0 if i == 0 else 1460.0
		var slide := (1.0 - k) * (-700.0 if i == 0 else 700.0)
		u.tex(m.render("vs%d" % i, sp, Vector2i(560, 600), 0.45 if i == 0 else -0.45), x - 280.0 + slide, 140.0, 560.0, 600.0)
		u.title(x + slide, 750.0, tr(Roster.POKEMON[sp].display_name).to_upper(), 110.0, UiKit.INK, 0, 760.0)
		var who := tr("You") if i == 0 else (tr("Rival") if m.online else tr("AI, %s") % tr(Menu.DIFFICULTY_NAME[m.choice.diff]).to_lower())
		u.text(x + slide, 880.0, who, 34.0, Color(UiKit.INK, 0.85), u.bold, 0)
	var vk := UiKit.ease((t - 0.25) / 0.3)
	u.title(980.0, 400.0 - 30.0 * (1.0 - vk), "VS", 220.0 * (0.6 + 0.4 * vk), Color(UiKit.YELLOW, vk), 0)


# ---------------------------------------------------------------- confirm

func _confirm() -> void:
	var c: Dictionary = m.confirm
	var k := UiKit.ease(c.get("t", 0.0) / 0.2)
	u.full(Color(0, 0, 0, 0.6 * k))
	# The whole screen is the question's: the mouse reaches nothing under it.
	zone("confirm", -1, 0.0, 0.0, 1920.0, 1080.0)
	var y := lerpf(1100.0, 380.0, k)
	u.slant(440.0, y, 1040.0, 320.0, UiKit.PANEL, UiKit.TALL)
	u.slant(440.0 + 306.0 * UiKit.TALL, y, 1040.0, 14.0, UiKit.RED, UiKit.TALL)
	u.para(500.0, y + 50.0, c.text, 920.0, 38.0, UiKit.INK, u.heavy, 1.25, 2)
	for i in 2:
		var sel: bool = int(c.on) == i
		var bx := 540.0 + i * 440.0
		u.slant(bx, y + 190.0, 360.0, 84.0, (UiKit.RED if i == 1 else UiKit.GREY) if sel else UiKit.PANEL_HI)
		zone("confirm", i, bx, y + 190.0, 360.0 + 84.0 * UiKit.SLANT, 84.0)
		u.title(bx + 40.0, y + 204.0, (tr("No") if i == 0 else tr("Yes")).to_upper(), 50.0, UiKit.INK)


# ---------------------------------------------------------------- profile

## Your profile in the main menu's top right corner: your trainer's head and shoulders,
## "Profile" and your name. Up from Online or Training gets to it.
func _profile_badge() -> void:
	var k := UiKit.ease((m.enter_t - 0.3) / 0.3)
	var x := lerpf(1980.0, 1220.0, k)
	var y := 30.0
	var w := 640.0
	var hgt := 92.0
	var o := on("mainprofile", m.cursor == 6)
	var col: Color = ITEM_COLOR.profile
	if o > 0.01:
		u.slant(x - 8.0 * o, y - 6.0 * o, w + 16.0 * o, hgt + 12.0 * o, Color(UiKit.INK, o))
	u.slant(x, y, w, hgt, UiKit.DARK.lerp(col, 0.35 + 0.65 * o))
	zone("main", 6, x, y, w + hgt * UiKit.SLANT, hgt)
	# Head and shoulders: the sprite's top half, enlarged.
	var tex := TrainerData.texture(m.main.options.trainer)
	u.tex_region(tex, u.edge(x, y, hgt, y + hgt) + 30.0, y + 2.0, 104.0, 88.0, Rect2(14, 4, 52, 44))
	var tx := u.edge(x, y, hgt, y + 40.0) + 160.0
	u.text(tx, y + 10.0, tr("Profile").to_upper(), 18.0, Color(UiKit.INK, 0.7), u.bold)
	u.title(u.edge(x, y, hgt, y + 80.0) + 160.0, y + 30.0, m.main.options.shown_name().to_upper(), 48.0, UiKit.INK, -1, w - 200.0)


## The profile screen: your trainer big on the left with your name; on the right the name
## to type and the trainers to pick from.
func _profile() -> void:
	var col: Color = ITEM_COLOR.profile
	_header(tr("Profile"), col)
	var opt: Settings = m.main.options
	var k := UiKit.ease(m.enter_t / 0.35)
	# Your card.
	var cx := lerpf(-700.0, 70.0, k)
	u.slant(cx, 150.0, 640.0, 760.0, col.darkened(0.35), UiKit.TALL)
	u.stripes(cx + 30.0, 150.0, 600.0, 760.0, Color(1, 1, 1, 0.035), 44.0)
	u.tex(TrainerData.texture(opt.trainer), cx + 60.0, 170.0, 560.0, 560.0)
	u.title(u.edge(cx, 150.0, 760.0, 860.0, UiKit.TALL) + 40.0, 760.0, opt.shown_name().to_upper(), 84.0, UiKit.INK, -1, 560.0)
	if opt.player_name != "":
		u.text(u.edge(cx, 150.0, 760.0, 880.0, UiKit.TALL) + 44.0, 860.0, tr(TrainerData.LIST[opt.trainer].name), 26.0, Color(UiKit.INK, 0.7), u.bold)
	# The name.
	var nx := 780.0
	var on_name := on("pfname", m.profile_cursor < 0)
	u.slant(nx, 150.0, 1070.0, 130.0, UiKit.PANEL.lerp(col, on_name))
	zone("pf", -1, nx, 150.0, 1070.0, 130.0)
	u.text(u.edge(nx, 150.0, 130.0, 170.0) + 30.0, 166.0, tr("Name").to_upper(), 20.0, Color(UiKit.INK, 0.7), u.bold)
	var shown: String = opt.player_name if opt.player_name != "" or m.name_edit else ""
	var ny := 196.0
	if shown == "" and not m.name_edit:
		u.title(u.edge(nx, 150.0, 130.0, ny + 60.0) + 30.0, ny, opt.shown_name().to_upper(), 56.0, Color(UiKit.INK, 0.45), -1, 700.0)
	else:
		u.title(u.edge(nx, 150.0, 130.0, ny + 60.0) + 30.0, ny, shown, 56.0, UiKit.INK, -1, 700.0)
	if m.name_edit:
		var cw := u.width(shown, 56.0, u.heavy)
		u.rect(u.edge(nx, 150.0, 130.0, ny + 60.0) + 40.0 + cw, ny + 58.0, 30.0, 7.0, Color(UiKit.YELLOW, 0.6 + 0.4 * sin(_t * TAU * 0.9)))
		u.text_fit(u.edge(nx, 150.0, 130.0, 260.0) + 860.0, 250.0, tr("Type with the keyboard (Enter ends) or use the keys below."), 1000.0, 18.0, Color(UiKit.INK, 0.8), u.bold, 1)
		_name_keyboard(col)
		u.hints([[Controls.glyph("jump"), tr("Press")], [Controls.glyph("menu_back"), tr("Delete")]])
		return
	# The trainers.
	var list := TrainerData.ids()
	var gx := 780.0
	var gy := 310.0
	var tw := 340.0
	var th := 190.0
	for i in list.size():
		var id: String = list[i]
		var x := gx + (i % Menu.PROFILE_COLUMNS) * (tw + 25.0)
		var y := gy + (i / Menu.PROFILE_COLUMNS) * (th + 15.0)
		var o := on("pf" + id, i == m.profile_cursor)
		var mine: bool = id == opt.trainer
		u.slant(x, y, tw, th, UiKit.PANEL.lerp(col, o))
		zone("pf", i, x, y, tw + th * UiKit.SLANT, th)
		if mine:
			u.slant(x, y + th - 8.0, tw, 8.0, UiKit.YELLOW)
			u.text(u.edge(x, y, th, y + 30.0) + 24.0, y + 14.0, tr("Yours").to_upper(), 20.0, UiKit.YELLOW, u.heavy)
		u.tex(TrainerData.texture(id), u.edge(x, y, th, y + th) + tw - 190.0, y - 4.0 - 6.0 * o, 190.0, 190.0)
		u.title(u.edge(x, y, th, y + th - 20.0) + 24.0, y + th - 66.0, tr(TrainerData.LIST[id].name).to_upper(), 40.0, UiKit.INK, -1, tw - 160.0)
	u.hints([[Controls.glyph("jump"), tr("Select")], [Controls.glyph("menu_back"), tr("Back")]])


# ---------------------------------------------------------------- mouse zones

func zone(kind: String, i: int, x: float, y: float, w: float, h: float) -> void:
	zones.append({"kind": kind, "i": i, "rect": Rect2(u.p(x, y), Vector2(w, h) * u.k)})


func zone_at(pos: Vector2) -> Dictionary:
	for k in range(zones.size() - 1, -1, -1):
		if zones[k].rect.has_point(pos):
			return zones[k]
	return {}


## The on-screen keyboard for the name, under it (in place of the trainers while editing).
func _name_keyboard(col: Color) -> void:
	var x0 := 780.0
	var y0 := 320.0
	var kw := 98.0
	var kh := 92.0
	var gap := 9.0
	var on_key: String = m.name_key_id()
	for row in 5:
		var keys: Array = Menu.NAME_KEYS[row]
		for c in keys.size():
			var key: String = keys[c]
			var w := kw if row < 4 else (kw + gap) * 2.5 - gap
			var x := x0 + c * (w + gap)
			var y := y0 + row * (kh + gap)
			var here: bool = m.name_key.y == row and (on_key == key)
			var o := on("nk%d_%d" % [row, c], here)
			u.slant(x, y, w, kh, UiKit.PANEL.lerp(col, o))
			# The wide keys of the last row stand for the columns they cover (Menu.name_key_id).
			zone("nkey", row * 10 + (int(ceilf(c * 2.5)) if row == 4 else c), x, y, w, kh)
			var label := key
			match key:
				"shift":
					label = "abc" if not m.name_lower else "ABC"
				"space":
					label = tr("Space")
				"del":
					label = "<-"
				"done":
					label = tr("Done")
				_:
					label = key.to_lower() if m.name_lower else key
			u.text_fit(x + w * 0.5 + 8.0, y + 24.0, label, w - 20.0, 38.0, UiKit.INK, u.heavy, 0)
