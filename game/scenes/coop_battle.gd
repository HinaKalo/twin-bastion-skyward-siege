extends Node2D
## 《双子堡垒：共守苍穹》 — Full Commercial 2-Player Co-op Tower Defense Battlefield
## Supports Solo+AI Partner, Local 2P Couch Co-op, and ENet LAN Co-op via `CoopTDDirector`.

const RETRO_DIR := "res://content/packs/jrpg_retro/"

var director := CoopTDDirector.new()
var ai_partner := CoopAIPartner.new()
var ai_enabled: bool = true

var _tower_types: Array[String] = ["arrow", "mage", "frost", "barracks"]
var _p1_tower: String = "arrow"
var _p2_tower: String = "barracks"
var _p1_pad_idx: int = 0
var _p2_pad_idx: int = 4

var _speed_mult: float = 1.0
var _is_paused: bool = false
var _is_finished: bool = false
var _flow_t: float = 0.0
var _ult_flash: float = 0.0
var _banner_ttl: float = 0.0
var _tutorial_step: int = 0 # 0=P1 build tower, 1=call wave 1, 2=done

var _shots: Array[Dictionary] = []
var _tex_cache: Dictionary = {}

var _hud_top: Label
var _guide_banner: Label
var _guide_beacon: ObjectiveBeacon2D
var _tower_btns: Dictionary = {}
var _ult_btn: Button
var _ai_btn: Button
var _speed_btn: Button
var _wave_btn: Button
var _result_panel: StageResultPanel


func _ready() -> void:
	ai_enabled = GameSession.is_ai_partner_enabled()
	var stage := CampaignData.get_stage_by_id(GameSession.selected_stage_id)
	director.setup_stage(stage, GameSession.meta)
	director.banner_event.connect(_show_banner)
	director.synchro_unleashed.connect(func(_h: int):
		_ult_flash = 0.65
		MoonRPG.play_sfx("sfx.quest_clear")
	)
	director.engine.tower_fired.connect(func(t: Dictionary, tgt: Dictionary, _dmg: float):
		var col := Color(0.55, 0.92, 1.0) if str(t["tower_id"]) == "frost" else (Color(0.86, 0.50, 1.0) if str(t["tower_id"]) == "mage" else Color(1.0, 0.94, 0.45))
		_shots.append({"from": t["pos"], "to": tgt["pos"], "color": col, "ttl": 0.14})
	)
	director.engine.lives_changed.connect(func(rem: int):
		if rem <= 0:
			_finish_stage(false)
	)
	if GameSession.net != null and not GameSession.net.command_received.is_connected(_on_net_command):
		GameSession.net.command_received.connect(_on_net_command)

	_p1_pad_idx = 0
	_p2_pad_idx = mini(director.pads.size() - 1, 4)

	_build_ui()
	_guide_beacon = ObjectiveBeacon2D.new()
	_guide_beacon.pad_size = Vector2(30, 30)
	_guide_beacon.badge_y_offset = -24.0
	add_child(_guide_beacon)
	_update_guide()
	MoonRPG.play_bgm("bgm.forest")
	_refresh_hud()


func _exit_tree() -> void:
	if GameSession.net != null and GameSession.net.command_received.is_connected(_on_net_command):
		GameSession.net.command_received.disconnect(_on_net_command)


