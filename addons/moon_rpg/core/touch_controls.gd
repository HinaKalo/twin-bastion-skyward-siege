class_name TouchControlsOverlay
extends CanvasLayer
## Zero-Coupling Mobile / Touchscreen Virtual Controls Overlay.
## Automatically appears when `DisplayServer.is_touchscreen_available()` is true
## (or when `force_visible = true` for desktop testing).
## Injects virtual button presses directly into Godot's `Input` actions (`move_left`,
## `move_right`, `move_up`, `move_down`, `jump`, `attack_light`, `interact`),
## so existing gameplay scripts need ZERO touch-specific code.

@export var force_visible: bool = false
@export var four_way_dpad: bool = true

var _held_actions: Dictionary = {} # action_name -> true
var _buttons: Array[Button] = []


func _ready() -> void:
	layer = 20
	visible = force_visible or DisplayServer.is_touchscreen_available()
	_build_controls()


func _exit_tree() -> void:
	release_all()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		release_all()


func release_all() -> void:
	for act in _held_actions.keys():
		if InputMap.has_action(act):
			Input.action_release(act)
	_held_actions.clear()


func _build_controls() -> void:
	# Left-side D-Pad
	_make_btn("◀", "move_left", Vector2(14, 214), Vector2(36, 36))
	_make_btn("▶", "move_right", Vector2(86, 214), Vector2(36, 36))
	if four_way_dpad:
		_make_btn("▲", "move_up", Vector2(50, 178), Vector2(36, 36))
		_make_btn("▼", "move_down", Vector2(50, 230), Vector2(36, 32))

	# Right-side Action Cluster
	_make_btn("攻", "attack_light", Vector2(376, 214), Vector2(42, 38))
	_make_btn("跳", "jump", Vector2(424, 214), Vector2(42, 38))
	_make_btn("交互", "interact", Vector2(400, 172), Vector2(48, 32))


func _make_btn(caption: String, action_name: String, pos: Vector2, sz: Vector2) -> void:
	var btn := Button.new()
	btn.text = caption
	btn.position = pos
	btn.custom_minimum_size = sz
	btn.size = sz
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 9)
	btn.modulate = Color(1.0, 1.0, 1.0, 0.72)
	btn.button_down.connect(func():
		if InputMap.has_action(action_name):
			Input.action_press(action_name)
			_held_actions[action_name] = true
	)
	btn.button_up.connect(func():
		if InputMap.has_action(action_name):
			Input.action_release(action_name)
		_held_actions.erase(action_name)
	)
	add_child(btn)
	_buttons.append(btn)
