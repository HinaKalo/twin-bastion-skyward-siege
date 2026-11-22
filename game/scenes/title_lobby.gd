extends Control
## 《双子堡垒：共守苍穹》 — Animated Pixel-Art Commercial Title & Co-op Lobby
## Features:
## - Live animated twilight-starlight sky, twinkling Twin Stars, drifting pixel clouds
## - Foreground hillside diorama with Royal Castle Gatehouse, flickering twin braziers,
##   and animated P1 Ranger (Sapphire) & P2 Knight (Crimson) standing watch
## - Styled gold-beveled RPG panels & buttons (zero default raw grey Godot boxes)

var _ip_input: LineEdit
var _status_lbl: Label
var _t: float = 0.0
var _stars: Array[Dictionary] = []
var _embers: Array[Dictionary] = []
var _gate_tex: Texture2D
var _p1_tex: Texture2D
var _p2_tex: Texture2D
var _tree_tex: Texture2D


func _ready() -> void:
	_gate_tex = load("res://content/packs/jrpg_retro/house_royal_gatehouse.png")
	_p1_tex = load("res://content/packs/jrpg_retro/hero_ranger.png")
	_p2_tex = load("res://content/packs/jrpg_retro/npc_guard.png")
	_tree_tex = AssetRegistry.get_prop_texture("tree") if AssetRegistry else null
	for i in range(38):
		_stars.append({"pos": Vector2(randf_range(6, 474), randf_range(6, 118)), "phase": randf_range(0, TAU), "r": randf_range(0.8, 1.8)})
	for i in range(20):
		_embers.append({"pos": Vector2(randf_range(295, 470), randf_range(120, 236)), "vy": randf_range(-18.0, -8.0), "phase": randf_range(0, TAU)})
	_build_ui()
	MoonRPG.play_bgm("bgm.forest")


func _process(delta: float) -> void:
	_t += delta
	for e in _embers:
		e["phase"] = float(e["phase"]) + delta * 3.0
		var p: Vector2 = e["pos"]
		p.y += float(e["vy"]) * delta
		p.x += sin(float(e["phase"])) * 7.0 * delta
		if p.y < 52.0:
			p.y = 226.0
			p.x = randf_range(310.0, 464.0)
		e["pos"] = p
	queue_redraw()