func _retro_tex(fname: String) -> Texture2D:
	if _tex_cache.has(fname):
		return _tex_cache[fname]
	var full := RETRO_DIR + fname
	var tex: Texture2D = load(full) if ResourceLoader.exists(full) else null
	_tex_cache[fname] = tex
	return tex


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var top_bg := ColorRect.new()
	top_bg.size = Vector2(480, 28)
	top_bg.color = Color(0.05, 0.09, 0.22, 0.95)
	layer.add_child(top_bg)
	var sep := ColorRect.new()
	sep.position = Vector2(0, 27)
	sep.size = Vector2(480, 1.5)
	sep.color = Color(0.86, 0.92, 1.0, 0.85)
	layer.add_child(sep)

	_hud_top = Label.new()
	_hud_top.position = Vector2(6, 2)
	_hud_top.custom_minimum_size = Vector2(468, 24)
	_hud_top.add_theme_font_size_override("font_size", 8)
	layer.add_child(_hud_top)

	# Guide / Event Pill (strictly click-through)
	var guide_bg := ColorRect.new()
	guide_bg.position = Vector2(14, 30)
	guide_bg.size = Vector2(452, 16)
	guide_bg.color = Color(0.05, 0.07, 0.14, 0.80)
	guide_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(guide_bg)

	_guide_banner = Label.new()
	_guide_banner.position = Vector2(18, 31)
	_guide_banner.custom_minimum_size = Vector2(444, 14)
	_guide_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_guide_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_guide_banner.add_theme_font_size_override("font_size", 7)
	_guide_banner.add_theme_color_override("font_color", Color(1.0, 0.94, 0.30))
	_guide_banner.add_theme_constant_override("outline_size", 2)
	_guide_banner.add_theme_color_override("font_outline_color", Color(0.06, 0.04, 0.02))
	layer.add_child(_guide_banner)

	# Bottom Command Dock
	var bot_bg := ColorRect.new()
	bot_bg.position = Vector2(0, 238)
	bot_bg.size = Vector2(480, 32)
	bot_bg.color = Color(0.05, 0.09, 0.22, 0.95)
	layer.add_child(bot_bg)
	var bot_sep := ColorRect.new()
	bot_sep.position = Vector2(0, 238)
	bot_sep.size = Vector2(480, 1.5)
	bot_sep.color = Color(0.75, 0.85, 1.0, 0.75)
	layer.add_child(bot_sep)

	var row := HBoxContainer.new()
	row.position = Vector2(4, 243)
	row.add_theme_constant_override("separation", 3)
	layer.add_child(row)

	for pair in [["arrow", "1箭"], ["mage", "2法"], ["frost", "3冰"], ["barracks", "4兵"]]:
		var b := Button.new()
		b.text = "%s%d" % [pair[1], director.get_tower_cost(pair[0])]
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 7)
		var tid: String = pair[0]
		b.pressed.connect(func(): _p1_tower = tid; _refresh_hud())
		row.add_child(b)
		_tower_btns[tid] = b

	var b_gold := Button.new()
	b_gold.text = "💰转50G"
	b_gold.focus_mode = Control.FOCUS_NONE
	b_gold.add_theme_font_size_override("font_size", 7)
	b_gold.pressed.connect(func(): _dispatch_cmd({"player_id": GameSession.local_player_id, "action": "transfer_gold", "amount": 50}))
	row.add_child(b_gold)

	_ult_btn = Button.new()
	_ult_btn.text = "☄双星0%"
	_ult_btn.focus_mode = Control.FOCUS_NONE
	_ult_btn.add_theme_font_size_override("font_size", 7)
	_ult_btn.pressed.connect(func(): _dispatch_cmd({"player_id": GameSession.local_player_id, "action": "synchro_ult"}))
	row.add_child(_ult_btn)

	_ai_btn = Button.new()
	_ai_btn.text = "AI:开" if ai_enabled else "AI:关"
	_ai_btn.focus_mode = Control.FOCUS_NONE
	_ai_btn.add_theme_font_size_override("font_size", 7)
	_ai_btn.pressed.connect(func():
		ai_enabled = not ai_enabled
		_ai_btn.text = "AI:开" if ai_enabled else "AI:关"
	)
	row.add_child(_ai_btn)

	_speed_btn = Button.new()
	_speed_btn.text = "1x"
	_speed_btn.focus_mode = Control.FOCUS_NONE
	_speed_btn.add_theme_font_size_override("font_size", 7)
	_speed_btn.pressed.connect(_cycle_speed)
	row.add_child(_speed_btn)

	_wave_btn = Button.new()
	_wave_btn.text = "▶召波"
	_wave_btn.focus_mode = Control.FOCUS_NONE
	_wave_btn.add_theme_font_size_override("font_size", 7)
	_wave_btn.pressed.connect(func(): _dispatch_cmd({"player_id": GameSession.local_player_id, "action": "call_wave"}))
	row.add_child(_wave_btn)

	var b_map := Button.new()
	b_map.text = "地图"
	b_map.focus_mode = Control.FOCUS_NONE
	b_map.add_theme_font_size_override("font_size", 7)
	b_map.pressed.connect(func(): get_tree().change_scene_to_file("res://game/scenes/campaign_map.tscn"))
	row.add_child(b_map)

	_result_panel = StageResultPanel.new()
	_result_panel.replay_requested.connect(func(): get_tree().reload_current_scene())
	_result_panel.continue_requested.connect(func(): get_tree().change_scene_to_file("res://game/scenes/campaign_map.tscn"))
	add_child(_result_panel)


