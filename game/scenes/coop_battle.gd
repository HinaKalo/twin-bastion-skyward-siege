extends Node2D
## 《双子堡垒：共守苍穹》 — 2-player co-op pixel tower defense battlefield.
## - Two seats (P1 / P2), each with its own cursor and radial build menu. Seats can be driven by the mouse,
##   the right-hand keyboard cluster (P2), a gamepad, the AI partner, or a LAN peer.
## - Every action becomes a director command (`_dispatch_cmd`), so local, AI and LAN play share one path.
## - World rendering is depth-sorted (towers, soldiers, heroes, creeps), with BattleVFX juice and cinematics.

const RETRO_DIR := "res://content/packs/jrpg_retro/"
const PLAY_TOP := 22.0
const PLAY_BOTTOM := 248.0
const CURSOR_SPEED := 170.0
const STICK_DEADZONE := 0.25
const VIEW := Vector2(480, 270)
const PAN_SPEED := 300.0
const ZOOM_MIN := 0.45
const ZOOM_MAX := 1.5

const TUTORIAL: Array[Dictionary] = [
	{"text": "教程 1/5：点击发光的塔位，在环形菜单中选择一座防御塔", "goal": "build", "hud": ""},
	{"text": "教程 2/5：点击下方【开战】或按 Space 召唤第一波敌人", "goal": "wave", "hud": "call_wave"},
	{"text": "教程 3/5：右键点击道路，让英雄前去拦截敌人", "goal": "rally", "hud": ""},
	{"text": "教程 4/5：敌人聚集时按 Q（或点技能按钮）释放【陨星箭雨】", "goal": "skill", "hud": "p1_skill"},
	{"text": "教程 5/5：再次点击你的塔进行升级 —— 与搭档的塔相邻还能触发连携！", "goal": "upgrade", "hud": ""},
]

const TIPS: Array[String] = [
	"提示：P1 与 P2 的塔相邻会形成连携，不同塔种组合效果不同",
	"提示：寒冰+法师 = 冰火超载；箭塔+兵营 = 箭兵破甲",
	"提示：铁壁盾卫的护盾会被魔法击碎，物理攻击几乎无效",
	"提示：倒计时期间提前召唤波次，双方都能拿到额外金币",
	"提示：双星能量满后，两人都按下合体键才能释放【苍穹双星陨落】",
	"提示：点击兵营可设置集结点，把卫兵部署到关键路口",
	"提示：萨满会治疗附近敌人，用狙击塔优先击杀",
	"提示：金币不够时，可以向搭档支援 50G",
	"提示：塔被打坏会冒烟，点开塔就能修；塔塌了，在废墟上重建省三成",
	"提示：敌人会绕开火力最猛的路，没人守的路口最危险",
	"提示：WASD 或把鼠标推到屏幕边缘移动视角，滚轮缩放，M 开关小地图",
	"提示：小地图上闪烁的红圈，是正在挨打的塔",
	"提示：黄色的裂变史莱姆打死会分成两只",
]


class Seat:
	var pid: int = 1
	var human: bool = true
	var remote: bool = false
	var uses_mouse: bool = false
	var keyboard: bool = false
	var joy: int = -1
	var pad_active: bool = false
	var cursor: Vector2 = Vector2(240, 136)
	var hover_pad: int = -1
	var menu: RadialMenu = null
	var targeting: String = ""
	var rally_pad: String = ""
	var stick_latch: bool = false
	var hold_t: float = 0.0


var director := CoopTDDirector.new()
var ai_partner: CoopAIPartner = null
var vfx := BattleVFX.new()
var biome: String = "bridge"
var ai_enabled: bool = false
var seats: Dictionary = {}

var hud: BattleHUD
var pause_menu: PauseMenu
var result_screen: ResultScreen
var story: StoryDialogue
var camera: Camera2D
var world_size: Vector2 = VIEW
var overlay: _Overlay
var _user_zoom: float = 1.0
var _zoom: float = 1.0
var _cam_center: Vector2 = Vector2(240, 135)
var _alerts: Array = [] # [{pos, ttl}]


class _Overlay extends Control:
	var scene: Node

	func _draw() -> void:
		scene._draw_overlay(self)

var _speed_mult: float = 1.0
var _is_finished: bool = false
var _flow_t: float = 0.0
var _banner_ttl: float = 0.0
var _hit_flash: Dictionary = {}
var _tex_cache: Dictionary = {}
var _fire_sfx_cd: float = 0.0
var _kill_sfx_cd: float = 0.0
var _boss_music: bool = false
var _tutorial_step: int = -1
var _tip_t: float = 0.0
var _tip_idx: int = 0


func _ready() -> void:
	var stage := CampaignData.get_stage_by_id(GameSession.selected_stage_id)
	biome = TowerArtRenderer.get_biome_for_stage(str(stage["id"]))
	director.setup_stage(stage, GameSession.meta, GameSession.difficulty, GameSession.endless_mode)
	world_size = stage.get("world", VIEW)
	camera = Camera2D.new()
	camera.position_smoothing_enabled = false
	add_child(camera)
	camera.make_current()
	var hs: Array = stage.get("hero_spawns", [])
	_cam_center = (hs[0] as Vector2) + Vector2(-140, 20) if not hs.is_empty() else world_size * 0.5
	_apply_camera()
	var ol := CanvasLayer.new()
	ol.layer = 4
	add_child(ol)
	overlay = _Overlay.new()
	overlay.scene = self
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ol.add_child(overlay)
	_setup_seats()
	Input.joy_connection_changed.connect(_on_joy_changed)
	_connect_signals()

	hud = BattleHUD.new()
	hud.director = director
	hud.ai_seat = 2 if ai_enabled else 0
	hud.local_seats = _local_seat_ids()
	hud.portraits = {1: UnitArtRenderer.get_portrait(1), 2: UnitArtRenderer.get_portrait(2)}
	hud.action.connect(_on_hud_action)
	hud.minimap_clicked.connect(func(wp: Vector2): _cam_center = wp)
	hud.world_size = world_size
	hud.road_polys = TerrainBaker.road_polylines(director.stage_def)
	add_child(hud)
	pause_menu = PauseMenu.new()
	pause_menu.restart_requested.connect(func(): SceneFader.go(get_tree(), "res://game/scenes/coop_battle.tscn"))
	pause_menu.map_requested.connect(func(): SceneFader.go(get_tree(), "res://game/scenes/campaign_map.tscn"))
	add_child(pause_menu)
	result_screen = ResultScreen.new()
	result_screen.replay_requested.connect(func(): SceneFader.go(get_tree(), "res://game/scenes/coop_battle.tscn"))
	result_screen.map_requested.connect(func(): SceneFader.go(get_tree(), "res://game/scenes/campaign_map.tscn"))
	result_screen.next_requested.connect(_go_next_stage)
	add_child(result_screen)

	story = StoryDialogue.new()
	add_child(story)

	vfx.init_ambient_motes(biome, int(24.0 * world_size.x * world_size.y / (VIEW.x * VIEW.y)), Rect2(Vector2(8, 8), world_size - Vector2(16, 16)))
	MoonRPG.play_bgm("bgm.forest")
	_start_stage_story(stage)
	if str(stage["id"]) == "stage_1_twin_bridge" and not GameSession.meta.tutorial_done and not _is_lan() and not director.endless:
		_tutorial_step = 0
		for pad in director.pads:
			if int(pad.get("owner_hint", 0)) == 1:
				_cam_center = (pad["pos"] as Vector2) + Vector2(60, 30)
				break
		_apply_camera()
	_refresh_hud_keys()


## First visit of a stage: play its intro dialogue, then the title curtain. Replays go straight to the curtain.
func _start_stage_story(stage: Dictionary) -> void:
	var sid := str(stage["id"])
	var intro: Array = StoryData.get_stage(sid).get("intro", [])
	var show := not director.endless and not _is_lan() and not intro.is_empty() and not GameSession.meta.has_seen(sid)
	if show:
		story.play(intro, func():
			GameSession.meta.mark_seen(sid)
			vfx.play_stage_intro(str(stage["name"]), str(stage["subtitle"])))
	else:
		vfx.play_stage_intro(str(stage["name"]), str(stage["subtitle"]))


func _show_bark(line: Dictionary) -> void:
	if line.is_empty() or hud == null:
		return
	var sp := StoryData.speaker(str(line["who"]))
	var who := str(sp.get("name", "")).split(" · ")[0]
	hud.banner_text = "%s：%s" % [who, str(line["text"])]
	hud.banner_color = sp["color"]
	_banner_ttl = 4.5


