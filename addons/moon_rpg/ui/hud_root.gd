class_name HudRoot
extends CanvasLayer
## Master Out-of-the-Box ARPG HUD.
## Includes HP/ST bars, Buff badges, Hotbar (1-4), Active Quest Tracker,
## Room Fade Transition + Area Title Banner, Minimap, Screen-Edge Objective Indicator,
## DialogueBox, InventoryPanel, Pause Menu (Esc), and Developer Debug HUD (F3).

const MinimapScript := preload("res://addons/moon_rpg/ui/minimap_widget.gd")
const IndicatorScript := preload("res://addons/moon_rpg/ui/objective_indicator.gd")
const DialogueBoxScript := preload("res://addons/moon_rpg/ui/dialogue_box.gd")
const InventoryPanelScript := preload("res://addons/moon_rpg/ui/inventory_panel.gd")

var _player_ref: Actor2D = null
var _p2_ref: Actor2D = null
var _p2_panel: PanelContainer = null
var _p2_hp_bar: ProgressBar = null
var _p2_st_bar: ProgressBar = null
var _p2_label: Label = null
var _hp_bar: ProgressBar
var _rally_bar: ProgressBar
var _st_bar: ProgressBar
var _status_label: Label
var _buff_box: HBoxContainer
var _quest_label: Label
var _interact_label: Label
var _toast_label: Label
var _toast_timer: float = 0.0
var _hotbar_buttons: Array[Button] = []

var _fader: ColorRect
var _area_banner: Label
var _area_banner_timer: float = 0.0
var _transitioning: bool = false

var _pause_panel: PanelContainer
var _pause_first_btn: Button = null
var _controls_hint: Label
var _debug_label: Label

var minimap: MinimapWidget
var objective_indicator: ObjectiveIndicator
var dialogue_box: DialogueBox
var inventory_panel: InventoryPanel


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_top_left_bars()
	_build_quest_tracker()
	_build_hotbar()
	_build_prompts_and_toast()

	objective_indicator = IndicatorScript.new()
	add_child(objective_indicator)

	minimap = MinimapScript.new()
	add_child(minimap)

	dialogue_box = DialogueBoxScript.new()
	add_child(dialogue_box)

	inventory_panel = InventoryPanelScript.new()
	add_child(inventory_panel)

	_build_transition_and_banner()
	_build_pause_menu()
	_build_debug_hud()

	if EventBus:
		EventBus.player_registered.connect(_on_player_registered)
		EventBus.player_stats_changed.connect(_refresh_bars)
		EventBus.status_effects_changed.connect(func(_a): _refresh_buffs())
		EventBus.gold_changed.connect(func(_g): _refresh_bars())
		EventBus.inventory_changed.connect(_refresh_hotbar)
		EventBus.hotbar_changed.connect(func(_i, _id): _refresh_hotbar())
		EventBus.quest_updated.connect(func(_q): _refresh_quest())
		EventBus.tracked_quest_changed.connect(func(_q): _refresh_quest())
		EventBus.interact_prompt_changed.connect(_on_interact_prompt)
		EventBus.toast_requested.connect(_on_toast)
		EventBus.room_transition_requested.connect(_on_room_transition_requested)
		EventBus.room_changed.connect(_on_room_changed)
		EventBus.input_device_changed.connect(func(_d, _b): _refresh_controls_hint())
		EventBus.player_joined.connect(_on_player_joined)
		EventBus.player_left.connect(_on_player_left)


