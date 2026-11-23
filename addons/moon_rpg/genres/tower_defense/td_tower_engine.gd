class_name TDTowerEngine
extends RefCounted
## Studio-Grade Pure-Data Tower Defense Simulation Core (Kingdom Rush × Arknights style).
## Handles 100+ creeps, towers, chain-lightning, and melee blocker soldiers in pure data:
## - Physical (Armor) / Magic (Magic Resist) / True damage split
## - Flying creeps & Anti-Air tower filtering (`is_flying` / `can_hit_air`)
## - Status effects: Slow, Burn/Poison DoT, Stun, Armor Shred
## - Chain Lightning bouncing across nearby targets (`chain_count`)
## - Barracks towers spawning rally-point melee soldiers that BLOCK ground creeps on the path!
## - Branching tower upgrades (`get_available_upgrades(uid)`), sell refunds, and serialization.

enum TargetPriority { FIRST, LAST, STRONGEST, CLOSEST }

signal gold_changed(new_gold: int)
signal lives_changed(new_lives: int)
signal tower_placed(tower: Dictionary)
signal tower_upgraded(tower: Dictionary)
signal tower_sold(tower_uid: String, refund: int)
signal tower_fired(tower: Dictionary, target_creep: Dictionary, damage: float)
signal chain_lightning_fired(points: Array)
signal creep_spawned(creep: Dictionary)
signal creep_killed(creep: Dictionary, bounty: int)
signal creep_leaked(creep: Dictionary, life_cost: int)
signal game_over(won: bool)

var gold: int = 200
var lives: int = 20
var sell_refund_ratio: float = 0.70

var lanes: Dictionary = {} # lane_id -> TDPathLane
var tower_defs: Dictionary = {} # tower_id -> def
var creep_defs: Dictionary = {} # enemy_id -> def
var towers: Dictionary = {} # uid -> tower instance dict
var creeps: Array[Dictionary] = []
var soldiers: Array[Dictionary] = [] # Barracks blockers & temporary reinforcements

var _uid_counter: int = 0


func register_lane(lane: TDPathLane) -> void:
	lanes[lane.lane_id] = lane


func register_tower_def(tower_id: String, def: Dictionary) -> void:
	tower_defs[tower_id] = def.duplicate(true)


func register_creep_def(enemy_id: String, def: Dictionary) -> void:
	creep_defs[enemy_id] = def.duplicate(true)


func place_tower(tower_id: String, pos: Vector2, slot_id: String = "", rally_pos: Vector2 = Vector2.ZERO) -> Dictionary:
	if not tower_defs.has(tower_id):
		return {"ok": false, "reason": "Unknown tower_id: %s" % tower_id}
	var def: Dictionary = tower_defs[tower_id]
	var cost := int(def.get("cost", 50))
	if gold < cost:
		return {"ok": false, "reason": "金币不足"}
	if not slot_id.is_empty():
		for t in towers.values():
			if str(t.get("slot_id", "")) == slot_id:
				return {"ok": false, "reason": "该建造点已有防御塔"}
	gold -= cost
	gold_changed.emit(gold)
	_uid_counter += 1
	var uid := "tower_%d" % _uid_counter
	var is_barracks := str(def.get("role", "")) == "barracks"
	var eff_rally := rally_pos if rally_pos != Vector2.ZERO else _find_nearest_lane_point(pos)
	var inst := {
		"uid": uid,
		"tower_id": tower_id,
		"name": str(def.get("name", tower_id)),
		"role": str(def.get("role", "ranged")), # "ranged" | "barracks"
		"slot_id": slot_id,
		"pos": pos,
		"rally_pos": eff_rally,
		"level": 1,
		"invested": cost,
		"damage": float(def.get("damage", 15.0)),
		"damage_type": str(def.get("damage_type", "physical")), # "physical" | "magic" | "true"
		"range": float(def.get("range", 110.0)),
		"fire_rate": maxf(0.1, float(def.get("fire_rate", 1.2))),
		"can_hit_air": bool(def.get("can_hit_air", not is_barracks)),
		"splash_radius": float(def.get("splash_radius", 0.0)),
		"chain_count": int(def.get("chain_count", 0)),
		"slow_factor": float(def.get("slow_factor", 1.0)),
		"slow_duration": float(def.get("slow_duration", 0.0)),
		"dot_dps": float(def.get("dot_dps", 0.0)),
		"dot_duration": float(def.get("dot_duration", 0.0)),
		"stun_chance": float(def.get("stun_chance", 0.0)),
		"stun_duration": float(def.get("stun_duration", 0.0)),
		"shred_amount": float(def.get("shred_amount", 0.0)),
		"shred_duration": float(def.get("shred_duration", 0.0)),
		"crit_chance": float(def.get("crit_chance", 0.0)),
		"priority": int(def.get("priority", TargetPriority.FIRST)),
		"cooldown": 0.0,
		"soldier_hp": float(def.get("soldier_hp", 75.0)),
		"soldier_atk": float(def.get("soldier_atk", 12.0)),
		"soldier_count": int(def.get("soldier_count", 2)),
	}
	towers[uid] = inst
	if is_barracks:
		_spawn_barracks_soldiers(inst)
	tower_placed.emit(inst)
	return {"ok": true, "tower": inst}


