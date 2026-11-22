extends Node
## Unified Keyboard + Gamepad Input Manager for MoonRPG Engine.
##
## Features:
## - Full out-of-the-box ARPG gamepad bindings (Left Stick + D-Pad, ABXY, LB/RB/LT/RT, Right Stick Hotbar)
## - Automatic device & brand detection (keyboard / xbox / playstation / nintendo)
## - Dynamic button prompt labels (`get_prompt("interact")` -> `[E]` / `[↑]`, `get_prompt("attack_light")` -> `[J]` / `[X]` / `[□]`)
## - Controller rumble/vibration API with combat presets + global enable/scale
## - Runtime remapping, analog deadzone config, and JSON persistence (`user://moon_rpg_input.json`)

const BINDINGS_SAVE_PATH := "user://moon_rpg_input.json"

enum InputDevice { KEYBOARD, GAMEPAD }

var current_device: int = InputDevice.KEYBOARD
var active_joy_id: int = 0
var active_brand: String = "xbox" # "xbox" | "playstation" | "nintendo" | "generic"
var deadzone: float = 0.22
var rumble_enabled: bool = true
var rumble_scale: float = 1.0

## Per-seat stick profiles (deadzone / press & release thresholds with hysteresis).
var seat_profiles: Dictionary = {} # seat:int -> SeatInputProfile
## Ticks after a menu closes during which gameplay action presses are swallowed,
## so the confirm press that closed a menu never leaks out as an attack.
var menu_close_guard_ticks: int = 2
var _menu_closed_at_frame: int = -1000
var _last_ui_depth: int = 0

const RUMBLE_PRESETS := {
	"hit": [0.22, 0.08, 0.07],
	"crit": [0.45, 0.55, 0.14],
	"parry": [0.35, 0.75, 0.16],
	"hurt": [0.30, 0.65, 0.18],
	"ultimate": [0.60, 0.85, 0.25],
}

const KEYBOARD_PROMPTS := {
	"move_left": "A",
	"move_right": "D",
	"move_up": "W",
	"move_down": "S",
	"jump": "Space",
	"attack_light": "J",
	"attack_heavy": "U",
	"skill_ultimate": "O",
	"guard": "L",
	"dodge": "Shift",
	"interact": "E",
	"toggle_inventory": "I",
	"toggle_map": "M",
	"pause": "Esc",
	"hotbar_1": "1",
	"hotbar_2": "2",
	"hotbar_3": "3",
	"hotbar_4": "4",
}

const GAMEPAD_PROMPTS := {
	"xbox": {
		"jump": "A", "attack_light": "X", "attack_heavy": "Y", "dodge": "B",
		"guard": "LB", "skill_ultimate": "RB", "interact": "↑",
		"toggle_inventory": "View", "toggle_map": "L3", "pause": "Menu",
		"hotbar_1": "R←", "hotbar_2": "R↑", "hotbar_3": "R→", "hotbar_4": "R↓",
	},
	"playstation": {
		"jump": "✕", "attack_light": "□", "attack_heavy": "△", "dodge": "○",
		"guard": "L1", "skill_ultimate": "R1", "interact": "↑",
		"toggle_inventory": "Share", "toggle_map": "L3", "pause": "Options",
		"hotbar_1": "R←", "hotbar_2": "R↑", "hotbar_3": "R→", "hotbar_4": "R↓",
	},
	"nintendo": {
		"jump": "B", "attack_light": "Y", "attack_heavy": "X", "dodge": "A",
		"guard": "L", "skill_ultimate": "R", "interact": "↑",
		"toggle_inventory": "-", "toggle_map": "L3", "pause": "+",
		"hotbar_1": "R←", "hotbar_2": "R↑", "hotbar_3": "R→", "hotbar_4": "R↓",
	},
	"steam_deck": {
		"jump": "A", "attack_light": "X", "attack_heavy": "Y", "dodge": "B",
		"guard": "L1", "skill_ultimate": "R1", "interact": "↑",
		"toggle_inventory": "View", "toggle_map": "L3", "pause": "Menu",
		"hotbar_1": "R←", "hotbar_2": "R↑", "hotbar_3": "R→", "hotbar_4": "R↓",
	},
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	install_default_gamepad_bindings()
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	var pads := Input.get_connected_joypads()
	if not pads.is_empty():
		active_joy_id = pads[0]
		active_brand = detect_brand(active_joy_id)
	load_bindings()
	if get_tree() != null and not get_tree().node_added.is_connected(_on_tree_node_added):
		get_tree().node_added.connect(_on_tree_node_added)
	if UIStack != null and UIStack.has_signal("stack_changed"):
		UIStack.stack_changed.connect(_on_ui_stack_changed)


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
		_switch_device(InputDevice.GAMEPAD, event.device)
	elif event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > maxf(deadzone, 0.35):
		_switch_device(InputDevice.GAMEPAD, event.device)
	elif (event is InputEventKey and (event as InputEventKey).pressed) or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed):
		_switch_device(InputDevice.KEYBOARD, -1)