func _build_top_left_bars() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(6, 6)
	panel.custom_minimum_size = Vector2(146, 42)
	var sb := AssetRegistry.get_ui_stylebox("panel_iron", 5.0) if AssetRegistry else null
	if sb != null:
		panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	panel.add_child(vbox)

	_status_label = Label.new()
	_status_label.text = "Lv.1  HP 120/120  金币 120"
	_status_label.add_theme_font_size_override("font_size", 7)
	vbox.add_child(_status_label)

	var hp_stack := Control.new()
	hp_stack.custom_minimum_size = Vector2(132, 7)
	vbox.add_child(hp_stack)

	_rally_bar = _make_bar(Color(0.96, 0.56, 0.16, 0.95))
	_rally_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	hp_stack.add_child(_rally_bar)

	_hp_bar = _make_bar(Color(0.86, 0.22, 0.22))
	_hp_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	var transparent_bg := StyleBoxEmpty.new()
	_hp_bar.add_theme_stylebox_override("background", transparent_bg)
	hp_stack.add_child(_hp_bar)

	_st_bar = _make_bar(Color(0.94, 0.72, 0.18))
	vbox.add_child(_st_bar)

	_buff_box = HBoxContainer.new()
	_buff_box.position = Vector2(6, 50)
	_buff_box.add_theme_constant_override("separation", 3)
	add_child(_buff_box)

	# Compact P2 status panel (auto-visible when P2 joins local or online co-op)
	_p2_panel = PanelContainer.new()
	_p2_panel.visible = false
	_p2_panel.position = Vector2(158, 6)
	_p2_panel.custom_minimum_size = Vector2(118, 42)
	if sb != null:
		_p2_panel.add_theme_stylebox_override("panel", sb)
	add_child(_p2_panel)

	var p2_vbox := VBoxContainer.new()
	p2_vbox.add_theme_constant_override("separation", 2)
	_p2_panel.add_child(p2_vbox)

	_p2_label = Label.new()
	_p2_label.text = "P2  HP 120/120"
	_p2_label.add_theme_font_size_override("font_size", 7)
	_p2_label.add_theme_color_override("font_color", Color(0.55, 0.92, 1.0))
	p2_vbox.add_child(_p2_label)

	_p2_hp_bar = _make_bar(Color(0.28, 0.78, 0.96))
	_p2_hp_bar.custom_minimum_size = Vector2(104, 7)
	p2_vbox.add_child(_p2_hp_bar)

	_p2_st_bar = _make_bar(Color(0.94, 0.72, 0.18))
	_p2_st_bar.custom_minimum_size = Vector2(104, 7)
	p2_vbox.add_child(_p2_st_bar)


func _make_bar(fill_col: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(132, 7)
	bar.show_percentage = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.10, 0.10, 0.14, 0.9)
	var fg := StyleBoxFlat.new()
	fg.bg_color = fill_col
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)
	return bar


func _build_quest_tracker() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(6, 64)
	panel.custom_minimum_size = Vector2(154, 24)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.06, 0.08, 0.12, 0.68)
	bg.content_margin_left = 5
	bg.content_margin_right = 5
	bg.content_margin_top = 3
	bg.content_margin_bottom = 3
	panel.add_theme_stylebox_override("panel", bg)
	add_child(panel)

	_quest_label = Label.new()
	_quest_label.text = "◆ 自由探索（与营地 NPC 交谈接取任务）"
	_quest_label.add_theme_font_size_override("font_size", 7)
	_quest_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.62))
	panel.add_child(_quest_label)


func _build_hotbar() -> void:
	var hbox := HBoxContainer.new()
	hbox.position = Vector2(6, 236)
	hbox.add_theme_constant_override("separation", 4)
	add_child(hbox)

	for i in range(4):
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(28, 28)
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_size_override("font_size", 7)
		btn.text = str(i + 1)
		var idx := i
		btn.pressed.connect(func(): InventoryManager.use_hotbar(idx))
		hbox.add_child(btn)
		_hotbar_buttons.append(btn)

	_controls_hint = Label.new()
	_controls_hint.position = Vector2(138, 250)
	_controls_hint.add_theme_font_size_override("font_size", 7)
	_controls_hint.add_theme_color_override("font_color", Color(0.85, 0.85, 0.88, 0.82))
	_controls_hint.add_theme_constant_override("outline_size", 2)
	_controls_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	add_child(_controls_hint)
	_refresh_controls_hint()


func _refresh_controls_hint() -> void:
	if _controls_hint == null or InputManager == null:
		return
	if InputManager.is_using_gamepad():
		_controls_hint.text = "摇杆移动 %s跳 %s轻击 %s重击 %s奥义 %s弹反 %s闪 %s背包 %s地图 %s菜单" % [
			InputManager.get_prompt("jump", false),
			InputManager.get_prompt("attack_light", false),
			InputManager.get_prompt("attack_heavy", false),
			InputManager.get_prompt("skill_ultimate", false),
			InputManager.get_prompt("guard", false),
			InputManager.get_prompt("dodge", false),
			InputManager.get_prompt("toggle_inventory", false),
			InputManager.get_prompt("toggle_map", false),
			InputManager.get_prompt("pause", false),
		]
	else:
		_controls_hint.text = "A/D移动 Space跳 J轻击 U重击 O奥义 L弹反 Shift闪 I背包 M地图 Esc菜单"