func get_available_upgrades(uid: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not towers.has(uid):
		return out
	var inst: Dictionary = towers[uid]
	var def: Dictionary = tower_defs.get(str(inst["tower_id"]), {})
	var upgrades: Array = def.get("upgrades", [])
	var cur_lv := int(inst["level"])
	for i in range(upgrades.size()):
		var u: Dictionary = upgrades[i]
		var req_lv := int(u.get("from_level", i + 1))
		if req_lv == cur_lv:
			var copy := u.duplicate(true)
			copy["_index"] = i
			out.append(copy)
	return out


func upgrade_tower(uid: String, upgrade_index: int = -1) -> Dictionary:
	if not towers.has(uid):
		return {"ok": false, "reason": "Tower not found"}
	var inst: Dictionary = towers[uid]
	var avail := get_available_upgrades(uid)
	if avail.is_empty():
		return {"ok": false, "reason": "已达最高等级"}
	var chosen: Dictionary = avail[0]
	if upgrade_index >= 0:
		for a in avail:
			if int(a.get("_index", -1)) == upgrade_index:
				chosen = a
				break
	var cost := int(chosen.get("cost", 60))
	if gold < cost:
		return {"ok": false, "reason": "金币不足"}
	gold -= cost
	gold_changed.emit(gold)
	inst["level"] = int(inst["level"]) + 1
	inst["invested"] = int(inst["invested"]) + cost
	inst["damage"] = float(inst["damage"]) + float(chosen.get("damage_add", 10.0))
	inst["range"] = float(inst["range"]) + float(chosen.get("range_add", 12.0))
	inst["fire_rate"] = float(inst["fire_rate"]) + float(chosen.get("fire_rate_add", 0.2))
	for k in ["splash_radius", "chain_count", "slow_factor", "slow_duration", "dot_dps", "dot_duration", "stun_chance", "stun_duration", "shred_amount", "shred_duration", "crit_chance", "damage_type", "name"]:
		if chosen.has(k):
			inst[k] = chosen[k]
	if str(inst["role"]) == "barracks":
		inst["soldier_hp"] = float(inst["soldier_hp"]) + float(chosen.get("soldier_hp_add", 35.0))
		inst["soldier_atk"] = float(inst["soldier_atk"]) + float(chosen.get("soldier_atk_add", 7.0))
		for s in soldiers:
			if str(s.get("owner_tower", "")) == uid:
				s["max_hp"] = float(inst["soldier_hp"])
				s["hp"] = float(inst["soldier_hp"])
				s["atk"] = float(inst["soldier_atk"])
	tower_upgraded.emit(inst)
	return {"ok": true, "tower": inst}


func sell_tower(uid: String) -> int:
	if not towers.has(uid):
		return 0
	var inst: Dictionary = towers[uid]
	var refund := int(round(float(inst.get("invested", 0)) * sell_refund_ratio))
	towers.erase(uid)
	for i in range(soldiers.size() - 1, -1, -1):
		if str(soldiers[i].get("owner_tower", "")) == uid:
			soldiers.remove_at(i)
	gold += refund
	gold_changed.emit(gold)
	tower_sold.emit(uid, refund)
	return refund


func spawn_temporary_blocker(pos: Vector2, hp: float = 65.0, atk: float = 11.0, lifetime: float = 12.0, block_count: int = 1) -> Dictionary:
	_uid_counter += 1
	var s := {
		"uid": "soldier_%d" % _uid_counter,
		"owner_tower": "",
		"pos": pos,
		"hp": hp,
		"max_hp": hp,
		"atk": atk,
		"block_count": block_count,
		"attack_cd": 0.0,
		"respawn_timer": 0.0,
		"lifetime": lifetime, # >0 = temporary reinforcement
		"is_hero": false,
		"home_pos": pos,
		"respawn_time": 6.0,
	}
	soldiers.append(s)
	return s


func _spawn_barracks_soldiers(tower: Dictionary) -> void:
	var cnt := int(tower.get("soldier_count", 2))
	var rally: Vector2 = tower["rally_pos"]
	for i in range(cnt):
		_uid_counter += 1
		var offset := Vector2(float(i) * 14.0 - 7.0, 0.0)
		soldiers.append({
			"uid": "soldier_%d" % _uid_counter,
			"owner_tower": str(tower["uid"]),
			"pos": rally + offset,
			"home_pos": rally + offset,
			"source_id": str(tower["uid"]),
			"respawn_time": float(tower.get("respawn_time", 6.0)),
			"hp": float(tower["soldier_hp"]),
			"max_hp": float(tower["soldier_hp"]),
			"atk": float(tower["soldier_atk"]),
			"block_count": int(tower.get("block_count", 1)),
			"attack_cd": 0.0,
			"respawn_timer": 0.0,
			"lifetime": -1.0, # permanent (respawns)
			"is_hero": false,
		})


func _find_nearest_lane_point(pos: Vector2) -> Vector2:
	var best := pos
	var best_d := INF
	for lane in lanes.values():
		var l := lane as TDPathLane
		for step in range(21):
			var pt := l.get_point_at_progress(float(step) / 20.0)
			var d := pos.distance_to(pt)
			if d < best_d:
				best_d = d
				best = pt
	return best


func spawn_creep(enemy_id: String, lane_id: String) -> Dictionary:
	if not lanes.has(lane_id):
		return {}
	var def: Dictionary = creep_defs.get(enemy_id, {"hp": 40.0, "speed": 52.0, "bounty": 15, "life_cost": 1})
	var lane: TDPathLane = lanes[lane_id]
	_uid_counter += 1
	var creep := {
		"uid": "creep_%d" % _uid_counter,
		"enemy_id": enemy_id,
		"lane_id": lane_id,
		"hp": float(def.get("hp", 40.0)),
		"max_hp": float(def.get("hp", 40.0)),
		"speed": float(def.get("speed", 52.0)),
		"armor": float(def.get("armor", 0.0)),
		"magic_resist": clampf(float(def.get("magic_resist", 0.0)), 0.0, 0.9),
		"atk": float(def.get("atk", 10.0)),
		"is_flying": bool(def.get("is_flying", false)),
		"is_boss": bool(def.get("is_boss", false)),
		"bounty": int(def.get("bounty", 15)),
		"life_cost": int(def.get("life_cost", 1)),
		"progress": 0.0,
		"pos": lane.get_point_at_progress(0.0),
		"slow_factor": 1.0,
		"slow_timer": 0.0,
		"dot_dps": 0.0,
		"dot_timer": 0.0,
		"stun_timer": 0.0,
		"shred_amount": 0.0,
		"shred_timer": 0.0,
		"attack_cd": 0.0,
		"blocked_by": "",
		"shield": float(def.get("shield", 0.0)),
		"max_shield": float(def.get("shield", 0.0)),
		"last_hit_by": "",
	}
	creeps.append(creep)
	creep_spawned.emit(creep)
	return creep


func apply_damage_to_creep(c: Dictionary, raw_dmg: float, dmg_type: String = "physical") -> float:
	# Optional absorb shield: magic/true damage depletes it first, physical damage is reduced while it holds.
	var shield := float(c.get("shield", 0.0))
	if shield > 0.0:
		if dmg_type == "physical":
			raw_dmg *= 0.30
		else:
			var absorbed := minf(shield, raw_dmg)
			c["shield"] = shield - absorbed
			raw_dmg -= absorbed
			if raw_dmg <= 0.0:
				return absorbed
	var net := raw_dmg
	if dmg_type == "physical":
		var eff_armor := maxf(0.0, float(c["armor"]) - float(c["shred_amount"]))
		net = maxf(1.0, raw_dmg - eff_armor)
	elif dmg_type == "magic":
		net = maxf(1.0, raw_dmg * (1.0 - float(c["magic_resist"])))
	c["hp"] = float(c["hp"]) - net
	return net


func apply_status_to_creep(c: Dictionary, kind: String, power: float, duration: float) -> void:
	if duration <= 0.0:
		return
	match kind:
		"slow":
			c["slow_factor"] = minf(float(c["slow_factor"]), power)
			c["slow_timer"] = maxf(float(c["slow_timer"]), duration)
		"dot", "burn", "poison":
			c["dot_dps"] = maxf(float(c["dot_dps"]), power)
			c["dot_timer"] = maxf(float(c["dot_timer"]), duration)
		"stun":
			c["stun_timer"] = maxf(float(c["stun_timer"]), duration)
		"shred":
			c["shred_amount"] = maxf(float(c["shred_amount"]), power)
			c["shred_timer"] = maxf(float(c["shred_timer"]), duration)


func tick(delta: float) -> void:
	# 1. Tick soldiers / blockers (respawns, lifetimes, melee engagement)
	var blocker_loads: Dictionary = {} # soldier_uid -> count
	for i in range(soldiers.size() - 1, -1, -1):
		var s: Dictionary = soldiers[i]
		if float(s["lifetime"]) > 0.0:
			s["lifetime"] = float(s["lifetime"]) - delta
			if float(s["lifetime"]) <= 0.0:
				soldiers.remove_at(i)
				continue
		if float(s["hp"]) <= 0.0:
			if float(s["lifetime"]) > 0.0:
				soldiers.remove_at(i)
				continue
			s["respawn_timer"] = maxf(0.0, float(s["respawn_timer"]) - delta)
			if float(s["respawn_timer"]) <= 0.0:
				s["hp"] = float(s["max_hp"])
				if s.has("home_pos"):
					s["pos"] = s["home_pos"]
			continue
		s["attack_cd"] = maxf(0.0, float(s["attack_cd"]) - delta)
		blocker_loads[str(s["uid"])] = 0

	# 2. Tick creeps (DoT, timers, blocking, movement, leaks)
	for i in range(creeps.size() - 1, -1, -1):
		var c: Dictionary = creeps[i]
		if float(c["slow_timer"]) > 0.0:
			c["slow_timer"] = maxf(0.0, float(c["slow_timer"]) - delta)
			if float(c["slow_timer"]) <= 0.0:
				c["slow_factor"] = 1.0
		if float(c["shred_timer"]) > 0.0:
			c["shred_timer"] = maxf(0.0, float(c["shred_timer"]) - delta)
			if float(c["shred_timer"]) <= 0.0:
				c["shred_amount"] = 0.0
		if float(c["dot_timer"]) > 0.0:
			c["dot_timer"] = maxf(0.0, float(c["dot_timer"]) - delta)
			c["hp"] = float(c["hp"]) - float(c["dot_dps"]) * delta
		if float(c["stun_timer"]) > 0.0:
			c["stun_timer"] = maxf(0.0, float(c["stun_timer"]) - delta)
		if float(c["hp"]) <= 0.0:
			continue

		# Check melee blocker engagement for ground creeps
		var blocked_soldier: Dictionary = {}
		if not bool(c["is_flying"]):
			for s in soldiers:
				if float(s["hp"]) <= 0.0:
					continue
				var suid := str(s["uid"])
				var load_n := int(blocker_loads.get(suid, 0))
				if load_n < int(s["block_count"]) and (s["pos"] as Vector2).distance_to(c["pos"]) <= 24.0:
					blocker_loads[suid] = load_n + 1
					blocked_soldier = s
					break

		if not blocked_soldier.is_empty():
			c["blocked_by"] = str(blocked_soldier["uid"])
			# Melee exchange!
			if float(blocked_soldier["attack_cd"]) <= 0.0:
				blocked_soldier["attack_cd"] = 0.85
				c["last_hit_by"] = str(blocked_soldier.get("source_id", blocked_soldier.get("owner_tower", "")))
				apply_damage_to_creep(c, float(blocked_soldier["atk"]), "physical")
			c["attack_cd"] = maxf(0.0, float(c["attack_cd"]) - delta)
			if float(c["stun_timer"]) <= 0.0 and float(c["attack_cd"]) <= 0.0:
				c["attack_cd"] = 1.0
				blocked_soldier["hp"] = float(blocked_soldier["hp"]) - float(c["atk"])
				if float(blocked_soldier["hp"]) <= 0.0:
					blocked_soldier["respawn_timer"] = float(blocked_soldier.get("respawn_time", 6.0))
			continue

		c["blocked_by"] = ""
		if float(c["stun_timer"]) > 0.0:
			continue

		var lane: TDPathLane = lanes.get(str(c["lane_id"]), null)
		if lane == null:
			creeps.remove_at(i)
			continue
		var eff_speed := float(c["speed"]) * float(c["slow_factor"])
		c["progress"] = lane.advance_progress(float(c["progress"]), eff_speed, delta)
		c["pos"] = lane.get_point_at_progress(float(c["progress"]))
		if float(c["progress"]) >= 1.0:
			var lcost := int(c["life_cost"])
			creeps.remove_at(i)
			lives = maxi(0, lives - lcost)
			lives_changed.emit(lives)
			creep_leaked.emit(c, lcost)
			if lives <= 0:
				game_over.emit(false)
				return

	_cleanup_dead_creeps()

	# 3. Tick ranged towers & fire at prioritized targets
	for t in towers.values():
		if str(t["role"]) == "barracks":
			continue
		t["cooldown"] = maxf(0.0, float(t["cooldown"]) - delta)
		if float(t["cooldown"]) > 0.0:
			continue
		var target := _select_target(t)
		if target.is_empty():
			continue
		t["cooldown"] = 1.0 / maxf(0.1, float(t["fire_rate"]))
		_apply_tower_hit(t, target)

	_cleanup_dead_creeps()


func _cleanup_dead_creeps() -> void:
	for i in range(creeps.size() - 1, -1, -1):
		if float(creeps[i]["hp"]) <= 0.0:
			var dead: Dictionary = creeps[i]
			creeps.remove_at(i)
			var bounty := int(dead["bounty"])
			gold += bounty
			gold_changed.emit(gold)
			creep_killed.emit(dead, bounty)


func _select_target(tower: Dictionary) -> Dictionary:
	var tpos: Vector2 = tower["pos"]
	var r := float(tower["range"])
	var prio := int(tower["priority"])
	var hit_air := bool(tower["can_hit_air"])
	var best: Dictionary = {}
	var best_score := -INF

	for c in creeps:
		if float(c["hp"]) <= 0.0:
			continue
		if bool(c["is_flying"]) and not hit_air:
			continue
		var dist := tpos.distance_to(c["pos"])
		if dist > r:
			continue
		var score := 0.0
		match prio:
			TargetPriority.FIRST:
				score = float(c["progress"])
			TargetPriority.LAST:
				score = -float(c["progress"])
			TargetPriority.STRONGEST:
				score = float(c["hp"])
			TargetPriority.CLOSEST:
				score = -dist
		if best.is_empty() or score > best_score:
			best = c
			best_score = score
	return best


func _apply_tower_hit(tower: Dictionary, primary: Dictionary) -> void:
	var dmg := float(tower["damage"])
	if float(tower["crit_chance"]) > 0.0 and randf() <= float(tower["crit_chance"]):
		dmg *= 1.85
	var dtype := str(tower["damage_type"])
	var splash := float(tower["splash_radius"])
	var hit_pos: Vector2 = primary["pos"]

	tower_fired.emit(tower, primary, dmg)

	var targets: Array[Dictionary] = [primary]
	if splash > 0.0:
		for c in creeps:
			if c != primary and float(c["hp"]) > 0.0 and hit_pos.distance_to(c["pos"]) <= splash:
				if not bool(c["is_flying"]) or bool(tower["can_hit_air"]):
					targets.append(c)

	# Chain Lightning bounces!
	var chains := int(tower["chain_count"])
	if chains > 0:
		var pts: Array = [tower["pos"], primary["pos"]]
		var last_c := primary
		for _b in range(chains):
			var next_c: Dictionary = {}
			var best_d := 78.0
			for c in creeps:
				if not targets.has(c) and float(c["hp"]) > 0.0:
					var d := (last_c["pos"] as Vector2).distance_to(c["pos"])
					if d < best_d:
						best_d = d
						next_c = c
			if next_c.is_empty():
				break
			targets.append(next_c)
			pts.append(next_c["pos"])
			last_c = next_c
		chain_lightning_fired.emit(pts)

	for c in targets:
		c["last_hit_by"] = str(tower["uid"])
		apply_damage_to_creep(c, dmg, dtype)
		if float(tower["slow_duration"]) > 0.0 and float(tower["slow_factor"]) < 1.0:
			apply_status_to_creep(c, "slow", float(tower["slow_factor"]), float(tower["slow_duration"]))
		if float(tower["dot_duration"]) > 0.0 and float(tower["dot_dps"]) > 0.0:
			apply_status_to_creep(c, "dot", float(tower["dot_dps"]), float(tower["dot_duration"]))
		if float(tower["shred_duration"]) > 0.0 and float(tower["shred_amount"]) > 0.0:
			apply_status_to_creep(c, "shred", float(tower["shred_amount"]), float(tower["shred_duration"]))
		if float(tower["stun_chance"]) > 0.0 and randf() <= float(tower["stun_chance"]):
			apply_status_to_creep(c, "stun", 1.0, float(tower["stun_duration"]))


func serialize() -> Dictionary:
	var t_arr: Array = []
	for t in towers.values():
		var copy := (t as Dictionary).duplicate()
		var p: Vector2 = copy["pos"]
		var rp: Vector2 = copy["rally_pos"]
		copy["pos"] = [p.x, p.y]
		copy["rally_pos"] = [rp.x, rp.y]
		t_arr.append(copy)
	return {"gold": gold, "lives": lives, "towers": t_arr}


func deserialize(data: Dictionary) -> void:
	gold = int(data.get("gold", 200))
	lives = int(data.get("lives", 20))
	towers.clear()
	soldiers.clear()
	for t in data.get("towers", []):
		var copy := (t as Dictionary).duplicate()
		var pa: Array = copy.get("pos", [0, 0])
		var rpa: Array = copy.get("rally_pos", pa)
		copy["pos"] = Vector2(float(pa[0]), float(pa[1]))
		copy["rally_pos"] = Vector2(float(rpa[0]), float(rpa[1]))
		towers[str(copy["uid"])] = copy
		if str(copy.get("role", "")) == "barracks":
			_spawn_barracks_soldiers(copy)
