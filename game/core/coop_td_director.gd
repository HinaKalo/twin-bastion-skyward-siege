class_name CoopTDDirector
extends RefCounted
## Commercial 2-Player Co-op Tower Defense Core Director (Pure-Data, Headless-Testable).
## Orchestrates:
## - Independent P1 & P2 Gold Wallets + Kill Counters + Gold Transfer (+Talent Bonus)
## - Dual Playable Rallyable Heroes (P1 Blue Ranger, P2 Crimson Knight)
## - Cross-Player Tower Combo Auras (Ice-Fire Overload, Arrow-Barracks Crit, Twin-Star Haste)
## - Shared Synchro Ultimate Charge (0..100%) with 5s Partner Sync Window -> Twin Star Meteor!
## - Unified Command Execution (`execute_command`) for Local 2P, ENet LAN, and Replay!

signal combo_links_updated(links: Array[Dictionary])
signal gold_transferred(from_p: int, to_p: int, amount: int, bonus: int)
signal synchro_requested(by_player: int)
signal synchro_unleashed(hits: int)
signal tactical_pinged(player_id: int, pos: Vector2, label: String)
signal banner_event(text: String, color: Color)

const COMBO_RADIUS := 98.0
const SYNCHRO_WINDOW_SEC := 5.0

var engine := TDTowerEngine.new()
var wave_dir := TDWaveDirector.new()
var commander_p1 := TDCommander.new()
var commander_p2 := TDCommander.new()

var stage_def: Dictionary = {}
var pads: Array[Dictionary] = []
var meta: MetaProgress = null

var gold: Dictionary = {1: 160, 2: 160}
var kills: Dictionary = {1: 0, 2: 0}
var tower_owners: Dictionary = {} # tower_uid -> 1 | 2
var pad_to_tower_uid: Dictionary = {} # pad_id -> tower_uid

var combo_links: Array[Dictionary] = [] # { from_pos, to_pos, kind, label, color, t1_uid, t2_uid }
var synchro_charge: float = 0.0 # 0.0 .. 100.0
var synchro_pending_by: int = 0 # 0=none, 1=P1 waiting P2, 2=P2 waiting P1
var synchro_window_timer: float = 0.0
var active_pings: Array[Dictionary] = [] # { player_id, pos, label, ttl }
var all_waves_done: bool = false


