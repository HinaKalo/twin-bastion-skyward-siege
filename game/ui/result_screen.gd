class_name ResultScreen
extends CanvasLayer
## End-of-stage screen: victory / defeat banner, animated stars (+ Hard crown), per-player stats with MVP,
## and Replay / Map / Next Stage buttons (keyboard + gamepad focusable).

signal replay_requested()
signal map_requested()
signal next_requested()

var _canvas: _Board
var _buttons: HBoxContainer
var _data: Dictionary = {}
var _t: float = 0.0


class _Board extends Control:
	var owner_screen: ResultScreen

	func _draw() -> void:
		owner_screen._draw_board(self)


func _ready() -> void:
	layer = 18
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.01, 0.02, 0.05, 0.78)
	add_child(dim)
	_canvas = _Board.new()
	_canvas.owner_screen = self
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)
	_buttons = HBoxContainer.new()
	_buttons.position = Vector2(90, 224)
	_buttons.custom_minimum_size = Vector2(300, 22)
	_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_buttons.add_theme_constant_override("separation", 8)
	add_child(_buttons)


func _process(delta: float) -> void:
	if visible:
		_t += delta
		_canvas.queue_redraw()


## data: won, stars, crown, difficulty, endless, wave, best_wave, new_record, elapsed, leaks, lives, max_lives,
##       stats {1:{...},2:{...}}, mvp, stage_name, has_next
func show_result(data: Dictionary) -> void:
	_data = data
	_t = 0.0
	visible = true
	for c in _buttons.get_children():
		c.queue_free()
	var focus: Array[Control] = []
	var won := bool(data.get("won", false))
	if won and bool(data.get("has_next", false)):
		var bn := UIKit.make_button("下一关", Color(0.25, 0.60, 0.35), Vector2(88, 20), 8)
		bn.pressed.connect(func(): next_requested.emit())
		_buttons.add_child(bn)
		focus.append(bn)
	var br := UIKit.make_button("再来一次", Color(0.60, 0.42, 0.22), Vector2(88, 20), 8)
	br.pressed.connect(func(): replay_requested.emit())
	_buttons.add_child(br)
	focus.append(br)
	var bm := UIKit.make_button("返回地图", Color(0.30, 0.42, 0.66), Vector2(88, 20), 8)
	bm.pressed.connect(func(): map_requested.emit())
	_buttons.add_child(bm)
	focus.append(bm)
	if ThemeManager:
		ThemeManager.apply_gamepad_focus_chain(focus, true, false)
	focus[0].call_deferred("grab_focus")