func _build_prompts_and_toast() -> void:
	_interact_label = Label.new()
	_interact_label.visible = false
	_interact_label.position = Vector2(160, 212)
	_interact_label.custom_minimum_size = Vector2(160, 18)
	_interact_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_interact_label.add_theme_font_size_override("font_size", 9)
	_interact_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.55))
	_interact_label.add_theme_constant_override("outline_size", 2)
	_interact_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	add_child(_interact_label)

	_toast_label = Label.new()
	_toast_label.visible = false
	_toast_label.position = Vector2(90, 22)
	_toast_label.custom_minimum_size = Vector2(300, 18)
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.add_theme_font_size_override("font_size", 9)
	_toast_label.add_theme_constant_override("outline_size", 2)
	_toast_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	add_child(_toast_label)


func _build_transition_and_banner() -> void:
	_area_banner = Label.new()
	_area_banner.visible = false
	_area_banner.position = Vector2(90, 56)
	_area_banner.custom_minimum_size = Vector2(300, 24)
	_area_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_area_banner.add_theme_font_size_override("font_size", 12)
	_area_banner.add_theme_color_override("font_color", Color(1.0, 0.93, 0.72))
	_area_banner.add_theme_constant_override("outline_size", 3)
	_area_banner.add_theme_color_override("font_outline_color", Color(0.04, 0.04, 0.06, 0.95))
	add_child(_area_banner)

	_fader = ColorRect.new()
	_fader.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fader.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fader.color = Color(0.0, 0.0, 0.0, 0.0)
	add_child(_fader)


func _build_pause_menu() -> void:
	_pause_panel = PanelContainer.new()
	_pause_panel.visible = false
	_pause_panel.position = Vector2(165, 58)
	_pause_panel.custom_minimum_size = Vector2(150, 140)
	var sb := AssetRegistry.get_ui_stylebox("panel_wood", 8.0) if AssetRegistry else null
	if sb != null:
		_pause_panel.add_theme_stylebox_override("panel", sb)
	add_child(_pause_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	_pause_panel.add_child(vbox)

	var title := Label.new()
	title.text = "— 游戏暂停 —"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 9)
	title.add_theme_color_override("font_color", Color(1.0, 0.90, 0.55))
	vbox.add_child(title)

	var items := [
		["继续游戏 [Esc]", _on_pause_resume],
		["开启/关闭本地双人", _on_pause_toggle_coop],
		["快速存档 [F5]", _on_pause_save],
		["快速读档 [F9]", _on_pause_load],
		["热重载台词表", _on_pause_reload_locale],
		["判定框调试 [F3]", _on_pause_debug],
	]
	for entry in items:
		var btn := Button.new()
		btn.text = entry[0]
		btn.add_theme_font_size_override("font_size", 8)
		btn.pressed.connect(entry[1])
		vbox.add_child(btn)
		if _pause_first_btn == null:
			_pause_first_btn = btn


func _on_pause_resume() -> void:
	_toggle_pause(false)


func _on_pause_toggle_coop() -> void:
	if MoonRPG.is_coop():
		MoonRPG.leave_coop()
		MoonRPG.toast("已退出双人模式", "info")
	else:
		MoonRPG.start_local_coop()
	_toggle_pause(false)


func _on_player_joined(idx: int, player: Node) -> void:
	if idx == 2 and player is Actor2D:
		_p2_ref = player as Actor2D
		_p2_panel.visible = true


func _on_player_left(idx: int) -> void:
	if idx == 2:
		_p2_ref = null
		_p2_panel.visible = false


func _on_pause_save() -> void:
	MoonRPG.save("slot_1")
	MoonRPG.toast("已保存至 slot_1", "gold")
	_toggle_pause(false)


