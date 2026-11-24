extends Control
## Title & co-op lobby: animated twilight diorama (twin stars, drifting clouds, two pixel bastions, both heroes
## standing guard, embers), the game logo, and the mode menu (solo + AI / couch 2P / LAN host & join /
## settings / quit) with live control hints and connected-gamepad info. Mouse, keyboard and gamepad friendly.

var _ip_input: LineEdit
var _status: String = ""
var _status_col: Color = UIKit.TEXT_DIM
var _hint: String = ""
var _t: float = 0.0
var _stars: Array[Dictionary] = []
var _embers: Array[Dictionary] = []
var _settings: PauseMenu

const HINTS: Dictionary = {
	"solo": "你操控 P1（鼠标或手柄），AI 搭档负责 P2：自动建塔、支援金币、响应合体",
	"local": "P1：鼠标 / 手柄1   P2：方向键+Enter+右Shift / 手柄2 —— 同一屏幕并肩作战",
	"host": "在本机开放房间（端口 24560），搭档输入你的 IP 加入",
	"join": "输入房主 IP 加入，作为 P2 参战",
	"settings": "音量、屏幕震动、伤害数字",
	"quit": "下次再见，指挥官！",
}


func _ready() -> void:
	if GameSession.is_lan():
		GameSession.leave_lan()
	if not GameSession.lan_notice.is_empty():
		_status = GameSession.lan_notice
		_status_col = UIKit.BAD
		GameSession.lan_notice = ""
	for i in range(46):
		_stars.append({"pos": Vector2(randf_range(4, 476), randf_range(4, 130)), "phase": randf_range(0, TAU), "big": randf() < 0.15})
	for i in range(22):
		_embers.append({"pos": Vector2(randf_range(250, 470), randf_range(120, 250)), "vy": randf_range(-16.0, -7.0), "phase": randf_range(0, TAU)})
	_build_ui()
	_hint = HINTS["solo"]
	MoonRPG.play_bgm("bgm.village")


func _process(delta: float) -> void:
	_t += delta
	for e in _embers:
		e["phase"] = float(e["phase"]) + delta * 3.0
		var p: Vector2 = e["pos"]
		p.y += float(e["vy"]) * delta
		p.x += sin(float(e["phase"])) * 6.0 * delta
		if p.y < 90.0:
			p = Vector2(randf_range(260.0, 470.0), 250.0)
		e["pos"] = p
	queue_redraw()


func _build_ui() -> void:
	var col := VBoxContainer.new()
	col.position = Vector2(20, 94)
	col.add_theme_constant_override("separation", 4)
	add_child(col)
	var focus: Array[Control] = []

	var b_solo := UIKit.make_button("单人 + AI 搭档", Color(0.26, 0.50, 0.86), Vector2(196, 22), 9)
	b_solo.pressed.connect(func():
		GameSession.play_mode = GameSession.PlayMode.SOLO_AI
		GameSession.local_player_id = 1
		GameSession.net.close_session()
		_go_campaign())
	_hook_hint(b_solo, "solo")
	col.add_child(b_solo)
	focus.append(b_solo)

	var b_local := UIKit.make_button("同屏双人合作", Color(0.72, 0.30, 0.42), Vector2(196, 22), 9)
	b_local.pressed.connect(func():
		GameSession.play_mode = GameSession.PlayMode.LOCAL_2P
		GameSession.local_player_id = 1
		GameSession.net.close_session()
		_go_campaign())
	_hook_hint(b_local, "local")
	col.add_child(b_local)
	focus.append(b_local)

	var lan := HBoxContainer.new()
	lan.add_theme_constant_override("separation", 4)
	col.add_child(lan)
	var b_host := UIKit.make_button("局域网建房", Color(0.24, 0.56, 0.48), Vector2(62, 18), 7)
	b_host.pressed.connect(_on_host_lan)
	_hook_hint(b_host, "host")
	lan.add_child(b_host)
	focus.append(b_host)
	_ip_input = LineEdit.new()
	_ip_input.text = "127.0.0.1"
	_ip_input.custom_minimum_size = Vector2(80, 18)
	_ip_input.add_theme_font_size_override("font_size", 7)
	_ip_input.add_theme_stylebox_override("normal", UIKit.make_box(Color(0.03, 0.04, 0.08), UIKit.GOLD_DIM, 1, 3))
	_ip_input.add_theme_stylebox_override("focus", UIKit.make_box(Color(0.03, 0.04, 0.08), UIKit.GOLD, 1, 3))
	lan.add_child(_ip_input)
	var b_join := UIKit.make_button("加入", Color(0.32, 0.46, 0.70), Vector2(46, 18), 7)
	b_join.pressed.connect(_on_join_lan)
	_hook_hint(b_join, "join")
	lan.add_child(b_join)
	focus.append(b_join)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	col.add_child(row)
	var b_set := UIKit.make_button("设置", Color(0.34, 0.40, 0.56), Vector2(96, 18), 8)
	b_set.pressed.connect(func(): _settings.open_settings_only())
	_hook_hint(b_set, "settings")
	row.add_child(b_set)
	focus.append(b_set)
	var b_quit := UIKit.make_button("退出游戏", Color(0.50, 0.24, 0.28), Vector2(96, 18), 8)
	b_quit.pressed.connect(func(): get_tree().quit())
	_hook_hint(b_quit, "quit")
	row.add_child(b_quit)
	focus.append(b_quit)

	_settings = PauseMenu.new()
	add_child(_settings)
	if ThemeManager:
		ThemeManager.apply_gamepad_focus_chain(focus, false, false)
	b_solo.call_deferred("grab_focus")