func _draw_board(c: Control) -> void:
	if _data.is_empty():
		return
	var won := bool(_data.get("won", false))
	var endless := bool(_data.get("endless", false))
	var appear := clampf(_t / 0.35, 0.0, 1.0)
	var r := Rect2(60, 18 + (1.0 - appear) * 12.0, 360, 200)
	UIKit.draw_panel(c, r, UIKit.GOLD if won else UIKit.BAD)

	# Banner
	var band := Rect2(r.position.x - 6, r.position.y + 6, r.size.x + 12, 24)
	c.draw_rect(band, (Color(0.40, 0.28, 0.06) if won else Color(0.36, 0.06, 0.08)))
	c.draw_rect(Rect2(band.position, Vector2(band.size.x, 1)), UIKit.GOLD if won else UIKit.BAD)
	c.draw_rect(Rect2(band.position + Vector2(0, band.size.y - 1), Vector2(band.size.x, 1)), UIKit.GOLD if won else UIKit.BAD)
	var title := "无尽挑战结束" if endless else ("双子大捷！" if won else "防线失守……")
	UIKit.draw_text(c, Vector2(band.position.x, band.position.y + 17), title, 13, Color(1.0, 0.95, 0.55) if won or endless else Color(1.0, 0.70, 0.66), HORIZONTAL_ALIGNMENT_CENTER, band.size.x)
	UIKit.draw_text(c, Vector2(r.position.x, r.position.y + 42), str(_data.get("stage_name", "")), 7, UIKit.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)

	# Stars or endless wave
	var cy := r.position.y + 60.0
	if endless:
		UIKit.draw_text(c, Vector2(r.position.x, cy + 4), "坚守到第 %d 波" % int(_data.get("wave", 0)), 11, UIKit.GOLD, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		var rec := "★ 新纪录！" if bool(_data.get("new_record", false)) else "最佳纪录：第 %d 波" % int(_data.get("best_wave", 0))
		UIKit.draw_text(c, Vector2(r.position.x, cy + 16), rec, 7, UIKit.GOOD if bool(_data.get("new_record", false)) else UIKit.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	else:
		var stars := int(_data.get("stars", 0))
		for i in range(3):
			var st := clampf((_t - 0.35 - i * 0.22) / 0.18, 0.0, 1.0)
			var sc := 2 if st >= 1.0 else (3 if st > 0.0 else 2)
			var name := "star" if (i < stars and st > 0.0) else "star_empty"
			PixelIcons.draw_icon(c, name, Vector2(240 + (i - 1) * 26, cy + 2), sc)
		if bool(_data.get("crown", false)) and _t > 1.1:
			PixelIcons.draw_icon(c, "crown", Vector2(240 + 50, cy - 2), 1)
	# Summary line
	var mins := int(float(_data.get("elapsed", 0.0)) / 60.0)
	var secs := int(float(_data.get("elapsed", 0.0))) % 60
	var diff_label := str(CoopTDDirector.DIFFICULTIES.get(str(_data.get("difficulty", "normal")), {"label": "普通"})["label"])
	var summary := "%s · 用时 %d:%02d · 城防 %d/%d · 漏怪 %d" % [diff_label, mins, secs, int(_data.get("lives", 0)), int(_data.get("max_lives", 20)), int(_data.get("leaks", 0))]
	UIKit.draw_text(c, Vector2(r.position.x, cy + 26), summary, 7, UIKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)

	# Per-player stats
	var stats: Dictionary = _data.get("stats", {})
	var mvp := int(_data.get("mvp", 0))
	var rows := [["击杀", "kills"], ["输出伤害", "damage"], ["建造 / 升级", "build"], ["连携触发", "combo_procs"], ["支援金币", "gold_sent"], ["英雄技能", "skill_casts"]]
	var tx := r.position.x + 30.0
	var ty := cy + 40.0
	UIKit.draw_text(c, Vector2(tx + 110, ty), "P1 苍穹游侠", 7, UIKit.P1, HORIZONTAL_ALIGNMENT_CENTER, 80)
	UIKit.draw_text(c, Vector2(tx + 200, ty), "P2 绯红圣骑", 7, UIKit.P2, HORIZONTAL_ALIGNMENT_CENTER, 80)
	if mvp > 0 and _t > 1.0:
		PixelIcons.draw_icon(c, "crown", Vector2(tx + 150 + (mvp - 1) * 90, ty - 12))
		UIKit.draw_text(c, Vector2(tx + 156 + (mvp - 1) * 90, ty - 9), "MVP", 6, UIKit.GOLD)
	for i in range(rows.size()):
		var yy := ty + 11.0 + i * 10.0
		if i % 2 == 0:
			c.draw_rect(Rect2(tx - 4, yy - 7, 300, 10), Color(1, 1, 1, 0.04))
		UIKit.draw_text(c, Vector2(tx, yy), rows[i][0], 7, UIKit.TEXT_DIM)
		for pid in [1, 2]:
			var s: Dictionary = stats.get(pid, {})
			var v := ""
			match rows[i][1]:
				"build":
					v = "%d / %d" % [int(s.get("builds", 0)), int(s.get("upgrades", 0))]
				"damage":
					v = str(int(float(s.get("damage", 0.0))))
				_:
					v = str(int(s.get(rows[i][1], 0)))
			UIKit.draw_text(c, Vector2(tx + 110 + (pid - 1) * 90, yy), v, 7, UIKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER, 80)