func _exit_tree() -> void:
	if GameSession.net != null and GameSession.net.command_received.is_connected(_on_net_command):
		GameSession.net.command_received.disconnect(_on_net_command)
	if Input.joy_connection_changed.is_connected(_on_joy_changed):
		Input.joy_connection_changed.disconnect(_on_joy_changed)


# ================================================================== seats

func _setup_seats() -> void:
	var s1 := Seat.new()
	s1.pid = 1
	s1.cursor = Vector2(200, 100)
	var s2 := Seat.new()
	s2.pid = 2
	s2.cursor = Vector2(200, 180)
	match GameSession.play_mode:
		GameSession.PlayMode.SOLO_AI:
			s1.uses_mouse = true
			s2.human = false
			ai_enabled = true
			ai_partner = CoopAIPartner.new(2)
		GameSession.PlayMode.LOCAL_2P:
			s1.uses_mouse = true
			s2.keyboard = true
		GameSession.PlayMode.LAN_HOST:
			s1.uses_mouse = true
			s2.human = false
			s2.remote = true
		GameSession.PlayMode.LAN_CLIENT:
			s2.uses_mouse = true
			s1.human = false
			s1.remote = true
	seats = {1: s1, 2: s2}
	_assign_joypads()


func _assign_joypads() -> void:
	var pads := Input.get_connected_joypads()
	for pid in seats.keys():
		(seats[pid] as Seat).joy = -1
	var humans: Array[Seat] = []
	for pid in [1, 2]:
		var s: Seat = seats[pid]
		if s.human and not s.remote:
			humans.append(s)
	if humans.size() == 1:
		if pads.size() >= 1:
			humans[0].joy = pads[0]
	elif humans.size() == 2:
		if pads.size() >= 2:
			humans[0].joy = pads[0]
			humans[1].joy = pads[1]
		elif pads.size() == 1:
			humans[1].joy = pads[0] # P1 keeps the mouse, P2 gets the only pad


func _on_joy_changed(_device: int, _connected: bool) -> void:
	_assign_joypads()
	_refresh_hud_keys()


func _local_seat_ids() -> Array[int]:
	var out: Array[int] = []
	for pid in [1, 2]:
		var s: Seat = seats[pid]
		if s.human and not s.remote:
			out.append(pid)
	return out


func _refresh_hud_keys() -> void:
	if hud == null:
		return
	for pid in [1, 2]:
		var s: Seat = seats[pid]
		if s.joy >= 0 and (s.pad_active or not (s.uses_mouse or s.keyboard)):
			hud.keys[pid] = {"skill": "X", "gift": "LB", "ult": "Y"}
		elif pid == 1 or s.uses_mouse:
			hud.keys[pid] = {"skill": "Q", "gift": "T", "ult": "R"}
		else:
			hud.keys[pid] = {"skill": "/", "gift": ",", "ult": "RC"}


func _is_lan() -> bool:
	return GameSession.play_mode == GameSession.PlayMode.LAN_HOST or GameSession.play_mode == GameSession.PlayMode.LAN_CLIENT


# ================================================================== signals / feedback

func _connect_signals() -> void:
	director.banner_event.connect(_show_banner)
	director.gold_transferred.connect(func(fp: int, tp: int, amt: int, bonus: int):
		var target := _screen_to_world(Vector2(70, 40) if tp == 1 else Vector2(410, 40))
		vfx.spawn_float_text(target, "+%dG" % (amt + bonus), UIKit.GOLD, 8)
		vfx.spawn_burst(target, UIKit.GOLD, 10, 50.0, 40.0)
		MoonRPG.play_sfx("sfx.collect")
		if fp == 2 and ai_enabled:
			_show_banner("AI 搭档向你支援了 %dG" % (amt + bonus), UIKit.GOLD)
	)
	director.synchro_requested.connect(func(by: int):
		MoonRPG.play_sfx("sfx.checkpoint")
		if ai_enabled and by == 2:
			_show_banner("AI 搭档请求【双星合体】！按 %s 响应！" % str(hud.keys[1]["ult"]), Color(1.0, 0.94, 0.3))
	)
	director.synchro_unleashed.connect(func(_h: int):
		vfx.play_synchro_ultimate_cinematic(_view_rect().grow(-30.0))
		MoonRPG.play_sfx("sfx.quest_clear")
	)
	director.hero_skill_cast.connect(_on_hero_skill_cast)
	director.creep_ability.connect(_on_creep_ability)
	director.combo_proc.connect(func(_k: String, pos: Vector2, col: Color):
		vfx.spawn_burst(pos, col, 4, 30.0, 0.0)
	)
	director.tower_built.connect(func(pid: int, _pad: String, t: Dictionary):
		var p: Vector2 = t["pos"]
		vfx.spawn_burst(p + Vector2(0, 6), Color(0.85, 0.75, 0.55), 12, 55.0, 30.0)
		vfx.spawn_shockwave(p + Vector2(0, 6), 22.0, UIKit.pcol(pid), 0.28)
		MoonRPG.play_sfx("sfx.land", -6.0)
		_tutorial_goal("build")
	)
	director.tower_upgraded.connect(func(pid: int, _pad: String, t: Dictionary):
		var p: Vector2 = t["pos"]
		vfx.spawn_burst(p - Vector2(0, 8), UIKit.GOLD, 16, 60.0, 20.0)
		vfx.spawn_shockwave(p, 26.0, UIKit.GOLD, 0.35)
		vfx.spawn_float_text(p - Vector2(0, 26), "%s Lv%d" % [str(t["name"]), int(t["level"])], UIKit.pcol(pid), 7)
		MoonRPG.play_sfx("sfx.checkpoint", -6.0)
		_tutorial_goal("upgrade")
	)
	director.tower_sold.connect(func(_pid: int, pad_id: String, refund: int):
		var pad := director._find_pad(pad_id)
		if not pad.is_empty():
			vfx.spawn_float_text(pad["pos"], "+%dG" % refund, UIKit.GOLD, 8)
			vfx.spawn_burst(pad["pos"], Color(0.7, 0.6, 0.5), 10, 45.0, 40.0)
		MoonRPG.play_sfx("sfx.collect")
	)
	director.wave_called.connect(func(_wi: int, _bonus: int): _tutorial_goal("wave"))
	director.wave_dir.wave_started.connect(func(wi: int, wname: String):
		vfx.play_wave_banner(wname)
		MoonRPG.play_sfx("sfx.door", -6.0)
		if not director.endless:
			_show_bark(StoryData.get_bark(str(director.stage_def["id"]), wi))
	)
	director.wave_dir.enemy_spawn_requested.connect(func(eid: String, _lid: String, _wi: int):
		if CreepCatalog.is_boss(eid):
			var bdef := CreepCatalog.get_def(eid)
			var quote := "" if director.endless else StoryData.get_boss_line(str(director.stage_def["id"]), eid)
			vfx.play_boss_cutin(str(bdef["name"]), str(bdef.get("cutin_sub", "")), _creep_texture(eid), quote)
			MoonRPG.play_sfx("sfx.hurt")
	)
	director.engine.tower_fired.connect(func(t: Dictionary, tgt: Dictionary, dmg: float):
		var tid := str(t["tower_id"])
		vfx.spawn_projectile(t["pos"] as Vector2 - Vector2(0, 14), tgt["pos"] as Vector2, tid, str(t.get("branch", "")))
		_hit_flash[str(tgt.get("uid", ""))] = 0.12
		t["fire_anim"] = 0.18
		if GameSettings.damage_numbers:
			var dcol := Color(0.76, 0.96, 1.0) if tid == "frost" else (Color(0.95, 0.65, 1.0) if tid == "mage" else Color(1.0, 0.96, 0.72))
			vfx.spawn_float_text(tgt["pos"] as Vector2, str(int(round(dmg))), dcol, 6)
		if _fire_sfx_cd <= 0.0:
			_fire_sfx_cd = 0.07
			AudioManager.play_sfx("sfx.magic" if tid != "arrow" else "sfx.swing_light", -16.0, 0.12)
	)
	director.engine.chain_lightning_fired.connect(func(pts: Array):
		for i in range(pts.size() - 1):
			vfx.spawn_lightning(pts[i], pts[i + 1], Color(0.80, 0.62, 1.0))
	)
	director.engine.creep_killed.connect(func(creep: Dictionary, bounty: int):
		var cp: Vector2 = creep["pos"]
		var is_boss := bool(creep.get("is_boss", false))
		vfx.spawn_burst(cp, Color(1.0, 0.55, 0.35) if is_boss else Color(0.95, 0.85, 0.40), 22 if is_boss else 8, 95.0 if is_boss else 50.0, 45.0)
		vfx.spawn_death(cp + (Vector2(0, -10) if bool(creep["is_flying"]) else Vector2.ZERO), _creep_texture(str(creep["enemy_id"])), UnitArtRenderer.creep_draw_size(str(creep["enemy_id"])))
		if is_boss:
			vfx.spawn_shockwave(cp, 44.0, UIKit.GOLD, 0.45)
			_shake(0.65)
		var share := maxi(1, int(ceil(float(bounty) * CoopTDDirector.tuning_bounty_share)))
		vfx.spawn_float_text(cp + Vector2(0, -8), "+%dG" % share, UIKit.GOLD, 7)
		if _kill_sfx_cd <= 0.0:
			_kill_sfx_cd = 0.08
			AudioManager.play_sfx("sfx.hit", -10.0, 0.15)
	)
	director.engine.creep_leaked.connect(func(_c: Dictionary, cost: int):
		_shake(0.45)
		vfx.spawn_float_text(TerrainBaker.gate_pos(director.stage_def) + Vector2(-6, -18), "-%d 城防" % cost, UIKit.BAD, 8)
		_add_alert(TerrainBaker.gate_pos(director.stage_def))
		MoonRPG.play_sfx("sfx.hurt", -4.0)
	)
	director.creep_attack.connect(func(cr: Dictionary, tp: Vector2, kind: String, _dmg: float):
		var cp: Vector2 = (cr["pos"] as Vector2) - Vector2(0, 8)
		match kind:
			"arrow":
				vfx.spawn_projectile(cp, tp - Vector2(0, 12), "enemy_arrow")
			"axe":
				vfx.spawn_projectile(cp, tp - Vector2(0, 12), "axe")
			"bolt":
				vfx.spawn_projectile(cp, tp - Vector2(0, 12), "bolt")
			"smash":
				vfx.spawn_shockwave(tp, 16.0, Color(0.85, 0.75, 0.55), 0.25)
				vfx.spawn_burst(tp - Vector2(0, 6), Color(0.60, 0.55, 0.50), 8, 50.0, 60.0)
				_shake(0.12)
				AudioManager.play_sfx("sfx.swing_heavy", -10.0, 0.1)
			"explode":
				vfx.spawn_shockwave(tp, 28.0, Color(1.0, 0.55, 0.20), 0.35)
				vfx.spawn_burst(tp, Color(1.0, 0.62, 0.22), 18, 80.0, 30.0)
				_shake(0.25)
				AudioManager.play_sfx("sfx.hurt", -6.0, 0.1)
	)
	director.tower_damaged.connect(func(t: Dictionary, _d: float):
		t["hit_flash"] = 0.10
		_add_alert(t["pos"])
	)
	director.tower_destroyed.connect(func(owner: int, _pad: String, t: Dictionary):
		var tp: Vector2 = t["pos"]
		vfx.spawn_burst(tp - Vector2(0, 10), Color(0.62, 0.60, 0.58), 26, 90.0, 80.0)
		vfx.spawn_burst(tp - Vector2(0, 14), UIKit.pcol(owner), 10, 60.0, 40.0)
		vfx.spawn_shockwave(tp, 34.0, Color(1.0, 0.6, 0.3), 0.45)
		vfx.spawn_float_text(tp - Vector2(0, 30), "塔被摧毁！", UIKit.BAD, 8)
		_shake(0.6)
		MoonRPG.play_sfx("sfx.door")
	)
	director.adaptive_pick.connect(func(_eid: String, reason: String):
		_show_banner(reason, Color(1.0, 0.70, 0.40))
	)
	if GameSession.net != null and not GameSession.net.command_received.is_connected(_on_net_command):
		GameSession.net.command_received.connect(_on_net_command)


