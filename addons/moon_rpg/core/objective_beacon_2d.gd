class_name ObjectiveBeacon2D
extends Node2D
## Reusable Core Objective / Mandatory-Guide Highlight Beacon.
## Displays a pulsing ground highlight pad and a bouncing high-contrast badge
## above any target NPC, building, chest, or portal (JRPG / ARPG / SRPG / Sim).

@export var accent_color: Color = Color(1.0, 0.88, 0.18)
@export var pad_size: Vector2 = Vector2(68, 44)
@export var badge_y_offset: float = -74.0
@export var pulse_speed: float = 5.2

var _ring: ColorRect = null
var _badge: Label = null
var _t: float = 0.0


func _ready() -> void:
	z_index = 20
	_build()


func _build() -> void:
	if _ring != null:
		return
	_ring = ColorRect.new()
	_ring.position = -pad_size * 0.5
	_ring.size = pad_size
	_ring.color = Color(accent_color.r, accent_color.g, accent_color.b, 0.32)
	_ring.z_index = -15
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ring)

	_badge = Label.new()
	_badge.position = Vector2(-72, badge_y_offset)
	_badge.custom_minimum_size = Vector2(144, 18)
	_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.add_theme_font_size_override("font_size", 9)
	_badge.add_theme_color_override("font_color", Color(1.0, 0.94, 0.25))
	_badge.add_theme_constant_override("outline_size", 3)
	_badge.add_theme_color_override("font_outline_color", Color(0.18, 0.08, 0.0, 1.0))
	add_child(_badge)


func point_to(world_pos: Vector2, label_text: String, color: Color = accent_color) -> void:
	_build()
	accent_color = color
	global_position = world_pos
	_badge.text = label_text
	visible = true


func clear_target() -> void:
	visible = false


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	var pulse := 0.5 + 0.5 * sin(_t * pulse_speed)
	if _ring != null:
		_ring.color = Color(accent_color.r, accent_color.g, accent_color.b, 0.20 + pulse * 0.34)
	if _badge != null:
		_badge.position.y = badge_y_offset - pulse * 5.0