func _on_pause_load() -> void:
	var ok := MoonRPG.load_save("slot_1")
	MoonRPG.toast("读档成功！" if ok else "尚未找到存档", "gold" if ok else "warn")
	_toggle_pause(false)


func _on_pause_reload_locale() -> void:
	MoonRPG.reload_locale()
	MoonRPG.toast("已重新加载台词表 (%s)" % LocaleManager.current_locale, "info")


func _on_pause_debug() -> void:
	MoonRPG.debug_hitboxes = not MoonRPG.debug_hitboxes
	_debug_label.visible = MoonRPG.debug_hitboxes


func _build_debug_hud() -> void:
	_debug_label = Label.new()
	_debug_label.visible = false
	_debug_label.position = Vector2(168, 6)
	_debug_label.add_theme_font_size_override("font_size", 7)
	_debug_label.add_theme_color_override("font_color", Color(0.55, 1.0, 0.65))
	_debug_label.add_theme_constant_override("outline_size", 2)
	_debug_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	add_child(_debug_label)


func _toggle_pause(paused: bool) -> void:
	_pause_panel.visible = paused
	get_tree().paused = paused
	if paused and _pause_first_btn != null:
		_pause_first_btn.grab_focus()


func _on_room_transition_requested(room_id: String, spawn_point: String) -> void:
	if _transitioning:
		return
	_transitioning = true
	var tween := create_tween()
	tween.tween_property(_fader, "color:a", 1.0, 0.16)
	await tween.finished
	WorldManager.load_room(room_id, spawn_point)
	var tween_in := create_tween()
	tween_in.tween_property(_fader, "color:a", 0.0, 0.22)
	await tween_in.finished
	_transitioning = false


func _on_room_changed(room_id: String, _spawn: String) -> void:
	var meta := DataRegistry.get_room_meta(room_id)
	var rname := LocaleManager.tr_key(str(meta.get("name_key", room_id)), {}, room_id)
	_area_banner.text = "— %s —" % rname
	_area_banner.visible = true
	_area_banner.modulate.a = 1.0
	_area_banner_timer = 1.8


func _on_player_registered(player: Node) -> void:
	if player is Actor2D:
		_player_ref = player as Actor2D
	_refresh_bars()
	_refresh_buffs()
	_refresh_hotbar()
	_refresh_quest()


func _refresh_bars() -> void:
	if _player_ref == null or _player_ref.stat_block == null:
		return
	var sb := _player_ref.stat_block
	var max_hp := sb.get_stat("max_hp")
	_hp_bar.max_value = max_hp
	_hp_bar.value = sb.hp
	if _rally_bar != null:
		_rally_bar.max_value = max_hp
		_rally_bar.value = minf(max_hp, sb.hp + _player_ref.rally_hp)
	_st_bar.max_value = sb.get_stat("max_st")
	_st_bar.value = sb.st
	var g := InventoryManager.gold if InventoryManager else 0
	_status_label.text = "Lv.%d  HP %d/%d  ST %d  金币 %d" % [sb.level, int(sb.hp), int(_hp_bar.max_value), int(sb.st), g]


func _refresh_buffs() -> void:
	for c in _buff_box.get_children():
		c.queue_free()
	if _player_ref == null or _player_ref.status_effects == null:
		return
	for eff in _player_ref.status_effects.get_active_effects():
		var lbl := Label.new()
		lbl.text = "[%s %ds]" % [str(eff.get("label", eff.get("id", ""))), int(ceil(float(eff.get("remaining", 0.0))))]
		lbl.add_theme_font_size_override("font_size", 7)
		lbl.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5) if bool(eff.get("is_debuff", false)) else Color(0.55, 0.96, 0.65))
		lbl.add_theme_constant_override("outline_size", 2)
		lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		_buff_box.add_child(lbl)


func _refresh_hotbar() -> void:
	if InventoryManager == null:
		return
	for i in range(mini(4, _hotbar_buttons.size())):
		var iid := InventoryManager.hotbar[i]
		var btn := _hotbar_buttons[i]
		if iid.is_empty():
			btn.text = str(i + 1)
			btn.icon = null
		else:
			var cnt := InventoryManager.get_item_count(iid)
			btn.text = "%d:%d" % [i + 1, cnt]
			var idef := DataRegistry.get_item(iid)
			btn.icon = AssetRegistry.get_icon(str(idef.get("icon_key", ""))) if AssetRegistry else null
			btn.expand_icon = true