func _on_hero_skill_cast(pid: int, _skill: String, pos: Vector2, _hits: int) -> void:
	if pid == 1:
		vfx.play_meteor_volley(pos)
		MoonRPG.play_sfx("sfx.magic", -2.0)
	else:
		vfx.spawn_shockwave(pos, 28.0, UIKit.GOLD, 0.4)
		vfx.spawn_burst(pos, Color(1.0, 0.95, 0.70), 16, 60.0, -10.0)
		vfx.spawn_float_text(pos - Vector2(0, 14), "圣盾援军!", UIKit.P2, 7)
		MoonRPG.play_sfx("sfx.block", -2.0)
	_tutorial_goal("skill")


func _on_creep_ability(_c: Dictionary, ability: String, pos: Vector2) -> void:
	match ability:
		"heal":
			vfx.spawn_shockwave(pos, 50.0, Color(0.45, 1.0, 0.55), 0.45)
			vfx.spawn_burst(pos, Color(0.5, 1.0, 0.6), 6, 25.0, -30.0)
		"war_cry":
			vfx.spawn_shockwave(pos, 64.0, Color(1.0, 0.35, 0.25), 0.5)
			vfx.spawn_float_text(pos - Vector2(0, 22), "战吼!", UIKit.BAD, 8)
			_shake(0.25)
		"frost_roar":
			vfx.spawn_shockwave(pos, 96.0, Color(0.6, 0.9, 1.0), 0.6)
			vfx.spawn_float_text(pos - Vector2(0, 26), "寒霜咆哮!", Color(0.7, 0.95, 1.0), 8)
			_shake(0.45)
			MoonRPG.play_sfx("sfx.block", -4.0)
		"summon":
			vfx.spawn_shockwave(pos, 56.0, Color(0.75, 0.35, 1.0), 0.6)
			vfx.spawn_burst(pos, Color(0.6, 0.3, 0.9), 20, 80.0, 0.0)
			_shake(0.55)
			MoonRPG.play_sfx("sfx.door", -2.0)
		"split":
			vfx.spawn_burst(pos, Color(0.55, 0.95, 0.45), 10, 45.0, 30.0)


func _shake(amount: float) -> void:
	if GameSettings.screen_shake:
		vfx.add_shake(amount)


func _show_banner(text: String, col: Color = Color(1.0, 0.94, 0.30)) -> void:
	if hud == null:
		return
	hud.banner_text = text
	hud.banner_color = col
	_banner_ttl = 3.2


# ================================================================== commands

func _dispatch_cmd(cmd: Dictionary) -> void:
	if _is_finished:
		return
	if _is_lan():
		GameSession.net.send_command("td_cmd", cmd)
	else:
		_apply_cmd(cmd)


func _on_net_command(_sender: int, cmd_type: String, payload: Dictionary) -> void:
	if cmd_type == "td_cmd":
		_apply_cmd(payload)


func _apply_cmd(cmd: Dictionary) -> void:
	var res := director.execute_command(cmd)
	var act := str(cmd.get("action", ""))
	var pid := int(cmd.get("player_id", 1))
	if bool(res.get("ok", false)):
		match act:
			"rally_hero":
				var p := Vector2(float(cmd.get("x", 0.0)), float(cmd.get("y", 0.0)))
				vfx.spawn_shockwave(p, 12.0, UIKit.pcol(pid), 0.25)
				_tutorial_goal("rally")
			"set_rally":
				vfx.spawn_shockwave(res["pos"], 14.0, UIKit.pcol(pid), 0.3)
				MoonRPG.play_sfx("sfx.ui_confirm", -6.0)
			"set_priority", "ping":
				MoonRPG.play_sfx("sfx.ui_confirm", -6.0)
	elif res.has("reason") and _is_local_seat(pid):
		_show_banner(str(res["reason"]), UIKit.BAD)
		MoonRPG.play_sfx("sfx.ui_back", -4.0)


func _is_local_seat(pid: int) -> bool:
	var s: Seat = seats.get(pid, null)
	return s != null and s.human and not s.remote


func _on_hud_action(id: String) -> void:
	var local := _local_seat_ids()
	var pid := local[0] if not local.is_empty() else 1
	match id:
		"call_wave":
			_dispatch_cmd({"player_id": pid, "action": "call_wave"})
		"ult":
			_dispatch_cmd({"player_id": pid, "action": "synchro_ult"})
		"speed":
			_cycle_speed()
		"pause":
			_open_pause()
		"p1_skill", "p2_skill":
			var sp := 1 if id == "p1_skill" else 2
			var s: Seat = seats[sp]
			s.targeting = "skill"
			_show_banner("点击地图选择【%s】的释放位置" % str(CoopTDDirector.HERO_SKILLS[sp]["name"]), UIKit.pcol(sp))
		"p1_gift":
			_dispatch_cmd({"player_id": 1, "action": "transfer_gold", "amount": 50})
		"p2_gift":
			_dispatch_cmd({"player_id": 2, "action": "transfer_gold", "amount": 50})


func _cycle_speed() -> void:
	_speed_mult = 2.0 if _speed_mult < 1.5 else (3.0 if _speed_mult < 2.5 else 1.0)
	MoonRPG.play_sfx("sfx.ui_confirm", -8.0)