func _on_joy_connection_changed(device_id: int, connected: bool) -> void:
	if connected:
		active_joy_id = device_id
		active_brand = detect_brand(device_id)
	else:
		var pads := Input.get_connected_joypads()
		if pads.is_empty():
			_switch_device(InputDevice.KEYBOARD, -1)
		else:
			active_joy_id = pads[0]
			active_brand = detect_brand(active_joy_id)


func _switch_device(device: int, joy_id: int) -> void:
	var new_brand := detect_brand(joy_id) if device == InputDevice.GAMEPAD else "keyboard"
	if device == current_device and (device == InputDevice.KEYBOARD or new_brand == active_brand):
		return
	current_device = device
	if device == InputDevice.GAMEPAD:
		active_joy_id = joy_id
		active_brand = new_brand
	if EventBus:
		EventBus.input_device_changed.emit(get_device_name(), active_brand if is_using_gamepad() else "keyboard")


func is_using_gamepad() -> bool:
	return current_device == InputDevice.GAMEPAD


func get_device_name() -> String:
	return "gamepad" if current_device == InputDevice.GAMEPAD else "keyboard"


func detect_brand(joy_id: int) -> String:
	var jname := Input.get_joy_name(joy_id).to_lower()
	if "steam" in jname or "valve" in jname or "neptune" in jname:
		return "steam_deck"
	if "dualshock" in jname or "dualsense" in jname or "playstation" in jname or "ps4" in jname or "ps5" in jname or "sony" in jname:
		return "playstation"
	if "nintendo" in jname or "switch" in jname or "pro controller" in jname or "joy-con" in jname:
		return "nintendo"
	return "xbox"


## Returns visual glyph metadata `{ text, bg_color, fg_color, shape, device, brand }`
## for crisp adaptive rendering across Xbox / PlayStation / Nintendo / Steam Deck / Keyboard.
func get_glyph_style(action_name: String) -> Dictionary:
	var tok := get_prompt(action_name, false)
	if not is_using_gamepad():
		return {
			"text": tok, "bg_color": Color(0.18, 0.20, 0.26), "fg_color": Color(0.95, 0.96, 1.0),
			"shape": "keycap", "device": "keyboard", "brand": "keyboard",
		}
	var bg := Color(0.22, 0.26, 0.34)
	var fg := Color.WHITE
	var shape := "pill" if tok.length() >= 2 else "circle"
	match active_brand:
		"xbox":
			if tok == "A": bg = Color(0.18, 0.68, 0.28)
			elif tok == "B": bg = Color(0.84, 0.22, 0.24)
			elif tok == "X": bg = Color(0.18, 0.48, 0.88)
			elif tok == "Y": bg = Color(0.88, 0.72, 0.14)
		"playstation":
			bg = Color(0.14, 0.16, 0.24)
			if tok == "✕": fg = Color(0.45, 0.74, 1.0)
			elif tok == "○": fg = Color(1.0, 0.42, 0.45)
			elif tok == "□": fg = Color(0.98, 0.56, 0.86)
			elif tok == "△": fg = Color(0.36, 0.92, 0.68)
		"nintendo":
			bg = Color(0.18, 0.20, 0.24)
			if tok == "A" or tok == "B": bg = Color(0.78, 0.22, 0.26)
			elif tok == "X" or tok == "Y": bg = Color(0.22, 0.46, 0.82)
		"steam_deck":
			bg = Color(0.12, 0.16, 0.22)
			fg = Color(0.45, 0.88, 1.0)
	return {
		"text": tok, "bg_color": bg, "fg_color": fg,
		"shape": shape, "device": "gamepad", "brand": active_brand,
	}


func get_connected_gamepads() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in Input.get_connected_joypads():
		out.append({
			"id": id,
			"name": Input.get_joy_name(id),
			"brand": detect_brand(id),
		})
	return out