func _hook_hint(b: Button, key: String) -> void:
	b.focus_entered.connect(func(): _hint = HINTS[key])
	b.mouse_entered.connect(func(): _hint = HINTS[key])


func _on_host_lan() -> void:
	if GameSession.net.host_game(24560, 1, "P1_Host"):
		GameSession.play_mode = GameSession.PlayMode.LAN_HOST
		GameSession.local_player_id = 1
		_go_campaign()
	else:
		_status = "端口 24560 被占用，无法建房"
		_status_col = UIKit.BAD
		MoonRPG.play_sfx("sfx.ui_back")


func _on_join_lan() -> void:
	var ip := _ip_input.text.strip_edges()
	if ip.is_empty():
		ip = "127.0.0.1"
	if GameSession.net.join_game(ip, 24560):
		GameSession.play_mode = GameSession.PlayMode.LAN_CLIENT
		GameSession.local_player_id = 2
		_go_campaign()
	else:
		_status = "无法连接 %s:24560" % ip
		_status_col = UIKit.BAD
		MoonRPG.play_sfx("sfx.ui_back")


func _go_campaign() -> void:
	MoonRPG.play_sfx("sfx.ui_confirm")
	SceneFader.go(get_tree(), "res://game/scenes/campaign_map.tscn")


# ------------------------------------------------------------------ drawing