func _open_pause() -> void:
	if _is_finished or pause_menu.visible:
		return
	for pid in seats.keys():
		_close_menu(seats[pid])
		(seats[pid] as Seat).targeting = ""
	queue_redraw()
	pause_menu.open()


# ================================================================== input

func _unhandled_input(event: InputEvent) -> void:
	if _is_finished:
		return
	if event is InputEventMouseMotion:
		var ms := _mouse_seat()
		if ms != null:
			ms.pad_active = false
			ms.cursor = get_global_mouse_position()
			_update_hover(ms)
			if ms.menu != null:
				var h := ms.menu.hit(ms.cursor)
				if h != ms.menu.hover:
					ms.menu.confirm_sell = false
				ms.menu.hover = h
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var ms := _mouse_seat()
		if ms == null:
			return
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_user_zoom = clampf(_user_zoom + (0.1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -0.1), ZOOM_MIN, ZOOM_MAX)
			get_viewport().set_input_as_handled()
			return
		if hud.is_point_on_hud(mb.position):
			return
		var pos := get_global_mouse_position()
		ms.cursor = pos
		_update_hover(ms)
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				_seat_confirm(ms, true)
			MOUSE_BUTTON_RIGHT:
				if ms.menu != null or ms.targeting != "":
					_seat_cancel(ms)
				else:
					_dispatch_cmd({"player_id": ms.pid, "action": "rally_hero", "x": pos.x, "y": pos.y})
			MOUSE_BUTTON_MIDDLE:
				_dispatch_cmd({"player_id": ms.pid, "action": "ping", "x": pos.x, "y": pos.y, "label": "P%d：支援这里！" % ms.pid})
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		_handle_key(event as InputEventKey)
		return
	if event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
		_handle_joy_button(event as InputEventJoypadButton)


func _mouse_seat() -> Seat:
	for pid in [1, 2]:
		var s: Seat = seats[pid]
		if s.uses_mouse and s.human and not s.remote:
			return s
	return null


func _key_seat() -> Seat:
	var s: Seat = seats[2]
	return s if s.keyboard and s.human else null


func _handle_key(k: InputEventKey) -> void:
	var ms := _mouse_seat()
	var ks := _key_seat()
	match k.keycode:
		KEY_ESCAPE:
			var open_any := false
			for pid in seats.keys():
				var s: Seat = seats[pid]
				if s.menu != null or s.targeting != "":
					_seat_cancel(s)
					open_any = true
			if not open_any:
				_open_pause()
		KEY_TAB:
			if _tutorial_step >= 0:
				_end_tutorial(true)
		KEY_SPACE:
			if ms != null:
				_dispatch_cmd({"player_id": ms.pid, "action": "call_wave"})
		KEY_F:
			_cycle_speed()
		KEY_M:
			hud.minimap_visible = not hud.minimap_visible
		KEY_HOME, KEY_C:
			focus_camera(TerrainBaker.gate_pos(director.stage_def) + Vector2(-160, 0))
	if ms != null:
		match k.keycode:
			KEY_Q:
				_cast_skill_at(ms, ms.cursor)
			KEY_T:
				_dispatch_cmd({"player_id": ms.pid, "action": "transfer_gold", "amount": 50})
			KEY_R:
				_dispatch_cmd({"player_id": ms.pid, "action": "synchro_ult"})
			KEY_1, KEY_2, KEY_3, KEY_4:
				if ms.hover_pad >= 0 and ms.menu == null:
					var tid: String = TowerCatalog.TOWER_IDS[k.keycode - KEY_1]
					_dispatch_cmd({"player_id": ms.pid, "action": "build_or_upgrade", "pad_id": str(director.pads[ms.hover_pad]["id"]), "tower_id": tid})
	if ks != null:
		ks.pad_active = false
		match k.keycode:
			KEY_ENTER, KEY_KP_ENTER:
				_seat_confirm(ks, false)
			KEY_SHIFT:
				if k.location == KEY_LOCATION_RIGHT:
					_seat_cancel(ks)
			KEY_CTRL:
				if k.location == KEY_LOCATION_RIGHT:
					_dispatch_cmd({"player_id": ks.pid, "action": "synchro_ult"})
			KEY_SLASH:
				_cast_skill_at(ks, ks.cursor)
			KEY_PERIOD:
				_dispatch_cmd({"player_id": ks.pid, "action": "rally_hero", "x": ks.cursor.x, "y": ks.cursor.y})
			KEY_COMMA:
				_dispatch_cmd({"player_id": ks.pid, "action": "transfer_gold", "amount": 50})
			KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT:
				if ks.menu != null:
					var dir := Vector2.ZERO
					dir.x = float(Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_key_pressed(KEY_LEFT))
					dir.y = float(Input.is_key_pressed(KEY_DOWN)) - float(Input.is_key_pressed(KEY_UP))
					ks.menu.move_selection(dir)
					MoonRPG.play_sfx("sfx.ui_confirm", -14.0)


func _handle_joy_button(jb: InputEventJoypadButton) -> void:
	var s: Seat = null
	for pid in [1, 2]:
		var cand: Seat = seats[pid]
		if cand.joy == jb.device and cand.human and not cand.remote:
			s = cand
	if s == null:
		return
	if not s.pad_active:
		s.pad_active = true
		_refresh_hud_keys()
	match jb.button_index:
		JOY_BUTTON_A:
			_seat_confirm(s, false)
		JOY_BUTTON_B:
			_seat_cancel(s)
		JOY_BUTTON_X:
			_cast_skill_at(s, s.cursor)
		JOY_BUTTON_Y:
			_dispatch_cmd({"player_id": s.pid, "action": "synchro_ult"})
		JOY_BUTTON_RIGHT_SHOULDER:
			_dispatch_cmd({"player_id": s.pid, "action": "rally_hero", "x": s.cursor.x, "y": s.cursor.y})
		JOY_BUTTON_LEFT_SHOULDER:
			_dispatch_cmd({"player_id": s.pid, "action": "transfer_gold", "amount": 50})
		JOY_BUTTON_START:
			_open_pause()
		JOY_BUTTON_BACK:
			_dispatch_cmd({"player_id": s.pid, "action": "call_wave"})
		JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT:
			if s.menu != null:
				var d := {JOY_BUTTON_DPAD_UP: Vector2.UP, JOY_BUTTON_DPAD_DOWN: Vector2.DOWN, JOY_BUTTON_DPAD_LEFT: Vector2.LEFT, JOY_BUTTON_DPAD_RIGHT: Vector2.RIGHT}
				s.menu.move_selection(d[jb.button_index])


func _cast_skill_at(s: Seat, pos: Vector2) -> void:
	s.targeting = ""
	_dispatch_cmd({"player_id": s.pid, "action": "hero_skill", "x": pos.x, "y": pos.y})


## Confirm = left click (mouse) / Enter (P2 keys) / A (gamepad).
func _seat_confirm(s: Seat, is_mouse: bool) -> void:
	if s.targeting == "skill":
		_cast_skill_at(s, s.cursor)
		return
	if s.targeting == "rally":
		_dispatch_cmd({"player_id": s.pid, "action": "set_rally", "pad_id": s.rally_pad, "x": s.cursor.x, "y": s.cursor.y})
		s.targeting = ""
		return
	if s.menu != null:
		var idx := s.menu.hit(s.cursor) if is_mouse else s.menu.hover
		if idx >= 0:
			_activate_option(s, idx)
			return
		if is_mouse and s.hover_pad >= 0 and s.hover_pad != s.menu.pad_idx:
			_open_menu(s, s.hover_pad)
			return
		if is_mouse and s.menu.is_inside(s.cursor):
			return
		_close_menu(s)
		return
	if s.hover_pad >= 0:
		_open_menu(s, s.hover_pad)


func _seat_cancel(s: Seat) -> void:
	if s.targeting != "":
		s.targeting = ""
		return
	_close_menu(s)


func _open_menu(s: Seat, pad_idx: int) -> void:
	s.menu = RadialMenu.new()
	s.menu.view_rect = _view_rect()
	s.menu.build(director, pad_idx, s.pid)
	s.menu.hover = -1
	MoonRPG.play_sfx("sfx.ui_confirm", -10.0)


func _close_menu(s: Seat) -> void:
	s.menu = null