func _refresh_quest() -> void:
	if QuestManager == null:
		return
	var info := QuestManager.get_tracked_objective_info()
	if info.is_empty():
		_quest_label.text = "◆ 自由探索（与营地 NPC 交谈接取任务）"
	else:
		_quest_label.text = "◆ %s\n  %s (%d/%d)" % [
			str(info.get("title", "")),
			str(info.get("description", "")),
			int(info.get("current", 0)),
			int(info.get("required", 1)),
		]


func _on_interact_prompt(vis: bool, label: String) -> void:
	_interact_label.visible = vis
	_interact_label.text = label


func _on_toast(message: String, style: String) -> void:
	_toast_label.text = message
	_toast_label.visible = true
	_toast_timer = 2.6
	match style:
		"gold":
			_toast_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.25))
		"warn":
			_toast_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.40))
		_:
			_toast_label.add_theme_color_override("font_color", Color(0.65, 0.92, 1.0))


func _process(delta: float) -> void:
	if _toast_timer > 0.0:
		_toast_timer -= delta
		if _toast_timer <= 0.0:
			_toast_label.visible = false
	if _area_banner_timer > 0.0:
		_area_banner_timer -= delta
		if _area_banner_timer < 0.5:
			_area_banner.modulate.a = clampf(_area_banner_timer / 0.5, 0.0, 1.0)
		if _area_banner_timer <= 0.0:
			_area_banner.visible = false
	if _buff_box.get_child_count() > 0:
		_refresh_buffs()
	if _p2_panel != null and _p2_panel.visible and is_instance_valid(_p2_ref) and _p2_ref.stat_block != null:
		var p2sb := _p2_ref.stat_block
		_p2_hp_bar.max_value = p2sb.get_stat("max_hp")
		_p2_hp_bar.value = p2sb.hp
		_p2_st_bar.max_value = p2sb.get_stat("max_st")
		_p2_st_bar.value = p2sb.st
		_p2_label.text = "P2  HP %d/%d" % [int(p2sb.hp), int(_p2_hp_bar.max_value)]
	if _debug_label.visible:
		var pos_str := "(%.0f, %.0f)" % [_player_ref.global_position.x, _player_ref.global_position.y] if is_instance_valid(_player_ref) else "-"
		_debug_label.text = "FPS:%d | Room:%s | Pos:%s | Pack:%s" % [
			Engine.get_frames_per_second(),
			WorldManager.current_room_id if WorldManager else "-",
			pos_str,
			AssetRegistry.active_pack_id if AssetRegistry else "-",
		]


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		if inventory_panel.visible:
			inventory_panel.toggle()
			get_viewport().set_input_as_handled()
			return
		elif minimap.is_expanded:
			minimap.toggle_expanded()
			get_viewport().set_input_as_handled()
			return
		elif event.is_action_pressed("pause") and not (DialogueRunner != null and DialogueRunner.is_active):
			_toggle_pause(not _pause_panel.visible)
			get_viewport().set_input_as_handled()
			return
		elif _pause_panel.visible:
			_toggle_pause(false)
			get_viewport().set_input_as_handled()
			return

	if event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).keycode
		if k == KEY_F3:
			MoonRPG.debug_hitboxes = not MoonRPG.debug_hitboxes
			_debug_label.visible = MoonRPG.debug_hitboxes
			return
		elif k == KEY_F5:
			MoonRPG.save("slot_1")
			MoonRPG.toast("快速存档完成 (slot_1)", "gold")
			return
		elif k == KEY_F9:
			var ok := MoonRPG.load_save("slot_1")
			MoonRPG.toast("快速读档完成！" if ok else "暂无存档可读取", "gold" if ok else "warn")
			return

	if get_tree().paused or (DialogueRunner != null and DialogueRunner.is_active):
		return
	if event.is_action_pressed("toggle_inventory"):
		inventory_panel.toggle()
	elif event.is_action_pressed("toggle_map"):
		minimap.toggle_expanded()
