class_name PauseMenu
extends CanvasLayer
## Pause overlay: resume / restart / settings (BGM, SFX, screen shake, damage numbers) / controls / back to map.
## Pauses the SceneTree while open; fully navigable with keyboard and gamepad (focus chain).

signal resume_requested()
signal restart_requested()
signal map_requested()

var _root: Control
var _main_box: VBoxContainer
var _settings_box: VBoxContainer
var _help_box: Control
var _first_button: Button
var _settings_only: bool = false
var pause_tree := true


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.01, 0.02, 0.05, 0.72)
	_root.add_child(dim)

	var panel := UIKit.make_panel(UIKit.PANEL, UIKit.GOLD, 8)
	panel.position = Vector2(150, 44)
	panel.custom_minimum_size = Vector2(180, 0)
	_root.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	panel.add_child(col)
	var title := UIKit.make_label("暂停", 12, UIKit.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	_main_box = VBoxContainer.new()
	_main_box.add_theme_constant_override("separation", 4)
	col.add_child(_main_box)
	var focus: Array[Control] = []
	for spec in [["继续游戏", Color(0.25, 0.55, 0.90), "resume"], ["重新开始", Color(0.60, 0.42, 0.22), "restart"],
			["设置", Color(0.35, 0.40, 0.58), "settings"], ["操作说明", Color(0.35, 0.40, 0.58), "help"],
			["返回地图", Color(0.62, 0.26, 0.30), "map"]]:
		var b := UIKit.make_button(spec[0], spec[1], Vector2(164, 20), 8)
		var id: String = spec[2]
		b.pressed.connect(func(): _on_button(id))
		_main_box.add_child(b)
		focus.append(b)
	_first_button = focus[0]
	if ThemeManager:
		ThemeManager.apply_gamepad_focus_chain(focus, false, false)

	_settings_box = VBoxContainer.new()
	_settings_box.add_theme_constant_override("separation", 4)
	_settings_box.visible = false
	col.add_child(_settings_box)
	_settings_box.add_child(_make_slider("音乐音量", GameSettings.bgm_volume, func(v: float):
		GameSettings.bgm_volume = v
		_apply_settings()))
	_settings_box.add_child(_make_slider("音效音量", GameSettings.sfx_volume, func(v: float):
		GameSettings.sfx_volume = v
		_apply_settings()
		MoonRPG.play_sfx("sfx.ui_confirm")))
	_settings_box.add_child(_make_toggle("屏幕震动", GameSettings.screen_shake, func(on: bool):
		GameSettings.screen_shake = on
		_apply_settings()))
	_settings_box.add_child(_make_toggle("伤害数字", GameSettings.damage_numbers, func(on: bool):
		GameSettings.damage_numbers = on
		_apply_settings()))
	var back := UIKit.make_button("返回", Color(0.35, 0.40, 0.58), Vector2(164, 18), 7)
	back.pressed.connect(_back)
	_settings_box.add_child(back)

	_help_box = VBoxContainer.new()
	_help_box.visible = false
	col.add_child(_help_box)
	var lines := [
		["P1 (鼠标 / 手柄1)", UIKit.P1],
		["左键 塔位菜单 · 右键 移动英雄", UIKit.TEXT],
		["Q 英雄技能 · T 支援50G · R 双星合体", UIKit.TEXT],
		["Space 开波就绪 · F 加速 · Esc 暂停", UIKit.TEXT],
		["WASD / 屏幕边缘 移动视角 · 滚轮缩放 · M 小地图", UIKit.TEXT],
		["P2 (键盘右手区 / 手柄2)", UIKit.P2],
		["方向键 移动光标 · Enter 菜单/确认", UIKit.TEXT],
		["RShift 取消 · . 移动英雄 · Backspace 开波就绪", UIKit.TEXT],
		["/ 英雄技能 · , 支援50G · RCtrl 合体", UIKit.TEXT],
		["手柄：左摇杆光标 A确认 B取消 Back开波就绪", UIKit.TEXT_DIM],
		["X技能 Y合体 RB英雄 LB支援 Start暂停 · 右摇杆移动视角", UIKit.TEXT_DIM],
	]
	for l in lines:
		_help_box.add_child(UIKit.make_label(l[0], 6, l[1]))
	var back2 := UIKit.make_button("返回", Color(0.35, 0.40, 0.58), Vector2(164, 18), 7)
	back2.pressed.connect(_back)
	_help_box.add_child(back2)


func open() -> void:
	_settings_only = false
	visible = true
	if pause_tree:
		get_tree().paused = true
	_show_section("main")


## Opens straight into the settings page (used by the title screen); "back" closes the overlay.
func open_settings_only() -> void:
	_settings_only = true
	visible = true
	get_tree().paused = true
	_show_section("settings")


func _back() -> void:
	MoonRPG.play_sfx("sfx.ui_back")
	if _settings_only:
		close()
		resume_requested.emit()
	else:
		_show_section("main")


func close() -> void:
	visible = false
	if pause_tree:
		get_tree().paused = false


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	var back := (event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo and (event as InputEventKey).keycode == KEY_ESCAPE) \
		or (event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed and ((event as InputEventJoypadButton).button_index == JOY_BUTTON_START or (event as InputEventJoypadButton).button_index == JOY_BUTTON_B))
	if back:
		get_viewport().set_input_as_handled()
		if _main_box.visible:
			_on_button("resume")
		else:
			_back()


func _on_button(id: String) -> void:
	MoonRPG.play_sfx("sfx.ui_confirm")
	match id:
		"resume":
			close()
			resume_requested.emit()
		"restart":
			close()
			restart_requested.emit()
		"map":
			close()
			map_requested.emit()
		"settings":
			_show_section("settings")
		"help":
			_show_section("help")


func _show_section(which: String) -> void:
	_main_box.visible = which == "main"
	_settings_box.visible = which == "settings"
	_help_box.visible = which == "help"
	if which == "main" and _first_button != null:
		_first_button.call_deferred("grab_focus")
	elif which == "settings":
		var s := _settings_box.get_child(0).get_child(1) as Control
		if s != null:
			s.call_deferred("grab_focus")
	elif which == "help":
		(_help_box.get_child(_help_box.get_child_count() - 1) as Control).call_deferred("grab_focus")


func _apply_settings() -> void:
	GameSettings.apply(AudioManager)
	GameSettings.save_settings()


func _make_slider(label: String, value: float, on_change: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var l := UIKit.make_label(label, 7, UIKit.TEXT)
	l.custom_minimum_size = Vector2(52, 0)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = value
	s.custom_minimum_size = Vector2(104, 14)
	s.focus_mode = Control.FOCUS_ALL
	s.add_theme_stylebox_override("slider", UIKit.make_box(Color(0.04, 0.05, 0.10), UIKit.GOLD_DIM, 1, 2))
	s.add_theme_stylebox_override("grabber_area", UIKit.make_box(UIKit.P1.darkened(0.3), UIKit.P1, 1, 2))
	s.add_theme_stylebox_override("grabber_area_highlight", UIKit.make_box(UIKit.P1, UIKit.GOLD, 1, 2))
	s.value_changed.connect(on_change)
	row.add_child(s)
	return row


func _make_toggle(label: String, value: bool, on_change: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var l := UIKit.make_label(label, 7, UIKit.TEXT)
	l.custom_minimum_size = Vector2(52, 0)
	row.add_child(l)
	var b := UIKit.make_button("开" if value else "关", UIKit.GOOD.darkened(0.2) if value else Color(0.4, 0.4, 0.45), Vector2(104, 16), 7)
	b.toggle_mode = true
	b.button_pressed = value
	b.toggled.connect(func(on: bool):
		b.text = "开" if on else "关"
		UIKit.style_button(b, UIKit.GOOD.darkened(0.2) if on else Color(0.4, 0.4, 0.45), 7)
		on_change.call(on))
	row.add_child(b)
	return row
