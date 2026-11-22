class_name SaveSlotModal
extends CanvasLayer
## Reusable Retro Pixel Multi-Slot Save & Load Manager Modal (3 Manual Slots + 1 AutoSave).
## Integrates directly with `SaveManager` atomic JSON snapshots, displays timestamps & metadata,
## and wires full Mouse + Keyboard + Gamepad focus navigation via `ThemeManager`.

signal slot_saved(slot_id: String)
signal slot_loaded(slot_id: String)
signal slot_deleted(slot_id: String)
signal closed()

const DISPLAY_SLOTS: Array[Dictionary] = [
	{"id": "slot_1", "label": "手动存档 1", "allow_save": true},
	{"id": "slot_2", "label": "手动存档 2", "allow_save": true},
	{"id": "slot_3", "label": "手动存档 3", "allow_save": true},
	{"id": "autosave_1", "label": "自动存档 1", "allow_save": false},
]

var _panel: PanelContainer
var _rows_box: VBoxContainer
var _status_lbl: Label
var _close_btn: Button
var _mode: String = "both" # "both" | "save" | "load"


func _ready() -> void:
	layer = 18
	visible = false
	_build()


func _build() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.03, 0.08, 0.80)
	add_child(dim)

	_panel = PanelContainer.new()
	_panel.position = Vector2(54, 24)
	_panel.custom_minimum_size = Vector2(372, 222)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.10, 0.24, 0.97)
	sb.border_color = Color(0.90, 0.94, 1.0, 0.95)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(3)
	sb.set_content_margin_all(8)
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)

	var root_box := VBoxContainer.new()
	root_box.add_theme_constant_override("separation", 5)
	_panel.add_child(root_box)

	var header := HBoxContainer.new()
	root_box.add_child(header)

	var title := Label.new()
	title.text = "★ 本地存档槽位管理 (F5快存 / F9快读) ★"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 9)
	title.add_theme_color_override("font_color", Color(1.0, 0.92, 0.36))
	header.add_child(title)

	_close_btn = Button.new()
	_close_btn.text = "关闭 [ESC]"
	_close_btn.add_theme_font_size_override("font_size", 7)
	_close_btn.pressed.connect(close_modal)
	header.add_child(_close_btn)

	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", 5)
	root_box.add_child(_rows_box)

	_status_lbl = Label.new()
	_status_lbl.text = "选择一个槽位进行保存、读取或删除。"
	_status_lbl.add_theme_font_size_override("font_size", 7)
	_status_lbl.add_theme_color_override("font_color", Color(0.72, 0.88, 1.0))
	root_box.add_child(_status_lbl)


func open_modal(mode: String = "both") -> void:
	_mode = mode
	visible = true
	refresh_slots()


func close_modal() -> void:
	visible = false
	closed.emit()


func refresh_slots() -> void:
	if _rows_box == null:
		return
	for c in _rows_box.get_children():
		_rows_box.remove_child(c)
		c.queue_free()

	var sm := get_node_or_null("/root/SaveManager")
	var mr := get_node_or_null("/root/MoonRPG")
	var tm := get_node_or_null("/root/ThemeManager")
	var focusables: Array[Control] = []
	for sdef in DISPLAY_SLOTS:
		var sid := str(sdef["id"])
		var slabel := str(sdef["label"])
		var allow_save := bool(sdef["allow_save"]) and _mode != "load"
		var has_data: bool = sm.has_save(sid) if sm != null else false
		var meta: Dictionary = sm.get_save_meta(sid) if (sm != null and has_data) else {}

		var card := PanelContainer.new()
		var csb := StyleBoxFlat.new()
		csb.bg_color = Color(0.10, 0.16, 0.34, 0.92) if has_data else Color(0.08, 0.11, 0.22, 0.78)
		csb.border_color = Color(0.60, 0.78, 1.0, 0.75) if has_data else Color(0.38, 0.44, 0.58, 0.6)
		csb.set_border_width_all(1)
		csb.set_content_margin_all(4)
		card.add_theme_stylebox_override("panel", csb)
		_rows_box.add_child(card)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		card.add_child(row)

		var info := Label.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_font_size_override("font_size", 7)
		if has_data:
			var ts := str(meta.get("saved_at", "已存档"))
			var room := str(meta.get("room_id", "world"))
			info.text = "%s | %s\n位置:%s" % [slabel, ts, room]
		else:
			info.text = "%s\n（空槽位）" % slabel
			info.add_theme_color_override("font_color", Color(0.65, 0.70, 0.78))
		row.add_child(info)

		if allow_save:
			var b_save := Button.new()
			b_save.text = "保存"
			b_save.add_theme_font_size_override("font_size", 7)
			b_save.pressed.connect(func():
				if sm != null and sm.save_game(sid):
					_status_lbl.text = "✓ 已成功保存至 %s！" % slabel
					slot_saved.emit(sid)
					if mr != null:
						mr.play_sfx("sfx.quest_clear")
					refresh_slots()
			)
			row.add_child(b_save)
			focusables.append(b_save)

		var b_load := Button.new()
		b_load.text = "读取"
		b_load.disabled = not has_data
		b_load.add_theme_font_size_override("font_size", 7)
		b_load.pressed.connect(func():
			if sm != null and sm.load_game(sid):
				_status_lbl.text = "✓ 已读取 %s！" % slabel
				slot_loaded.emit(sid)
				if mr != null:
					mr.play_sfx("sfx.ui_confirm")
				close_modal()
		)
		row.add_child(b_load)
		if not b_load.disabled:
			focusables.append(b_load)

		var b_del := Button.new()
		b_del.text = "删除"
		b_del.disabled = not has_data
		b_del.add_theme_font_size_override("font_size", 7)
		b_del.pressed.connect(func():
			if sm != null and sm.delete_save(sid):
				_status_lbl.text = "已删除 %s。" % slabel
				slot_deleted.emit(sid)
				if mr != null:
					mr.play_sfx("sfx.hurt")
				refresh_slots()
		)
		row.add_child(b_del)

	focusables.append(_close_btn)
	if tm != null and visible:
		tm.apply_gamepad_focus_chain(focusables, true)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		close_modal()
		get_viewport().set_input_as_handled()
