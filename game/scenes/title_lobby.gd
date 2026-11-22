extends Control
## 《双子堡垒：共守苍穹》 — Commercial Title & Co-op Lobby Scene
## Supports Solo + AI Partner, Local 2P Couch Co-op, and ENet LAN Host/Join.

var _ip_input: LineEdit
var _status_lbl: Label


func _ready() -> void:
	_build_ui()
	MoonRPG.play_bgm("bgm.forest")


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.06, 0.09, 0.18)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# Decorative pixel castle & heroes vignette on right side
	var gate := TextureRect.new()
	var gtex: Texture2D = load("res://content/packs/jrpg_retro/house_royal_gatehouse.png")
	if gtex != null:
		gate.texture = gtex
		gate.position = Vector2(318, 52)
		gate.custom_minimum_size = Vector2(138, 152)
		gate.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		gate.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(gate)

	# Title Banner
	var title := Label.new()
	title.position = Vector2(18, 14)
	title.custom_minimum_size = Vector2(444, 24)
	title.text = "★ 《双子堡垒：共守苍穹》 Twin Bastion TD ★"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", Color(1.0, 0.92, 0.36))
	title.add_theme_constant_override("outline_size", 3)
	title.add_theme_color_override("font_outline_color", Color(0.10, 0.06, 0.02))
	add_child(title)

	var sub := Label.new()
	sub.position = Vector2(18, 38)
	sub.custom_minimum_size = Vector2(444, 14)
	sub.text = "双人合作像素塔防 · 跨玩家元素连携 · 双星合体大招 · 3大关卡天赋树"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 7)
	sub.add_theme_color_override("font_color", Color(0.72, 0.90, 1.0))
	add_child(sub)

	# Left Menu Panel
	var panel := PanelContainer.new()
	panel.position = Vector2(18, 58)
	panel.custom_minimum_size = Vector2(284, 174)
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	var focusables: Array[Control] = []

	var b_solo := Button.new()
	b_solo.text = "▶ 单人 + 智能 AI 搭档（推荐即刻开玩）"
	b_solo.custom_minimum_size = Vector2(268, 28)
	b_solo.add_theme_font_size_override("font_size", 8)
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
	b_local.custom_minimum_size = Vector2(268, 28)
	b_local.add_theme_font_size_override("font_size", 8)
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
	b_host.custom_minimum_size = Vector2(104, 24)
	b_host.add_theme_font_size_override("font_size", 7)
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
	b_join.pressed.connect(_on_join_lan)
	lan_row.add_child(b_join)
	focusables.append(b_join)

	var b_save := Button.new()
	b_save.text = "💾 本地存档槽位管理（累计星数: %d★）" % GameSession.meta.get_total_stars()
	b_save.custom_minimum_size = Vector2(268, 24)
	b_save.add_theme_font_size_override("font_size", 7)
	b_save.pressed.connect(func(): MoonRPG.open_save_menu("both"))
	vbox.add_child(b_save)
	focusables.append(b_save)

	_status_lbl = Label.new()
	_status_lbl.text = "提示：选择任意模式进入 3 大战役大地图与合作天赋树！"
	_status_lbl.add_theme_font_size_override("font_size", 7)
	_status_lbl.add_theme_color_override("font_color", Color(0.82, 0.90, 1.0))
	vbox.add_child(_status_lbl)

	# Bottom Adaptive Glyph Strip
	var gbar := HBoxContainer.new()
	gbar.position = Vector2(18, 242)
	gbar.add_theme_constant_override("separation", 10)
	add_child(gbar)
	for gp in [["jump", "确认/建塔"], ["guard", "切换防御塔"], ["skill_ultimate", "双星大招"], ["attack_heavy", "召波"]]:
		var badge := InputGlyphBadge.new()
		badge.action_name = gp[0]
		badge.caption = gp[1]
		badge.custom_minimum_size = Vector2(92, 18)
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