func _cycle_speed() -> void:
	if _is_paused:
		_is_paused = false
		_speed_mult = 1.0
	elif _speed_mult < 1.5:
		_speed_mult = 2.0
	else:
		_is_paused = true
	_speed_btn.text = "暂停" if _is_paused else ("2x" if _speed_mult > 1.5 else "1x")


func _dispatch_cmd(cmd: Dictionary) -> void:
	if _is_finished:
		return
	if GameSession.play_mode == GameSession.PlayMode.LAN_HOST or GameSession.play_mode == GameSession.PlayMode.LAN_CLIENT:
		GameSession.net.send_command("td_cmd", cmd)
	else:
		_apply_cmd(cmd)


func _on_net_command(_sender: int, cmd_type: String, payload: Dictionary) -> void:
	if cmd_type == "td_cmd":
		_apply_cmd(payload)


func _apply_cmd(cmd: Dictionary) -> void:
	var res := director.execute_command(cmd)
	var act := str(cmd.get("action", ""))
	if bool(res.get("ok", false)):
		MoonRPG.play_sfx("sfx.ui_confirm")
		if act == "build_or_upgrade" and _tutorial_step == 0:
			_tutorial_step = 1
			_update_guide()
		elif act == "call_wave" and _tutorial_step < 2:
			_tutorial_step = 2
			_update_guide()
	else:
		if res.has("reason"):
			_show_banner("⚠ " + str(res["reason"]), Color(1.0, 0.45, 0.35))
			MoonRPG.play_sfx("sfx.hurt")
	_refresh_hud()


func _show_banner(text: String, col: Color = Color(1.0, 0.94, 0.30)) -> void:
	if _guide_banner == null:
		return
	_guide_banner.text = text
	_guide_banner.add_theme_color_override("font_color", col)
	_banner_ttl = 3.2


func _update_guide() -> void:
	if _guide_banner == null or _guide_beacon == null:
		return
	_guide_banner.add_theme_color_override("font_color", Color(1.0, 0.94, 0.30))
	match _tutorial_step:
		0:
			if not director.pads.is_empty():
				_guide_beacon.point_to(director.pads[0]["pos"], "▼ P1点此建塔 ▼")
			_guide_banner.text = "★ 合作引导 [1/2]：左键点击蓝色高亮塔位建塔！P2(AI或方向键+Enter)将守卫南路并与你触发连携！"
		1:
			_guide_beacon.clear_target()
			_guide_banner.text = "★ 合作引导 [2/2]：防线就绪！按 [Space] 或点击【▶召波】开始战斗！相邻建不同塔可激活发光连携！"
		_:
			_guide_beacon.clear_target()
			_guide_banner.text = "🤝 提示：P1×P2相邻建【寒冰+法师】触发冰火超载，满100%按【☄双星】释放全屏合体大招！"


