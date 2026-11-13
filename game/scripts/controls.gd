class_name Controls
extends RefCounted
## Control map: gamepad (Xbox, with its PlayStation equivalents) and keyboard with
## mouse. Triggers are axes with a threshold: "just_pressed" fires once when crossing
## it, so holding them does not repeat the action.
##
##   Action          Xbox      PlayStation   Keyboard and mouse
##   move            L stick   L stick       WASD
##   camera          R stick   R stick       mouse
##   jump            A         Cross         Space
##   dodge           B         Circle        Shift
##   lock on         RS (R3)   R3            middle click or Tab   (Y/△ are free)
##   move 1          LB        L1            Q
##   move 2          RB        R1            E
##   move 3          LT        L2            right click
##   move 4          RT        R2            F
##   pause           Menu      Options       Esc
##   descend (flying) LS (L3)  L3            Ctrl
##   details (menus)  Y        Triangle      X
## The player can change any of the battle actions in Options (Settings): the glyphs are
## read from the map, so they always show what is really bound.

const ACTIONS := ["jump", "dodge", "lock_on", "mov1", "mov2", "mov3", "mov4", "pause",
	"move_left", "move_right", "move_up", "move_down", "cam_left", "cam_right", "cam_up", "cam_down",
	"menu_accept", "menu_back", "menu_info", "menu_extra", "debug", "reset", "descend"]

## What the HUD shows next to each action, per controller type (translated on display).
const GLYPHS := {
	"xbox": {"jump": "A", "dodge": "B", "lock_on": "RS", "mov1": "LB", "mov2": "RB", "mov3": "LT", "mov4": "RT", "menu_back": "B", "menu_info": "Y", "menu_extra": "X", "descend": "LS"},
	"playstation": {"jump": "✕", "dodge": "○", "lock_on": "R3", "mov1": "L1", "mov2": "R1", "mov3": "L2", "mov4": "R2", "menu_back": "○", "menu_info": "△", "menu_extra": "□", "descend": "L3"},
	"keyboard": {"jump": "Space", "dodge": "Shift", "lock_on": "Tab", "mov1": "Q", "mov2": "E", "mov3": "RMB", "mov4": "F", "menu_back": "Backspace", "menu_info": "X", "menu_extra": "R", "descend": "Ctrl"},
}
const PAD_NAME := {
	"xbox": {JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y", JOY_BUTTON_LEFT_SHOULDER: "LB",
		JOY_BUTTON_RIGHT_SHOULDER: "RB", JOY_BUTTON_LEFT_STICK: "LS", JOY_BUTTON_RIGHT_STICK: "RS", JOY_BUTTON_BACK: "View",
		JOY_BUTTON_START: "Menu", JOY_BUTTON_DPAD_UP: "D-pad up", JOY_BUTTON_DPAD_DOWN: "D-pad down",
		JOY_BUTTON_DPAD_LEFT: "D-pad left", JOY_BUTTON_DPAD_RIGHT: "D-pad right"},
	"playstation": {JOY_BUTTON_A: "✕", JOY_BUTTON_B: "○", JOY_BUTTON_X: "□", JOY_BUTTON_Y: "△", JOY_BUTTON_LEFT_SHOULDER: "L1",
		JOY_BUTTON_RIGHT_SHOULDER: "R1", JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3", JOY_BUTTON_BACK: "Share",
		JOY_BUTTON_START: "Options", JOY_BUTTON_DPAD_UP: "D-pad up", JOY_BUTTON_DPAD_DOWN: "D-pad down",
		JOY_BUTTON_DPAD_LEFT: "D-pad left", JOY_BUTTON_DPAD_RIGHT: "D-pad right"},
}

static var last_device := "keyboard"


