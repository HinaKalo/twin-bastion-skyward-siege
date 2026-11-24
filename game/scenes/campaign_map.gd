extends Control
## Campaign map: baked pixel world map with 5 stage nodes (locks, stars, hard crowns, marching trail),
## a stage card with new-enemy preview, difficulty + mode (campaign / endless) selectors, a launch button,
## and the 8-node co-op talent grid. Fully usable with mouse, keyboard and gamepad.

const MAP_RECT := Rect2(8, 26, 244, 160)
const NODES: Array[Dictionary] = [
	{"id": "stage_1_twin_bridge", "pos": Vector2(42, 128), "col": Color(0.36, 0.80, 0.40)},
	{"id": "stage_2_rift_cross", "pos": Vector2(96, 86), "col": Color(0.76, 0.42, 1.0)},
	{"id": "stage_3_royal_siege", "pos": Vector2(150, 50), "col": Color(0.80, 0.80, 0.86)},
	{"id": "stage_4_frost_trail", "pos": Vector2(204, 92), "col": Color(0.70, 0.90, 1.0)},
	{"id": "stage_5_abyss_corridor", "pos": Vector2(156, 132), "col": Color(0.86, 0.30, 0.62)},
]

var _selected: String = "stage_1_twin_bridge"
var _t: float = 0.0
var _map_tex: ImageTexture
var _diff_buttons: Dictionary = {}
var _mode_buttons: Dictionary = {}
var _launch_btn: Button
var _talent_grid: GridContainer
var _stars_label: Label
var _settings: PauseMenu
var _story: StoryDialogue


func _ready() -> void:
	_selected = GameSession.selected_stage_id
	if not CampaignData.is_unlocked(_selected, GameSession.meta):
		_selected = "stage_1_twin_bridge"
	if GameSession.endless_mode and not CampaignData.is_endless_unlocked(GameSession.meta):
		GameSession.endless_mode = false
	_map_tex = _bake_map()
	_build_ui()
	_refresh()
	MoonRPG.play_bgm("bgm.village")
	if not GameSession.is_lan() and not GameSession.meta.has_seen("prologue"):
		_story.play(StoryData.PROLOGUE, func(): GameSession.meta.mark_seen("prologue"))


func _process(delta: float) -> void:
	_t += delta
	if GameSession.play_mode == GameSession.PlayMode.LAN_CLIENT:
		_launch_btn.disabled = true
		_launch_btn.text = "等待房主开战"
	elif GameSession.play_mode == GameSession.PlayMode.LAN_HOST:
		var valid := CampaignData.is_unlocked(_selected, GameSession.meta)
		_launch_btn.disabled = not valid or GameSession.net.peers.size() < 2
		_launch_btn.text = "等待搭档加入" if GameSession.net.peers.size() < 2 else "开始战斗"
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mpos := get_global_mouse_position()
		for n in NODES:
			if mpos.distance_to(MAP_RECT.position + (n["pos"] as Vector2)) <= 11.0:
				_select(str(n["id"]))
				get_viewport().set_input_as_handled()
				return
	elif event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		match (event as InputEventKey).keycode:
			KEY_ESCAPE:
				SceneFader.go(get_tree(), "res://game/scenes/title_lobby.tscn")
			KEY_PAGEUP, KEY_Q:
				_step_stage(-1)
			KEY_PAGEDOWN, KEY_E:
				_step_stage(1)
	elif event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
		match (event as InputEventJoypadButton).button_index:
			JOY_BUTTON_LEFT_SHOULDER: _step_stage(-1)
			JOY_BUTTON_RIGHT_SHOULDER: _step_stage(1)
			JOY_BUTTON_B: SceneFader.go(get_tree(), "res://game/scenes/title_lobby.tscn")


func _step_stage(d: int) -> void:
	var ids := CampaignData.get_stage_ids()
	var i := ids.find(_selected)
	for k in range(1, ids.size()):
		var j := posmod(i + d * k, ids.size())
		if CampaignData.is_unlocked(ids[j], GameSession.meta):
			_select(ids[j])
			return


func _select(sid: String) -> void:
	if not CampaignData.is_unlocked(sid, GameSession.meta):
		MoonRPG.play_sfx("sfx.ui_back")
		return
	_selected = sid
	GameSession.selected_stage_id = sid
	MoonRPG.play_sfx("sfx.ui_confirm")
	_refresh()


# ------------------------------------------------------------------ UI

