class_name WorldMarker2D
extends Node2D
## Overhead pulsing quest/interactable highlight marker (! / ? / tracked beacon).

var symbol: String = ""
var marker_color: Color = Color(1.0, 0.85, 0.2)
var _time: float = 0.0
var _label: Label = null


func _ready() -> void:
	z_index = 45
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.position = Vector2(-12, -14)
	_label.custom_minimum_size = Vector2(24, 16)
	_label.add_theme_font_size_override("font_size", 11)
	_label.add_theme_constant_override("outline_size", 2)
	_label.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.08, 1.0))
	add_child(_label)
	set_marker("")


func set_marker(sym: String, col: Color = Color(1.0, 0.85, 0.2)) -> void:
	symbol = sym
	marker_color = col
	visible = not sym.is_empty()
	if _label != null:
		_label.text = sym
		_label.add_theme_color_override("font_color", col)
	queue_redraw()


func _process(delta: float) -> void:
	if not visible:
		return
	_time += delta
	position.y = -58.0 + sin(_time * 4.5) * 3.0
	queue_redraw()


func _draw() -> void:
	if not visible:
		return
	var pulse := 1.0 + 0.18 * sin(_time * 6.0)
	draw_circle(Vector2(0, -6), 7.5 * pulse, Color(marker_color.r, marker_color.g, marker_color.b, 0.22))