func _draw() -> void:
	# 1. Layered Pixel Twilight Sky Gradient
	var sky_bands := [
		Color(0.04, 0.06, 0.16), Color(0.06, 0.08, 0.22), Color(0.10, 0.10, 0.28),
		Color(0.16, 0.12, 0.30), Color(0.24, 0.15, 0.28), Color(0.32, 0.18, 0.24),
	]
	for i in range(sky_bands.size()):
		draw_rect(Rect2(0, i * 28, 480, 29), sky_bands[i])

	# 2. Twinkling Stars & Glowing Twin Stars (Sapphire + Crimson) in upper-right sky
	for st in _stars:
		var a := 0.30 + 0.65 * absf(sin(_t * 2.2 + float(st["phase"])))
		draw_circle(st["pos"], float(st["r"]), Color(0.92, 0.96, 1.0, a))
	var p_twin := 0.75 + 0.25 * sin(_t * 3.4)
	draw_circle(Vector2(372, 62), 14.0, Color(0.30, 0.78, 1.0, 0.20 * p_twin))
	draw_circle(Vector2(372, 62), 4.5, Color(0.55, 0.92, 1.0))
	draw_circle(Vector2(404, 54), 14.0, Color(1.0, 0.35, 0.45, 0.20 * p_twin))
	draw_circle(Vector2(404, 54), 4.5, Color(1.0, 0.52, 0.58))
	draw_line(Vector2(372, 62), Vector2(404, 54), Color(1.0, 0.94, 0.65, 0.45 * p_twin), 1.6)

	# 3. Drifting Pixel Clouds
	for ci in range(3):
		var cx := fmod(float(ci) * 165.0 + _t * (6.0 + ci * 2.0), 540.0) - 40.0
		var cy := 58.0 + float(ci) * 18.0
		draw_rect(Rect2(cx, cy, 48, 8), Color(0.26, 0.24, 0.38, 0.45))
		draw_rect(Rect2(cx + 8, cy - 5, 28, 6), Color(0.32, 0.28, 0.44, 0.45))

	# 4. Distant Mountain Silhouette & Foreground Meadow Hillside
	draw_polygon(PackedVector2Array([Vector2(0, 185), Vector2(95, 132), Vector2(185, 175), Vector2(280, 120), Vector2(360, 162), Vector2(480, 118), Vector2(480, 270), Vector2(0, 270)]), PackedColorArray([Color(0.08, 0.11, 0.20)]))
	draw_rect(Rect2(0, 186, 480, 84), Color(0.11, 0.22, 0.15))
	draw_rect(Rect2(0, 184, 480, 4), Color(0.22, 0.40, 0.24))

	# 5. Right-Side Animated Castle Diorama (Gatehouse + Trees + Flickering Braziers + P1 & P2 Heroes!)
	if _tree_tex != null:
		draw_texture_rect(_tree_tex, Rect2(Vector2(304, 152), Vector2(32, 36)), false)
		draw_texture_rect(_tree_tex, Rect2(Vector2(442, 154), Vector2(32, 36)), false)
	if _gate_tex != null:
		draw_texture_rect(_gate_tex, Rect2(Vector2(342, 92), Vector2(104, 112)), false)

	# Flickering Twin Braziers
	var fl := 2.8 * sin(_t * 14.0)
	for bp in [Vector2(340, 198), Vector2(446, 198)]:
		draw_circle(bp, 18.0, Color(1.0, 0.56, 0.18, 0.22))
		draw_rect(Rect2(bp + Vector2(-4, 0), Vector2(8, 6)), Color(0.25, 0.22, 0.24))
		draw_polygon(PackedVector2Array([bp + Vector2(-4, 0), bp + Vector2(4, 0), bp + Vector2(0, -10 + fl)]), PackedColorArray([Color(1.0, 0.48, 0.12)]))
		draw_polygon(PackedVector2Array([bp + Vector2(-2, 0), bp + Vector2(2, 0), bp + Vector2(0, -5 + fl * 0.5)]), PackedColorArray([Color(1.0, 0.94, 0.36)]))

	# Animated P1 Ranger & P2 Knight standing guard in front of the gate!
	var b1 := absf(sin(_t * 3.8)) * 2.0
	var b2 := absf(sin(_t * 3.8 + 1.4)) * 2.0
	if _p1_tex != null:
		draw_circle(Vector2(372, 214), 12.0, Color(0.32, 0.80, 1.0, 0.25))
		draw_texture_rect(_p1_tex, Rect2(Vector2(358, 186 - b1), Vector2(28, 28)), false)
	if _p2_tex != null:
		draw_circle(Vector2(416, 214), 12.0, Color(1.0, 0.38, 0.44, 0.25))
		draw_texture_rect(_p2_tex, Rect2(Vector2(402, 186 - b2), Vector2(28, 28)), false)

	# Floating Embers
	for e in _embers:
		draw_rect(Rect2(e["pos"], Vector2(1.8, 1.8)), Color(1.0, 0.78, 0.32, 0.75))

	# Bottom Footer Strip
	draw_rect(Rect2(0, 236, 480, 34), Color(0.04, 0.06, 0.14, 0.90))
	draw_line(Vector2(0, 236), Vector2(480, 236), Color(0.86, 0.74, 0.38, 0.85), 1.5)