## Returns a formatted prompt string for the given action matching the currently active device.
func get_prompt(action_name: String, bracketed: bool = true) -> String:
	var token := ""
	if is_using_gamepad():
		var table: Dictionary = GAMEPAD_PROMPTS.get(active_brand, GAMEPAD_PROMPTS["xbox"])
		token = str(table.get(action_name, KEYBOARD_PROMPTS.get(action_name, action_name)))
	else:
		token = str(KEYBOARD_PROMPTS.get(action_name, action_name))
	return "[%s]" % token if bracketed else token


func set_active_brand_override(brand: String) -> void:
	if GAMEPAD_PROMPTS.has(brand):
		active_brand = brand
		current_device = InputDevice.GAMEPAD
		if EventBus:
			EventBus.input_device_changed.emit("gamepad", active_brand)


func set_deadzone(value: float) -> void:
	deadzone = clampf(value, 0.05, 0.6)
	for action_name in ["move_left", "move_right", "move_up", "move_down", "hotbar_1", "hotbar_2", "hotbar_3", "hotbar_4"]:
		if InputMap.has_action(action_name):
			InputMap.action_set_deadzone(action_name, deadzone)


func get_seat_profile(seat: int) -> SeatInputProfile:
	if not seat_profiles.has(seat):
		var prof := SeatInputProfile.new(seat)
		prof.configure(deadzone, maxf(0.5, deadzone + 0.2), maxf(deadzone, 0.3))
		seat_profiles[seat] = prof
	return seat_profiles[seat]


# =============================================================================
# Menu / Action input separation
# =============================================================================

func _on_ui_stack_changed(depth: int) -> void:
	if depth < _last_ui_depth:
		notify_menu_closed()
	_last_ui_depth = depth


## Marks "a menu just closed"; gameplay should call `is_action_input_blocked()` before buffering.
func notify_menu_closed(frame: int = -1) -> void:
	_menu_closed_at_frame = frame if frame >= 0 else Engine.get_physics_frames()


## True while a menu is open or within `menu_close_guard_ticks` after one closed.
func is_action_input_blocked(frame: int = -1) -> bool:
	var f := frame if frame >= 0 else Engine.get_physics_frames()
	if UIStack != null and UIStack.has_method("is_empty") and not UIStack.is_empty():
		return true
	var since := f - _menu_closed_at_frame
	return since >= 0 and since <= menu_close_guard_ticks


## Consumes the menu-close edge (returns true once if the guard window is active).
func consume_menu_close_edge(frame: int = -1) -> bool:
	var blocked := is_action_input_blocked(frame) and _menu_closed_at_frame > -1000
	if blocked:
		_menu_closed_at_frame = -1000
	return blocked


## Unified 2D movement vector across WASD, Arrow Keys, Left Stick, and D-Pad.
func get_move_vector() -> Vector2:
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")


# =============================================================================
# Rumble / Haptic Vibration
# =============================================================================

func rumble(weak: float = 0.25, strong: float = 0.45, duration: float = 0.12) -> void:
	if not rumble_enabled or not is_using_gamepad():
		return
	if Input.get_connected_joypads().is_empty():
		return
	var acc := _accessibility_rumble_scale()
	var w := clampf(weak * rumble_scale * acc, 0.0, 1.0)
	var s := clampf(strong * rumble_scale * acc, 0.0, 1.0)
	Input.start_joy_vibration(active_joy_id, w, s, maxf(0.02, duration))


func _accessibility_rumble_scale() -> float:
	var api := get_node_or_null("/root/MoonRPG")
	if api != null and "accessibility" in api and api.accessibility != null:
		return float(api.accessibility.get_scale("rumble"))
	return 1.0


func rumble_preset(preset_name: String) -> void:
	if not RUMBLE_PRESETS.has(preset_name):
		return
	var p: Array = RUMBLE_PRESETS[preset_name]
	rumble(float(p[0]), float(p[1]), float(p[2]))


func stop_rumble() -> void:
	for id in Input.get_connected_joypads():
		Input.stop_joy_vibration(id)


# =============================================================================
# Default Gamepad Bindings & Runtime Remapping
# =============================================================================

