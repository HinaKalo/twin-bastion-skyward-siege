extends Control
## Illustrated Fantasy World Map + 6-Node Constellation Co-op Talent Tree.
## Left side renders a live animated pixel continent map with 3 clickable landmark nodes
## (Emerald Bridges -> Arcane Rift -> Royal Obsidian Citadel); right side hosts the styled Talent Tree.

const MAP_NODES: Array[Dictionary] = [
	{"id": "stage_1_twin_bridge", "pos": Vector2(62, 166),  "icon_col": Color(0.32, 0.88, 0.48), "short": "1.翡翠双桥"},
	{"id": "stage_2_rift_cross",  "pos": Vector2(132, 118), "icon_col": Color(0.82, 0.42, 1.0),  "short": "2.裂谷交叉"},
	{"id": "stage_3_royal_siege", "pos": Vector2(192, 74),  "icon_col": Color(1.0, 0.36, 0.36),  "short": "3.王城终局"},
	{"id": "stage_4_frost_trail", "pos": Vector2(196, 150), "icon_col": Color(0.70, 0.90, 1.0),  "short": "4.霜原雪径"},
	{"id": "stage_5_abyss_corridor", "pos": Vector2(120, 176), "icon_col": Color(0.55, 0.25, 0.75), "short": "5.深渊回廊"},
]

var _stars_lbl: Label
var _stage_info_lbl: Label
var _launch_btn: Button
var _talent_box: VBoxContainer
var _selected_stage_id: String = "stage_1_twin_bridge"
var _t: float = 0.0
var _gate_tex: Texture2D
var _boss_tex: Texture2D


func _ready() -> void:
	_selected_stage_id = GameSession.selected_stage_id
	_gate_tex = load("res://content/packs/jrpg_retro/house_royal_gatehouse.png")
	_boss_tex = load("res://content/packs/jrpg_retro/boss_obsidian_clean.png")
	_build_ui()


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mpos := InputManager.get_canvas_mouse_pos(self)
		for mn in MAP_NODES:
			if mpos.distance_to(mn["pos"] as Vector2) <= 22.0:
				_select_stage(str(mn["id"]))
				get_viewport().set_input_as_handled()
				return


func _draw() -> void:
	var font := ThemeManager.get_font() if ThemeManager else ThemeDB.fallback_font

	# Full deep-navy background
	draw_rect(Rect2(0, 0, 480, 270), Color(0.05, 0.08, 0.16))

	# Illustrated Fantasy World Map Canvas (x = 10..236, y = 32..204)
	var mr := Rect2(Vector2(10, 32), Vector2(226, 172))
	draw_rect(mr, Color(0.08, 0.22, 0.38)) # Ocean
	# Shimmering ocean waves
	for wy in range(42, 198, 22):
		var wx := 18.0 + fmod(_t * 10.0 + float(wy) * 1.7, 190.0)
		draw_line(Vector2(wx, wy), Vector2(wx + 12, wy), Color(0.45, 0.72, 0.92, 0.32), 1.2)

	# Fantasy Continent Landmass (Green Meadow -> Twilight Highlands -> Volcanic Citadel)
	draw_polygon(PackedVector2Array([
		Vector2(22, 186), Vector2(26, 134), Vector2(68, 108), Vector2(124, 82),
		Vector2(168, 44), Vector2(224, 50), Vector2(226, 126), Vector2(182, 178), Vector2(92, 196)
	]), PackedColorArray([Color(0.18, 0.36, 0.22)]))
	# Highlands & Volcanic North-East Region
	draw_polygon(PackedVector2Array([
		Vector2(114, 96), Vector2(168, 44), Vector2(224, 50), Vector2(220, 114), Vector2(154, 134)
	]), PackedColorArray([Color(0.24, 0.18, 0.32)]))
	# Emerald River winding past Stage 1
	draw_polyline(PackedVector2Array([Vector2(42, 194), Vector2(66, 166), Vector2(88, 138), Vector2(74, 108)]), Color(0.22, 0.62, 0.88), 5.0)
	# Glowing Rift Crack near Stage 2
	draw_polyline(PackedVector2Array([Vector2(116, 136), Vector2(134, 118), Vector2(152, 104)]), Color(0.84, 0.35, 1.0, 0.85), 3.0)
	# Royal Citadel Mini-Sprite near Stage 3
	if _gate_tex != null:
		draw_texture_rect(_gate_tex, Rect2(Vector2(184, 46), Vector2(36, 38)), false)

	# Dotted Marching Trail connecting Stage 1 -> Stage 2 -> Stage 3
	for ni in range(MAP_NODES.size() - 1):
		var a: Vector2 = MAP_NODES[ni]["pos"]
		var b: Vector2 = MAP_NODES[ni + 1]["pos"]
		for k in range(1, 7):
			var p := a.lerp(b, float(k) / 7.0)
			draw_circle(p, 1.8, Color(1.0, 0.92, 0.52, 0.85))

	# Draw 3 Interactive Stage Landmark Badges
	for mn in MAP_NODES:
		var sid := str(mn["id"])
		var p: Vector2 = mn["pos"]
		var col: Color = mn["icon_col"]
		var is_sel := (sid == _selected_stage_id)
		var earned := int(GameSession.meta.stage_stars.get(sid, 0))
		if is_sel:
			var pr := 16.0 + 2.0 * sin(_t * 6.0)
			draw_arc(p, pr, 0.0, TAU, 20, Color(1.0, 0.94, 0.30), 2.2)
		draw_circle(p, 11.0, Color(0.06, 0.08, 0.16, 0.92))
		draw_circle(p, 8.5, col)
		draw_arc(p, 11.0, 0.0, TAU, 16, Color(1.0, 0.92, 0.45) if is_sel else Color.WHITE, 1.5)
		draw_string(font, p + Vector2(-28, 20), str(mn["short"]), HORIZONTAL_ALIGNMENT_CENTER, 56, 7, Color(1.0, 0.96, 0.65) if is_sel else Color.WHITE)
		var star_txt := "★".repeat(earned) + "☆".repeat(3 - earned)
		draw_string(font, p + Vector2(-22, -13), star_txt, HORIZONTAL_ALIGNMENT_CENTER, 44, 7, Color(1.0, 0.90, 0.25))

	# Map Gold Bevel Frame
	draw_rect(mr, Color(0.86, 0.74, 0.38, 0.95), false, 2.0)