static func configure() -> void:
	for a in ACTIONS:
		if InputMap.has_action(a):
			InputMap.erase_action(a)
		InputMap.add_action(a, 0.25)
	_button("jump", JOY_BUTTON_A)
	_button("dodge", JOY_BUTTON_B)
	_button("lock_on", JOY_BUTTON_RIGHT_STICK)
	_button("descend", JOY_BUTTON_LEFT_STICK)
	_button("mov1", JOY_BUTTON_LEFT_SHOULDER)
	_button("mov2", JOY_BUTTON_RIGHT_SHOULDER)
	_axis("mov3", JOY_AXIS_TRIGGER_LEFT, 1.0)
	_axis("mov4", JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_button("pause", JOY_BUTTON_START)
	_button("debug", JOY_BUTTON_BACK)
	_button("menu_accept", JOY_BUTTON_A)
	_button("menu_back", JOY_BUTTON_B)
	_button("menu_info", JOY_BUTTON_Y)
	_button("menu_extra", JOY_BUTTON_X)
	_axis("move_left", JOY_AXIS_LEFT_X, -1.0)
	_axis("move_right", JOY_AXIS_LEFT_X, 1.0)
	_axis("move_up", JOY_AXIS_LEFT_Y, -1.0)
	_axis("move_down", JOY_AXIS_LEFT_Y, 1.0)
	# D-pad: moves just like the stick and works in the menus.
	_button("move_left", JOY_BUTTON_DPAD_LEFT)
	_button("move_right", JOY_BUTTON_DPAD_RIGHT)
	_button("move_up", JOY_BUTTON_DPAD_UP)
	_button("move_down", JOY_BUTTON_DPAD_DOWN)
	_axis("cam_left", JOY_AXIS_RIGHT_X, -1.0)
	_axis("cam_right", JOY_AXIS_RIGHT_X, 1.0)
	_axis("cam_up", JOY_AXIS_RIGHT_Y, -1.0)
	_axis("cam_down", JOY_AXIS_RIGHT_Y, 1.0)
	for ac in [["jump", KEY_SPACE], ["dodge", KEY_SHIFT], ["lock_on", KEY_TAB], ["mov1", KEY_Q], ["mov2", KEY_E],
			["mov4", KEY_F], ["pause", KEY_ESCAPE], ["move_left", KEY_A], ["move_right", KEY_D], ["move_up", KEY_W],
			["move_down", KEY_S], ["move_left", KEY_LEFT], ["move_right", KEY_RIGHT], ["move_up", KEY_UP],
			["move_down", KEY_DOWN], ["menu_accept", KEY_ENTER], ["menu_accept", KEY_SPACE], ["menu_back", KEY_BACKSPACE], ["menu_info", KEY_X], ["menu_extra", KEY_R],
			["debug", KEY_F3], ["reset", KEY_R], ["descend", KEY_CTRL]]:
		var ev := InputEventKey.new()
		ev.physical_keycode = ac[1]
		InputMap.action_add_event(ac[0], ev)
	for ac in [["mov3", MOUSE_BUTTON_RIGHT], ["lock_on", MOUSE_BUTTON_MIDDLE]]:
		var mb := InputEventMouseButton.new()
		mb.button_index = ac[1]
		InputMap.action_add_event(ac[0], mb)


static func _button(action: String, b: JoyButton) -> void:
	var ev := InputEventJoypadButton.new()
	ev.button_index = b
	ev.device = -1
	InputMap.action_add_event(action, ev)


static func _axis(action: String, axis: JoyAxis, direction: float) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = direction
	ev.device = -1
	InputMap.action_add_event(action, ev)
	if axis in [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT]:
		InputMap.action_set_deadzone(action, 0.45)


## Remembers what was touched last to show the right glyphs.
static func notice(ev: InputEvent) -> void:
	if ev is InputEventJoypadButton or (ev is InputEventJoypadMotion and absf(ev.axis_value) > 0.5):
		var pad_name := Input.get_joy_name(ev.device).to_lower()
		last_device = "playstation" if (pad_name.contains("ps") or pad_name.contains("dualsense") or pad_name.contains("dualshock") or pad_name.contains("sony")) else "xbox"
	elif ev is InputEventKey or ev is InputEventMouseButton:
		last_device = "keyboard"


static func glyph(action: String) -> String:
	var pad := last_device != "keyboard"
	for ev in InputMap.action_get_events(action) if InputMap.has_action(action) else []:
		if is_pad(ev) == pad:
			return event_name(ev, last_device)
	return TranslationServer.translate(GLYPHS[last_device].get(action, action))


static func is_pad(ev: InputEvent) -> bool:
	return ev is InputEventJoypadButton or ev is InputEventJoypadMotion


## What a key, mouse button or pad button is called on screen.
static func event_name(ev: InputEvent, device := "xbox") -> String:
	if ev is InputEventKey:
		var code: Key = ev.physical_keycode if ev.physical_keycode != KEY_NONE else ev.keycode
		# The key's label in the player's layout (not available without a window).
		if DisplayServer.get_name() != "headless":
			code = DisplayServer.keyboard_get_keycode_from_physical(code)
		return OS.get_keycode_string(code)
	if ev is InputEventMouseButton:
		match ev.button_index:
			MOUSE_BUTTON_LEFT: return TranslationServer.translate("LMB")
			MOUSE_BUTTON_RIGHT: return TranslationServer.translate("RMB")
			MOUSE_BUTTON_MIDDLE: return TranslationServer.translate("Middle click")
		return TranslationServer.translate("Mouse %d") % ev.button_index
	var names: Dictionary = PAD_NAME["playstation" if device == "playstation" else "xbox"]
	if ev is InputEventJoypadButton:
		return TranslationServer.translate(names.get(ev.button_index, "Button %d" % ev.button_index))
	if ev is InputEventJoypadMotion:
		if ev.axis == JOY_AXIS_TRIGGER_LEFT:
			return "L2" if device == "playstation" else "LT"
		if ev.axis == JOY_AXIS_TRIGGER_RIGHT:
			return "R2" if device == "playstation" else "RT"
		return TranslationServer.translate("Stick %d%s") % [ev.axis, "+" if ev.axis_value > 0.0 else "-"]
	return "?"


## Puts "ev" on the action in place of what it had on that kind of device (keyboard and
## mouse, or gamepad); the other kind is kept.
static func rebind(action: String, ev: InputEvent) -> void:
	var pad := is_pad(ev)
	for old in InputMap.action_get_events(action):
		if is_pad(old) == pad:
			InputMap.action_erase_event(action, old)
	var clean: InputEvent
	if ev is InputEventKey:
		clean = InputEventKey.new()
		clean.physical_keycode = ev.physical_keycode if ev.physical_keycode != KEY_NONE else ev.keycode
	elif ev is InputEventMouseButton:
		clean = InputEventMouseButton.new()
		clean.button_index = ev.button_index
	elif ev is InputEventJoypadButton:
		clean = InputEventJoypadButton.new()
		clean.button_index = ev.button_index
		clean.device = -1
	elif ev is InputEventJoypadMotion:
		clean = InputEventJoypadMotion.new()
		clean.axis = ev.axis
		clean.axis_value = signf(ev.axis_value)
		clean.device = -1
	if clean:
		InputMap.action_add_event(action, clean)


## A binding as plain data (to save it) and back.
static func to_data(ev: InputEvent) -> Array:
	if ev is InputEventKey:
		return ["key", int(ev.physical_keycode)]
	if ev is InputEventMouseButton:
		return ["mouse", int(ev.button_index)]
	if ev is InputEventJoypadButton:
		return ["button", int(ev.button_index)]
	if ev is InputEventJoypadMotion:
		return ["axis", int(ev.axis), signf(ev.axis_value)]
	return []


static func from_data(d: Array) -> InputEvent:
	if d.size() < 2:
		return null
	match str(d[0]):
		"key":
			var e := InputEventKey.new()
			e.physical_keycode = int(d[1]) as Key
			return e
		"mouse":
			var e := InputEventMouseButton.new()
			e.button_index = int(d[1]) as MouseButton
			return e
		"button":
			var e := InputEventJoypadButton.new()
			e.button_index = int(d[1]) as JoyButton
			return e
		"axis":
			var e := InputEventJoypadMotion.new()
			e.axis = int(d[1]) as JoyAxis
			e.axis_value = float(d[2]) if d.size() > 2 else 1.0
			return e
	return null