func _unhandled_input(event: InputEvent) -> void:
	if _is_finished:
		return
	var local_p := GameSession.local_player_id

	if event is InputEventMouseMotion:
		var mpos := InputManager.get_canvas_mouse_pos(self)
		for i in range(director.pads.size()):
			if mpos.distance_to(director.pads[i]["pos"]) <= 22.0:
				_p1_pad_idx = i
				break
		return

	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mb := event as InputEventMouseButton
		var mpos := InputManager.get_canvas_mouse_pos(self)
		if mpos.y < 30.0 or mpos.y > 238.0:
			return
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_dispatch_cmd({"player_id": local_p, "action": "rally_hero", "x": mpos.x, "y": mpos.y})
			get_viewport().set_input_as_handled()
			return
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_dispatch_cmd({"player_id": local_p, "action": "ping", "x": mpos.x, "y": mpos.y, "label": "⚠ P%d请求支援!" % local_p})
			get_viewport().set_input_as_handled()
			return
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			for i in range(director.pads.size()):
				if mpos.distance_to(director.pads[i]["pos"]) <= 22.0:
					_p1_pad_idx = i
					_dispatch_cmd({
						"player_id": local_p, "action": "build_or_upgrade",
						"pad_id": str(director.pads[i]["id"]), "tower_id": _p1_tower,
					})
					get_viewport().set_input_as_handled()
					return

	elif event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		var kc := (event as InputEventKey).keycode
		match kc:
			KEY_1: _p1_tower = "arrow"; _refresh_hud()
			KEY_2: _p1_tower = "mage"; _refresh_hud()
			KEY_3: _p1_tower = "frost"; _refresh_hud()
			KEY_4: _p1_tower = "barracks"; _refresh_hud()
			KEY_SPACE: _dispatch_cmd({"player_id": local_p, "action": "call_wave"})
			KEY_T: _dispatch_cmd({"player_id": local_p, "action": "transfer_gold", "amount": 50})
			KEY_U: _dispatch_cmd({"player_id": local_p, "action": "synchro_ult"})
			KEY_P:
				var mp := InputManager.get_canvas_mouse_pos(self)
				_dispatch_cmd({"player_id": local_p, "action": "ping", "x": mp.x, "y": mp.y, "label": "⚠ P%d标记!" % local_p})
			# Local 2P Dedicated P2 Controls (Arrow Keys + Enter + M + G + O)
			KEY_LEFT, KEY_UP:
				if not ai_enabled and not director.pads.is_empty():
					_p2_pad_idx = (_p2_pad_idx - 1 + director.pads.size()) % director.pads.size()
			KEY_RIGHT, KEY_DOWN:
				if not ai_enabled and not director.pads.is_empty():
					_p2_pad_idx = (_p2_pad_idx + 1) % director.pads.size()
			KEY_ENTER, KEY_KP_ENTER:
				if not ai_enabled and not director.pads.is_empty():
					_dispatch_cmd({
						"player_id": 2, "action": "build_or_upgrade",
						"pad_id": str(director.pads[_p2_pad_idx]["id"]), "tower_id": _p2_tower,
					})
			KEY_M:
				var idx := _tower_types.find(_p2_tower)
				_p2_tower = _tower_types[(idx + 1) % _tower_types.size()]
				_show_banner("P2 切换选塔：%s" % _p2_tower, Color(1.0, 0.58, 0.58))
			KEY_G:
				if not ai_enabled:
					_dispatch_cmd({"player_id": 2, "action": "transfer_gold", "amount": 50})
			KEY_O:
				if not ai_enabled:
					_dispatch_cmd({"player_id": 2, "action": "synchro_ult"})


func _process(delta: float) -> void:
	if _is_finished:
		return
	_flow_t += delta
	_ult_flash = maxf(0.0, _ult_flash - delta)
	if _banner_ttl > 0.0:
		_banner_ttl -= delta
		if _banner_ttl <= 0.0:
			_update_guide()

	if not _is_paused:
		var dt := delta * _speed_mult
		director.tick(dt)
		if ai_enabled and GameSession.play_mode != GameSession.PlayMode.LAN_CLIENT:
			ai_partner.tick(dt, director)
		if director.all_waves_done and director.engine.creeps.is_empty() and director.engine.lives > 0:
			_finish_stage(true)

	for i in range(_shots.size() - 1, -1, -1):
		_shots[i]["ttl"] = float(_shots[i]["ttl"]) - delta
		if float(_shots[i]["ttl"]) <= 0.0:
			_shots.remove_at(i)

	_refresh_hud()
	queue_redraw()