func _build_ui() -> void:
	var top := ColorRect.new()
	top.size = Vector2(480, 26)
	top.color = Color(0.07, 0.11, 0.24)
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
	TowerArtRenderer.style_button(b_back, Color(0.30, 0.40, 0.58))
	b_back.pressed.connect(func():
		MoonRPG.play_sfx("sfx.ui_confirm")
		get_tree().change_scene_to_file("res://game/scenes/title_lobby.tscn")
	)
	add_child(b_back)

	# Bottom-Left Selected Stage Launch Card (below the illustrated map)
	var card := PanelContainer.new()
	card.position = Vector2(10, 208)
	card.custom_minimum_size = Vector2(226, 54)
	card.add_theme_stylebox_override("panel", TowerArtRenderer.make_panel_style(Color(0.07, 0.11, 0.24, 0.96), Color(0.90, 0.78, 0.38)))
	add_child(card)

	var crow := HBoxContainer.new()
	crow.add_theme_constant_override("separation", 6)
	card.add_child(crow)

	_stage_info_lbl = Label.new()
	_stage_info_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stage_info_lbl.add_theme_font_size_override("font_size", 7)
	crow.add_child(_stage_info_lbl)

	_launch_btn = Button.new()
	_launch_btn.text = "⚔ 立即出战!"
	_launch_btn.custom_minimum_size = Vector2(72, 34)
	_launch_btn.add_theme_font_size_override("font_size", 8)
	TowerArtRenderer.style_button(_launch_btn, Color(0.82, 0.34, 0.22))
	_launch_btn.pressed.connect(func():
		GameSession.selected_stage_id = _selected_stage_id
		MoonRPG.play_sfx("sfx.ui_confirm")
		get_tree().change_scene_to_file("res://game/scenes/coop_battle.tscn")
	)
	crow.add_child(_launch_btn)

	# Right Column: 6-Node Permanent Co-op Talent Tree (Styled Fantasy Panel)
	var tpanel := PanelContainer.new()
	tpanel.position = Vector2(244, 32)
	tpanel.custom_minimum_size = Vector2(226, 230)
	tpanel.add_theme_stylebox_override("panel", TowerArtRenderer.make_panel_style(Color(0.07, 0.10, 0.22, 0.96), Color(0.86, 0.74, 0.38)))
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
	thdr.add_theme_color_override("font_color", Color(1.0, 0.90, 0.38))
	thdr_row.add_child(thdr)

	var b_reset := Button.new()
	b_reset.text = "洗点重置"
	b_reset.add_theme_font_size_override("font_size", 6)
	TowerArtRenderer.style_button(b_reset, Color(0.45, 0.32, 0.56))
	b_reset.pressed.connect(func():
		GameSession.meta.reset_talents()
		MoonRPG.play_sfx("sfx.ui_confirm")
		_refresh_talents()
	)
	thdr_row.add_child(b_reset)

	_talent_box = VBoxContainer.new()
	_talent_box.add_theme_constant_override("separation", 4)
	twrap.add_child(_talent_box)

	_select_stage(_selected_stage_id)
	_refresh_talents()
	if ThemeManager:
		ThemeManager.apply_gamepad_focus_chain([_launch_btn, b_back], true)


func _select_stage(sid: String) -> void:
	_selected_stage_id = sid
	GameSession.selected_stage_id = sid
	var st := CampaignData.get_stage_by_id(sid)
	var earned := int(GameSession.meta.stage_stars.get(sid, 0))
	_stage_info_lbl.text = "%s (%d/3★)\n%s" % [str(st["name"]), earned, str(st["subtitle"])]
	queue_redraw()


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
		b.custom_minimum_size = Vector2(210, 28)
		b.add_theme_font_size_override("font_size", 6)
		TowerArtRenderer.style_button(b, Color(0.22, 0.62, 0.36) if unlocked else (Color(0.24, 0.42, 0.72) if GameSession.meta.get_available_stars() >= cost else Color(0.22, 0.24, 0.32)))
		b.disabled = unlocked or GameSession.meta.get_available_stars() < cost
		b.pressed.connect(func():
			if GameSession.meta.unlock_talent(tid):
				MoonRPG.play_sfx("sfx.quest_clear")
				_refresh_talents()
		)
		_talent_box.add_child(b)
