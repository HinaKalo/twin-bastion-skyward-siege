class_name ObjectiveIndicator
extends Control
## Screen-edge directional arrow + label pointing toward the active quest objective
## (or the BFS next-hop portal when the objective is in another room).

var _pulse: float = 0.0
var _active: bool = false
var _screen_pos: Vector2 = Vector2.ZERO
var _dir: Vector2 = Vector2.RIGHT
var _label_text: String = ""
var _distance_m: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(delta: float) -> void:
	_pulse += delta
	_active = false
	if WorldManager == null:
		queue_redraw()
		return
	var resolved := WorldManager.resolve_tracked_objective_node()
	if resolved.is_empty():
		queue_redraw()
		return
	var target_node: Node2D = resolved.get("node", null)
	if not is_instance_valid(target_node):
		queue_redraw()
		return

	var cam := get_viewport().get_camera_2d()
	if cam == null:
		queue_redraw()
		return

	var vp_size := get_viewport_rect().size
	var cam_center := cam.get_screen_center_position()
	var rel := target_node.global_position + Vector2(0, -24) - cam_center
	var screen_pt := vp_size * 0.5 + rel

	# Only show screen-edge arrow if target is outside inner viewport margin
	var margin := 24.0
	var inner_rect := Rect2(Vector2(margin, margin), vp_size - Vector2(margin * 2.0, margin * 2.0))
	if inner_rect.has_point(screen_pt):
		queue_redraw()
		return

	_active = true
	_dir = rel.normalized()
	_screen_pos = Vector2(
		clampf(screen_pt.x, 18.0, vp_size.x - 18.0),
		clampf(screen_pt.y, 38.0, vp_size.y - 26.0)
	)
	_label_text = str(resolved.get("label", "任务目标"))
	_distance_m = int(round(rel.length() / 16.0))
	queue_redraw()


func _draw() -> void:
	if not _active:
		return
	var alpha := 0.78 + 0.22 * sin(_pulse * 6.0)
	var col := Color(1.0, 0.84, 0.22, alpha)
	var perp := Vector2(-_dir.y, _dir.x)
	var tip := _screen_pos + _dir * 8.0
	var left := _screen_pos - _dir * 5.0 + perp * 5.5
	var right := _screen_pos - _dir * 5.0 - perp * 5.5
	draw_colored_polygon(PackedVector2Array([tip, left, right]), col)

	var font: Font = ThemeManager.get_font() if ThemeManager else ThemeDB.fallback_font
	var caption := "%s (%dm)" % [_label_text, _distance_m]
	var text_pos := _screen_pos + Vector2(-84 if _dir.x > 0.0 else 10, 3)
	draw_string(font, text_pos + Vector2(1, 1), caption, HORIZONTAL_ALIGNMENT_LEFT, 92, 8, Color(0, 0, 0, 0.9))
	draw_string(font, text_pos, caption, HORIZONTAL_ALIGNMENT_LEFT, 92, 8, Color(1.0, 0.94, 0.72))
