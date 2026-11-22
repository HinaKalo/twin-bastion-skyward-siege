class_name StageResultPanel
extends CanvasLayer
## Retro-styled Stage Completion / Defeat Result Overlay.
## Displays Grade (S/A/B/C/D), Collectibles, Elapsed Time, No-Hit Medal,
## and full Keyboard + Gamepad focused Replay / Continue buttons.

signal replay_requested()
signal continue_requested()

var _panel: PanelContainer
var _eyebrow: Label
var _title: Label
var _grade_label: Label
var _detail_label: Label
var _replay_btn: Button
var _continue_btn: Button


func _ready() -> void:
	layer = 16
	visible = false
	_build()


func _build() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.03, 0.07, 0.78)
	add_child(dim)

	_panel = PanelContainer.new()
	_panel.position = Vector2(96, 46)
	_panel.custom_minimum_size = Vector2(288, 178)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.11, 0.30, 0.96)
	sb.border_color = Color(0.90, 0.95, 1.0, 0.96)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(3)
	sb.set_content_margin_all(10)
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_panel.add_child(vbox)

	_eyebrow = Label.new()
	_eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_eyebrow.add_theme_font_size_override("font_size", 8)
	_eyebrow.add_theme_color_override("font_color", Color(0.68, 0.88, 1.0))
	vbox.add_child(_eyebrow)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 13)
	_title.add_theme_color_override("font_color", Color(1.0, 0.92, 0.42))
	vbox.add_child(_title)

	_grade_label = Label.new()
	_grade_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_grade_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(_grade_label)

	_detail_label = Label.new()
	_detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_label.add_theme_font_size_override("font_size", 8)
	vbox.add_child(_detail_label)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 10)
	vbox.add_child(btn_row)

	_replay_btn = Button.new()
	_replay_btn.text = "再玩一次"
	_replay_btn.add_theme_font_size_override("font_size", 9)
	_replay_btn.pressed.connect(func():
		visible = false
		replay_requested.emit()
	)
	btn_row.add_child(_replay_btn)

	_continue_btn = Button.new()
	_continue_btn.text = "继续"
	_continue_btn.add_theme_font_size_override("font_size", 9)
	_continue_btn.pressed.connect(func():
		visible = false
		continue_requested.emit()
	)
	btn_row.add_child(_continue_btn)


func show_result(summary: Dictionary, win_title: String = "关卡通关！", lose_title: String = "挑战失败") -> void:
	var won := bool(summary.get("won", false))
	var grade := str(summary.get("grade", "C"))
	var col := int(summary.get("collected", 0))
	var tot := int(summary.get("total_collectibles", 0))
	var sec := float(summary.get("elapsed_sec", 0.0))
	var no_hit := bool(summary.get("no_hit", false))

	_eyebrow.text = "STAGE CLEAR" if won else "TRY AGAIN"
	_title.text = win_title if won else lose_title
	_grade_label.text = "评级: %s%s" % [grade, "  ★ 无伤达成" if (won and no_hit) else ""]
	_grade_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.25) if grade == "S" else (Color(0.55, 0.96, 0.72) if won else Color(1.0, 0.45, 0.45)))
	_detail_label.text = "收集品: %d / %d   |   用时: %.1fs" % [col, tot, sec]
	_continue_btn.visible = won
	visible = true
	if won:
		_continue_btn.call_deferred("grab_focus")
	else:
		_replay_btn.call_deferred("grab_focus")
