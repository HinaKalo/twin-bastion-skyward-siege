class_name MinimapWidget
extends Control
## Room-Topology Minimap with Fog-of-War, Live Player Dot, Active Quest Pulsing Marker,
## and Compact Corner <-> Full Expanded Map (`M` / `Tab`) toggle.

var is_expanded: bool = false
var _pulse_time: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_layout()
	if EventBus:
		EventBus.room_changed.connect(func(_r, _s): queue_redraw())
		EventBus.room_discovered.connect(func(_r): queue_redraw())
		EventBus.quest_updated.connect(func(_q): queue_redraw())
		EventBus.tracked_quest_changed.connect(func(_q): queue_redraw())


func toggle_expanded() -> void:
	is_expanded = not is_expanded
	_apply_layout()
	queue_redraw()


func _apply_layout() -> void:
	if is_expanded:
		set_anchors_preset(Control.PRESET_CENTER)
		size = Vector2(300, 180)
		position = Vector2(90, 45)
	else:
		set_anchors_preset(Control.PRESET_TOP_RIGHT)
		size = Vector2(104, 56)
		position = Vector2(480 - 110, 6)


func _process(delta: float) -> void:
	_pulse_time += delta
	queue_redraw()


func _draw() -> void:
	var bg_col := Color(0.06, 0.08, 0.12, 0.90 if is_expanded else 0.72)
	draw_rect(Rect2(Vector2.ZERO, size), bg_col, true)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.65, 0.58, 0.42, 0.85), false, 1.5)

	if DataRegistry == null or WorldManager == null:
		return
	var rooms: Dictionary = DataRegistry.world_graph.get("rooms", {})
	if rooms.is_empty():
		return

	var cell_w := 68.0 if is_expanded else 34.0
	var cell_h := 32.0 if is_expanded else 18.0
	var origin := Vector2(30, 50) if is_expanded else Vector2(14, 18)

	var tracked_room := ""
	if QuestManager:
		var info := QuestManager.get_tracked_objective_info()
		tracked_room = str(info.get("room_id", ""))

	# Draw connections first
	for rid in rooms.keys():
		if not WorldManager.is_room_discovered(str(rid)) and str(rid) != tracked_room:
			continue
		var rmeta: Dictionary = rooms[rid]
		var gp: Array = rmeta.get("map_grid", [0, 0])
		var center_a := origin + Vector2(float(gp[0]) * (cell_w + 10.0) + cell_w * 0.5, float(gp[1]) * (cell_h + 10.0) + cell_h * 0.5)
		for conn in rmeta.get("connections", []):
			var to_id := str(conn.get("to_room", "")) if typeof(conn) == TYPE_DICTIONARY else str(conn)
			if not rooms.has(to_id):
				continue
			var gp_b: Array = rooms[to_id].get("map_grid", [0, 0])
			var center_b := origin + Vector2(float(gp_b[0]) * (cell_w + 10.0) + cell_w * 0.5, float(gp_b[1]) * (cell_h + 10.0) + cell_h * 0.5)
			draw_line(center_a, center_b, Color(0.75, 0.72, 0.62, 0.7), 2.0)

	# Draw room boxes
	var font: Font = ThemeManager.get_font() if ThemeManager else ThemeDB.fallback_font
	for rid in rooms.keys():
		var room_id := str(rid)
		var discovered := WorldManager.is_room_discovered(room_id)
		var is_target := room_id == tracked_room
		if not discovered and not is_target:
			continue
		var rmeta: Dictionary = rooms[room_id]
		var gp: Array = rmeta.get("map_grid", [0, 0])
		var rect := Rect2(
			origin + Vector2(float(gp[0]) * (cell_w + 10.0), float(gp[1]) * (cell_h + 10.0)),
			Vector2(cell_w, cell_h)
		)
		var is_current := room_id == WorldManager.current_room_id
		var fill := Color(0.26, 0.44, 0.34, 0.92) if is_current else (Color(0.20, 0.24, 0.32, 0.85) if discovered else Color(0.14, 0.14, 0.18, 0.55))
		draw_rect(rect, fill, true)
		var border := Color(1.0, 0.88, 0.35, 1.0) if is_current else Color(0.7, 0.75, 0.82, 0.8)
		draw_rect(rect, border, false, 1.2)

		if is_expanded:
			var rname := LocaleManager.tr_key(str(rmeta.get("name_key", room_id)), {}, room_id)
			draw_string(font, rect.position + Vector2(4, 13), rname, HORIZONTAL_ALIGNMENT_LEFT, cell_w - 6, 8, Color.WHITE)

		# Live player dot normalized inside current room bounds
		if is_current:
			var players := get_tree().get_nodes_in_group("player")
			if not players.is_empty() and players[0] is Node2D:
				var ppos := (players[0] as Node2D).global_position
				var bounds := WorldManager.get_current_room_bounds()
				var nx := clampf((ppos.x - bounds.position.x) / maxf(1.0, bounds.size.x), 0.08, 0.92)
				var ny := clampf((ppos.y - bounds.position.y) / maxf(1.0, bounds.size.y), 0.15, 0.85)
				var dot := rect.position + Vector2(rect.size.x * nx, rect.size.y * ny)
				draw_circle(dot, 2.8, Color(0.35, 0.95, 1.0))

		# Pulsing quest objective diamond
		if is_target:
			var pulse := 0.55 + 0.45 * sin(_pulse_time * 6.0)
			var qpos := rect.position + Vector2(rect.size.x - 8, 8)
			var r := 3.5 + pulse * 1.5
			var pts := PackedVector2Array([
				qpos + Vector2(0, -r), qpos + Vector2(r, 0),
				qpos + Vector2(0, r), qpos + Vector2(-r, 0),
			])
			draw_colored_polygon(pts, Color(1.0, 0.82, 0.18, 0.95))

	# Header / hint
	var title := "世界地图 [M关闭]   ◆ 任务目标   ● 当前位置" if is_expanded else "地图 [M]"
	draw_string(font, Vector2(6, 11), title, HORIZONTAL_ALIGNMENT_LEFT, size.x - 10, 8, Color(0.92, 0.88, 0.76))