func _activate_option(s: Seat, idx: int) -> void:
	var o: Dictionary = s.menu.options[idx]
	if not bool(o["enabled"]):
		_show_banner("P%d 金币不足（需要 %dG）" % [s.pid, int(o.get("cost", 0))], UIKit.BAD)
		MoonRPG.play_sfx("sfx.ui_back", -4.0)
		return
	match str(o["kind"]):
		"sell":
			if not s.menu.confirm_sell:
				s.menu.confirm_sell = true
				s.menu.hover = idx
				MoonRPG.play_sfx("sfx.ui_confirm", -8.0)
				return
		"rally":
			s.targeting = "rally"
			s.rally_pad = s.menu.pad_id
			_close_menu(s)
			_show_banner("选择道路上的新集结点（右键取消）", UIKit.pcol(s.pid))
			return
	var cmd: Dictionary = (o["cmd"] as Dictionary).duplicate()
	cmd["player_id"] = s.pid
	_dispatch_cmd(cmd)
	if str(o["kind"]) == "priority":
		s.menu.view_rect = _view_rect()
		s.menu.build(director, s.menu.pad_idx, s.pid)
		s.menu.anim = 1.0
		s.menu.hover = idx
	else:
		_close_menu(s)


func _update_hover(s: Seat) -> void:
	s.hover_pad = _pad_at(s.cursor)


func _pad_at(p: Vector2) -> int:
	var best := -1
	var best_d := INF
	for i in range(director.pads.size()):
		var pp: Vector2 = director.pads[i]["pos"]
		var hit := p.distance_to(pp) <= 15.0
		if not hit and director.pad_to_tower_uid.has(str(director.pads[i]["id"])):
			hit = Rect2(pp + Vector2(-13, -30), Vector2(26, 40)).has_point(p)
		if hit and p.distance_to(pp) < best_d:
			best_d = p.distance_to(pp)
			best = i
	return best


func _update_seat_motion(delta: float) -> void:
	for pid in [1, 2]:
		var s: Seat = seats[pid]
		if not s.human or s.remote:
			continue
		var move := Vector2.ZERO
		if s.keyboard and s.menu == null:
			move.x = float(Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_key_pressed(KEY_LEFT))
			move.y = float(Input.is_key_pressed(KEY_DOWN)) - float(Input.is_key_pressed(KEY_UP))
		if s.joy >= 0:
			var stick := Vector2(Input.get_joy_axis(s.joy, JOY_AXIS_LEFT_X), Input.get_joy_axis(s.joy, JOY_AXIS_LEFT_Y))
			if stick.length() > STICK_DEADZONE:
				if not s.pad_active:
					s.pad_active = true
					_refresh_hud_keys()
				if s.menu != null:
					if not s.stick_latch and stick.length() > 0.6:
						s.menu.move_selection(stick)
						s.stick_latch = true
				else:
					move += stick
			else:
				s.stick_latch = false
			if s.menu == null:
				move.x += float(Input.is_joy_button_pressed(s.joy, JOY_BUTTON_DPAD_RIGHT)) - float(Input.is_joy_button_pressed(s.joy, JOY_BUTTON_DPAD_LEFT))
				move.y += float(Input.is_joy_button_pressed(s.joy, JOY_BUTTON_DPAD_DOWN)) - float(Input.is_joy_button_pressed(s.joy, JOY_BUTTON_DPAD_UP))
		if move.length() > 0.01:
			s.hold_t += delta
			var accel := 1.0 + clampf((s.hold_t - 0.4) * 1.5, 0.0, 1.0)
			s.cursor += move.limit_length(1.0) * CURSOR_SPEED * accel * delta
			s.cursor = Vector2(clampf(s.cursor.x, 6.0, world_size.x - 6.0), clampf(s.cursor.y, 6.0, world_size.y - 6.0))
			_update_hover(s)
		else:
			s.hold_t = 0.0
			if (s.keyboard or s.pad_active) and s.hover_pad >= 0 and s.menu == null:
				# gentle magnetic snap onto the hovered pad for keyboard / gamepad users
				s.cursor = s.cursor.lerp(director.pads[s.hover_pad]["pos"], minf(1.0, delta * 10.0))
		if s.menu != null:
			s.menu.tick(delta)
			var keep_hover := s.menu.hover
			var keep_anim := s.menu.anim
			var keep_confirm := s.menu.confirm_sell
			s.menu.view_rect = _view_rect()
			s.menu.build(director, s.menu.pad_idx, s.pid)
			s.menu.hover = keep_hover if keep_hover < s.menu.options.size() else -1
			s.menu.anim = keep_anim
			s.menu.confirm_sell = keep_confirm


# ================================================================== tutorial

func _tutorial_goal(goal: String) -> void:
	if _tutorial_step < 0 or _tutorial_step >= TUTORIAL.size():
		return
	if str(TUTORIAL[_tutorial_step]["goal"]) != goal:
		return
	_tutorial_step += 1
	MoonRPG.play_sfx("sfx.checkpoint", -6.0)
	if _tutorial_step >= TUTORIAL.size():
		_end_tutorial(false)


func _end_tutorial(skipped: bool) -> void:
	_tutorial_step = -1
	GameSession.meta.mark_tutorial_done()
	_show_banner("已跳过教程" if skipped else "教程完成！与搭档并肩守住王城吧！", UIKit.GOOD)


func _update_guide(delta: float) -> void:
	if _banner_ttl > 0.0:
		_banner_ttl -= delta
		hud.banner_alpha = clampf(_banner_ttl / 0.4, 0.0, 1.0)
		hud.highlight = ""
		return
	if _tutorial_step >= 0:
		var step: Dictionary = TUTORIAL[_tutorial_step]
		hud.banner_text = str(step["text"]) + "   [Tab 跳过]"
		hud.banner_color = Color(1.0, 0.94, 0.40)
		hud.banner_alpha = 1.0
		hud.highlight = str(step["hud"])
		return
	hud.highlight = ""
	_tip_t += delta
	if _tip_t > 16.0:
		_tip_t = 0.0
		_tip_idx = (_tip_idx + 1) % TIPS.size()
	var show_tip := _tip_t < 7.0 and director.wave_dir.current_wave_index >= 0
	hud.banner_text = TIPS[_tip_idx]
	hud.banner_color = UIKit.TEXT_DIM
	hud.banner_alpha = clampf(minf(_tip_t * 2.0, (7.0 - _tip_t) * 2.0), 0.0, 0.85) if show_tip else 0.0


# ================================================================== main loop

func _process(delta: float) -> void:
	_flow_t += delta
	_fire_sfx_cd -= delta
	_kill_sfx_cd -= delta
	var dt := delta * _speed_mult
	vfx.tick(dt)
	_update_camera(delta)
	for cuid in _hit_flash.keys():
		_hit_flash[cuid] = maxf(0.0, float(_hit_flash[cuid]) - delta)
	for t in director.engine.towers.values():
		if float(t.get("fire_anim", 0.0)) > 0.0:
			t["fire_anim"] = maxf(0.0, float(t["fire_anim"]) - dt)
		if float(t.get("hit_flash", 0.0)) > 0.0:
			t["hit_flash"] = maxf(0.0, float(t["hit_flash"]) - delta)
	_update_seat_motion(delta)
	if not _is_finished:
		director.tick(dt)
		if ai_partner != null and GameSession.play_mode != GameSession.PlayMode.LAN_CLIENT:
			ai_partner.tick(dt, director)
		if director.is_victory():
			_finish_stage(true)
		elif director.is_defeat():
			_finish_stage(false)
		_update_music()
	_update_guide(delta)
	hud.speed_mult = _speed_mult
	hud.refresh(delta)
	queue_redraw()
	overlay.queue_redraw()


func _update_music() -> void:
	var boss_alive := false
	for c in director.engine.creeps:
		if bool(c.get("is_boss", false)):
			boss_alive = true
			break
	if boss_alive != _boss_music:
		_boss_music = boss_alive
		MoonRPG.play_bgm("bgm.boss" if boss_alive else "bgm.forest", 0.8)


func _finish_stage(won: bool) -> void:
	if _is_finished:
		return
	_is_finished = true
	for pid in seats.keys():
		_close_menu(seats[pid])
		(seats[pid] as Seat).targeting = ""
	var sid := str(director.stage_def["id"])
	var meta := GameSession.meta
	var stars := 0
	var new_record := false
	if director.endless:
		new_record = meta.record_endless(sid, director.wave_dir.current_wave_index + 1)
	elif won:
		stars = meta.record_stage_clear(sid, director.engine.lives, director.max_lives, director.difficulty, director.leaks)
	if _tutorial_step >= 0 and won:
		_end_tutorial(false)
	MoonRPG.play_sfx("sfx.quest_clear" if (won or director.endless) else "sfx.hurt")
	MoonRPG.play_bgm("bgm.village", 1.2)
	var ids := CampaignData.get_stage_ids()
	var next_idx := ids.find(sid) + 1
	var st := StoryData.get_stage(sid)
	var story_line := "" if director.endless else str(st.get("win" if won else "lose", ""))
	if won and StoryData.is_final_stage(sid) and not director.endless:
		story_line = "双星重新连上了。"
	var data := {
		"won": won, "stars": stars, "crown": won and director.difficulty == "hard", "difficulty": director.difficulty,
		"endless": director.endless, "wave": director.wave_dir.current_wave_index + 1,
		"best_wave": int(meta.endless_best.get(sid, 0)), "new_record": new_record,
		"elapsed": director.elapsed, "leaks": director.leaks, "lives": director.engine.lives, "max_lives": director.max_lives,
		"stats": director.stats, "mvp": director.get_mvp(), "stage_name": str(director.stage_def["name"]),
		"has_next": next_idx > 0 and next_idx < ids.size() and not director.endless,
		"story": story_line,
	}
	if won and StoryData.is_final_stage(sid) and not director.endless:
		story.play(StoryData.EPILOGUE, func():
			meta.mark_seen("ending")
			result_screen.show_result(data))
	else:
		result_screen.show_result(data)


