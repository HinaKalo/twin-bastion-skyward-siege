class_name InputGlyphBadge
extends Control
## Adaptive Pixel-Art Input Prompt Badge (Keyboard / Xbox / PlayStation / Switch / Steam Deck).
## Automatically listens to `EventBus.input_device_changed` and redraws with authentic
## brand shapes & colors (circle face buttons, pill bumpers, square keycaps) with zero external art.

@export var action_name: String = "jump":
	set(v):
		action_name = v
		queue_redraw()
@export var caption: String = "":
	set(v):
		caption = v
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(56, 18)
	var eb := get_node_or_null("/root/EventBus")
	if eb != null and eb.has_signal("input_device_changed") and not eb.input_device_changed.is_connected(_on_device_changed):
		eb.input_device_changed.connect(_on_device_changed)
	queue_redraw()


func _exit_tree() -> void:
	var eb := get_node_or_null("/root/EventBus")
	if eb != null and eb.has_signal("input_device_changed") and eb.input_device_changed.is_connected(_on_device_changed):
		eb.input_device_changed.disconnect(_on_device_changed)


func _on_device_changed(_dev: String, _brand: String) -> void:
	queue_redraw()


func _draw() -> void:
	var im := get_node_or_null("/root/InputManager")
	var tm := get_node_or_null("/root/ThemeManager")
	var style: Dictionary = im.get_glyph_style(action_name) if im != null else {
		"text": action_name, "bg_color": Color(0.2, 0.22, 0.28), "fg_color": Color.WHITE, "shape": "keycap"
	}
	var font: Font = tm.get_font() if tm != null else ThemeDB.fallback_font
	var tok := str(style.get("text", "?"))
	var bg: Color = style.get("bg_color", Color(0.2, 0.22, 0.28))
	var fg: Color = style.get("fg_color", Color.WHITE)
	var shape := str(style.get("shape", "keycap"))

	var bw := maxf(16.0, float(tok.length()) * 6.0 + 8.0)
	var bh := 15.0
	var cy := size.y * 0.5
	if shape == "circle":
		var r := 7.5
		draw_circle(Vector2(r + 1.0, cy), r, bg)
		draw_arc(Vector2(r + 1.0, cy), r, 0.0, TAU, 16, Color(1, 1, 1, 0.8), 1.1)
		draw_string(font, Vector2(1.0, cy + 3.0), tok, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 8, fg)
		bw = r * 2.0 + 2.0
	else:
		var rect := Rect2(Vector2(1.0, cy - bh * 0.5), Vector2(bw, bh))
		draw_rect(rect, bg)
		draw_rect(rect, Color(0.85, 0.90, 1.0, 0.85), false, 1.2)
		draw_string(font, Vector2(1.0, cy + 3.0), tok, HORIZONTAL_ALIGNMENT_CENTER, bw, 7, fg)

	if not caption.is_empty():
		draw_string(font, Vector2(bw + 4.0, cy + 3.0), caption, HORIZONTAL_ALIGNMENT_LEFT, maxf(20.0, size.x - bw - 4.0), 7, Color(0.92, 0.94, 1.0))