func install_default_gamepad_bindings() -> void:
	_ensure_action("pause")
	_add_key_if_missing("pause", KEY_ESCAPE)

	# Movement: Left Stick + D-Pad
	_add_axis_if_missing("move_left", JOY_AXIS_LEFT_X, -1.0)
	_add_button_if_missing("move_left", JOY_BUTTON_DPAD_LEFT)
	_add_axis_if_missing("move_right", JOY_AXIS_LEFT_X, 1.0)
	_add_button_if_missing("move_right", JOY_BUTTON_DPAD_RIGHT)
	_add_axis_if_missing("move_up", JOY_AXIS_LEFT_Y, -1.0)
	_add_button_if_missing("move_up", JOY_BUTTON_DPAD_UP)
	_add_key_if_missing("move_up", KEY_W)
	_add_key_if_missing("move_up", KEY_UP)
	_add_axis_if_missing("move_down", JOY_AXIS_LEFT_Y, 1.0)
	_add_button_if_missing("move_down", JOY_BUTTON_DPAD_DOWN)

	# Core ARPG Actions
	_add_button_if_missing("jump", JOY_BUTTON_A)
	_add_button_if_missing("attack_light", JOY_BUTTON_X)
	_add_button_if_missing("attack_heavy", JOY_BUTTON_Y)
	_add_button_if_missing("dodge", JOY_BUTTON_B)
	_add_axis_if_missing("dodge", JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_add_button_if_missing("guard", JOY_BUTTON_LEFT_SHOULDER)
	_add_axis_if_missing("guard", JOY_AXIS_TRIGGER_LEFT, 1.0)
	_add_button_if_missing("skill_ultimate", JOY_BUTTON_RIGHT_SHOULDER)

	# Interaction & Menus
	_add_button_if_missing("interact", JOY_BUTTON_DPAD_UP)
	_add_button_if_missing("toggle_inventory", JOY_BUTTON_BACK)
	_add_button_if_missing("toggle_map", JOY_BUTTON_LEFT_STICK)
	_add_button_if_missing("pause", JOY_BUTTON_START)

	# Quick-Use Hotbar 1-4 on Right Stick 4 directions
	_add_axis_if_missing("hotbar_1", JOY_AXIS_RIGHT_X, -1.0)
	_add_axis_if_missing("hotbar_2", JOY_AXIS_RIGHT_Y, -1.0)
	_add_axis_if_missing("hotbar_3", JOY_AXIS_RIGHT_X, 1.0)
	_add_axis_if_missing("hotbar_4", JOY_AXIS_RIGHT_Y, 1.0)

	# Standard UI navigation bindings for DialogueBox, Pause Menu & InventoryPanel
	_add_button_if_missing("ui_accept", JOY_BUTTON_A)
	_add_button_if_missing("ui_cancel", JOY_BUTTON_B)
	_add_button_if_missing("ui_up", JOY_BUTTON_DPAD_UP)
	_add_button_if_missing("ui_down", JOY_BUTTON_DPAD_DOWN)
	_add_button_if_missing("ui_left", JOY_BUTTON_DPAD_LEFT)
	_add_button_if_missing("ui_right", JOY_BUTTON_DPAD_RIGHT)
	_add_axis_if_missing("ui_up", JOY_AXIS_LEFT_Y, -1.0)
	_add_axis_if_missing("ui_down", JOY_AXIS_LEFT_Y, 1.0)
	_add_axis_if_missing("ui_left", JOY_AXIS_LEFT_X, -1.0)
	_add_axis_if_missing("ui_right", JOY_AXIS_LEFT_X, 1.0)

	set_deadzone(deadzone)


func rebind_action(action_name: String, new_event: InputEvent, replace_same_device_only: bool = true) -> bool:
	if not InputMap.has_action(action_name) or new_event == null:
		return false
	var is_new_joy := (new_event is InputEventJoypadButton) or (new_event is InputEventJoypadMotion)
	if replace_same_device_only:
		for ev in InputMap.action_get_events(action_name):
			var is_ev_joy := (ev is InputEventJoypadButton) or (ev is InputEventJoypadMotion)
			if is_ev_joy == is_new_joy:
				InputMap.action_erase_event(action_name, ev)
	else:
		InputMap.action_erase_events(action_name)
	InputMap.action_add_event(action_name, new_event)
	return true


func reset_default_bindings() -> void:
	for action_name in KEYBOARD_PROMPTS.keys():
		if not InputMap.has_action(action_name):
			continue
		for ev in InputMap.action_get_events(action_name):
			if (ev is InputEventJoypadButton) or (ev is InputEventJoypadMotion):
				InputMap.action_erase_event(action_name, ev)
	install_default_gamepad_bindings()


func save_bindings(custom_path: String = "") -> bool:
	var path := custom_path if not custom_path.is_empty() else BINDINGS_SAVE_PATH
	var data := {
		"deadzone": deadzone,
		"rumble_enabled": rumble_enabled,
		"rumble_scale": rumble_scale,
		"actions": {},
	}
	for action_name in KEYBOARD_PROMPTS.keys():
		if not InputMap.has_action(action_name):
			continue
		var serialized: Array = []
		for ev in InputMap.action_get_events(action_name):
			if ev is InputEventJoypadButton:
				serialized.append({"type": "joy_btn", "button": (ev as InputEventJoypadButton).button_index})
			elif ev is InputEventJoypadMotion:
				serialized.append({"type": "joy_axis", "axis": (ev as InputEventJoypadMotion).axis, "val": (ev as InputEventJoypadMotion).axis_value})
		data["actions"][action_name] = serialized
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return true


func load_bindings(custom_path: String = "") -> bool:
	var path := custom_path if not custom_path.is_empty() else BINDINGS_SAVE_PATH
	if not FileAccess.file_exists(path):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	set_deadzone(float(parsed.get("deadzone", deadzone)))
	rumble_enabled = bool(parsed.get("rumble_enabled", true))
	rumble_scale = clampf(float(parsed.get("rumble_scale", 1.0)), 0.0, 1.0)
	var actions: Dictionary = parsed.get("actions", {})
	for action_name in actions.keys():
		if not InputMap.has_action(str(action_name)):
			continue
		for ev in InputMap.action_get_events(str(action_name)):
			if (ev is InputEventJoypadButton) or (ev is InputEventJoypadMotion):
				InputMap.action_erase_event(str(action_name), ev)
		for entry in actions[action_name]:
			var t := str(entry.get("type", ""))
			if t == "joy_btn":
				_add_button_if_missing(str(action_name), int(entry.get("button", 0)))
			elif t == "joy_axis":
				_add_axis_if_missing(str(action_name), int(entry.get("axis", 0)), float(entry.get("val", 1.0)))
	return true


func _ensure_action(action_name: String) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name, deadzone)