func setup_stage(stage: Dictionary, meta_prog: MetaProgress = null) -> void:
	stage_def = stage.duplicate(true)
	meta = meta_prog
	engine = TDTowerEngine.new()
	wave_dir = TDWaveDirector.new()
	commander_p1 = TDCommander.new()
	commander_p2 = TDCommander.new()
	tower_owners.clear()
	pad_to_tower_uid.clear()
	combo_links.clear()
	active_pings.clear()
	synchro_charge = 0.0
	synchro_pending_by = 0
	synchro_window_timer = 0.0
	all_waves_done = false

	var bonus_gold := 40 if (meta != null and meta.has_talent("start_gold")) else 0
	var start_g := int(stage_def.get("start_gold", 160)) + bonus_gold
	gold = {1: start_g, 2: start_g}
	kills = {1: 0, 2: 0}
	engine.gold = 99999 # CoopTDDirector owns independent P1/P2 wallets!
	engine.lives = int(stage_def.get("lives", 20))

	# Register Lanes
	for ldef in stage_def.get("lanes", []):
		var lane := TDPathLane.new()
		lane.setup(str(ldef["id"]), ldef["points"])
		engine.register_lane(lane)

	# Pads
	pads.clear()
	for p in stage_def.get("pads", []):
		pads.append((p as Dictionary).duplicate(true))

	# Tower Defs (apply 10% discount if talent unlocked)
	var disc := 0.90 if (meta != null and meta.has_talent("discount")) else 1.0
	var guard_hp_mult := 1.30 if (meta != null and meta.has_talent("guard_hp")) else 1.0
	engine.register_tower_def("arrow", {
		"name": "箭塔", "role": "dps", "cost": int(round(60 * disc)), "range": 115.0, "damage": 16.0,
		"damage_type": "physical", "fire_rate": 1.35, "anti_air": true, "upgrade_cost": int(round(55 * disc)),
	})
	engine.register_tower_def("mage", {
		"name": "法师塔", "role": "dps", "cost": int(round(80 * disc)), "range": 108.0, "damage": 24.0,
		"damage_type": "magic", "fire_rate": 0.90, "anti_air": true, "chain_count": 2, "chain_range": 64.0,
		"upgrade_cost": int(round(70 * disc)),
	})
	engine.register_tower_def("frost", {
		"name": "寒冰塔", "role": "dps", "cost": int(round(75 * disc)), "range": 102.0, "damage": 12.0,
		"damage_type": "magic", "fire_rate": 0.85, "anti_air": true, "slow_pct": 0.45, "slow_dur": 2.4,
		"upgrade_cost": int(round(65 * disc)),
	})
	engine.register_tower_def("barracks", {
		"name": "兵营塔", "role": "barracks", "cost": int(round(70 * disc)), "range": 85.0,
		"soldier_count": 2, "soldier_hp": 72.0 * guard_hp_mult, "soldier_atk": 9.0, "respawn_time": 6.5,
		"upgrade_cost": int(round(60 * disc)),
	})

	# Creep Defs
	engine.register_creep_def("slime",        {"hp": 52.0,  "speed": 30.0, "armor": 0.0,  "magic_resist": 0.0,  "bounty": 16})
	engine.register_creep_def("goblin",       {"hp": 88.0,  "speed": 26.0, "armor": 10.0, "magic_resist": 0.0,  "bounty": 22})
	engine.register_creep_def("wolf",         {"hp": 68.0,  "speed": 46.0, "armor": 2.0,  "magic_resist": 0.0,  "bounty": 20})
	engine.register_creep_def("bat",          {"hp": 58.0,  "speed": 42.0, "armor": 0.0,  "magic_resist": 0.15, "bounty": 20, "is_flying": true})
	engine.register_creep_def("boss_warlord", {"hp": 320.0, "speed": 20.0, "armor": 12.0, "magic_resist": 0.15, "bounty": 90, "life_cost": 4})
	engine.register_creep_def("boss_obsidian",{"hp": 540.0, "speed": 18.0, "armor": 16.0, "magic_resist": 0.25, "bounty": 140, "life_cost": 6})

	# Waves
	for wdef in stage_def.get("waves", []):
		wave_dir.register_wave(wdef as Dictionary)
	wave_dir.enemy_spawn_requested.connect(func(eid: String, lid: String, _wi: int): engine.spawn_creep(eid, lid))
	wave_dir.all_waves_finished.connect(func(): all_waves_done = true)

	# Split bounty 50/50 + charge Synchro Ultimate on every kill!
	engine.creep_killed.connect(_on_creep_killed)
	engine.tower_fired.connect(_on_tower_fired)

	# Setup Dual Playable Heroes (P1 & P2)
	var h1 := commander_p1.setup_hero(engine, Vector2(345, 108), "P1苍穹游侠")
	h1["uid"] = "td_hero_p1"
	h1["max_hp"] = 140.0 * guard_hp_mult
	h1["hp"] = h1["max_hp"]
	var h2 := commander_p2.setup_hero(engine, Vector2(345, 162), "P2绯红圣骑")
	h2["uid"] = "td_hero_p2"
	h2["max_hp"] = 165.0 * guard_hp_mult
	h2["hp"] = h2["max_hp"]


func _on_creep_killed(creep: Dictionary, bounty: int) -> void:
	# Both players share bounty equally (with +1 rounding bonus) to reward team play!
	var half := maxi(1, int(ceil(float(bounty) * 0.60)))
	gold[1] = int(gold[1]) + half
	gold[2] = int(gold[2]) + half
	var killer_p := 1 if (creep["pos"] as Vector2).y < 136.0 else 2
	kills[killer_p] = int(kills[killer_p]) + 1

	var charge_mult := 1.40 if (meta != null and meta.has_talent("ult_charge")) else 1.0
	synchro_charge = minf(100.0, synchro_charge + 6.5 * charge_mult)


func _on_tower_fired(tower: Dictionary, target: Dictionary, _dmg: float) -> void:
	# Apply Cross-Player Combo bonus damage on hit!
	var tuid := str(tower["uid"])
	var combo_mult := 1.25 if (meta != null and meta.has_talent("combo_power")) else 1.0
	for link in combo_links:
		if str(link["t1_uid"]) != tuid and str(link["t2_uid"]) != tuid:
			continue
		var kind := str(link["kind"])
		if kind == "ice_fire_overload" and float(target.get("slow_timer", 0.0)) > 0.0:
			engine.apply_damage_to_creep(target, 9.0 * combo_mult, "true")
		elif kind == "arrow_barracks_crit" and str(target.get("blocked_by", "")) != "":
			engine.apply_damage_to_creep(target, 8.0 * combo_mult, "true")


func get_tower_cost(tower_id: String) -> int:
	var def: Dictionary = engine.tower_defs.get(tower_id, {})
	return int(def.get("cost", 60))