func _draw() -> void:
	# sky bands
	var bands := [Color(0.04, 0.05, 0.14), Color(0.06, 0.07, 0.19), Color(0.09, 0.09, 0.25), Color(0.14, 0.11, 0.28), Color(0.22, 0.14, 0.28), Color(0.32, 0.18, 0.26), Color(0.44, 0.24, 0.24)]
	for i in range(bands.size()):
		draw_rect(Rect2(0, i * 24, 480, 25), bands[i])
	for st in _stars:
		var a := 0.3 + 0.6 * absf(sin(_t * 2.0 + float(st["phase"])))
		var p: Vector2 = st["pos"]
		if bool(st["big"]):
			draw_rect(Rect2(p - Vector2(1, 0), Vector2(3, 1)), Color(1, 1, 1, a * 0.6))
			draw_rect(Rect2(p - Vector2(0, 1), Vector2(1, 3)), Color(1, 1, 1, a * 0.6))
		draw_rect(Rect2(p, Vector2(1, 1)), Color(0.95, 0.97, 1.0, a))
	# twin stars
	var tw := 0.75 + 0.25 * sin(_t * 3.0)
	for spec in [[Vector2(392, 40), UIKit.P1], [Vector2(424, 32), UIKit.P2]]:
		var c: Color = spec[1]
		draw_circle(spec[0], 12.0, Color(c.r, c.g, c.b, 0.16 * tw))
		draw_circle(spec[0], 6.0, Color(c.r, c.g, c.b, 0.35 * tw))
		draw_circle(spec[0], 3.0, c.lightened(0.4))
	draw_line(Vector2(392, 40), Vector2(424, 32), Color(1.0, 0.94, 0.65, 0.4 * tw), 1.0)
	# clouds
	for ci in range(4):
		var cx := fmod(float(ci) * 140.0 + _t * (5.0 + ci * 1.5), 560.0) - 60.0
		var cy := 62.0 + float(ci) * 13.0
		draw_rect(Rect2(cx, cy, 52, 6), Color(0.30, 0.24, 0.40, 0.45))
		draw_rect(Rect2(cx + 8, cy - 4, 30, 5), Color(0.36, 0.28, 0.46, 0.45))
	# mountains
	draw_colored_polygon(PackedVector2Array([Vector2(0, 170), Vector2(70, 128), Vector2(140, 160), Vector2(230, 112), Vector2(320, 150), Vector2(400, 118), Vector2(480, 146), Vector2(480, 270), Vector2(0, 270)]), Color(0.10, 0.10, 0.22))
	draw_colored_polygon(PackedVector2Array([Vector2(0, 196), Vector2(110, 168), Vector2(220, 186), Vector2(330, 160), Vector2(480, 178), Vector2(480, 270), Vector2(0, 270)]), Color(0.08, 0.14, 0.16))
	draw_rect(Rect2(0, 214, 480, 56), Color(0.10, 0.20, 0.14))
	draw_rect(Rect2(0, 212, 480, 3), Color(0.20, 0.36, 0.22))

	# diorama: twin bastions + gate + heroes
	var t1 := PixelTowerSprites.get_tower_texture("barracks", 1, 3, "paladin")
	var t2 := PixelTowerSprites.get_tower_texture("barracks", 2, 3, "paladin")
	draw_texture_rect(t1, Rect2(Vector2(284, 132), Vector2(64, 80)), false)
	draw_texture_rect(t2, Rect2(Vector2(404, 132), Vector2(64, 80)), false)
	var gate := PixelTowerSprites.get_tower_texture("mage", 1, 3, "arcane")
	draw_texture_rect(gate, Rect2(Vector2(348, 124 + sin(_t * 2.0) * 1.0), Vector2(56, 70)), false)
	for i in range(2):
		var cx := 300.0 + float(i) * 132.0
		draw_circle(Vector2(cx + 16, 208), 16.0, Color(1.0, 0.55, 0.18, 0.12))
	var h1 := PixelCreepSprites.get_frame("hero_p1", 0, 1)
	var h2 := PixelCreepSprites.get_frame("hero_p2", 0, 2, true)
	var b1 := absf(sin(_t * 3.0)) * 1.5
	var b2 := absf(sin(_t * 3.0 + 1.3)) * 1.5
	_shadow(Vector2(352, 230))
	_shadow(Vector2(402, 230))
	draw_texture_rect(h1, Rect2(Vector2(336, 200 - b1), Vector2(32, 32)), false)
	draw_texture_rect(h2, Rect2(Vector2(386, 200 - b2), Vector2(32, 32)), false)
	for e in _embers:
		draw_rect(Rect2(e["pos"], Vector2(1, 1)), Color(1.0, 0.78, 0.32, 0.8))

	# logo
	var lx := 20.0
	UIKit.draw_text(self, Vector2(lx, 42), "双子堡垒", 24, UIKit.GOLD)
	UIKit.draw_text(self, Vector2(lx + 104, 42), "共守苍穹", 12, Color(0.80, 0.90, 1.0))
	UIKit.draw_text(self, Vector2(lx + 2, 56), "TWIN BASTION  ·  SKYWARD SIEGE", 6, UIKit.TEXT_DIM)
	draw_rect(Rect2(lx, 62, 196, 1), UIKit.GOLD_DIM)
	UIKit.draw_text(self, Vector2(lx, 74), "封印魔王的双星正在变暗，守塔的只有你们两个。", 7, UIKit.TEXT)
	var meta := GameSession.meta
	UIKit.draw_text(self, Vector2(lx, 86), "战役星数 %d★ · 已通关 %d/5" % [meta.get_total_stars(), _cleared_count()], 6, UIKit.GOLD_DIM)

	# hint + status + footer
	var hr := Rect2(20, 208, 250, 24)
	UIKit.draw_panel(self, hr, UIKit.GOLD_DIM)
	UIKit.draw_text(self, hr.position + Vector2(5, 10), _hint, 6, UIKit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, 242)
	var pads := Input.get_connected_joypads().size()
	var pad_txt := "已连接手柄：%d" % pads if pads > 0 else "未检测到手柄（可随时插入）"
	UIKit.draw_text(self, hr.position + Vector2(5, 20), _status if _status != "" else pad_txt, 6, _status_col if _status != "" else UIKit.TEXT_DIM)
	draw_rect(Rect2(0, 252, 480, 18), Color(0.03, 0.04, 0.09, 0.9))
	draw_rect(Rect2(0, 252, 480, 1), UIKit.GOLD_DIM)
	UIKit.draw_text(self, Vector2(8, 264), "鼠标 · 键盘 · 手柄 均可操作      Esc / B 返回", 6, UIKit.TEXT_DIM)
	UIKit.draw_text(self, Vector2(472, 264), "v1.0", 6, UIKit.TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT)


func _shadow(p: Vector2) -> void:
	var pts := PackedVector2Array()
	for i in range(12):
		var a := TAU * float(i) / 12.0
		pts.append(p + Vector2(cos(a) * 10.0, sin(a) * 3.0))
	draw_colored_polygon(pts, Color(0, 0, 0, 0.35))


func _cleared_count() -> int:
	var n := 0
	for sid in CampaignData.get_stage_ids():
		if GameSession.meta.is_stage_cleared(sid):
			n += 1
	return n