func _go_next_stage() -> void:
	var ids := CampaignData.get_stage_ids()
	var next_idx := ids.find(str(director.stage_def["id"])) + 1
	if next_idx > 0 and next_idx < ids.size():
		GameSession.selected_stage_id = ids[next_idx]
		SceneFader.go(get_tree(), "res://game/scenes/coop_battle.tscn")


# ================================================================== camera

func _half_view() -> Vector2:
	return VIEW * 0.5 / _zoom


## Visible playfield in world coordinates (excludes the HUD bars).
func _view_rect() -> Rect2:
	var hv := _half_view()
	var top := PLAY_TOP / _zoom
	var bottom := (VIEW.y - PLAY_BOTTOM) / _zoom
	return Rect2(_cam_center - hv + Vector2(0, top), hv * 2.0 - Vector2(0, top + bottom))


func _world_to_screen(p: Vector2) -> Vector2:
	return (p - _cam_center) * _zoom + VIEW * 0.5


func _screen_to_world(p: Vector2) -> Vector2:
	return (p - VIEW * 0.5) / _zoom + _cam_center


func focus_camera(world_pos: Vector2) -> void:
	_cam_center = world_pos
	_apply_camera()


func _apply_camera() -> void:
	if camera == null:
		return
	var hv := _half_view()
	var min_c := Vector2(hv.x, hv.y - PLAY_TOP / _zoom)
	var max_c := Vector2(world_size.x - hv.x, world_size.y - hv.y + (VIEW.y - PLAY_BOTTOM) / _zoom)
	_cam_center.x = world_size.x * 0.5 if min_c.x > max_c.x else clampf(_cam_center.x, min_c.x, max_c.x)
	_cam_center.y = world_size.y * 0.5 if min_c.y > max_c.y else clampf(_cam_center.y, min_c.y, max_c.y)
	camera.zoom = Vector2(_zoom, _zoom)
	camera.position = _cam_center
	camera.offset = vfx.shake_offset if GameSettings.screen_shake else Vector2.ZERO


func _update_camera(delta: float) -> void:
	var pan := Vector2.ZERO
	var ms := _mouse_seat()
	if ms != null and not _is_finished:
		pan.x += float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A))
		pan.y += float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
		var mp := get_viewport().get_mouse_position()
		var vp := get_viewport().get_visible_rect()
		if vp.has_point(mp) and DisplayServer.window_is_focused():
			if mp.x < 5.0:
				pan.x -= 1.0
			elif mp.x > VIEW.x - 5.0:
				pan.x += 1.0
			if mp.y < 4.0:
				pan.y -= 1.0
			elif mp.y > VIEW.y - 4.0:
				pan.y += 1.0
	for pid in [1, 2]:
		var s: Seat = seats[pid]
		if s.human and not s.remote and s.joy >= 0:
			var rs := Vector2(Input.get_joy_axis(s.joy, JOY_AXIS_RIGHT_X), Input.get_joy_axis(s.joy, JOY_AXIS_RIGHT_Y))
			if rs.length() > STICK_DEADZONE:
				pan += rs
	if pan.length() > 0.01:
		_cam_center += pan.limit_length(1.0) * PAN_SPEED * delta / _zoom
	# keep keyboard / gamepad cursors on screen, zoom out when the two players spread apart
	var focus: Array[Vector2] = []
	for pid in [1, 2]:
		var s: Seat = seats[pid]
		if s.human and not s.remote:
			if s.keyboard or (s.joy >= 0 and s.pad_active):
				focus.append(s.cursor)
			elif s.uses_mouse:
				focus.append(s.cursor)
	var want_zoom := _user_zoom
	if focus.size() == 2:
		var spread := (focus[0] - focus[1]).abs() + Vector2(70, 70)
		var fit := minf(VIEW.x / spread.x, (PLAY_BOTTOM - PLAY_TOP) / spread.y)
		want_zoom = clampf(minf(_user_zoom, fit), ZOOM_MIN, ZOOM_MAX)
	_zoom = move_toward(_zoom, want_zoom, delta * 1.2)
	var vr := _view_rect().grow(-18.0 / _zoom)
	for pid in [1, 2]:
		var s: Seat = seats[pid]
		if s.human and not s.remote and (s.keyboard or (s.joy >= 0 and s.pad_active)):
			if s.cursor.x < vr.position.x:
				_cam_center.x -= vr.position.x - s.cursor.x
			elif s.cursor.x > vr.end.x:
				_cam_center.x += s.cursor.x - vr.end.x
			if s.cursor.y < vr.position.y:
				_cam_center.y -= vr.position.y - s.cursor.y
			elif s.cursor.y > vr.end.y:
				_cam_center.y += s.cursor.y - vr.end.y
	_apply_camera()
	if ms != null and not ms.pad_active:
		ms.cursor = get_global_mouse_position()
		_update_hover(ms)
	hud.view_rect = _view_rect()
	for i in range(_alerts.size() - 1, -1, -1):
		_alerts[i]["ttl"] = float(_alerts[i]["ttl"]) - delta
		if float(_alerts[i]["ttl"]) <= 0.0:
			_alerts.remove_at(i)
	hud.alerts = _alerts


func _add_alert(pos: Vector2) -> void:
	for a in _alerts:
		if (a["pos"] as Vector2).distance_to(pos) < 40.0:
			a["ttl"] = 2.5
			return
	_alerts.append({"pos": pos, "ttl": 2.5})


# ================================================================== screen overlay

func _draw_overlay(c: Control) -> void:
	var font := UIKit.get_font()
	_draw_offscreen_arrows(c)
	vfx.draw_cinematic_overlays(c, font)


func _draw_offscreen_arrows(c: Control) -> void:
	var vr := _view_rect()
	var threats: Array = [] # [pos, color, icon, weight]
	for cr in director.engine.creeps:
		var cp: Vector2 = cr["pos"]
		if vr.has_point(cp):
			continue
		if bool(cr.get("is_boss", false)):
			threats.append([cp, UIKit.BAD, "skull", 6.0])
		elif float(cr["progress"]) > 0.6:
			threats.append([cp, Color(1.0, 0.55, 0.35), "sword", 1.0])
	for a in _alerts:
		if not vr.has_point(a["pos"]):
			threats.append([a["pos"], Color(1.0, 0.35, 0.30), "flame", 3.0])
	var nxt := director.get_next_wave_def()
	if not nxt.is_empty() and not director.wave_dir.is_spawning and director.stage_def.has("graph"):
		var g: Dictionary = director.stage_def["graph"]
		for grp in nxt.get("groups", []):
			var sp := str(grp["lane_id"])
			if g["spawns"].has(sp):
				var spos: Vector2 = g["nodes"][g["spawns"][sp]]
				if not vr.has_point(spos):
					threats.append([spos, UIKit.GOLD, "skull", 0.5])
	if _tutorial_step == 0:
		for pad in director.pads:
			if int(pad.get("owner_hint", 0)) == 1 and not director.pad_to_tower_uid.has(str(pad["id"])):
				if not vr.has_point(pad["pos"]):
					threats.append([pad["pos"], UIKit.GOLD, "flag", 9.0])
				break
	# bucket by direction so arrows don't stack
	var buckets := {}
	var center := VIEW * 0.5 + Vector2(0, (PLAY_TOP - (VIEW.y - PLAY_BOTTOM)) * 0.5)
	for th in threats:
		var sp: Vector2 = _world_to_screen(th[0])
		var dir := (sp - center)
		var key := int(round(dir.angle() / (TAU / 16.0)))
		if not buckets.has(key) or float(buckets[key][3]) < float(th[3]):
			var count := 1 + (int(buckets[key][4]) if buckets.has(key) else 0)
			buckets[key] = [th[0], th[1], th[2], th[3], count]
		else:
			buckets[key][4] = int(buckets[key][4]) + 1
	var edge := Rect2(Vector2(10, PLAY_TOP + 10), Vector2(VIEW.x - 20, PLAY_BOTTOM - PLAY_TOP - 20))
	var pulse := 0.7 + 0.3 * sin(_flow_t * 7.0)
	for key in buckets.keys():
		var b: Array = buckets[key]
		var sp: Vector2 = _world_to_screen(b[0])
		var dir := (sp - center).normalized()
		var tmax := INF
		if absf(dir.x) > 0.001:
			tmax = minf(tmax, ((edge.end.x if dir.x > 0 else edge.position.x) - center.x) / dir.x)
		if absf(dir.y) > 0.001:
			tmax = minf(tmax, ((edge.end.y if dir.y > 0 else edge.position.y) - center.y) / dir.y)
		var ap := center + dir * tmax
		var col: Color = b[1]
		var tip := ap + dir * 6.0
		var perp := dir.orthogonal()
		c.draw_colored_polygon(PackedVector2Array([tip, ap - dir * 2.0 + perp * 5.0, ap - dir * 2.0 - perp * 5.0]), Color(col.r, col.g, col.b, pulse))
		c.draw_circle(ap - dir * 8.0, 6.0, Color(0.03, 0.03, 0.06, 0.85))
		PixelIcons.draw_icon(c, str(b[2]), ap - dir * 8.0)
		if int(b[4]) > 1:
			UIKit.draw_text(c, ap - dir * 8.0 + Vector2(4, 8), str(int(b[4])), 6, col)