func build_or_upgrade_pad(player_id: int, pad_id: String, tower_id: String) -> Dictionary:
	var pad := _find_pad(pad_id)
	if pad.is_empty():
		return {"ok": false, "reason": "无效塔位"}

	# Upgrade if pad already has a tower owned by this player
	if pad_to_tower_uid.has(pad_id):
		var tuid := str(pad_to_tower_uid[pad_id])
		var owner := int(tower_owners.get(tuid, 1))
		if owner != player_id:
			return {"ok": false, "reason": "该塔归属搭档 P%d" % owner}
		var t: Dictionary = engine.towers.get(tuid, {})
		if t.is_empty():
			return {"ok": false, "reason": "防御塔不存在"}
		var ucost := int(t.get("upgrade_cost", 60))
		if int(gold[player_id]) < ucost:
			return {"ok": false, "reason": "P%d 金币不足(需%dG)" % [player_id, ucost]}
		engine.gold = 99999
		var ures := engine.upgrade_tower(tuid)
		if bool(ures["ok"]):
			gold[player_id] = int(gold[player_id]) - ucost
			banner_event.emit("P%d 升级了【%s】至 Lv%d！" % [player_id, str(t["name"]), int(t["level"])], Color(0.55, 0.94, 1.0) if player_id == 1 else Color(1.0, 0.58, 0.58))
		return ures

	# Build new tower
	var cost := get_tower_cost(tower_id)
	if int(gold[player_id]) < cost:
		return {"ok": false, "reason": "P%d 金币不足(需%dG)" % [player_id, cost]}
	engine.gold = 99999
	var pres := engine.place_tower(tower_id, pad["pos"], pad_id, pad["rally"])
	if bool(pres["ok"]):
		gold[player_id] = int(gold[player_id]) - cost
		var tuid := str((pres["tower"] as Dictionary)["uid"])
		tower_owners[tuid] = player_id
		pad_to_tower_uid[pad_id] = tuid
		recompute_combos()
		banner_event.emit("P%d 建造了【%s】！" % [player_id, str((pres["tower"] as Dictionary)["name"])], Color(0.55, 0.94, 1.0) if player_id == 1 else Color(1.0, 0.58, 0.58))
	return pres


func sell_pad(player_id: int, pad_id: String) -> Dictionary:
	if not pad_to_tower_uid.has(pad_id):
		return {"ok": false, "reason": "空塔位"}
	var tuid := str(pad_to_tower_uid[pad_id])
	if int(tower_owners.get(tuid, 1)) != player_id:
		return {"ok": false, "reason": "无法出售搭档的塔"}
	var refund := engine.sell_tower(tuid)
	gold[player_id] = int(gold[player_id]) + refund
	tower_owners.erase(tuid)
	pad_to_tower_uid.erase(pad_id)
	recompute_combos()
	return {"ok": true, "refund": refund}


func transfer_gold(from_p: int, to_p: int, amount: int = 50) -> bool:
	if from_p == to_p or amount <= 0 or int(gold.get(from_p, 0)) < amount:
		return false
	var bonus := 15 if (meta != null and meta.has_talent("gold_gift")) else 0
	gold[from_p] = int(gold[from_p]) - amount
	gold[to_p] = int(gold[to_p]) + amount + bonus
	gold_transferred.emit(from_p, to_p, amount, bonus)
	banner_event.emit("💰 P%d 向 P%d 转账 +%dG%s！" % [from_p, to_p, amount, ("(含赠+%dG)" % bonus if bonus > 0 else "")], Color(1.0, 0.92, 0.32))
	return true


func recompute_combos() -> Array[Dictionary]:
	combo_links.clear()
	# Reset haste multiplier before recomputing
	for t in engine.towers.values():
		var def: Dictionary = engine.tower_defs.get(str(t["tower_id"]), {})
		if def.has("fire_rate"):
			t["fire_rate"] = float(def["fire_rate"])

	var uids := engine.towers.keys()
	for i in range(uids.size()):
		for j in range(i + 1, uids.size()):
			var u1 := str(uids[i])
			var u2 := str(uids[j])
			var o1 := int(tower_owners.get(u1, 1))
			var o2 := int(tower_owners.get(u2, 1))
			if o1 == o2:
				continue # Must be cross-player P1 × P2!
			var t1: Dictionary = engine.towers[u1]
			var t2: Dictionary = engine.towers[u2]
			if (t1["pos"] as Vector2).distance_to(t2["pos"] as Vector2) > COMBO_RADIUS:
				continue

			var id1 := str(t1["tower_id"])
			var id2 := str(t2["tower_id"])
			var kind := "twin_star_haste"
			var label := "双星共鸣(+15%速)"
			var col := Color(1.0, 0.92, 0.35)
			if (id1 == "frost" and id2 == "mage") or (id1 == "mage" and id2 == "frost"):
				kind = "ice_fire_overload"
				label = "冰火超载(真伤+)"
				col = Color(0.85, 0.45, 1.0)
			elif (id1 == "arrow" and id2 == "barracks") or (id1 == "barracks" and id2 == "arrow"):
				kind = "arrow_barracks_crit"
				label = "箭兵破甲(暴击+)"
				col = Color(0.45, 1.0, 0.58)
			else:
				t1["fire_rate"] = float(t1.get("fire_rate", 1.0)) * 1.15
				t2["fire_rate"] = float(t2.get("fire_rate", 1.0)) * 1.15

			combo_links.append({
				"t1_uid": u1, "t2_uid": u2,
				"from_pos": t1["pos"], "to_pos": t2["pos"],
				"kind": kind, "label": label, "color": col,
			})
	combo_links_updated.emit(combo_links)
	return combo_links