func _add_key_if_missing(action_name: String, keycode: Key) -> void:
	_ensure_action(action_name)
	for ev in InputMap.action_get_events(action_name):
		if ev is InputEventKey and (ev as InputEventKey).keycode == keycode:
			return
	var k := InputEventKey.new()
	k.keycode = keycode
	InputMap.action_add_event(action_name, k)


func _add_button_if_missing(action_name: String, btn: JoyButton) -> void:
	_ensure_action(action_name)
	for ev in InputMap.action_get_events(action_name):
		if ev is InputEventJoypadButton and (ev as InputEventJoypadButton).button_index == btn:
			return
	var jb := InputEventJoypadButton.new()
	jb.button_index = btn
	InputMap.action_add_event(action_name, jb)


func _add_axis_if_missing(action_name: String, axis: JoyAxis, axis_val: float) -> void:
	_ensure_action(action_name)
	for ev in InputMap.action_get_events(action_name):
		if ev is InputEventJoypadMotion and (ev as InputEventJoypadMotion).axis == axis and signf((ev as InputEventJoypadMotion).axis_value) == signf(axis_val):
			return
	var jm := InputEventJoypadMotion.new()
	jm.axis = axis
	jm.axis_value = axis_val
	InputMap.action_add_event(action_name, jm)


# =============================================================================
# Engine-Layer Pointer Safety (Stretch-Safe Coords + World Click-Through Guard)
# =============================================================================

## Canonical stretch-safe, camera-safe mouse coordinate getter for any 2D/CanvasItem node.
## Always use this instead of raw `InputEventMouseButton.position`, which is in physical
## window pixels under `canvas_items` stretch mode!
func get_canvas_mouse_pos(node: CanvasItem) -> Vector2:
	if node == null or not is_instance_valid(node):
		return Vector2.ZERO
	return node.get_local_mouse_position()


## Recursively marks decorative non-interactive Controls (ColorRect, Label, TextureRect)
## as MOUSE_FILTER_IGNORE so they never swallow gameplay mouse clicks.
func enforce_click_through(root: Node) -> void:
	if root == null:
		return
	if (root is ColorRect or root is Label or root is TextureRect) and not (root is BaseButton):
		(root as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in root.get_children():
		enforce_click_through(child)


func _on_tree_node_added(node: Node) -> void:
	# Engine-layer invariant: decorative Controls placed directly under a Node2D world node
	# (e.g. ObjectiveBeacon2D rings, enemy HP bars, world labels) must NEVER swallow world clicks!
	if node is ColorRect or node is Label or node is TextureRect:
		var p := node.get_parent()
		if p is Node2D:
			(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