# ================================================================== textures

func _retro_tex(fname: String) -> Texture2D:
	if _tex_cache.has(fname):
		return _tex_cache[fname]
	var full := RETRO_DIR + fname
	var tex: Texture2D = load(full) if ResourceLoader.exists(full) else null
	_tex_cache[fname] = tex
	return tex


func _creep_texture(eid: String) -> Texture2D:
	return PixelCreepSprites.get_frame(eid, 0)


# ================================================================== drawing

func _draw() -> void:
	var font := UIKit.get_font()
	TerrainBaker.draw_ground(self, director.stage_def, biome, _flow_t)
	_draw_pads()
	_draw_ranges()
	_draw_combo_links()
	_draw_actors()
	TerrainBaker.draw_foreground(self, director.stage_def, biome, _flow_t)
	vfx.draw_world_fx(self, font)
	_draw_wave_preview()
	_draw_pings()
	_draw_seat_overlays()


func _draw_pads() -> void:
	for i in range(director.pads.size()):
		var pad: Dictionary = director.pads[i]
		var pp: Vector2 = pad["pos"]
		var pid := str(pad["id"])
		if director.pad_to_tower_uid.has(pid):
			continue
		var hint := int(pad.get("owner_hint", 0))
		var ptex := PixelTowerSprites.get_pad_texture(hint)
		if ptex != null:
			draw_texture_rect(ptex, Rect2(pp - Vector2(14, 10), Vector2(28, 22)), false)
		if bool(pad.get("ruin", false)):
			draw_texture_rect(PixelTowerSprites.get_ruin_texture(), Rect2(pp - Vector2(10, 6), Vector2(20, 6)), false)
		for spid in [1, 2]:
			var s: Seat = seats[spid]
			if s.hover_pad == i and (s.human and not s.remote):
				var pr := 14.0 + 1.0 * sin(_flow_t * 6.0)
				draw_arc(pp + Vector2(0, 1), pr, 0.0, TAU, 24, UIKit.pcol(spid), 1.5)
	if _tutorial_step == 0:
		for pad in director.pads:
			if int(pad.get("owner_hint", 0)) == 1 and not director.pad_to_tower_uid.has(str(pad["id"])):
				var p: Vector2 = pad["pos"]
				var bob := sin(_flow_t * 5.0) * 2.5
				draw_arc(p + Vector2(0, 1), 16.0 + 3.0 * absf(sin(_flow_t * 3.0)), 0.0, TAU, 28, UIKit.GOLD, 2.0)
				draw_colored_polygon(PackedVector2Array([p + Vector2(-5, -30 + bob), p + Vector2(5, -30 + bob), p + Vector2(0, -22 + bob)]), UIKit.GOLD)
				UIKit.draw_text(self, p + Vector2(-40, -33 + bob), "点击建塔", 7, UIKit.GOLD, HORIZONTAL_ALIGNMENT_CENTER, 80)
				break


func _draw_ranges() -> void:
	for spid in [1, 2]:
		var s: Seat = seats[spid]
		if not s.human or s.remote:
			continue
		var col := UIKit.pcol(spid)
		if s.menu != null and not s.menu.read_only:
			var h := s.menu.get_hovered()
			if not h.is_empty() and float(h.get("range", 0.0)) > 0.0 and str(h["kind"]) != "rally":
				_range_ring(s.menu.anchor, float(h["range"]), col)
			elif h.is_empty():
				var t := director.get_tower_at_pad(s.menu.pad_id)
				if not t.is_empty() and str(t["role"]) != "barracks":
					_range_ring(t["pos"], float(t["range"]), col)
		elif s.hover_pad >= 0 and s.targeting == "":
			var t := director.get_tower_at_pad(str(director.pads[s.hover_pad]["id"]))
			if not t.is_empty() and str(t["role"]) != "barracks":
				_range_ring(t["pos"], float(t["range"]), col)


func _range_ring(center: Vector2, r: float, col: Color) -> void:
	draw_circle(center, r, Color(col.r, col.g, col.b, 0.07))
	var seg := 48
	for i in range(seg):
		if i % 2 == 0:
			var a0 := TAU * float(i) / float(seg) + _flow_t * 0.3
			var a1 := TAU * float(i + 1) / float(seg) + _flow_t * 0.3
			draw_line(center + Vector2(cos(a0), sin(a0)) * r, center + Vector2(cos(a1), sin(a1)) * r, Color(col.r, col.g, col.b, 0.55), 1.0)


func _draw_combo_links() -> void:
	var hovered_uids := {}
	for spid in [1, 2]:
		var s: Seat = seats[spid]
		if s.hover_pad >= 0:
			var hp := str(director.pads[s.hover_pad]["id"])
			if director.pad_to_tower_uid.has(hp):
				hovered_uids[str(director.pad_to_tower_uid[hp])] = true
	for link in director.combo_links:
		var a: Vector2 = (link["from_pos"] as Vector2) - Vector2(0, 10)
		var b: Vector2 = (link["to_pos"] as Vector2) - Vector2(0, 10)
		var lcol: Color = link["color"]
		var pulse := 0.6 + 0.4 * sin(_flow_t * 5.0)
		draw_line(a, b, Color(lcol.r, lcol.g, lcol.b, 0.18 * pulse), 4.0)
		draw_line(a, b, Color(lcol.r, lcol.g, lcol.b, 0.70), 1.0)
		var sp := a.lerp(b, fmod(_flow_t * 0.8, 1.0))
		draw_circle(sp, 1.6, Color(1, 1, 1, 0.9))
		var mid := (a + b) * 0.5
		draw_colored_polygon(PackedVector2Array([mid + Vector2(0, -3.5), mid + Vector2(3.5, 0), mid + Vector2(0, 3.5), mid + Vector2(-3.5, 0)]), lcol)
		if hovered_uids.has(str(link["t1_uid"])) or hovered_uids.has(str(link["t2_uid"])):
			var label := "%s · %s" % [str(link["label"]), str(link.get("desc", ""))]
			var w := UIKit.text_width(label, 6) + 10.0
			var r := Rect2(mid + Vector2(-w * 0.5, -16), Vector2(w, 11))
			UIKit.draw_panel(self, r, lcol)
			UIKit.draw_text(self, r.position + Vector2(5, 8), label, 6, lcol.lightened(0.3))


func _draw_actors() -> void:
	var items: Array = []
	for uid in director.engine.towers.keys():
		var t: Dictionary = director.engine.towers[uid]
		items.append({"y": (t["pos"] as Vector2).y + 4.0, "kind": 0, "ref": t})
	for s in director.engine.soldiers:
		if float(s["hp"]) > 0.0:
			items.append({"y": (s["pos"] as Vector2).y, "kind": 1, "ref": s})
	for c in director.engine.creeps:
		items.append({"y": (c["pos"] as Vector2).y + (30.0 if bool(c["is_flying"]) else 0.0), "kind": 2, "ref": c})
	items.sort_custom(func(a, b): return float(a["y"]) < float(b["y"]))
	for it in items:
		match int(it["kind"]):
			0: _draw_tower(it["ref"])
			1: _draw_soldier(it["ref"])
			2: _draw_creep(it["ref"])