func _build_ui() -> void:
	# Royal Gold-Trimmed Title Crest
	var crest := PanelContainer.new()
	crest.position = Vector2(18, 10)
	crest.custom_minimum_size = Vector2(304, 42)
	crest.add_theme_stylebox_override("panel", TowerArtRenderer.make_panel_style(Color(0.07, 0.10, 0.24, 0.92), Color(0.95, 0.82, 0.36)))
	add_child(crest)

	var cbox := VBoxContainer.new()
	cbox.add_theme_constant_override("separation", 1)
	crest.add_child(cbox)

	var title := Label.new()
	title.text = "⚔ 《双子堡垒：共守苍穹》 ⚔"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(1.0, 0.94, 0.40))
	title.add_theme_constant_override("outline_size", 3)
	title.add_theme_color_override("font_outline_color", Color(0.10, 0.05, 0.02))
	cbox.add_child(title)

	var sub := Label.new()
	sub.text = "双人合作像素塔防 · 跨玩家元素连携 · 双星合体奥义"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 7)
	sub.add_theme_color_override("font_color", Color(0.76, 0.92, 1.0))
	cbox.add_child(sub)

	# Left Menu Panel (Gold-Beveled Fantasy RPG Card)
	var panel := PanelContainer.new()
	panel.position = Vector2(18, 58)
	panel.custom_minimum_size = Vector2(284, 170)
	panel.add_theme_stylebox_override("panel", TowerArtRenderer.make_panel_style(Color(0.06, 0.09, 0.20, 0.92), Color(0.84, 0.72, 0.38)))
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	panel.add_child(vbox)

	var focusables: Array[Control] = []

	var b_solo := Button.new()
	b_solo.text = "▶ 单人 + 智能 AI 搭档（推荐即刻出征）"
	b_solo.custom_minimum_size = Vector2(266, 28)
	b_solo.add_theme_font_size_override("font_size", 8)
	TowerArtRenderer.style_button(b_solo, Color(0.22, 0.46, 0.82))
	b_solo.pressed.connect(func():
		GameSession.play_mode = GameSession.PlayMode.SOLO_AI
		GameSession.local_player_id = 1
		GameSession.net.close_session()
		_go_campaign()
	)
	vbox.add_child(b_solo)
	focusables.append(b_solo)

	var b_local := Button.new()
	b_local.text = "👥 同屏双人合作（P1键鼠/手柄0 + P2方向键/手柄1）"
	b_local.custom_minimum_size = Vector2(266, 26)
	b_local.add_theme_font_size_override("font_size", 8)
	TowerArtRenderer.style_button(b_local, Color(0.68, 0.28, 0.42))
	b_local.pressed.connect(func():
		GameSession.play_mode = GameSession.PlayMode.LOCAL_2P
		GameSession.local_player_id = 1
		GameSession.net.close_session()
		_go_campaign()
	)
	vbox.add_child(b_local)
	focusables.append(b_local)

	var lan_row := HBoxContainer.new()
	lan_row.add_theme_constant_override("separation", 4)
	vbox.add_child(lan_row)

	var b_host := Button.new()
	b_host.text = "🌐 局域网建房(P1)"
	b_host.custom_minimum_size = Vector2(102, 24)
	b_host.add_theme_font_size_override("font_size", 7)
	TowerArtRenderer.style_button(b_host, Color(0.24, 0.52, 0.46))
	b_host.pressed.connect(_on_host_lan)
	lan_row.add_child(b_host)
	focusables.append(b_host)

	_ip_input = LineEdit.new()
	_ip_input.text = "127.0.0.1"
	_ip_input.custom_minimum_size = Vector2(82, 24)
	_ip_input.add_theme_font_size_override("font_size", 7)
	lan_row.add_child(_ip_input)

	var b_join := Button.new()
	b_join.text = "加入(P2)"
	b_join.custom_minimum_size = Vector2(72, 24)
	b_join.add_theme_font_size_override("font_size", 7)
	TowerArtRenderer.style_button(b_join, Color(0.32, 0.46, 0.66))
	b_join.pressed.connect(_on_join_lan)
	lan_row.add_child(b_join)
	focusables.append(b_join)

	var b_save := Button.new()
	b_save.text = "💾 本地存档槽位管理（已获战役星数: %d★）" % GameSession.meta.get_total_stars()
	b_save.custom_minimum_size = Vector2(266, 24)
	b_save.add_theme_font_size_override("font_size", 7)
	TowerArtRenderer.style_button(b_save, Color(0.56, 0.44, 0.22))
	b_save.pressed.connect(func(): MoonRPG.open_save_menu("both"))
	vbox.add_child(b_save)
	focusables.append(b_save)

	_status_lbl = Label.new()
	_status_lbl.text = "★ 3 大特色地形战役 + 6 项永久合作天赋树等你挑战！"
	_status_lbl.add_theme_font_size_override("font_size", 7)
	_status_lbl.add_theme_color_override("font_color", Color(0.95, 0.90, 0.65))
	vbox.add_child(_status_lbl)

	# Bottom Adaptive Glyph Strip
	var gbar := HBoxContainer.new()
	gbar.position = Vector2(18, 244)
	gbar.add_theme_constant_override("separation", 10)
	add_child(gbar)
	for gp in [["jump", "确认"], ["guard", "切塔"], ["skill_ultimate", "大招"], ["attack_heavy", "召波"]]:
		var badge := InputGlyphBadge.new()
		badge.action_name = gp[0]
		badge.caption = gp[1]
		badge.custom_minimum_size = Vector2(96, 18)
		gbar.add_child(badge)

	if ThemeManager:
		ThemeManager.apply_gamepad_focus_chain(focusables, true)


func _on_host_lan() -> void:
	if GameSession.net.host_game(24560, 2, "P1_Host"):
		GameSession.play_mode = GameSession.PlayMode.LAN_HOST
		GameSession.local_player_id = 1
		_go_campaign()
	else:
		_status_lbl.text = "⚠ 端口 24560 被占用，无法建房。"
		MoonRPG.play_sfx("sfx.hurt")


func _on_join_lan() -> void:
	var ip := _ip_input.text.strip_edges()
	if ip.is_empty():
		ip = "127.0.0.1"
	if GameSession.net.join_game(ip, 24560):
		GameSession.play_mode = GameSession.PlayMode.LAN_CLIENT
		GameSession.local_player_id = 2
		_go_campaign()
	else:
		_status_lbl.text = "⚠ 连接 %s:24560 失败。" % ip
		MoonRPG.play_sfx("sfx.hurt")


func _go_campaign() -> void:
	MoonRPG.play_sfx("sfx.ui_confirm")
	get_tree().change_scene_to_file("res://game/scenes/campaign_map.tscn")