func _finish_stage(won: bool) -> void:
	if _is_finished:
		return
	_is_finished = true
	MoonRPG.play_sfx("sfx.quest_clear" if won else "sfx.hurt")
	var stars := 0
	if won:
		stars = GameSession.meta.record_stage_clear(str(director.stage_def["id"]), director.engine.lives, int(director.stage_def.get("lives", 20)))
	var grade := "S" if stars == 3 else ("A" if stars == 2 else ("B" if won else "D"))
	_result_panel.show_result({
		"won": won, "grade": grade, "collected": stars, "total_collectibles": 3,
		"elapsed_sec": float(director.wave_dir.current_wave_index + 1), "no_hit": director.engine.lives >= 20,
	}, "双子大捷！获得 %d★（可前往大地图点亮合作天赋）" % stars, "王城防线被攻破…调整双人连携再战！")


func _refresh_hud() -> void:
	if _hud_top == null:
		return
	_hud_top.text = "【%s】 P1(蓝):%dG | 城防:%d/20 波:%d/%d 连携:%d条 | P2(红):%dG (%s)\nP1:左键建/升 右键英雄 T转账 U大招 | P2:%s" % [
		str(director.stage_def.get("name", "双子堡垒")),
		int(director.gold[1]), director.engine.lives,
		maxi(0, director.wave_dir.current_wave_index + 1), director.wave_dir.get_total_waves(),
		director.combo_links.size(), int(director.gold[2]),
		("AI搭档" if ai_enabled else "玩家操控"),
		("AI自动协作中" if ai_enabled else "方向键选位 Enter建塔 M换塔 G转账 O大招")
	]
	for tid in _tower_btns.keys():
		(_tower_btns[tid] as Button).modulate = Color(1.0, 0.94, 0.30) if tid == _p1_tower else Color(0.84, 0.88, 0.96)
	if _ult_btn != null:
		var pct := int(director.synchro_charge)
		_ult_btn.text = "☄双星就绪!" if pct >= 100 else "☄双星%d%%" % pct
		_ult_btn.modulate = Color(1.0, 0.45, 0.96) if pct >= 100 else Color(0.75, 0.78, 0.86)
	if _wave_btn != null:
		_wave_btn.modulate = Color(1.0, 0.92, 0.28) if _tutorial_step == 1 else Color.WHITE