func _build_ui() -> void:
	var back := UIKit.make_button("返回标题", Color(0.30, 0.40, 0.58), Vector2(58, 16), 7)
	back.position = Vector2(416, 3)
	back.pressed.connect(func(): SceneFader.go(get_tree(), "res://game/scenes/title_lobby.tscn"))
	add_child(back)
	var gear := UIKit.make_button("设置", Color(0.30, 0.40, 0.58), Vector2(34, 16), 7)
	gear.position = Vector2(378, 3)
	gear.pressed.connect(func(): _settings.open_settings_only())
	add_child(gear)
	_settings = PauseMenu.new()
	add_child(_settings)
	_story = StoryDialogue.new()
	add_child(_story)

	var replay := UIKit.make_button("剧情", Color(0.55, 0.42, 0.22), Vector2(28, 14), 6)
	replay.position = Vector2(174, 194)
	replay.pressed.connect(func():
		var intro: Array = StoryData.get_stage(_selected).get("intro", [])
		if GameSession.meta.is_stage_cleared(_selected) or GameSession.meta.has_seen(_selected):
			_story.play(intro)
		else:
			MoonRPG.play_sfx("sfx.ui_back"))
	add_child(replay)
	var lore := UIKit.make_button("序章", Color(0.55, 0.42, 0.22), Vector2(34, 16), 7)
	lore.position = Vector2(340, 3)
	lore.pressed.connect(func(): _story.play(StoryData.PROLOGUE))
	add_child(lore)

	_stars_label = UIKit.make_label("", 7, UIKit.GOLD)
	_stars_label.position = Vector2(150, 5)
	add_child(_stars_label)

	var prev := UIKit.make_button("<", Color(0.30, 0.40, 0.58), Vector2(14, 14), 7)
	prev.position = Vector2(206, 194)
	prev.pressed.connect(func(): _step_stage(-1))
	add_child(prev)
	var nxt := UIKit.make_button(">", Color(0.30, 0.40, 0.58), Vector2(14, 14), 7)
	nxt.position = Vector2(232, 194)
	nxt.pressed.connect(func(): _step_stage(1))
	add_child(nxt)

	var dx := 262.0
	var diff_keys: Array[String] = ["casual", "normal", "hard"]
	var diff_cols: Array[Color] = [UIKit.GOOD, UIKit.GOLD, UIKit.BAD]
	for i in range(3):
		var key: String = diff_keys[i]
		var b := UIKit.make_button(str(CoopTDDirector.DIFFICULTIES[key]["label"]), diff_cols[i].darkened(0.1), Vector2(52, 16), 7)
		b.position = Vector2(dx + 40 + i * 56, 42)
		b.toggle_mode = true
		b.pressed.connect(func():
			GameSession.difficulty = key
			MoonRPG.play_sfx("sfx.ui_confirm")
			_refresh())
		add_child(b)
		_diff_buttons[key] = b
	var mode_keys: Array[String] = ["campaign", "endless"]
	for i in range(2):
		var mode: String = mode_keys[i]
		var b := UIKit.make_button("战役模式" if i == 0 else "无尽模式", Color(0.30, 0.46, 0.70) if i == 0 else Color(0.55, 0.30, 0.70), Vector2(80, 16), 7)
		b.position = Vector2(dx + 40 + i * 84, 62)
		b.toggle_mode = true
		b.pressed.connect(func():
			if mode == "endless" and not CampaignData.is_endless_unlocked(GameSession.meta):
				MoonRPG.play_sfx("sfx.ui_back")
				_refresh()
				return
			GameSession.endless_mode = mode == "endless"
			MoonRPG.play_sfx("sfx.ui_confirm")
			_refresh())
		add_child(b)
		_mode_buttons[mode] = b
	_launch_btn = UIKit.make_button("出征！", Color(0.85, 0.36, 0.22), Vector2(208, 20), 10)
	_launch_btn.position = Vector2(dx, 82)
	_launch_btn.pressed.connect(_launch)
	add_child(_launch_btn)

	var reset := UIKit.make_button("洗点", Color(0.45, 0.32, 0.56), Vector2(30, 13), 6)
	reset.position = Vector2(438, 109)
	reset.pressed.connect(func():
		GameSession.meta.reset_talents()
		MoonRPG.play_sfx("sfx.ui_confirm")
		_refresh())
	add_child(reset)

	_talent_grid = GridContainer.new()
	_talent_grid.columns = 2
	_talent_grid.position = Vector2(dx, 126)
	_talent_grid.add_theme_constant_override("h_separation", 4)
	_talent_grid.add_theme_constant_override("v_separation", 3)
	add_child(_talent_grid)
	for t in MetaProgress.TALENT_DEFS:
		_talent_grid.add_child(_make_talent_card(t))
	_launch_btn.call_deferred("grab_focus")


