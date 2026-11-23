extends Node2D
## 《双子堡垒：共守苍穹》 — Commercial-Grade 2-Player Co-op Pixel Tower Defense Battlefield
## Features:
## - 3 Distinct Animated Biomes (Emerald River & Bridges / Arcane Rift Highlands / Royal Siege Courtyard)
## - Multi-Tier Pixel-Art Tower Architecture (Lv1..Lv3) + Owner Heraldry + Glowing Cross-Player Combo Lines
## - Full Combat Juice via BattleVFX (Ballistic Arrows, Arcane Orbs, Frost Shards, Chain Lightning,
##   Floating Damage/Gold Numbers, Hit-Flash, Build Dust, Shockwaves, Trauma Screen Shake)
## - Dramatic Cinematics (Stage Intro Curtain, Wave Slide-In Banner, Boss Warning Cut-In,
##   and Full-Screen Twin-Star Comet Barrage Synchro Ultimate!)
## - Contextual Tower Inspector Card (Range Ring Preview, Lv, DPS, Upgrade/Sell `[X]`)

const RETRO_DIR := "res://content/packs/jrpg_retro/"

var director := CoopTDDirector.new()
var ai_partner := CoopAIPartner.new(2)
var vfx := BattleVFX.new()
var ai_enabled: bool = true
var biome: String = "bridge"

var _tower_types: Array[String] = ["arrow", "mage", "frost", "barracks"]
var _p1_tower: String = "arrow"
var _p2_tower: String = "barracks"
var _p1_pad_idx: int = 0
var _p2_pad_idx: int = 4

var _speed_mult: float = 1.0
var _is_paused: bool = false
var _is_finished: bool = false
var _flow_t: float = 0.0
var _banner_ttl: float = 0.0
var _tutorial_step: int = 0 # 0=P1 build tower, 1=call wave 1, 2=done