func _draw() -> void:
	var font := ThemeManager.get_font() if ThemeManager else ThemeDB.fallback_font

	# 1. Tiled Pixel Meadow
	draw_rect(Rect2(0, 28, 480, 210), Color(0.15, 0.28, 0.16))
	var mtex := _retro_tex("tile_meadow.png")
	if mtex != null:
		for tx in range(0, 480, 32):
			for ty in range(28, 240, 32):
				draw_texture_rect(mtex, Rect2(Vector2(tx, ty), Vector2(32, 32)), false)

	# 2. Multi-Lane Dirt Roads + Flowing Directional Chevrons
	for lane in director.engine.lanes.values():
		var l := lane as TDPathLane
		if l.waypoints.size() >= 2:
			draw_polyline(l.waypoints, Color(0.28, 0.20, 0.12), 23.0)
			draw_polyline(l.waypoints, Color(0.56, 0.44, 0.28), 17.0)
			var total_len: float = l.total_length
			if total_len > 24.0:
				var spacing := 44.0
				var d := fmod(_flow_t * 28.0, spacing)
				while d < total_len - 18.0:
					var p1 := l.get_point_at_progress(d / total_len)
					var p2 := l.get_point_at_progress(minf(total_len, d + 4.0) / total_len)
					var dir := (p2 - p1).normalized()
					var perp := Vector2(-dir.y, dir.x)
					draw_polyline(PackedVector2Array([p1 - dir * 2.5 + perp * 3.8, p1 + dir * 4.2, p1 - dir * 2.5 - perp * 3.8]), Color(1.0, 0.92, 0.55, 0.58), 1.5)
					d += spacing

	# 3. Royal Castle Gatehouse
	var gate_tex := _retro_tex("house_royal_gatehouse.png")
	if gate_tex != null:
		draw_texture_rect(gate_tex, Rect2(Vector2(412, 96), Vector2(64, 74)), false)

	# 4. Build Pads (Blue=P1, Red=P2, Gold=Shared)
	for i in range(director.pads.size()):
		var pad: Dictionary = director.pads[i]
		var pp: Vector2 = pad["pos"]
		var hint := int(pad.get("owner_hint", 0))
		var base_col := Color(0.32, 0.72, 1.0) if hint == 1 else (Color(1.0, 0.42, 0.45) if hint == 2 else Color(1.0, 0.88, 0.30))
		if not director.pad_to_tower_uid.has(str(pad["id"])):
			draw_circle(pp, 11.0, Color(0.16, 0.18, 0.22, 0.78))
			draw_circle(pp, 8.5, Color(base_col.r, base_col.g, base_col.b, 0.25))
			draw_line(pp + Vector2(-4, 0), pp + Vector2(4, 0), base_col, 1.4)
			draw_line(pp + Vector2(0, -4), pp + Vector2(0, 4), base_col, 1.4)
		if i == _p1_pad_idx:
			draw_arc(pp, 15.0, 0.0, TAU, 20, Color(0.42, 0.88, 1.0), 2.4)
		if not ai_enabled and i == _p2_pad_idx:
			draw_arc(pp, 17.5, 0.0, TAU, 20, Color(1.0, 0.40, 0.45), 2.2)

	# 5. Glowing Cross-Player Co-op Tower Combo Energy Lines!
	for link in director.combo_links:
		var a: Vector2 = link["from_pos"]
		var b: Vector2 = link["to_pos"]
		var lcol: Color = link["color"]
		var pulse := 0.6 + 0.4 * sin(_flow_t * 7.0)
		draw_line(a, b, Color(lcol.r, lcol.g, lcol.b, 0.35 * pulse), 5.0)
		draw_line(a, b, Color(lcol.r, lcol.g, lcol.b, 0.95), 1.8)
		var mid := (a + b) * 0.5
		draw_string(font, mid + Vector2(-30, -4), str(link["label"]), HORIZONTAL_ALIGNMENT_CENTER, 60, 6, lcol)

	# 6. Towers with P1 (Blue) / P2 (Red) Ownership Badges
	for uid in director.engine.towers.keys():
		var t: Dictionary = director.engine.towers[uid]
		var p: Vector2 = t["pos"]
		var owner := int(director.tower_owners.get(uid, 1))
		var ocol := Color(0.32, 0.78, 1.0) if owner == 1 else Color(1.0, 0.38, 0.42)
		var tid := str(t["tower_id"])
		draw_circle(p + Vector2(0, 8), 11.5, Color(ocol.r, ocol.g, ocol.b, 0.42))
		var tcol := Color(0.40, 0.82, 0.98) if tid == "frost" else (Color(0.68, 0.38, 0.95) if tid == "mage" else (Color(0.62, 0.64, 0.70) if tid == "barracks" else Color(0.62, 0.42, 0.22)))
		draw_rect(Rect2(p - Vector2(9, 10), Vector2(18, 18)), tcol)
		draw_rect(Rect2(p - Vector2(9, 10), Vector2(18, 18)), ocol, false, 1.8)
		var tname := "箭" if tid == "arrow" else ("法" if tid == "mage" else ("冰" if tid == "frost" else "兵"))
		draw_string(font, p + Vector2(-20, 18), "P%d%sLv%d" % [owner, tname, int(t["level"])], HORIZONTAL_ALIGNMENT_CENTER, 40, 6, ocol)

	# 7. Dual Heroes & Barracks Soldiers
	var guard_tex := _retro_tex("npc_guard.png")
	var hero_tex := _retro_tex("hero_ranger.png")
	for s in director.engine.soldiers:
		if float(s["hp"]) <= 0.0:
			continue
		var sp: Vector2 = s["pos"]
		if bool(s["is_hero"]):
			var is_p1 := str(s.get("name", "")).begins_with("P1")
			var tex := hero_tex if is_p1 else guard_tex
			if tex != null:
				draw_texture_rect(tex, Rect2(sp - Vector2(13, 16), Vector2(26, 26)), false)
			draw_arc(sp + Vector2(0, 6), 10.0, 0.0, TAU, 14, Color(0.35, 0.85, 1.0) if is_p1 else Color(1.0, 0.38, 0.42), 1.8)
		elif guard_tex != null:
			draw_texture_rect(guard_tex, Rect2(sp - Vector2(9, 11), Vector2(18, 18)), false)
		var shp := clampf(float(s["hp"]) / maxf(1.0, float(s["max_hp"])), 0.0, 1.0)
		draw_rect(Rect2(sp.x - 8, sp.y - 13, 16 * shp, 2.2), Color(0.35, 0.98, 0.50))

	# 8. Creeps (Ground / Flapping Bats / Warlord & Obsidian Bosses)
	for c in director.engine.creeps:
		var cp: Vector2 = c["pos"]
		var eid := str(c["enemy_id"])
		var is_fly := bool(c["is_flying"])
		var dp := cp + (Vector2(0, -10) if is_fly else Vector2.ZERO)
		if is_fly:
			draw_circle(cp + Vector2(0, 4), 4.5, Color(0, 0, 0, 0.32))
			var wy := sin(_flow_t * 14.0 + cp.x * 0.2) * 4.0
			draw_polygon(PackedVector2Array([dp, dp + Vector2(-9, -2 + wy), dp + Vector2(-4, 4)]), PackedColorArray([Color(0.58, 0.22, 0.80)]))
			draw_polygon(PackedVector2Array([dp, dp + Vector2(9, -2 + wy), dp + Vector2(4, 4)]), PackedColorArray([Color(0.58, 0.22, 0.80)]))
			draw_circle(dp, 4.0, Color(0.80, 0.40, 0.98))
		else:
			var tname := "boss_obsidian_clean.png" if eid == "boss_obsidian" else ("enemy_goblin.png" if (eid == "goblin" or eid == "boss_warlord") else ("enemy_wolf.png" if eid == "wolf" else "enemy_slime.png"))
			var ctex := _retro_tex(tname)
			var sz := Vector2(34, 34) if eid.begins_with("boss") else Vector2(21, 21)
			if ctex != null:
				draw_texture_rect(ctex, Rect2(dp - sz * 0.5, sz), false)
		var hp_pct := clampf(float(c["hp"]) / maxf(1.0, float(c["max_hp"])), 0.0, 1.0)
		var bw := 26.0 if eid.begins_with("boss") else 15.0
		draw_rect(Rect2(dp.x - bw * 0.5, dp.y - 14, bw, 2.8), Color(0.1, 0.1, 0.15))
		draw_rect(Rect2(dp.x - bw * 0.5, dp.y - 14, bw * hp_pct, 2.8), Color(1.0, 0.30, 0.34))

	# 9. Projectiles, Tactical Pings & Twin Star Ultimate Flash
	for s in _shots:
		draw_line(s["from"], s["to"], s["color"], 2.0)
	for pg in director.active_pings:
		var pp: Vector2 = pg["pos"]
		var pr := 10.0 + fmod(_flow_t * 24.0, 18.0)
		draw_arc(pp, pr, 0.0, TAU, 16, Color(1.0, 0.92, 0.25), 2.0)
		draw_string(font, pp + Vector2(-36, -14), str(pg["label"]), HORIZONTAL_ALIGNMENT_CENTER, 72, 7, Color(1.0, 0.94, 0.35))
	if _ult_flash > 0.0:
		draw_rect(Rect2(0, 28, 480, 210), Color(1.0, 0.65, 0.98, _ult_flash * 0.55))