func _make_talent_card(t: Dictionary) -> Button:
	var tid := str(t["id"])
	var b := Button.new()
	b.custom_minimum_size = Vector2(102, 30)
	b.focus_mode = Control.FOCUS_ALL
	b.set_meta("tid", tid)
	var name_l := UIKit.make_label("%s  %d★" % [str(t["name"]), int(t["cost"])], 7, UIKit.GOLD)
	name_l.position = Vector2(4, 1)
	b.add_child(name_l)
	b.set_meta("name_label", name_l)
	var desc_l := UIKit.make_label(str(t["desc"]), 6, UIKit.TEXT_DIM)
	desc_l.position = Vector2(4, 15)
	b.add_child(desc_l)
	b.pressed.connect(func():
		if GameSession.meta.unlock_talent(tid):
			MoonRPG.play_sfx("sfx.quest_clear")
		else:
			MoonRPG.play_sfx("sfx.ui_back")
		_refresh())
	return b


func _refresh() -> void:
	var meta := GameSession.meta
	_stars_label.text = "累计 %d★   可用 %d★" % [meta.get_total_stars(), meta.get_available_stars()]
	for key in _diff_buttons.keys():
		(_diff_buttons[key] as Button).button_pressed = (key == GameSession.difficulty)
	var endless_ok := CampaignData.is_endless_unlocked(meta)
	(_mode_buttons["campaign"] as Button).button_pressed = not GameSession.endless_mode
	(_mode_buttons["endless"] as Button).button_pressed = GameSession.endless_mode
	(_mode_buttons["endless"] as Button).text = "无尽模式" if endless_ok else "无尽(需通关3)"
	var unlocked := CampaignData.is_unlocked(_selected, meta)
	_launch_btn.disabled = not unlocked
	_launch_btn.text = ("无尽出征！" if GameSession.endless_mode else "出征！") if unlocked else "未解锁"
	for card in _talent_grid.get_children():
		var b := card as Button
		var tid := str(b.get_meta("tid"))
		var cost := 0
		for t in MetaProgress.TALENT_DEFS:
			if str(t["id"]) == tid:
				cost = int(t["cost"])
		var owned := meta.has_talent(tid)
		var afford := meta.get_available_stars() >= cost
		var accent := UIKit.GOOD.darkened(0.25) if owned else (UIKit.P1.darkened(0.3) if afford else Color(0.30, 0.31, 0.38))
		UIKit.style_button(b, accent, 6)
		var name_l := b.get_meta("name_label") as Label
		name_l.text = ("已解锁 · " if owned else "") + "%s  %d★" % [_talent_name(tid), cost]
		name_l.add_theme_color_override("font_color", UIKit.GOOD if owned else (UIKit.GOLD if afford else UIKit.TEXT_DIM))
	queue_redraw()


func _talent_name(tid: String) -> String:
	for t in MetaProgress.TALENT_DEFS:
		if str(t["id"]) == tid:
			return str(t["name"])
	return tid


func _launch() -> void:
	if not CampaignData.is_unlocked(_selected, GameSession.meta):
		return
	MoonRPG.play_sfx("sfx.ui_confirm")
	if GameSession.is_lan():
		GameSession.request_lan_match(_selected)
		return
	GameSession.selected_stage_id = _selected
	SceneFader.go(get_tree(), "res://game/scenes/coop_battle.tscn")


# ------------------------------------------------------------------ drawing