var _hit_flash: Dictionary = {} # creep_uid -> float
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
	biome = TowerArtRenderer.get_biome_for_stage(str(stage["id"]))
	vfx.init_ambient_motes(biome, 24)
	director.setup_stage(stage, GameSession.meta, GameSession.difficulty, GameSession.endless_mode)

	# Wire rich VFX & Cinematic callbacks!
	director.banner_event.connect(_show_banner)
	director.gold_transferred.connect(func(_fp: int, _tp: int, amt: int, bonus: int):
		vfx.spawn_float_text(Vector2(240, 120), "💰 +%dG!" % (amt + bonus), Color(1.0, 0.94, 0.32), 9)
		vfx.spawn_burst(Vector2(240, 120), Color(1.0, 0.90, 0.30), 12, 70.0, 45.0)
	)
	director.synchro_unleashed.connect(func(_h: int):
		vfx.play_synchro_ultimate_cinematic()
		MoonRPG.play_sfx("sfx.quest_clear")
	)
	director.wave_dir.wave_started.connect(func(_wi: int, wname: String):
		vfx.play_wave_banner(wname)
	)
	director.wave_dir.enemy_spawn_requested.connect(func(eid: String, _lid: String, _wi: int):
		if CreepCatalog.is_boss(eid):
			var bdef := CreepCatalog.get_def(eid)
			vfx.play_boss_cutin(str(bdef["name"]), str(bdef.get("cutin_sub", "")), _retro_tex("boss_obsidian_clean.png" if eid.begins_with("boss_obsidian") else ("enemy_boss_golem.png" if eid == "boss_frost_colossus" else "enemy_goblin.png")))
			MoonRPG.play_sfx("sfx.hurt")
	)
	director.engine.tower_fired.connect(func(t: Dictionary, tgt: Dictionary, dmg: float):
		var tid := str(t["tower_id"])
		vfx.spawn_projectile(t["pos"] as Vector2, tgt["pos"] as Vector2, tid)
		var cuid := str(tgt.get("uid", ""))
		_hit_flash[cuid] = 0.12
		var dcol := Color(0.76, 0.96, 1.0) if tid == "frost" else (Color(0.95, 0.65, 1.0) if tid == "mage" else Color(1.0, 0.96, 0.72))
		vfx.spawn_float_text(tgt["pos"] as Vector2, "-%d" % int(round(dmg)), dcol, 7)
	)
	director.engine.chain_lightning_fired.connect(func(pts: Array):
		for i in range(pts.size() - 1):
			vfx.spawn_lightning(pts[i], pts[i + 1], Color(0.80, 0.62, 1.0))
	)
	director.engine.creep_killed.connect(func(creep: Dictionary, bounty: int):
		var cp: Vector2 = creep["pos"]
		var is_boss := str(creep.get("enemy_id", "")).begins_with("boss")
		vfx.spawn_burst(cp, Color(1.0, 0.55, 0.35) if is_boss else Color(0.95, 0.85, 0.40), 22 if is_boss else 10, 95.0 if is_boss else 55.0, 45.0)
		if is_boss:
			vfx.spawn_shockwave(cp, 44.0, Color(1.0, 0.86, 0.35), 0.45)
			vfx.add_shake(0.65)
		vfx.spawn_float_text(cp + Vector2(0, -8), "+%dG" % bounty, Color(1.0, 0.92, 0.32), 8 if is_boss else 7)
	)
	director.engine.lives_changed.connect(func(rem: int):
		vfx.add_shake(0.45)
		vfx.spawn_float_text(Vector2(422, 118), "城防受击!", Color(1.0, 0.28, 0.28), 8)
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
	vfx.play_stage_intro(str(stage["name"]), str(stage["subtitle"]))
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
	top_bg.color = Color(0.05, 0.08, 0.18, 0.95)
	layer.add_child(top_bg)
	var sep := ColorRect.new()
	sep.position = Vector2(0, 27)
	sep.size = Vector2(480, 1.5)
	sep.color = Color(0.90, 0.78, 0.42, 0.92)
	layer.add_child(sep)

	_hud_top = Label.new()
	_hud_top.position = Vector2(10, 2)
	_hud_top.custom_minimum_size = Vector2(460, 24)
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

	# Bottom Command Dock (Styled Fantasy Bevel Bar)
	var bot_bg := ColorRect.new()
	bot_bg.position = Vector2(0, 238)
	bot_bg.size = Vector2(480, 32)
	bot_bg.color = Color(0.05, 0.08, 0.18, 0.96)
	layer.add_child(bot_bg)
	var bot_sep := ColorRect.new()
	bot_sep.position = Vector2(0, 238)
	bot_sep.size = Vector2(480, 1.5)
	bot_sep.color = Color(0.90, 0.78, 0.42, 0.88)
	layer.add_child(bot_sep)

	var row := HBoxContainer.new()
	row.position = Vector2(8, 243)
	row.add_theme_constant_override("separation", 3)
	layer.add_child(row)

	for pair in [["arrow", "1箭", Color(0.45, 0.62, 0.28)], ["mage", "2法", Color(0.55, 0.30, 0.82)], ["frost", "3冰", Color(0.24, 0.62, 0.86)], ["barracks", "4兵", Color(0.76, 0.56, 0.24)]]:
		var b := Button.new()
		b.text = "%s%d" % [pair[1], director.get_tower_cost(pair[0])]
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 7)
		TowerArtRenderer.style_button(b, pair[2])
		var tid: String = pair[0]
		b.pressed.connect(func(): _p1_tower = tid; _refresh_hud())
		row.add_child(b)
		_tower_btns[tid] = b

	var b_gold := Button.new()
	b_gold.text = "💰转50G"
	b_gold.focus_mode = Control.FOCUS_NONE
	b_gold.add_theme_font_size_override("font_size", 7)
	TowerArtRenderer.style_button(b_gold, Color(0.76, 0.62, 0.18))
	b_gold.pressed.connect(func(): _dispatch_cmd({"player_id": GameSession.local_player_id, "action": "transfer_gold", "amount": 50}))
	row.add_child(b_gold)

	_ult_btn = Button.new()
	_ult_btn.text = "☄双星0%"
	_ult_btn.focus_mode = Control.FOCUS_NONE
	_ult_btn.add_theme_font_size_override("font_size", 7)
	TowerArtRenderer.style_button(_ult_btn, Color(0.72, 0.24, 0.68))
	_ult_btn.pressed.connect(func(): _dispatch_cmd({"player_id": GameSession.local_player_id, "action": "synchro_ult"}))
	row.add_child(_ult_btn)

	_ai_btn = Button.new()
	_ai_btn.text = "AI:开" if ai_enabled else "AI:关"
	_ai_btn.focus_mode = Control.FOCUS_NONE
	_ai_btn.add_theme_font_size_override("font_size", 7)
	TowerArtRenderer.style_button(_ai_btn, Color(0.26, 0.44, 0.64))
	_ai_btn.pressed.connect(func():
		ai_enabled = not ai_enabled
		_ai_btn.text = "AI:开" if ai_enabled else "AI:关"
	)
	row.add_child(_ai_btn)

	_speed_btn = Button.new()
	_speed_btn.text = "1x"
	_speed_btn.focus_mode = Control.FOCUS_NONE
	_speed_btn.add_theme_font_size_override("font_size", 7)
	TowerArtRenderer.style_button(_speed_btn, Color(0.32, 0.42, 0.56))
	_speed_btn.pressed.connect(_cycle_speed)
	row.add_child(_speed_btn)

	_wave_btn = Button.new()
	_wave_btn.text = "▶召波"
	_wave_btn.focus_mode = Control.FOCUS_NONE
	_wave_btn.add_theme_font_size_override("font_size", 7)
	TowerArtRenderer.style_button(_wave_btn, Color(0.78, 0.30, 0.22))
	_wave_btn.pressed.connect(func(): _dispatch_cmd({"player_id": GameSession.local_player_id, "action": "call_wave"}))
	row.add_child(_wave_btn)

	var b_map := Button.new()
	b_map.text = "地图"
	b_map.focus_mode = Control.FOCUS_NONE
	b_map.add_theme_font_size_override("font_size", 7)
	TowerArtRenderer.style_button(b_map, Color(0.28, 0.34, 0.48))
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
		if act == "build_or_upgrade":
			var pad_id := str(cmd.get("pad_id", ""))
			for p in director.pads:
				if str(p["id"]) == pad_id:
					vfx.spawn_burst(p["pos"] as Vector2, Color(1.0, 0.92, 0.55), 12, 62.0, 35.0)
					vfx.spawn_shockwave(p["pos"] as Vector2, 22.0, Color(0.42, 0.90, 1.0) if int(cmd.get("player_id", 1)) == 1 else Color(1.0, 0.45, 0.48), 0.28)
					break
			if _tutorial_step == 0:
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
				var p0: Vector2 = director.pads[0]["pos"]
				_guide_beacon.badge_y_offset = 16.0 if p0.y < 85.0 else -24.0
				_guide_beacon.point_to(p0, "▲ P1点此建塔 ▲" if p0.y < 85.0 else "▼ P1点此建塔 ▼")
			_guide_banner.text = "★ 合作引导 [1/2]：左键点击蓝色高亮塔位建塔！P2(AI或方向键+Enter)将守卫南路并与你触发连携！"
		1:
			_guide_beacon.clear_target()
			_guide_banner.text = "★ 合作引导 [2/2]：防线就绪！按 [Space] 或点击【▶召波】开始战斗！按 [X] 可出售选中塔！"
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
			vfx.spawn_shockwave(mpos, 16.0, Color(0.40, 0.88, 1.0), 0.25)
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
			KEY_X:
				if not director.pads.is_empty():
					_dispatch_cmd({"player_id": local_p, "action": "sell", "pad_id": str(director.pads[_p1_pad_idx]["id"])})
			KEY_SPACE: _dispatch_cmd({"player_id": local_p, "action": "call_wave"})
			KEY_T: _dispatch_cmd({"player_id": local_p, "action": "transfer_gold", "amount": 50})
			KEY_U: _dispatch_cmd({"player_id": local_p, "action": "synchro_ult"})
			KEY_P:
				var mp := InputManager.get_canvas_mouse_pos(self)
				_dispatch_cmd({"player_id": local_p, "action": "ping", "x": mp.x, "y": mp.y, "label": "⚠ P%d标记!" % local_p})
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
	vfx.tick(delta)
	position = vfx.shake_offset
	if _guide_beacon != null:
		var in_cine := (vfx.intro_timer > 0.0 or vfx.boss_cutin_timer > 0.0 or vfx.ult_cinematic_timer > 0.0)
		_guide_beacon.visible = (_tutorial_step == 0 and not in_cine)

	for cuid in _hit_flash.keys():
		_hit_flash[cuid] = maxf(0.0, float(_hit_flash[cuid]) - delta)

	if _banner_ttl > 0.0:
		_banner_ttl -= delta
		if _banner_ttl <= 0.0:
			_update_guide()

	if not _is_paused:
		var dt := delta * _speed_mult
		director.tick(dt)
		if ai_enabled and GameSession.play_mode != GameSession.PlayMode.LAN_CLIENT:
			ai_partner.tick(dt, director)
		if director.is_victory():
			_finish_stage(true)

	_refresh_hud()
	queue_redraw()