func trigger_synchro_ult(player_id: int) -> Dictionary:
	if synchro_charge < 100.0:
		return {"ok": false, "reason": "双星能量未满(%d%%)" % int(synchro_charge)}
	if synchro_pending_by == 0:
		synchro_pending_by = player_id
		synchro_window_timer = SYNCHRO_WINDOW_SEC
		synchro_requested.emit(player_id)
		banner_event.emit("⚡ P%d 发起【双星合体大招】！请搭档在 5 秒内按合体键响应！" % player_id, Color(1.0, 0.94, 0.30))
		return {"ok": true, "state": "pending"}
	if synchro_pending_by != player_id:
		# Partner confirmed! Unleash full-screen Twin Star Meteor!
		synchro_charge = 0.0
		synchro_pending_by = 0
		synchro_window_timer = 0.0
		var hits := 0
		for c in engine.creeps.duplicate():
			engine.apply_damage_to_creep(c, 120.0, "true")
			c["stun_timer"] = maxf(float(c.get("stun_timer", 0.0)), 3.0)
			hits += 1
		for s in engine.soldiers:
			s["hp"] = float(s["max_hp"])
		synchro_unleashed.emit(hits)
		banner_event.emit("☄ 【苍穹双星陨落】爆发！命中 %d 敌军 + 3秒冰封 + 全军满血！" % hits, Color(1.0, 0.52, 0.96))
		return {"ok": true, "state": "unleashed", "hits": hits}
	return {"ok": false, "reason": "等待搭档响应中..."}


func send_ping(player_id: int, pos: Vector2, label: String = "⚠ 支援这里!") -> void:
	active_pings.append({"player_id": player_id, "pos": pos, "label": label, "ttl": 3.5})
	tactical_pinged.emit(player_id, pos, label)


func call_next_wave() -> Dictionary:
	var res := wave_dir.start_next_wave()
	if bool(res["ok"]) and int(res["early_bonus"]) > 0:
		gold[1] = int(gold[1]) + int(res["early_bonus"])
		gold[2] = int(gold[2]) + int(res["early_bonus"])
	return res


func execute_command(cmd: Dictionary) -> Dictionary:
	var pid := int(cmd.get("player_id", 1))
	var act := str(cmd.get("action", ""))
	match act:
		"build_or_upgrade":
			return build_or_upgrade_pad(pid, str(cmd.get("pad_id", "")), str(cmd.get("tower_id", "arrow")))
		"sell":
			return sell_pad(pid, str(cmd.get("pad_id", "")))
		"transfer_gold":
			var to_p := 2 if pid == 1 else 1
			return {"ok": transfer_gold(pid, to_p, int(cmd.get("amount", 50)))}
		"rally_hero":
			var pos := Vector2(float(cmd.get("x", 340.0)), float(cmd.get("y", 136.0)))
			if pid == 1:
				commander_p1.rally_hero(pos)
			else:
				commander_p2.rally_hero(pos)
			return {"ok": true}
		"synchro_ult":
			return trigger_synchro_ult(pid)
		"ping":
			send_ping(pid, Vector2(float(cmd.get("x", 240.0)), float(cmd.get("y", 136.0))), str(cmd.get("label", "⚠ 支援!")))
			return {"ok": true}
		"call_wave":
			return call_next_wave()
		_:
			return {"ok": false, "reason": "未知指令"}


func tick(delta: float) -> void:
	wave_dir.tick(delta)
	commander_p1.tick(delta)
	commander_p2.tick(delta)
	engine.tick(delta)
	if synchro_pending_by != 0:
		synchro_window_timer -= delta
		if synchro_window_timer <= 0.0:
			synchro_pending_by = 0
	for i in range(active_pings.size() - 1, -1, -1):
		active_pings[i]["ttl"] = float(active_pings[i]["ttl"]) - delta
		if float(active_pings[i]["ttl"]) <= 0.0:
			active_pings.remove_at(i)


func _find_pad(pad_id: String) -> Dictionary:
	for p in pads:
		if str(p["id"]) == pad_id:
			return p
	return {}