func _draw() -> void:
	draw_rect(Rect2(0, 0, 480, 270), Color(0.04, 0.05, 0.11))
	draw_rect(Rect2(0, 0, 480, 22), Color(0.05, 0.06, 0.13))
	draw_rect(Rect2(0, 21, 480, 1), UIKit.GOLD_DIM)
	PixelIcons.draw_icon(self, "flag", Vector2(12, 11), 1, UIKit.GOLD)
	UIKit.draw_text(self, Vector2(20, 15), "战役地图", 9, UIKit.GOLD)
	UIKit.draw_text(self, Vector2(64, 15), GameSession.get_mode_label(), 7, UIKit.TEXT_DIM)
	PixelIcons.draw_icon(self, "star", Vector2(144, 11))

	UIKit.draw_panel(self, MAP_RECT.grow(2), UIKit.GOLD_DIM)
	draw_texture(_map_tex, MAP_RECT.position)
	_draw_map_overlay()

	var card := Rect2(8, 190, 244, 74)
	UIKit.draw_panel(self, card, UIKit.GOLD_DIM)
	var st := CampaignData.get_stage_by_id(_selected)
	var meta := GameSession.meta
	UIKit.draw_text(self, card.position + Vector2(6, 13), str(st["name"]), 9, UIKit.GOLD)
	var brief := str(StoryData.get_stage(_selected).get("briefing", st["subtitle"]))
	var blines := _wrap(brief, 6, 232.0)
	for li in range(mini(2, blines.size())):
		UIKit.draw_text(self, card.position + Vector2(6, 23 + li * 8), blines[li], 6, Color(0.92, 0.88, 0.78))
	var stars := meta.get_stage_stars(_selected)
	for i in range(3):
		PixelIcons.draw_icon(self, "star" if i < stars else "star_empty", card.position + Vector2(10 + i * 11, 45))
	if meta.hard_clears.has(_selected):
		PixelIcons.draw_icon(self, "crown", card.position + Vector2(46, 45))
	var best := int(meta.endless_best.get(_selected, 0))
	UIKit.draw_text(self, card.position + Vector2(58, 48), "%d 波 · 无尽最佳 %s" % [(st["waves"] as Array).size(), ("第%d波" % best) if best > 0 else "—"], 6, UIKit.TEXT_DIM)
	UIKit.draw_text(self, card.position + Vector2(6, 64), "新敌人", 6, UIKit.BAD)
	var ex := card.position.x + 32.0
	for eid in st.get("intro_enemies", []):
		var tex := PixelCreepSprites.get_frame(str(eid), int(_t * 4.0))
		var w := float(PixelCreepSprites.get_width(str(eid)))
		var sz := 14.0 if w <= 16 else 16.0
		var br := Rect2(Vector2(ex, card.position.y + 54), Vector2(17, 17))
		draw_rect(br, Color(0.02, 0.03, 0.06, 0.8))
		draw_rect(br, Color(UIKit.BAD.r, UIKit.BAD.g, UIKit.BAD.b, 0.4), false, 1.0)
		draw_texture_rect(tex, Rect2(br.get_center() - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), false)
		ex += 19.0
	UIKit.draw_text(self, Vector2(card.end.x - 4, card.position.y + 70), "Q/E · LB/RB 切换", 5, UIKit.TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT)

	var rp := Rect2(258, 26, 216, 238)
	UIKit.draw_panel(self, rp, UIKit.GOLD_DIM)
	var dinfo: Dictionary = CoopTDDirector.DIFFICULTIES[GameSession.difficulty]
	var dtxt := "敌人生命 ×%.2f · 城防 %+d · 开局金币 %+d" % [float(dinfo["hp_mult"]), int(dinfo["lives_add"]), int(dinfo["gold_add"])]
	UIKit.draw_text(self, Vector2(264, 36), dtxt, 6, UIKit.TEXT_DIM)
	UIKit.draw_text(self, Vector2(264, 53), "难度", 7, UIKit.TEXT)
	UIKit.draw_text(self, Vector2(264, 73), "模式", 7, UIKit.TEXT)
	draw_rect(Rect2(262, 106, 208, 1), Color(UIKit.GOLD_DIM.r, UIKit.GOLD_DIM.g, UIKit.GOLD_DIM.b, 0.5))
	UIKit.draw_text(self, Vector2(264, 119), "合作天赋", 8, UIKit.GOLD)
	UIKit.draw_text(self, Vector2(306, 119), "用星星解锁永久加成", 6, UIKit.TEXT_DIM)


func _wrap(text: String, size: int, width: float) -> Array[String]:
	var out: Array[String] = []
	var cur := ""
	for ch in text:
		if UIKit.text_width(cur + ch, size) > width and cur != "":
			out.append(cur)
			cur = ""
		cur += ch
	if cur != "":
		out.append(cur)
	return out