func _finish_stage(won: bool) -> void:
	if _is_finished:
		return
	_is_finished = true
	position = Vector2.ZERO
	MoonRPG.play_sfx("sfx.quest_clear" if won else "sfx.hurt")
	var stars := 0
	if won:
		stars = GameSession.meta.record_stage_clear(str(director.stage_def["id"]), director.engine.lives, director.max_lives, director.difficulty, director.leaks)
	var grade := "S" if stars == 3 else ("A" if stars == 2 else ("B" if won else "D"))
	_result_panel.show_result({
		"won": won, "grade": grade, "collected": stars, "total_collectibles": 3,
		"elapsed_sec": director.elapsed, "no_hit": director.leaks == 0,
	}, "双子大捷！获得 %d★（可前往大地图点亮合作天赋）" % stars, "王城防线被攻破…调整双人连携再战！")


func _refresh_hud() -> void:
	if _hud_top == null:
		return
	_hud_top.text = "【%s】 P1(蓝):%dG | 城防:%d/%d 波:%d/%d 连携:%d条 | P2(红):%dG (%s)\nP1:左键建/升 右键英雄 X卖塔 T转账 U大招 | P2:%s" % [
		str(director.stage_def.get("name", "双子堡垒")),
		int(director.gold[1]), director.engine.lives, director.max_lives,
		maxi(0, director.wave_dir.current_wave_index + 1), director.wave_dir.get_total_waves(),
		director.combo_links.size(), int(director.gold[2]),
		("AI搭档" if ai_enabled else "玩家操控"),
		("AI自动协作中" if ai_enabled else "方向键选位 Enter建塔 M换塔 G转账 O大招")
	]
	for tid in _tower_btns.keys():
		(_tower_btns[tid] as Button).modulate = Color(1.0, 0.96, 0.45) if tid == _p1_tower else Color(0.84, 0.88, 0.96)
	if _ult_btn != null:
		var pct := int(director.synchro_charge)
		_ult_btn.text = "☄双星就绪!" if pct >= 100 else "☄双星%d%%" % pct
		_ult_btn.modulate = Color(1.0, 0.62, 1.0) if pct >= 100 else Color(0.75, 0.78, 0.86)
	if _wave_btn != null:
		_wave_btn.modulate = Color(1.0, 0.92, 0.32) if _tutorial_step == 1 else Color.WHITE


