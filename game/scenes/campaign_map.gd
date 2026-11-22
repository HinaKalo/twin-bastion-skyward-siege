extends Control
## Campaign Stage Selection Map & 6-Node Permanent Co-op Talent Tree.

var _stars_lbl: Label
var _talent_box: VBoxContainer


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.06, 0.10, 0.16)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var top := ColorRect.new()
	top.size = Vector2(480, 26)
	top.color = Color(0.08, 0.14, 0.28)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)

	_stars_lbl = Label.new()
	_stars_lbl.position = Vector2(10, 4)
	_stars_lbl.custom_minimum_size = Vector2(360, 18)
	_stars_lbl.add_theme_font_size_override("font_size", 8)
	_stars_lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.36))
	add_child(_stars_lbl)

	var b_back := Button.new()
	b_back.text = "◀ 返回大厅"
	b_back.position = Vector2(404, 3)
	b_back.custom_minimum_size = Vector2(70, 20)
	b_back.add_theme_font_size_override("font_size", 7)
	b_back.pressed.connect(func():
		MoonRPG.play_sfx("sfx.ui_confirm")
		get_tree().change_scene_to_file("res://game/scenes/title_lobby.tscn")
	)
	add_child(b_back)

	# Left Column: 3 Campaign Stages
	var stage_panel := PanelContainer.new()
	stage_panel.position = Vector2(10, 32)
	stage_panel.custom_minimum_size = Vector2(226, 228)
	add_child(stage_panel)

	var sbox := VBoxContainer.new()
	sbox.add_theme_constant_override("separation", 8)
	stage_panel.add_child(sbox)

	var shdr := Label.new()
	shdr.text = "🗺 战役关卡（点击直接出战）"
	shdr.add_theme_font_size_override("font_size", 8)
	shdr.add_theme_color_override("font_color", Color(0.65, 0.90, 1.0))
	sbox.add_child(shdr)

	var focusables: Array[Control] = []
	for st in CampaignData.get_stages():
		var sid := str(st["id"])
		var earned := int(GameSession.meta.stage_stars.get(sid, 0))
		var star_str := "★".repeat(earned) + "☆".repeat(3 - earned)
		var btn := Button.new()
		btn.text = "%s  [%s]\n%s" % [str(st["name"]), star_str, str(st["subtitle"])]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(210, 56)
		btn.add_theme_font_size_override("font_size", 7)
		btn.pressed.connect(func():
			GameSession.selected_stage_id = sid
			MoonRPG.play_sfx("sfx.ui_confirm")
			get_tree().change_scene_to_file("res://game/scenes/coop_battle.tscn")
		)
		sbox.add_child(btn)
		focusables.append(btn)

	# Right Column: 6-Node Permanent Co-op Talent Tree
	var tpanel := PanelContainer.new()
	tpanel.position = Vector2(244, 32)
	tpanel.custom_minimum_size = Vector2(226, 228)
	add_child(tpanel)

	var twrap := VBoxContainer.new()
	twrap.add_theme_constant_override("separation", 4)
	tpanel.add_child(twrap)

	var thdr_row := HBoxContainer.new()
	twrap.add_child(thdr_row)
	var thdr := Label.new()
	thdr.text = "⭐ 永久合作天赋树"
	thdr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	thdr.add_theme_font_size_override("font_size", 8)
	thdr.add_theme_color_override("font_color", Color(1.0, 0.88, 0.36))
	thdr_row.add_child(thdr)

	var b_reset := Button.new()
	b_reset.text = "洗点"
	b_reset.add_theme_font_size_override("font_size", 6)
	b_reset.pressed.connect(func():
		GameSession.meta.reset_talents()
		MoonRPG.play_sfx("sfx.ui_confirm")
		_refresh_talents()
	)
	thdr_row.add_child(b_reset)

	_talent_box = VBoxContainer.new()
	_talent_box.add_theme_constant_override("separation", 4)
	twrap.add_child(_talent_box)

	_refresh_talents()
	if ThemeManager:
		ThemeManager.apply_gamepad_focus_chain(focusables, true)


func _refresh_talents() -> void:
	_stars_lbl.text = "模式: %s | 累计星数: %d★ | 可用天赋星: %d★" % [
		GameSession.get_mode_label(), GameSession.meta.get_total_stars(), GameSession.meta.get_available_stars()
	]
	for c in _talent_box.get_children():
		_talent_box.remove_child(c)
		c.queue_free()

	for t in MetaProgress.TALENT_DEFS:
		var tid := str(t["id"])
		var unlocked := GameSession.meta.has_talent(tid)
		var cost := int(t["cost"])
		var b := Button.new()
		b.text = "%s【%s】(%d★) %s" % [("✓" if unlocked else "+"), str(t["name"]), cost, str(t["desc"])]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(210, 26)
		b.add_theme_font_size_override("font_size", 6)
		b.modulate = Color(0.55, 1.0, 0.65) if unlocked else (Color.WHITE if GameSession.meta.get_available_stars() >= cost else Color(0.62, 0.66, 0.74))
		b.disabled = unlocked or GameSession.meta.get_available_stars() < cost
		b.pressed.connect(func():
			if GameSession.meta.unlock_talent(tid):
				MoonRPG.play_sfx("sfx.quest_clear")
				_refresh_talents()
		)
		_talent_box.add_child(b)