func _draw_tower(t: Dictionary) -> void:
	var owner := int(director.tower_owners.get(str(t["uid"]), 1))
	TowerArtRenderer.draw_tower_detailed(self, t, owner, _flow_t)


func _draw_soldier(s: Dictionary) -> void:
	var sp: Vector2 = s["pos"]
	var is_hero := bool(s.get("is_hero", false))
	var target: Vector2 = s.get("rally_pos", s.get("home_pos", sp)) if is_hero else s.get("home_pos", sp)
	var moving := target.distance_to(sp) > 1.5
	var owner := int(s.get("owner_player", 0))
	if owner == 0:
		owner = director._owner_of_source(str(s.get("source_id", "")))
		if owner == 0:
			owner = 2 if bool(s.get("is_reinforcement", false)) else 1
	UnitArtRenderer.draw_soldier(self, s, owner, is_hero, moving, target, _flow_t)


func _draw_creep(c: Dictionary) -> void:
	var flash := float(_hit_flash.get(str(c.get("uid", "")), 0.0)) > 0.0
	UnitArtRenderer.draw_creep(self, c, flash, _flow_t)


func _draw_wave_preview() -> void:
	var nxt := director.get_next_wave_def()
	if nxt.is_empty() or director.wave_dir.is_spawning:
		return
	var by_lane := {}
	for g in nxt.get("groups", []):
		var lid := str(g["lane_id"])
		if not by_lane.has(lid):
			by_lane[lid] = []
		if not (by_lane[lid] as Array).has(str(g["enemy_id"])):
			(by_lane[lid] as Array).append(str(g["enemy_id"]))
	var g: Dictionary = director.stage_def.get("graph", {})
	if by_lane.has("random") and not g.is_empty():
		var rnd: Array = by_lane["random"]
		by_lane.erase("random")
		for sp in (g["spawns"] as Dictionary).keys():
			if not by_lane.has(sp):
				by_lane[sp] = []
			if not (by_lane[sp] as Array).has("?"):
				(by_lane[sp] as Array).append("?")
		if rnd.is_empty():
			pass
	for lid in by_lane.keys():
		var p := Vector2.ZERO
		if not g.is_empty() and g["spawns"].has(lid):
			var node: Vector2 = g["nodes"][g["spawns"][lid]]
			p = node + (Vector2(14, 0) if node.x < 40.0 else (Vector2(0, 14) if node.y < 40.0 else (Vector2(0, -14) if node.y > world_size.y - 40.0 else Vector2.ZERO)))
		else:
			var lane: TDPathLane = director.engine.lanes.get(lid, null)
			if lane == null:
				continue
			p = lane.get_point_at_progress(0.0) + Vector2(12, 0)
		var pulse := 1.0 + 0.12 * sin(_flow_t * 6.0)
		draw_circle(p, 8.0 * pulse, Color(0.35, 0.05, 0.06, 0.9))
		draw_arc(p, 8.0 * pulse, 0.0, TAU, 20, UIKit.BAD, 1.5)
		if director.wave_countdown > 0.0:
			var frac := director.wave_countdown / maxf(1.0, director.countdown_total)
			draw_arc(p, 10.5, -PI * 0.5, -PI * 0.5 + TAU * frac, 24, UIKit.GOLD, 1.5)
		PixelIcons.draw_icon(self, "skull", p)
		var ids: Array = by_lane[lid]
		for k in range(mini(3, ids.size())):
			var ip := p + Vector2(12 + k * 12, -6)
			draw_rect(Rect2(ip, Vector2(11, 11)), Color(0.04, 0.04, 0.08, 0.85))
			draw_rect(Rect2(ip, Vector2(11, 11)), Color(UIKit.BAD.r, UIKit.BAD.g, UIKit.BAD.b, 0.6), false, 1.0)
			var eid := str(ids[k])
			if eid == "?" or eid == "adaptive":
				UIKit.draw_text(self, ip + Vector2(0, 9), "?", 8, UIKit.GOLD, HORIZONTAL_ALIGNMENT_CENTER, 11)
			else:
				draw_texture_rect(_creep_texture(eid), Rect2(ip + Vector2(0.5, 0.5), Vector2(10, 10)), false)


func _draw_pings() -> void:
	for pg in director.active_pings:
		var pp: Vector2 = pg["pos"]
		var col := UIKit.pcol(int(pg["player_id"]))
		var pr := 6.0 + fmod(_flow_t * 24.0, 16.0)
		draw_arc(pp, pr, 0.0, TAU, 16, col, 1.5)
		PixelIcons.draw_icon(self, "flag", pp + Vector2(2, -8), 1, col.lightened(0.3))
		UIKit.draw_text(self, pp + Vector2(-40, -16), str(pg["label"]), 6, col, HORIZONTAL_ALIGNMENT_CENTER, 80)


func _draw_seat_overlays() -> void:
	for spid in [1, 2]:
		var s: Seat = seats[spid]
		if not s.human or s.remote:
			continue
		var col := UIKit.pcol(spid)
		if s.menu == null and s.hover_pad >= 0 and s.targeting == "":
			var t := director.get_tower_at_pad(str(director.pads[s.hover_pad]["id"]))
			if not t.is_empty():
				_draw_inspector(t)
		if s.targeting == "skill":
			var sk: Dictionary = CoopTDDirector.HERO_SKILLS[spid]
			var r := float(sk.get("radius", 18.0))
			draw_circle(s.cursor, r, Color(col.r, col.g, col.b, 0.12))
			draw_arc(s.cursor, r, 0.0, TAU, 32, col, 1.2)
		elif s.targeting == "rally":
			var t := director.get_tower_at_pad(s.rally_pad)
			if not t.is_empty():
				_range_ring(t["pos"], CoopTDDirector.RALLY_RANGE, col)
				var snap := director._nearest_lane_point(s.cursor)
				var ok := snap.distance_to(s.cursor) <= 20.0 and snap.distance_to(t["pos"]) <= CoopTDDirector.RALLY_RANGE
				PixelIcons.draw_icon(self, "flag", snap + Vector2(2, -6), 1, Color.WHITE if ok else Color(1, 0.4, 0.4))
		if s.menu != null:
			s.menu.draw(self, _flow_t)
		var show_reticle := s.keyboard or (s.joy >= 0 and s.pad_active) or (not s.uses_mouse)
		if show_reticle:
			var c := s.cursor
			var k := 1.0 + 0.15 * sin(_flow_t * 8.0)
			for a in [0.0, PI * 0.5, PI, PI * 1.5]:
				var d := Vector2(cos(a), sin(a))
				draw_line(c + d * 3.0 * k, c + d * 7.0 * k, Color(0, 0, 0, 0.7), 3.0)
				draw_line(c + d * 3.0 * k, c + d * 7.0 * k, col, 1.4)
			UIKit.draw_text(self, c + Vector2(6, -6), "P%d" % spid, 6, col)


func _draw_inspector(t: Dictionary) -> void:
	var owner := int(director.tower_owners.get(str(t["uid"]), 1))
	var lines: Array[String] = []
	lines.append("耐久 %d/%d" % [int(t.get("hp", 0)), int(t.get("max_hp", 0))])
	if str(t["role"]) == "barracks":
		lines.append("卫兵 %d 名 · 生命 %d · 攻击 %d" % [int(t.get("soldier_count", 2)), int(t["soldier_hp"]), int(t["soldier_atk"])])
	else:
		lines.append("伤害 %d · 射程 %d · 攻速 %.2f" % [int(t["damage"]), int(t["range"]), float(t["fire_rate"])])
		lines.append("目标：%s" % TowerCatalog.PRIORITY_LABELS[int(t.get("priority", 0))])
	var title := "%s  Lv%d" % [str(t["name"]), int(t["level"])]
	var w := 122.0
	var h := 13.0 + 8.0 * lines.size() + 3.0
	var p: Vector2 = t["pos"]
	var vr := _view_rect()
	var x := p.x + 16.0
	if x + w > vr.end.x - 4.0:
		x = p.x - 16.0 - w
	var y := clampf(p.y - 34.0, vr.position.y + 2.0, vr.end.y - h - 2.0)
	var r := Rect2(x, y, w, h)
	UIKit.draw_panel(self, r, UIKit.pcol(owner))
	UIKit.draw_text(self, r.position + Vector2(5, 9), title, 7, UIKit.GOLD)
	UIKit.draw_text(self, Vector2(r.end.x - 5, r.position.y + 9), "P%d" % owner, 6, UIKit.pcol(owner), HORIZONTAL_ALIGNMENT_RIGHT, -1)
	var yy := r.position.y + 9.0
	for line in lines:
		yy += 8.0
		UIKit.draw_text(self, Vector2(r.position.x + 5, yy), line, 6, UIKit.TEXT)