func _draw() -> void:
	var font := ThemeManager.get_font() if ThemeManager else ThemeDB.fallback_font
	var tree_tex: Texture2D = AssetRegistry.get_prop_texture("tree") if AssetRegistry else null
	var bush_tex: Texture2D = AssetRegistry.get_prop_texture("bush") if AssetRegistry else null

	# 1. Biome-Specific Pixel-Art Battlefield Backdrop!
	TowerArtRenderer.draw_biome_backdrop(self, biome, _flow_t, _retro_tex("tile_meadow.png"), _retro_tex("tile_stone.png"), tree_tex, bush_tex)

	# 2. Multi-Lane Roads (Grassy Trim + Stone Rim + Shaded Dirt/Cobble Center + Animated Chevrons)
	var road_outer := Color(0.24, 0.17, 0.10) if biome == "bridge" else (Color(0.20, 0.14, 0.26) if biome == "rift" else Color(0.24, 0.23, 0.28))
	var road_inner := Color(0.54, 0.42, 0.26) if biome == "bridge" else (Color(0.40, 0.32, 0.46) if biome == "rift" else Color(0.46, 0.44, 0.50))
	var road_center := Color(0.64, 0.52, 0.34, 0.55) if biome == "bridge" else (Color(0.50, 0.42, 0.58, 0.45) if biome == "rift" else Color(0.56, 0.54, 0.60, 0.45))
	for lane in director.engine.lanes.values():
		var l := lane as TDPathLane
		if l.waypoints.size() >= 2:
			draw_polyline(l.waypoints, Color(0.10, 0.14, 0.08, 0.50), 26.0)
			draw_polyline(l.waypoints, road_outer, 22.0)
			draw_polyline(l.waypoints, road_inner, 17.0)
			draw_polyline(l.waypoints, road_center, 9.0)
			var total_len: float = l.total_length
			if total_len > 24.0:
				var spacing := 44.0
				var d := fmod(_flow_t * 28.0, spacing)
				while d < total_len - 18.0:
					var p1 := l.get_point_at_progress(d / total_len)
					var p2 := l.get_point_at_progress(minf(total_len, d + 4.0) / total_len)
					var dir := (p2 - p1).normalized()
					var perp := Vector2(-dir.y, dir.x)
					draw_polyline(PackedVector2Array([p1 - dir * 2.5 + perp * 3.8, p1 + dir * 4.2, p1 - dir * 2.5 - perp * 3.8]), Color(1.0, 0.92, 0.55, 0.55), 1.5)
					d += spacing

	# 2b. Wooden Plank Bridges over Emerald River (Stage 1)
	TowerArtRenderer.draw_biome_bridges(self, biome)

	# 3. Royal Castle Gatehouse + Banner
	var gate_tex := _retro_tex("house_royal_gatehouse.png")
	if gate_tex != null:
		draw_texture_rect(gate_tex, Rect2(Vector2(412, 96), Vector2(64, 74)), false)

	# 4. Carved Stone Build Pad Pedestals + Selected Range Circle Preview!
	for i in range(director.pads.size()):
		var pad: Dictionary = director.pads[i]
		var pp: Vector2 = pad["pos"]
		var pid := str(pad["id"])
		var hint := int(pad.get("owner_hint", 0))
		if not director.pad_to_tower_uid.has(pid):
			var ptex := PixelTowerSprites.get_pad_texture(hint)
			if ptex != null:
				draw_texture_rect(ptex, Rect2(pp - Vector2(14, 10), Vector2(28, 22)), false)
		if i == _p1_pad_idx:
			var pr := 15.0 + 1.2 * sin(_flow_t * 6.0)
			draw_arc(pp, pr, 0.0, TAU, 20, Color(0.42, 0.90, 1.0), 2.4)
			# Range Preview Circle for selected tower or existing tower
			var r_val := 105.0
			if director.pad_to_tower_uid.has(pid):
				var existing: Dictionary = director.engine.towers.get(str(director.pad_to_tower_uid[pid]), {})
				r_val = float(existing.get("range", 105.0))
			else:
				var def: Dictionary = director.engine.tower_defs.get(_p1_tower, {})
				r_val = float(def.get("range", 105.0))
			draw_circle(pp, r_val, Color(0.42, 0.90, 1.0, 0.06))
			draw_arc(pp, r_val, 0.0, TAU, 36, Color(0.42, 0.90, 1.0, 0.32), 1.1)
		if not ai_enabled and i == _p2_pad_idx:
			draw_arc(pp, 17.5, 0.0, TAU, 20, Color(1.0, 0.40, 0.45), 2.2)

	# 5. Glowing Cross-Player Co-op Tower Combo Energy Lines!
	for link in director.combo_links:
		var a: Vector2 = link["from_pos"]
		var b: Vector2 = link["to_pos"]
		var lcol: Color = link["color"]
		var pulse := 0.6 + 0.4 * sin(_flow_t * 7.0)
		draw_line(a, b, Color(lcol.r, lcol.g, lcol.b, 0.32 * pulse), 5.5)
		draw_line(a, b, Color(lcol.r, lcol.g, lcol.b, 0.96), 1.8)
		# Animated traveling spark along the combo tether!
		var spark_p := a.lerp(b, fmod(_flow_t * 0.9, 1.0))
		draw_circle(spark_p, 2.5, Color.WHITE)
		var mid := (a + b) * 0.5
		draw_rect(Rect2(mid - Vector2(28, 10), Vector2(56, 11)), Color(0.06, 0.05, 0.12, 0.78))
		draw_string(font, mid + Vector2(-28, -2), str(link["label"]), HORIZONTAL_ALIGNMENT_CENTER, 56, 6, lcol)

	# 6. Multi-Tier Pixel-Art Towers!
	for uid in director.engine.towers.keys():
		var t: Dictionary = director.engine.towers[uid]
		var owner := int(director.tower_owners.get(uid, 1))
		TowerArtRenderer.draw_tower_detailed(self, str(t["tower_id"]), t["pos"] as Vector2, int(t["level"]), owner, _flow_t, font)

	# 7. Dual Heroes & Barracks Soldiers (with walk bobbing!)
	var guard_tex := _retro_tex("npc_guard.png")
	var hero_tex := _retro_tex("hero_ranger.png")
	for s in director.engine.soldiers:
		if float(s["hp"]) <= 0.0:
			continue
		var sp: Vector2 = s["pos"]
		var bob := absf(sin(_flow_t * 8.0 + sp.x * 0.2)) * 1.8
		draw_circle(sp + Vector2(0, 6), 7.5, Color(0, 0, 0, 0.30))
		if bool(s["is_hero"]):
			var is_p1 := str(s.get("name", "")).begins_with("P1")
			var tex := hero_tex if is_p1 else guard_tex
			if tex != null:
				draw_texture_rect(tex, Rect2(sp - Vector2(13, 16 + bob), Vector2(26, 26)), false)
			draw_arc(sp + Vector2(0, 6), 10.5, 0.0, TAU, 14, Color(0.35, 0.85, 1.0) if is_p1 else Color(1.0, 0.38, 0.42), 1.8)
		elif guard_tex != null:
			draw_texture_rect(guard_tex, Rect2(sp - Vector2(9, 11 + bob), Vector2(18, 18)), false)
		var shp := clampf(float(s["hp"]) / maxf(1.0, float(s["max_hp"])), 0.0, 1.0)
		draw_rect(Rect2(sp.x - 8, sp.y - 14, 16, 2.2), Color(0.08, 0.10, 0.12))
		draw_rect(Rect2(sp.x - 8, sp.y - 14, 16 * shp, 2.2), Color(0.35, 0.98, 0.50))

	# 8. Creeps (Walk Bobbing, White Hit-Flash, Frost Tint, Flapping Bats, Boss Auras!)
	for c in director.engine.creeps:
		var cp: Vector2 = c["pos"]
		var eid := str(c["enemy_id"])
		var cuid := str(c.get("uid", ""))
		var is_fly := bool(c["is_flying"])
		var is_boss := eid.begins_with("boss")
		var bob := absf(sin(_flow_t * 10.0 + cp.x * 0.15)) * (1.2 if is_boss else 2.2)
		var dp := cp + (Vector2(0, -10) if is_fly else Vector2(0, -bob))
		var flash := float(_hit_flash.get(cuid, 0.0)) > 0.0
		var tint := Color(2.2, 2.2, 2.2) if flash else (Color(0.55, 0.88, 1.0) if float(c.get("slow_timer", 0.0)) > 0.0 else Color.WHITE)

		draw_circle(cp + Vector2(0, 5), 11.0 if is_boss else 5.5, Color(0, 0, 0, 0.34))
		if is_boss:
			draw_arc(cp + Vector2(0, 5), 14.0 + 1.5 * sin(_flow_t * 6.0), 0.0, TAU, 20, Color(1.0, 0.25, 0.28, 0.75), 1.8)
		if is_fly:
			var wy := sin(_flow_t * 14.0 + cp.x * 0.2) * 4.5
			draw_polygon(PackedVector2Array([dp, dp + Vector2(-9, -2 + wy), dp + Vector2(-4, 4)]), PackedColorArray([Color(0.58, 0.22, 0.80) * tint]))
			draw_polygon(PackedVector2Array([dp, dp + Vector2(9, -2 + wy), dp + Vector2(4, 4)]), PackedColorArray([Color(0.58, 0.22, 0.80) * tint]))
			draw_circle(dp, 4.2, Color(0.80, 0.40, 0.98) * tint)
		else:
			var tname := "boss_obsidian_clean.png" if eid.begins_with("boss_obsidian") else ("enemy_boss_golem.png" if eid == "boss_frost_colossus" else ("enemy_goblin.png" if (eid in ["goblin", "boss_warlord", "shield_bearer", "shaman"]) else ("enemy_wolf.png" if eid in ["wolf", "assassin"] else "enemy_slime.png")))
			var ctex := _retro_tex(tname)
			var sz := Vector2(36, 36) if is_boss else Vector2(22, 22)
			if ctex != null:
				draw_texture_rect(ctex, Rect2(dp - sz * 0.5, sz), false, tint)
		var hp_pct := clampf(float(c["hp"]) / maxf(1.0, float(c["max_hp"])), 0.0, 1.0)
		var bw := 28.0 if is_boss else 16.0
		draw_rect(Rect2(dp.x - bw * 0.5, dp.y - 16, bw, 3.0), Color(0.08, 0.08, 0.12))
		draw_rect(Rect2(dp.x - bw * 0.5, dp.y - 16, bw * hp_pct, 3.0), Color(1.0, 0.28, 0.32))

	# 9. World VFX (Ambient Motes, Projectiles, Chain Lightning, Particles, Floating Damage/Gold!)
	vfx.draw_world_fx(self, font)

	# 10. Tactical Pings
	for pg in director.active_pings:
		var pp: Vector2 = pg["pos"]
		var pr := 10.0 + fmod(_flow_t * 24.0, 18.0)
		draw_arc(pp, pr, 0.0, TAU, 16, Color(1.0, 0.92, 0.25), 2.0)
		draw_string(font, pp + Vector2(-36, -14), str(pg["label"]), HORIZONTAL_ALIGNMENT_CENTER, 72, 7, Color(1.0, 0.94, 0.35))

	# 11. Contextual Mini Tower Inspector Badge (when hovering an existing tower)
	if _p1_pad_idx >= 0 and _p1_pad_idx < director.pads.size():
		var hpid := str(director.pads[_p1_pad_idx]["id"])
		if director.pad_to_tower_uid.has(hpid):
			var htuid := str(director.pad_to_tower_uid[hpid])
			var ht: Dictionary = director.engine.towers.get(htuid, {})
			if not ht.is_empty():
				var ir := Rect2(Vector2(354, 198), Vector2(120, 36))
				draw_rect(ir, Color(0.05, 0.08, 0.18, 0.90))
				draw_rect(ir, Color(0.88, 0.76, 0.38, 0.90), false, 1.4)
				draw_string(font, ir.position + Vector2(5, 11), "【%s】Lv%d (P%d)" % [str(ht["name"]), int(ht["level"]), int(director.tower_owners.get(htuid, 1))], HORIZONTAL_ALIGNMENT_LEFT, 110, 7, Color(1.0, 0.94, 0.42))
				draw_string(font, ir.position + Vector2(5, 22), "射程:%d 升级:%dG" % [int(ht.get("range", 0)), int(ht.get("upgrade_cost", 60))], HORIZONTAL_ALIGNMENT_LEFT, 110, 6, Color(0.80, 0.92, 1.0))
				draw_string(font, ir.position + Vector2(5, 32), "左键升级 | [X]出售", HORIZONTAL_ALIGNMENT_LEFT, 110, 6, Color(0.75, 0.85, 0.78))

	# 12. Full-Screen Cinematic Overlays (Intro Curtain, Wave Banner, Boss Cut-In, Synchro Ult Comets!)
	vfx.draw_cinematic_overlays(self, font)