func _draw_map_overlay() -> void:
	var o := MAP_RECT.position
	var meta := GameSession.meta
	for i in range(NODES.size() - 1):
		var a: Vector2 = o + (NODES[i]["pos"] as Vector2)
		var b: Vector2 = o + (NODES[i + 1]["pos"] as Vector2)
		var open := CampaignData.is_unlocked(str(NODES[i + 1]["id"]), meta)
		var steps := int(a.distance_to(b) / 6.0)
		for k in range(1, steps):
			var p := a.lerp(b, float(k) / float(steps))
			var lit := open and fmod(_t * 2.0 - float(k) * 0.15, 1.0) < 0.5
			draw_rect(Rect2(p - Vector2(1, 1), Vector2(2, 2)), UIKit.GOLD if lit else (UIKit.GOLD_DIM if open else Color(0.3, 0.3, 0.35)))
	for ni in range(NODES.size()):
		var n: Dictionary = NODES[ni]
		var sid := str(n["id"])
		var p: Vector2 = o + (n["pos"] as Vector2)
		var open := CampaignData.is_unlocked(sid, meta)
		var sel := sid == _selected
		var col: Color = n["col"] if open else Color(0.35, 0.36, 0.42)
		if sel:
			draw_arc(p, 11.0 + 1.5 * sin(_t * 5.0), 0.0, TAU, 24, UIKit.GOLD, 1.5)
		draw_circle(p + Vector2(0, 1), 8.0, Color(0, 0, 0, 0.5))
		draw_circle(p, 7.5, UIKit.INK)
		draw_circle(p, 6.5, col.darkened(0.2))
		draw_circle(p - Vector2(1.5, 1.5), 2.5, col.lightened(0.3))
		if not open:
			PixelIcons.draw_icon(self, "lock", p)
			continue
		UIKit.draw_text(self, p + Vector2(-6, 3), str(ni + 1), 8, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 12)
		var stars := meta.get_stage_stars(sid)
		for k in range(3):
			draw_texture_rect(PixelIcons.get_icon("star" if k < stars else "star_empty"), Rect2(p + Vector2(-11 + k * 7, 8), Vector2(7, 7)), false)
		if meta.hard_clears.has(sid):
			draw_texture_rect(PixelIcons.get_icon("crown"), Rect2(p + Vector2(-4, -15), Vector2(9, 9)), false)


func _bake_map() -> ImageTexture:
	var w := int(MAP_RECT.size.x)
	var h := int(MAP_RECT.size.y)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = 4242
	noise.frequency = 0.03
	noise.fractal_octaves = 4
	var jitter := FastNoiseLite.new()
	jitter.seed = 77
	jitter.frequency = 0.08
	var biome_cols: Array = [
		[Color(0.24, 0.48, 0.24), Color(0.30, 0.56, 0.28)],
		[Color(0.26, 0.20, 0.34), Color(0.32, 0.24, 0.42)],
		[Color(0.40, 0.40, 0.44), Color(0.48, 0.48, 0.52)],
		[Color(0.82, 0.88, 0.96), Color(0.92, 0.95, 1.0)],
		[Color(0.18, 0.08, 0.20), Color(0.26, 0.10, 0.28)],
	]
	for y in range(h):
		for x in range(w):
			var p := Vector2(x, y)
			var falloff := 1.0 - clampf(p.distance_to(Vector2(w * 0.52, h * 0.55)) / (w * 0.52), 0.0, 1.0)
			var land := noise.get_noise_2d(x, y) * 0.5 + falloff * 1.1 - 0.18
			var bay := float(TerrainBaker.BAYER[(y % 4) * 4 + (x % 4)]) / 16.0
			var c: Color
			if land < 0.0:
				var deep := clampf(-land * 3.0, 0.0, 1.0)
				c = Color(0.10, 0.24, 0.42).lerp(Color(0.06, 0.14, 0.28), deep)
				if (x + y * 3) % 23 == 0 and deep > 0.3:
					c = Color(0.25, 0.45, 0.62)
			elif land < 0.06:
				c = Color(0.70, 0.62, 0.42)
			else:
				var best := 0
				var best_d := INF
				for i in range(NODES.size()):
					var d := p.distance_to(NODES[i]["pos"]) + jitter.get_noise_2d(x, y) * 18.0
					if d < best_d:
						best_d = d
						best = i
				var pair: Array = biome_cols[best]
				c = pair[0] if (noise.get_noise_2d(x * 3, y * 3) * 0.5 + 0.5 + (bay - 0.5) * 0.3) < 0.5 else pair[1]
				if land > 0.55:
					c = c.lightened(0.12)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)
