class_name CoopTDDirector
extends RefCounted
## 2-Player Co-op Tower Defense Core Director (pure data, headless-testable).
## Orchestrates:
## - Independent P1 & P2 gold wallets, gold transfer, per-player stats (kills, damage, combos, income)
## - Tower build / Lv2 upgrade / Lv3 branch choice / sell / target priority (TowerCatalog)
## - Cross-player tower combo matrix (only P1 x P2 pairs within COMBO_RADIUS link up)
## - Enemy abilities (shield, heal aura, split, boss war-cry / frost roar / summon+shield) via CreepCatalog
## - Two heroes with one active skill each (P1 meteor volley, P2 reinforcements)
## - Shared Synchro Ultimate (needs both players to confirm within SYNCHRO_WINDOW_SEC)
## - Wave flow: manual first wave, then auto countdown between waves with scaled early-call bonus
## - Difficulty presets and Endless mode
## Every player action goes through `execute_command`, so local 2P, AI, LAN and replays share one path.

signal combo_links_updated(links: Array[Dictionary])
signal gold_transferred(from_p: int, to_p: int, amount: int, bonus: int)
signal synchro_requested(by_player: int)
signal synchro_unleashed(hits: int)
signal tactical_pinged(player_id: int, pos: Vector2, label: String)
signal banner_event(text: String, color: Color)
signal tower_built(player_id: int, pad_id: String, tower: Dictionary)
signal tower_upgraded(player_id: int, pad_id: String, tower: Dictionary)
signal tower_sold(player_id: int, pad_id: String, refund: int)
signal hero_skill_cast(player_id: int, skill_id: String, pos: Vector2, hits: int)
signal creep_ability(creep: Dictionary, ability: String, pos: Vector2)
signal combo_proc(kind: String, pos: Vector2, color: Color)
signal wave_called(wave_index: int, bonus: int)
signal countdown_started(seconds: float)
signal creep_attack(creep: Dictionary, target_pos: Vector2, kind: String, damage: float)
signal tower_damaged(tower: Dictionary, damage: float)
signal tower_destroyed(owner: int, pad_id: String, tower: Dictionary)
signal adaptive_pick(enemy_id: String, reason: String)

const COMBO_RADIUS := 98.0
## Global balance knobs (tuned with tests/balance_sim.gd; the sim can override them per run).
static var tuning_hp_scale: float = 1.5
static var tuning_bounty_share: float = 0.50
static var tuning_wave_ramp: float = 0.20
const SYNCHRO_WINDOW_SEC := 5.0
const RALLY_RANGE := 80.0
const SOLDIER_WALK_SPEED := 55.0
const P1_COLOR := Color(0.55, 0.94, 1.0)
const P2_COLOR := Color(1.0, 0.58, 0.58)

const DIFFICULTIES: Dictionary = {
	"casual": {"label": "休闲", "hp_mult": 0.70, "gold_add": 40, "lives_add": 5, "bounty_mult": 1.10, "countdown": 20.0, "tower_dmg": 0.65, "cunning_add": -0.2},
	"normal": {"label": "普通", "hp_mult": 1.00, "gold_add": 0, "lives_add": 0, "bounty_mult": 1.00, "countdown": 16.0, "tower_dmg": 1.0, "cunning_add": 0.0},
	"hard": {"label": "困难", "hp_mult": 1.32, "gold_add": -20, "lives_add": -5, "bounty_mult": 0.92, "countdown": 13.0, "tower_dmg": 1.25, "cunning_add": 0.2},
}

const HERO_SKILLS: Dictionary = {
	1: {"id": "meteor_volley", "name": "陨星箭雨", "cooldown": 16.0, "radius": 60.0, "damage": 70.0},
	2: {"id": "holy_reinforce", "name": "圣盾援军", "cooldown": 14.0, "hp": 95.0, "atk": 12.0, "lifetime": 14.0},
}

const COMBO_DEFS: Dictionary = {
	"ice_fire_overload": {"label": "冰火超载", "desc": "命中减速目标 +9 真伤", "color": Color(0.85, 0.45, 1.0)},
	"arrow_barracks_crit": {"label": "箭兵破甲", "desc": "命中被拦截目标 +8 真伤", "color": Color(0.45, 1.0, 0.58)},
	"shatter_arrow": {"label": "碎冰箭", "desc": "箭矢命中减速目标 +6 真伤", "color": Color(0.62, 0.92, 1.0)},
	"arcane_shred": {"label": "奥术破甲", "desc": "命中时削减 5 点护甲", "color": Color(1.0, 0.62, 0.92)},
	"frost_bulwark": {"label": "寒霜壁垒", "desc": "被卫兵拦住的敌人减速", "color": Color(0.55, 0.80, 1.0)},
	"twin_star_haste": {"label": "双星共鸣", "desc": "双方攻速 +15%", "color": Color(1.0, 0.92, 0.35)},
}

var engine := TDTowerEngine.new()
var wave_dir := TDWaveDirector.new()
var commander_p1 := TDCommander.new()
var commander_p2 := TDCommander.new()

var stage_def: Dictionary = {}
var pads: Array[Dictionary] = []
var meta: MetaProgress = null
var difficulty: String = "normal"
var endless: bool = false

var gold: Dictionary = {1: 160, 2: 160}
var kills: Dictionary = {1: 0, 2: 0}
var stats: Dictionary = {}
var tower_owners: Dictionary = {} # tower_uid -> 1 | 2 (live towers)
var pad_to_tower_uid: Dictionary = {} # pad_id -> tower_uid

var combo_links: Array[Dictionary] = []
var synchro_charge: float = 0.0
var synchro_pending_by: int = 0
var synchro_window_timer: float = 0.0
var active_pings: Array[Dictionary] = []
var all_waves_done: bool = false

var max_lives: int = 20
var leaks: int = 0
var elapsed: float = 0.0
var wave_countdown: float = -1.0 # <0 = inactive
var countdown_total: float = 14.0
var hero_skill_cd: Dictionary = {1: 0.0, 2: 0.0}
var hero_skill_max: Dictionary = {1: 16.0, 2: 14.0}
var heroes: Dictionary = {} # player_id -> hero soldier dict
var endless_best_wave: int = 0

var routes: Array = [] # MapGraph routes: {id, spawn, nodes, points, node_dist, total, forks, sample_dist, suffix}
var spawn_routes: Dictionary = {} # spawn id -> Array of route indices
var air_routes: Dictionary = {} # spawn id -> flight lane id
var route_index: Dictionary = {} # lane id -> route index
var spawn_ids: Array[String] = []
var rng := RandomNumberGenerator.new()
var _danger_dirty: bool = true
var _adaptive_wave: int = -99

var _source_owner: Dictionary = {} # tower uid -> owner (kept after selling, for kill credit)
var _diff: Dictionary = DIFFICULTIES["normal"]
var _bounty_mult: float = 1.0
var _hp_mult: float = 1.0
var _suppress_charge: bool = false


func setup_stage(stage: Dictionary, meta_prog: MetaProgress = null, diff: String = "normal", endless_mode: bool = false) -> void:
	stage_def = stage.duplicate(true)
	meta = meta_prog
	difficulty = diff if DIFFICULTIES.has(diff) else "normal"
	endless = endless_mode
	_diff = DIFFICULTIES[difficulty]
	engine = TDTowerEngine.new()
	wave_dir = TDWaveDirector.new()
	commander_p1 = TDCommander.new()
	commander_p2 = TDCommander.new()
	tower_owners.clear()
	pad_to_tower_uid.clear()
	_source_owner.clear()
	combo_links.clear()
	active_pings.clear()
	heroes.clear()
	synchro_charge = 0.0
	synchro_pending_by = 0
	synchro_window_timer = 0.0
	all_waves_done = false
	leaks = 0
	elapsed = 0.0
	wave_countdown = -1.0
	countdown_total = float(_diff["countdown"])
	hero_skill_cd = {1: 0.0, 2: 0.0}
	endless_best_wave = 0
	stats = {1: _new_stats(), 2: _new_stats()}
	kills = {1: 0, 2: 0}

	var start_g := int(stage_def.get("start_gold", 160)) + int(_diff["gold_add"]) + (40 if _has_talent("start_gold") else 0)
	gold = {1: start_g, 2: start_g}
	max_lives = maxi(1, int(stage_def.get("lives", 20)) + int(_diff["lives_add"]))
	engine.gold = 99999 # CoopTDDirector owns the P1/P2 wallets
	engine.lives = max_lives
	_bounty_mult = float(_diff["bounty_mult"])
	_hp_mult = float(_diff["hp_mult"]) * float(stage_def.get("hp_scale", 1.0)) * tuning_hp_scale

	rng.seed = randi()
	routes.clear()
	spawn_routes.clear()
	air_routes.clear()
	route_index.clear()
	spawn_ids.clear()
	_danger_dirty = true
	_adaptive_wave = -99
	if stage_def.has("graph"):
		var built := MapGraph.build_routes(stage_def["graph"])
		routes = built["routes"]
		for i in range(routes.size()):
			var r: Dictionary = routes[i]
			var lane := TDPathLane.new()
			lane.setup(str(r["id"]), r["points"])
			engine.register_lane(lane)
			route_index[str(r["id"])] = i
			if not spawn_routes.has(r["spawn"]):
				spawn_routes[r["spawn"]] = []
			(spawn_routes[r["spawn"]] as Array).append(i)
			var forks := {}
			for k in range((r["nodes"] as Array).size() - 1):
				var alts := MapGraph.fork_alternatives(routes, i, k)
				if not alts.is_empty():
					forks[k] = alts
			r["forks"] = forks
		for sp in (built["air"] as Dictionary).keys():
			var a: Dictionary = built["air"][sp]
			var alane := TDPathLane.new()
			alane.setup(str(a["id"]), a["points"])
			engine.register_lane(alane)
			air_routes[sp] = str(a["id"])
		for sp in (stage_def["graph"]["spawns"] as Dictionary).keys():
			spawn_ids.append(str(sp))
	else:
		for ldef in stage_def.get("lanes", []):
			var lane := TDPathLane.new()
			lane.setup(str(ldef["id"]), ldef["points"])
			engine.register_lane(lane)
			spawn_ids.append(str(ldef["id"]))

	pads.clear()
	for p in stage_def.get("pads", []):
		pads.append((p as Dictionary).duplicate(true))

	var build_mult := 0.90 if _has_talent("discount") else 1.0
	var branch_mult := 0.90 if _has_talent("branch_discount") else 1.0
	var guard_mult := 1.30 if _has_talent("guard_hp") else 1.0
	var defs := TowerCatalog.build_defs(build_mult, branch_mult, guard_mult)
	for tid in defs.keys():
		engine.register_tower_def(tid, defs[tid])

	for eid in CreepCatalog.ROSTER.keys():
		var cdef := (CreepCatalog.ROSTER[eid] as Dictionary).duplicate(true)
		cdef["hp"] = float(cdef["hp"]) * _hp_mult
		if cdef.has("shield"):
			cdef["shield"] = float(cdef["shield"]) * _hp_mult
		engine.register_creep_def(eid, cdef)

	for wdef in stage_def.get("waves", []):
		wave_dir.register_wave(wdef as Dictionary)
	if endless:
		_ensure_endless_queue()
	wave_dir.enemy_spawn_requested.connect(_on_spawn_requested)
	wave_dir.all_waves_finished.connect(func(): all_waves_done = true)
	wave_dir.wave_spawning_finished.connect(_on_wave_spawning_finished)

	engine.creep_killed.connect(_on_creep_killed)
	engine.tower_fired.connect(_on_tower_fired)
	engine.creep_leaked.connect(func(_c: Dictionary, _cost: int): leaks += 1)

	var cd_mult := 0.80 if _has_talent("hero_cd") else 1.0
	hero_skill_max = {1: float(HERO_SKILLS[1]["cooldown"]) * cd_mult, 2: float(HERO_SKILLS[2]["cooldown"]) * cd_mult}

	var spawns: Array = stage_def.get("hero_spawns", [Vector2(345, 108), Vector2(345, 162)])
	var h1 := commander_p1.setup_hero(engine, spawns[0], "苍穹游侠")
	_init_hero(h1, 1, 140.0 * guard_mult, 22.0, spawns[0])
	var h2 := commander_p2.setup_hero(engine, spawns[1], "绯红圣骑")
	_init_hero(h2, 2, 175.0 * guard_mult, 18.0, spawns[1])


func _init_hero(h: Dictionary, pid: int, hp: float, atk: float, home: Vector2) -> void:
	h["uid"] = "td_hero_p%d" % pid
	h["source_id"] = "td_hero_p%d" % pid
	h["name"] = ("P1苍穹游侠" if pid == 1 else "P2绯红圣骑")
	h["max_hp"] = hp
	h["hp"] = hp
	h["atk"] = atk
	h["home_pos"] = home
	h["respawn_time"] = 8.0
	h["owner_player"] = pid
	heroes[pid] = h


func _new_stats() -> Dictionary:
	return {"kills": 0, "damage": 0.0, "builds": 0, "upgrades": 0, "combo_procs": 0, "gold_sent": 0, "income": 0, "skill_casts": 0, "towers_lost": 0, "repairs": 0}


func _has_talent(tid: String) -> bool:
	return meta != null and meta.has_talent(tid)


# ---------------------------------------------------------------- spawning & enemy abilities

func _on_spawn_requested(eid: String, lid: String, wi: int) -> void:
	var spawn := lid
	if spawn == "random" and not spawn_ids.is_empty():
		spawn = spawn_ids[rng.randi() % spawn_ids.size()]
	if eid == "adaptive":
		eid = _counter_pick(wi)
	var lane_id := spawn
	if not routes.is_empty():
		var def := CreepCatalog.get_def(eid)
		if bool(def.get("is_flying", false)):
			lane_id = str(air_routes.get(spawn, air_routes.values()[0]))
		else:
			if not spawn_routes.has(spawn):
				spawn = str(spawn_routes.keys()[0])
			lane_id = str(routes[_choose_route(spawn, def, 0.0, spawn_routes[spawn])]["id"])
	var c := engine.spawn_creep(eid, lane_id)
	if c.is_empty():
		return
	c["spawn"] = spawn
	_init_creep(c, wi)


## Every road route reachable from `spawn`, ranked by tower coverage (danger), length and enemy cunning.
func _choose_route(_spawn: String, def: Dictionary, from_dist: float, cands: Array) -> int:
	if cands.size() == 1:
		return int(cands[0])
	_refresh_danger()
	var cunning := clampf(float(def.get("cunning", 0.5)) + float(_diff.get("cunning_add", 0.0)), 0.0, 1.0)
	var siege := def.has("siege")
	var dmin := INF
	var dmax := -INF
	var lmin := INF
	var ds: Array[float] = []
	var ls: Array[float] = []
	for ri in cands:
		var d := _route_danger_from(int(ri), from_dist)
		var l := float(routes[int(ri)]["total"]) - from_dist
		ds.append(d)
		ls.append(l)
		dmin = minf(dmin, d)
		dmax = maxf(dmax, d)
		lmin = minf(lmin, l)
	var weights: Array[float] = []
	var total := 0.0
	for i in range(cands.size()):
		var norm := (ds[i] - dmin) / (dmax - dmin + 1.0)
		var w := exp((2.2 if siege else -3.4) * cunning * norm)
		w *= exp(-1.4 * (ls[i] / maxf(1.0, lmin) - 1.0))
		w *= rng.randf_range(0.6, 1.4)
		weights.append(w)
		total += w
	var roll := rng.randf() * total
	for i in range(cands.size()):
		roll -= weights[i]
		if roll <= 0.0:
			return int(cands[i])
	return int(cands[cands.size() - 1])


func _refresh_danger() -> void:
	if not _danger_dirty:
		return
	_danger_dirty = false
	var tlist: Array = engine.towers.values()
	for r in routes:
		var pts: PackedVector2Array = r["points"]
		var sd := PackedFloat32Array()
		var dv := PackedFloat32Array()
		var acc := 0.0
		for i in range(pts.size() - 1):
			var a := pts[i]
			var b := pts[i + 1]
			var seg := a.distance_to(b)
			var n := maxi(1, int(seg / 16.0))
			for k in range(n):
				var p := a.lerp(b, float(k) / float(n))
				var dval := 0.0
				for t in tlist:
					var tp: Vector2 = t["pos"]
					if str(t["role"]) == "barracks":
						if tp.distance_to(p) <= 80.0:
							dval += 14.0 * float(t["level"])
					elif tp.distance_to(p) <= float(t["range"]):
						var mult := 1.0 + (0.5 if (float(t.get("splash_radius", 0.0)) > 0.0 or int(t.get("chain_count", 0)) > 0) else 0.0)
						dval += float(t["damage"]) * float(t["fire_rate"]) * mult
				sd.append(acc + seg * float(k) / float(n))
				dv.append(dval)
			acc += seg
		var suffix := PackedFloat32Array()
		suffix.resize(dv.size() + 1)
		suffix[dv.size()] = 0.0
		for i in range(dv.size() - 1, -1, -1):
			suffix[i] = suffix[i + 1] + dv[i]
		r["sample_dist"] = sd
		r["suffix"] = suffix


func _route_danger_from(ri: int, dist: float) -> float:
	var r: Dictionary = routes[ri]
	var sd: PackedFloat32Array = r["sample_dist"]
	var idx := sd.bsearch(dist)
	return float((r["suffix"] as PackedFloat32Array)[clampi(idx, 0, sd.size())])


## Smart enemies re-think their route at every fork they reach.
func _tick_reroute() -> void:
	if routes.is_empty():
		return
	for c in engine.creeps:
		if bool(c["is_flying"]) or float(c["hp"]) <= 0.0 or bool(c.get("diving", false)):
			continue
		var ri := int(c.get("route_idx", -1))
		if ri < 0:
			continue
		var r: Dictionary = routes[ri]
		var nd: Array = r["node_dist"]
		var k := int(c.get("fork_k", 1))
		if k >= nd.size() - 1:
			continue
		var dist := float(c["progress"]) * float(r["total"])
		if dist + 1.0 < float(nd[k]):
			continue
		c["fork_k"] = k + 1
		var forks: Dictionary = r["forks"]
		if not forks.has(k):
			continue
		var def := CreepCatalog.get_def(str(c["enemy_id"]))
		var cunning := clampf(float(def.get("cunning", 0.5)) + float(_diff.get("cunning_add", 0.0)), 0.0, 1.0)
		if rng.randf() > 0.25 + 0.7 * cunning:
			continue
		var cands: Array = [ri]
		cands.append_array(forks[k])
		var ni := _choose_route(str(r["spawn"]), def, dist, cands)
		if ni != ri:
			var nr: Dictionary = routes[ni]
			c["lane_id"] = str(nr["id"])
			c["route_idx"] = ni
			c["progress"] = clampf(dist / float(nr["total"]), 0.0, 1.0)


## Adaptive groups counter the players' current tower mix.
func _counter_pick(wi: int) -> String:
	var phys := 0.0
	var magic := 0.0
	var barracks := 0
	var count := 0
	for t in engine.towers.values():
		count += 1
		if str(t["role"]) == "barracks":
			barracks += 1
		elif str(t["damage_type"]) == "physical":
			phys += float(t["damage"]) * float(t["fire_rate"])
		else:
			magic += float(t["damage"]) * float(t["fire_rate"])
	var w := {"wolf": 1.0, "goblin": 1.0}
	var reason := "敌军改变了编制"
	if count == 0:
		return "wolf"
	var share := phys / maxf(0.001, phys + magic)
	if share > 0.6:
		w["shield_bearer"] = 3.0
		w["gargoyle"] = 2.0
		reason = "斥候报告：敌人看到你们箭塔多，派来了盾卫和石像鬼"
	elif share < 0.4:
		w["assassin"] = 3.0
		w["shaman"] = 1.5
		reason = "斥候报告：敌人想用快兵冲过你们的法阵"
	if float(barracks) / float(count) > 0.3:
		w["bat"] = 2.0
		w["bomb_bat"] = 2.0
		reason = "斥候报告：敌人打算从空中绕过你们的卫兵"
	if count >= 10:
		w["troll_breaker"] = 1.5
		w["goblin_archer"] = 2.0
	var total := 0.0
	for k in w.keys():
		total += float(w[k])
	var roll := rng.randf() * total
	var pick := "wolf"
	for k in w.keys():
		roll -= float(w[k])
		if roll <= 0.0:
			pick = str(k)
			break
	if wi != _adaptive_wave:
		_adaptive_wave = wi
		adaptive_pick.emit(pick, reason)
	return pick


# ---------------------------------------------------------------- monster attacks & tower HP

func _towers_near(pos: Vector2, r: float) -> Array:
	var out: Array = []
	for t in engine.towers.values():
		var d := (t["pos"] as Vector2).distance_to(pos)
		if d <= r:
			out.append([d, t])
	out.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	return out


func _tick_creep_attacks(delta: float) -> void:
	var tdm := float(_diff.get("tower_dmg", 1.0))
	for c in engine.creeps.duplicate():
		if float(c["hp"]) <= 0.0:
			continue
		var def := CreepCatalog.get_def(str(c["enemy_id"]))
		var cp: Vector2 = c["pos"]
		var stunned := float(c.get("stun_timer", 0.0)) > 0.0 and not bool(c.get("diving", false))
		var ta: Dictionary = def.get("tower_attack", {})
		if not ta.is_empty() and not stunned:
			c["atk_timer"] = float(c.get("atk_timer", 0.6)) - delta
			if float(c["atk_timer"]) <= 0.0:
				var hits := _towers_near(cp, float(ta["range"]))
				var fired := false
				for k in range(mini(int(ta.get("count", 1)), hits.size())):
					var t: Dictionary = hits[k][1]
					creep_attack.emit(c, t["pos"], str(ta["kind"]), float(ta["damage"]) * tdm)
					_damage_tower(t, float(ta["damage"]) * tdm)
					fired = true
				if not fired and bool(ta.get("soldiers", false)):
					for s in engine.soldiers:
						if float(s["hp"]) > 0.0 and (s["pos"] as Vector2).distance_to(cp) <= float(ta["range"]):
							creep_attack.emit(c, s["pos"], str(ta["kind"]), float(ta["damage"]))
							_damage_soldier(s, float(ta["damage"]))
							fired = true
							break
				c["atk_timer"] = float(ta["interval"]) if fired else 0.3
		var sg: Dictionary = def.get("siege", {})
		if not sg.is_empty():
			var near := _towers_near(cp, float(sg["reach"]))
			if not near.is_empty() and not stunned and str(c.get("blocked_by", "")) == "":
				c["sieging"] = true
				c["speed"] = 0.0
				c["siege_timer"] = float(c.get("siege_timer", 0.8)) - delta
				if float(c["siege_timer"]) <= 0.0:
					c["siege_timer"] = float(sg["interval"])
					var t: Dictionary = near[0][1]
					creep_attack.emit(c, t["pos"], "smash", float(sg["damage"]) * tdm)
					_damage_tower(t, float(sg["damage"]) * tdm)
			elif bool(c.get("sieging", false)):
				c["sieging"] = false
				c["speed"] = float(c.get("base_speed", c["speed"]))
		var kz: Dictionary = def.get("kamikaze", {})
		if not kz.is_empty():
			if not bool(c.get("diving", false)):
				var near2 := _towers_near(cp, float(kz["seek"]))
				if not near2.is_empty() and not stunned:
					c["diving"] = true
					c["dive_target"] = str((near2[0][1] as Dictionary)["uid"])
					c["stun_timer"] = 99.0
			else:
				var tgt: Dictionary = engine.towers.get(str(c.get("dive_target", "")), {})
				if tgt.is_empty():
					c["diving"] = false
					c["stun_timer"] = 0.0
					continue
				var aim: Vector2 = (tgt["pos"] as Vector2) - Vector2(0, 10)
				var step := float(c["base_speed"]) * 2.4 * delta
				if cp.distance_to(aim) <= maxf(6.0, step):
					for pair in _towers_near(aim, float(kz["radius"])):
						_damage_tower(pair[1], float(kz["damage"]) * tdm)
					creep_attack.emit(c, aim, "explode", float(kz["damage"]) * tdm)
					c["self_destruct"] = true
					c["bounty"] = 0
					c["hp"] = 0.0
				else:
					c["pos"] = cp + (aim - cp).normalized() * step
	engine._cleanup_dead_creeps()


func _damage_soldier(s: Dictionary, dmg: float) -> void:
	s["hp"] = float(s["hp"]) - dmg
	if float(s["hp"]) <= 0.0:
		s["hp"] = 0.0
		s["respawn_timer"] = float(s.get("respawn_time", 6.0))


func _damage_tower(t: Dictionary, dmg: float) -> void:
	if not engine.towers.has(str(t["uid"])):
		return
	t["hp"] = float(t.get("hp", 100.0)) - dmg
	t["last_hit_t"] = elapsed
	tower_damaged.emit(t, dmg)
	if float(t["hp"]) <= 0.0:
		_destroy_tower(t)


func _destroy_tower(t: Dictionary) -> void:
	var uid := str(t["uid"])
	var owner := int(tower_owners.get(uid, 0))
	var pad_id := str(t.get("slot_id", ""))
	engine.towers.erase(uid)
	for i in range(engine.soldiers.size() - 1, -1, -1):
		if str(engine.soldiers[i].get("owner_tower", "")) == uid:
			engine.soldiers.remove_at(i)
	tower_owners.erase(uid)
	pad_to_tower_uid.erase(pad_id)
	var pad := _find_pad(pad_id)
	if not pad.is_empty():
		pad["ruin"] = true
		pad["ruin_tower"] = str(t["tower_id"])
	if owner != 0:
		stats[owner]["towers_lost"] = int(stats[owner].get("towers_lost", 0)) + 1
	recompute_combos()
	tower_destroyed.emit(owner, pad_id, t)
	banner_event.emit("P%d 的【%s】被摧毁了！废墟上重建可省三成费用" % [owner, str(t["name"])], Color(1.0, 0.45, 0.35))


func _tick_tower_regen(delta: float) -> void:
	for t in engine.towers.values():
		var mx := float(t.get("max_hp", 0.0))
		if mx > 0.0 and float(t["hp"]) < mx and elapsed - float(t.get("last_hit_t", -99.0)) > 4.0:
			t["hp"] = minf(mx, float(t["hp"]) + mx * 0.03 * delta)


func get_build_cost(pad_id: String, tower_id: String) -> int:
	var cost := get_tower_cost(tower_id)
	var pad := _find_pad(pad_id)
	if bool(pad.get("ruin", false)):
		cost = int(round(float(cost) * 0.7))
	return cost


func get_repair_cost(pad_id: String) -> int:
	var t := get_tower_at_pad(pad_id)
	if t.is_empty():
		return 0
	var missing := 1.0 - float(t["hp"]) / maxf(1.0, float(t["max_hp"]))
	if missing <= 0.01:
		return 0
	return maxi(5, int(ceil(missing * float(t["invested"]) * 0.35)))


func repair_pad(player_id: int, pad_id: String) -> Dictionary:
	var t := get_tower_at_pad(pad_id)
	if t.is_empty():
		return {"ok": false, "reason": "空塔位"}
	if int(tower_owners.get(str(t["uid"]), 0)) != player_id:
		return {"ok": false, "reason": "只能修理自己的塔"}
	var cost := get_repair_cost(pad_id)
	if cost <= 0:
		return {"ok": false, "reason": "这座塔不需要修理"}
	if int(gold[player_id]) < cost:
		return {"ok": false, "reason": "P%d 金币不足(需%dG)" % [player_id, cost]}
	gold[player_id] = int(gold[player_id]) - cost
	t["hp"] = float(t["max_hp"])
	stats[player_id]["repairs"] = int(stats[player_id].get("repairs", 0)) + 1
	return {"ok": true, "cost": cost}


func _init_creep(c: Dictionary, wave_index: int) -> void:
	var def := CreepCatalog.get_def(str(c["enemy_id"]))
	var ri := int(route_index.get(str(c["lane_id"]), -1))
	c["route_idx"] = ri
	c["fork_k"] = 1
	if ri >= 0:
		var dist := float(c["progress"]) * float(routes[ri]["total"])
		var nd: Array = routes[ri]["node_dist"]
		var k := 1
		while k < nd.size() - 1 and float(nd[k]) <= dist:
			k += 1
		c["fork_k"] = k
	c["atk_timer"] = 0.8
	c["base_speed"] = float(c["speed"])
	c["haste_timer"] = 0.0
	c["haste_mult"] = 1.0
	c["ab_timer"] = float(def.get("heal_interval", def.get("cry_interval", def.get("roar_interval", 0.0)))) * 0.6
	c["summoned"] = false
	c["is_boss"] = bool(def.get("is_boss", false))
	var scale := 1.0
	if endless and wave_index >= 0:
		scale = get_endless_hp_scale(wave_index)
	elif wave_index > 0:
		scale = 1.0 + float(stage_def.get("wave_hp_ramp", tuning_wave_ramp)) * float(wave_index)
	if scale != 1.0:
		c["hp"] = float(c["hp"]) * scale
		c["max_hp"] = float(c["max_hp"]) * scale
		c["shield"] = float(c.get("shield", 0.0)) * scale
		c["max_shield"] = float(c.get("max_shield", 0.0)) * scale


func get_endless_hp_scale(wave_index: int) -> float:
	return 1.0 + 0.14 * float(wave_index) + 0.006 * float(wave_index * wave_index)


func _spawn_at_progress(eid: String, lane_id: String, progress: float) -> Dictionary:
	var c := engine.spawn_creep(eid, lane_id)
	if c.is_empty():
		return c
	var lane: TDPathLane = engine.lanes[lane_id]
	c["progress"] = clampf(progress, 0.0, 0.98)
	c["pos"] = lane.get_point_at_progress(float(c["progress"]))
	_init_creep(c, wave_dir.current_wave_index)
	return c


func _tick_creep_abilities(delta: float) -> void:
	for c in engine.creeps.duplicate():
		if float(c["hp"]) <= 0.0:
			continue
		# Haste (from boss war cry)
		if float(c.get("haste_timer", 0.0)) > 0.0:
			c["haste_timer"] = float(c["haste_timer"]) - delta
			c["speed"] = float(c["base_speed"]) * float(c.get("haste_mult", 1.0))
			if float(c["haste_timer"]) <= 0.0:
				c["speed"] = float(c["base_speed"])
		var def := CreepCatalog.get_def(str(c["enemy_id"]))
		var ability := str(def.get("ability", ""))
		if ability == "" or ability == "shield" or ability == "split":
			continue
		var cp: Vector2 = c["pos"]
		if ability == "summon_shield":
			if not bool(c.get("summoned", false)) and float(c["hp"]) <= float(c["max_hp"]) * 0.5:
				c["summoned"] = true
				var sh := float(def.get("summon_shield", 200.0)) * _hp_mult
				c["shield"] = sh
				c["max_shield"] = sh
				for k in range(int(def.get("summon_count", 4))):
					_spawn_at_progress(str(def.get("summon_id", "slime")), str(c["lane_id"]), float(c["progress"]) - 0.015 * float(k + 1))
				creep_ability.emit(c, "summon", cp)
				banner_event.emit("⚠ %s 展开黑曜护盾并召唤仆从！用魔法击碎护盾！" % CreepCatalog.get_display_name(str(c["enemy_id"])), Color(1.0, 0.45, 0.35))
			continue
		c["ab_timer"] = float(c.get("ab_timer", 0.0)) - delta
		if float(c["ab_timer"]) > 0.0:
			continue
		match ability:
			"heal_aura":
				c["ab_timer"] = float(def.get("heal_interval", 2.6))
				var healed := false
				for o in engine.creeps:
					if float(o["hp"]) > 0.0 and float(o["hp"]) < float(o["max_hp"]) and cp.distance_to(o["pos"]) <= float(def.get("heal_radius", 50.0)):
						o["hp"] = minf(float(o["max_hp"]), float(o["hp"]) + float(def.get("heal_amount", 16.0)) * _hp_mult)
						healed = true
				if healed:
					creep_ability.emit(c, "heal", cp)
			"war_cry":
				c["ab_timer"] = float(def.get("cry_interval", 6.5))
				for o in engine.creeps:
					if o != c and float(o["hp"]) > 0.0 and cp.distance_to(o["pos"]) <= float(def.get("cry_radius", 64.0)):
						o["haste_timer"] = float(def.get("cry_duration", 3.0))
						o["haste_mult"] = float(def.get("cry_haste", 1.4))
				creep_ability.emit(c, "war_cry", cp)
			"frost_roar":
				c["ab_timer"] = float(def.get("roar_interval", 8.0))
				var freeze := float(def.get("roar_freeze", 2.2))
				for t in engine.towers.values().duplicate():
					if (t["pos"] as Vector2).distance_to(cp) <= float(def.get("roar_radius", 96.0)):
						t["cooldown"] = maxf(float(t["cooldown"]), freeze)
						t["frozen_timer"] = freeze
						_damage_tower(t, float(def.get("roar_damage", 0.0)) * float(_diff.get("tower_dmg", 1.0)))
				creep_ability.emit(c, "frost_roar", cp)


func _on_creep_killed(creep: Dictionary, bounty: int) -> void:
	if bool(creep.get("self_destruct", false)):
		return
	var share := maxi(1, int(ceil(float(bounty) * tuning_bounty_share * _bounty_mult)))
	for pid in [1, 2]:
		gold[pid] = int(gold[pid]) + share
		stats[pid]["income"] = int(stats[pid]["income"]) + share

	var killer := _owner_of_source(str(creep.get("last_hit_by", "")))
	if killer == 0:
		killer = 1 if (creep["pos"] as Vector2).y < 136.0 else 2
	kills[killer] = int(kills[killer]) + 1
	stats[killer]["kills"] = int(stats[killer]["kills"]) + 1

	if not _suppress_charge:
		var charge_mult := 1.40 if _has_talent("ult_charge") else 1.0
		var gain := 20.0 if bool(creep.get("is_boss", false)) else 6.5
		synchro_charge = minf(100.0, synchro_charge + gain * charge_mult)

	var def := CreepCatalog.get_def(str(creep["enemy_id"]))
	if str(def.get("ability", "")) == "split":
		for k in range(int(def.get("split_count", 2))):
			var child := _spawn_at_progress(str(def.get("split_into", "slimelet")), str(creep["lane_id"]), float(creep["progress"]) - 0.012 * float(k))
			if not child.is_empty():
				child["pos"] = (child["pos"] as Vector2) + Vector2(0, -5 + 10 * k)
		creep_ability.emit(creep, "split", creep["pos"])


func _owner_of_source(src: String) -> int:
	if src == "":
		return 0
	if src.begins_with("td_hero_p1") or src.begins_with("__p1"):
		return 1
	if src.begins_with("td_hero_p2") or src.begins_with("__p2"):
		return 2
	return int(_source_owner.get(src, 0))


# ---------------------------------------------------------------- combos

func _on_tower_fired(tower: Dictionary, target: Dictionary, dmg: float) -> void:
	var tuid := str(tower["uid"])
	var owner := int(tower_owners.get(tuid, 0))
	if owner != 0:
		stats[owner]["damage"] = float(stats[owner]["damage"]) + dmg
	var combo_mult := 1.25 if _has_talent("combo_power") else 1.0
	var tid := str(tower["tower_id"])
	for link in combo_links:
		if str(link["t1_uid"]) != tuid and str(link["t2_uid"]) != tuid:
			continue
		var kind := str(link["kind"])
		var procced := false
		match kind:
			"ice_fire_overload":
				if float(target.get("slow_timer", 0.0)) > 0.0:
					engine.apply_damage_to_creep(target, 9.0 * combo_mult, "true")
					procced = true
			"arrow_barracks_crit":
				if str(target.get("blocked_by", "")) != "":
					engine.apply_damage_to_creep(target, 8.0 * combo_mult, "true")
					procced = true
			"shatter_arrow":
				if tid == "arrow" and float(target.get("slow_timer", 0.0)) > 0.0:
					engine.apply_damage_to_creep(target, 6.0 * combo_mult, "true")
					procced = true
			"arcane_shred":
				engine.apply_status_to_creep(target, "shred", 5.0 * combo_mult, 2.5)
				procced = true
		if procced:
			_count_combo_proc(link, target["pos"])


func _count_combo_proc(link: Dictionary, pos: Vector2) -> void:
	for pid in [1, 2]:
		stats[pid]["combo_procs"] = int(stats[pid]["combo_procs"]) + 1
	if float(link.get("proc_cd", 0.0)) <= 0.0:
		link["proc_cd"] = 0.45
		combo_proc.emit(str(link["kind"]), pos, link["color"])


func _tick_combo_passives(delta: float) -> void:
	for link in combo_links:
		link["proc_cd"] = maxf(0.0, float(link.get("proc_cd", 0.0)) - delta)
		if str(link["kind"]) != "frost_bulwark":
			continue
		var t1: Dictionary = engine.towers.get(str(link["t1_uid"]), {})
		var t2: Dictionary = engine.towers.get(str(link["t2_uid"]), {})
		var barracks_uid := str(link["t1_uid"]) if str(t1.get("role", "")) == "barracks" else str(link["t2_uid"])
		if t2.is_empty() or t1.is_empty():
			continue
		var soldier_uids := {}
		for s in engine.soldiers:
			if str(s.get("owner_tower", "")) == barracks_uid:
				soldier_uids[str(s["uid"])] = true
		for c in engine.creeps:
			if soldier_uids.has(str(c.get("blocked_by", ""))):
				var was_slow := float(c.get("slow_timer", 0.0)) > 0.0
				engine.apply_status_to_creep(c, "slow", 0.6, 0.6)
				if not was_slow:
					_count_combo_proc(link, c["pos"])


func _combo_kind_for(id1: String, id2: String) -> String:
	var pair := [id1, id2]
	pair.sort()
	var key := "%s+%s" % [pair[0], pair[1]]
	match key:
		"frost+mage": return "ice_fire_overload"
		"arrow+barracks": return "arrow_barracks_crit"
		"arrow+frost": return "shatter_arrow"
		"arrow+mage": return "arcane_shred"
		"barracks+frost": return "frost_bulwark"
	return "twin_star_haste"


func recompute_combos() -> Array[Dictionary]:
	_danger_dirty = true
	combo_links.clear()
	var haste_counts: Dictionary = {}
	var uids := engine.towers.keys()
	for i in range(uids.size()):
		for j in range(i + 1, uids.size()):
			var u1 := str(uids[i])
			var u2 := str(uids[j])
			if int(tower_owners.get(u1, 1)) == int(tower_owners.get(u2, 1)):
				continue # combos are strictly cross-player
			var t1: Dictionary = engine.towers[u1]
			var t2: Dictionary = engine.towers[u2]
			if (t1["pos"] as Vector2).distance_to(t2["pos"] as Vector2) > COMBO_RADIUS:
				continue
			var kind := _combo_kind_for(str(t1["tower_id"]), str(t2["tower_id"]))
			var cdef: Dictionary = COMBO_DEFS[kind]
			if kind == "twin_star_haste":
				haste_counts[u1] = int(haste_counts.get(u1, 0)) + 1
				haste_counts[u2] = int(haste_counts.get(u2, 0)) + 1
			combo_links.append({
				"t1_uid": u1, "t2_uid": u2,
				"from_pos": t1["pos"], "to_pos": t2["pos"],
				"kind": kind, "label": str(cdef["label"]), "desc": str(cdef["desc"]), "color": cdef["color"],
				"proc_cd": 0.0,
			})
	for uid in engine.towers.keys():
		var t: Dictionary = engine.towers[uid]
		var n := mini(2, int(haste_counts.get(uid, 0)))
		t["fire_rate"] = float(t.get("base_fire_rate", t["fire_rate"])) * (1.0 + 0.15 * float(n))
	combo_links_updated.emit(combo_links)
	return combo_links


# ---------------------------------------------------------------- towers

func get_tower_cost(tower_id: String) -> int:
	var def: Dictionary = engine.tower_defs.get(tower_id, {})
	return int(def.get("cost", 60))


func get_tower_at_pad(pad_id: String) -> Dictionary:
	if not pad_to_tower_uid.has(pad_id):
		return {}
	return engine.towers.get(str(pad_to_tower_uid[pad_id]), {})


func get_pad_owner(pad_id: String) -> int:
	if not pad_to_tower_uid.has(pad_id):
		return 0
	return int(tower_owners.get(str(pad_to_tower_uid[pad_id]), 0))


## Returns [{index, name, cost, desc, branch}] for the tower on `pad_id` (empty at max level).
func get_upgrade_options(pad_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not pad_to_tower_uid.has(pad_id):
		return out
	for u in engine.get_available_upgrades(str(pad_to_tower_uid[pad_id])):
		out.append({
			"index": int(u["_index"]), "name": str(u.get("name", "")), "cost": int(u.get("cost", 60)),
			"desc": str(u.get("desc", "")), "branch": str(u.get("branch", "")),
		})
	return out


func get_sell_refund(pad_id: String) -> int:
	var t := get_tower_at_pad(pad_id)
	if t.is_empty():
		return 0
	return int(round(float(t.get("invested", 0)) * engine.sell_refund_ratio))


func build_or_upgrade_pad(player_id: int, pad_id: String, tower_id: String, branch: int = -1) -> Dictionary:
	var pad := _find_pad(pad_id)
	if pad.is_empty():
		return {"ok": false, "reason": "无效塔位"}
	if pad_to_tower_uid.has(pad_id):
		return upgrade_pad(player_id, pad_id, branch)

	if not engine.tower_defs.has(tower_id):
		return {"ok": false, "reason": "未知塔种"}
	var cost := get_build_cost(pad_id, tower_id)
	if int(gold[player_id]) < cost:
		return {"ok": false, "reason": "P%d 金币不足(需%dG)" % [player_id, cost]}
	engine.gold = 99999
	var pres := engine.place_tower(tower_id, pad["pos"], pad_id, pad["rally"])
	if bool(pres["ok"]):
		gold[player_id] = int(gold[player_id]) - cost
		var tower: Dictionary = pres["tower"]
		var tuid := str(tower["uid"])
		tower["base_fire_rate"] = float(tower["fire_rate"])
		tower["branch"] = ""
		tower["owner"] = player_id
		tower["frozen_timer"] = 0.0
		tower["respawn_time"] = float(engine.tower_defs[tower_id].get("respawn_time", 6.0))
		tower["block_count"] = int(engine.tower_defs[tower_id].get("block_count", 1))
		tower["max_hp"] = float(engine.tower_defs[tower_id].get("max_hp", 160.0))
		tower["hp"] = float(tower["max_hp"])
		tower["last_hit_t"] = -99.0
		tower["invested"] = cost
		pad["ruin"] = false
		tower_owners[tuid] = player_id
		_source_owner[tuid] = player_id
		pad_to_tower_uid[pad_id] = tuid
		_sync_barracks_soldiers(tower)
		stats[player_id]["builds"] = int(stats[player_id]["builds"]) + 1
		recompute_combos()
		tower_built.emit(player_id, pad_id, tower)
	return pres


func upgrade_pad(player_id: int, pad_id: String, branch: int = -1) -> Dictionary:
	if not pad_to_tower_uid.has(pad_id):
		return {"ok": false, "reason": "空塔位"}
	var tuid := str(pad_to_tower_uid[pad_id])
	var owner := int(tower_owners.get(tuid, 1))
	if owner != player_id:
		return {"ok": false, "reason": "该塔归属搭档 P%d" % owner}
	var t: Dictionary = engine.towers.get(tuid, {})
	if t.is_empty():
		return {"ok": false, "reason": "防御塔不存在"}
	var avail := engine.get_available_upgrades(tuid)
	if avail.is_empty():
		return {"ok": false, "reason": "已达最高等级"}
	var chosen: Dictionary = avail[clampi(branch, 0, avail.size() - 1)] if branch >= 0 else avail[0]
	var cost := int(chosen.get("cost", 60))
	if int(gold[player_id]) < cost:
		return {"ok": false, "reason": "P%d 金币不足(需%dG)" % [player_id, cost]}
	t["fire_rate"] = float(t.get("base_fire_rate", t["fire_rate"]))
	engine.gold = 99999
	var ures := engine.upgrade_tower(tuid, int(chosen["_index"]))
	if not bool(ures["ok"]):
		recompute_combos()
		return ures
	gold[player_id] = int(gold[player_id]) - cost
	t["fire_rate"] = maxf(0.2, float(t["fire_rate"]))
	t["base_fire_rate"] = float(t["fire_rate"])
	var sets: Dictionary = chosen.get("set", {})
	for k in sets.keys():
		t[k] = sets[k]
	var hp_add := float(chosen.get("hp_add", 0.0))
	t["max_hp"] = float(t.get("max_hp", 160.0)) + hp_add
	t["hp"] = float(t.get("hp", t["max_hp"])) + hp_add
	_sync_barracks_soldiers(t)
	stats[player_id]["upgrades"] = int(stats[player_id]["upgrades"]) + 1
	recompute_combos()
	tower_upgraded.emit(player_id, pad_id, t)
	return ures


func _sync_barracks_soldiers(t: Dictionary) -> void:
	if str(t.get("role", "")) != "barracks":
		return
	var tuid := str(t["uid"])
	var mine: Array[Dictionary] = []
	for s in engine.soldiers:
		if str(s.get("owner_tower", "")) == tuid:
			mine.append(s)
	var want := int(t.get("soldier_count", 2))
	var rally: Vector2 = t["rally_pos"]
	while mine.size() < want:
		var s := engine.spawn_temporary_blocker(rally, float(t["soldier_hp"]), float(t["soldier_atk"]), -1.0, 1)
		s["owner_tower"] = tuid
		s["source_id"] = tuid
		mine.append(s)
	for i in range(mine.size()):
		var s: Dictionary = mine[i]
		var offset := Vector2((float(i) - float(mine.size() - 1) * 0.5) * 12.0, (i % 2) * 3.0)
		s["home_pos"] = rally + offset
		s["respawn_time"] = float(t.get("respawn_time", 6.0))
		s["block_count"] = int(t.get("block_count", 1))
		s["max_hp"] = float(t["soldier_hp"])
		s["atk"] = float(t["soldier_atk"])


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
	tower_sold.emit(player_id, pad_id, refund)
	return {"ok": true, "refund": refund}


func set_tower_priority(player_id: int, pad_id: String, priority: int) -> Dictionary:
	var t := get_tower_at_pad(pad_id)
	if t.is_empty():
		return {"ok": false, "reason": "空塔位"}
	if int(tower_owners.get(str(t["uid"]), 0)) != player_id:
		return {"ok": false, "reason": "只能调整自己的塔"}
	t["priority"] = posmod(priority, 4)
	return {"ok": true, "priority": int(t["priority"])}


func set_barracks_rally(player_id: int, pad_id: String, pos: Vector2) -> Dictionary:
	var t := get_tower_at_pad(pad_id)
	if t.is_empty() or str(t.get("role", "")) != "barracks":
		return {"ok": false, "reason": "只有兵营可以设置集结点"}
	if int(tower_owners.get(str(t["uid"]), 0)) != player_id:
		return {"ok": false, "reason": "只能调整自己的兵营"}
	var snap := _nearest_lane_point(pos)
	if snap.distance_to(pos) > 20.0:
		return {"ok": false, "reason": "集结点必须在道路上"}
	if snap.distance_to(t["pos"]) > RALLY_RANGE:
		return {"ok": false, "reason": "集结点超出兵营范围"}
	t["rally_pos"] = snap
	_sync_barracks_soldiers(t)
	return {"ok": true, "pos": snap}


func _tick_soldier_walk(delta: float) -> void:
	var engaged := {}
	for c in engine.creeps:
		var b := str(c.get("blocked_by", ""))
		if b != "":
			engaged[b] = true
	for s in engine.soldiers:
		if bool(s.get("is_hero", false)) or float(s["hp"]) <= 0.0 or engaged.has(str(s["uid"])):
			continue
		var home: Vector2 = s.get("home_pos", s["pos"])
		var cur: Vector2 = s["pos"]
		var d := home - cur
		if d.length() > 0.5:
			s["pos"] = cur + d.normalized() * minf(d.length(), SOLDIER_WALK_SPEED * delta)
		else:
			s["hp"] = minf(float(s["max_hp"]), float(s["hp"]) + 4.0 * delta)


func transfer_gold(from_p: int, to_p: int, amount: int = 50) -> bool:
	if from_p == to_p or amount <= 0 or int(gold.get(from_p, 0)) < amount:
		return false
	var bonus := 15 if _has_talent("gold_gift") else 0
	gold[from_p] = int(gold[from_p]) - amount
	gold[to_p] = int(gold[to_p]) + amount + bonus
	stats[from_p]["gold_sent"] = int(stats[from_p]["gold_sent"]) + amount
	gold_transferred.emit(from_p, to_p, amount, bonus)
	banner_event.emit("P%d 向 P%d 支援 %dG%s" % [from_p, to_p, amount, ("（天赋加赠 %dG）" % bonus if bonus > 0 else "")], Color(1.0, 0.92, 0.32))
	return true


# ---------------------------------------------------------------- heroes & ultimate

func rally_hero(player_id: int, pos: Vector2) -> void:
	(commander_p1 if player_id == 1 else commander_p2).rally_hero(pos)


func cast_hero_skill(player_id: int, pos: Vector2) -> Dictionary:
	if float(hero_skill_cd.get(player_id, 0.0)) > 0.0:
		return {"ok": false, "reason": "技能冷却中(%.0fs)" % float(hero_skill_cd[player_id])}
	var sk: Dictionary = HERO_SKILLS[player_id]
	var hits := 0
	if player_id == 1:
		var r := float(sk["radius"])
		for c in engine.creeps:
			if float(c["hp"]) > 0.0 and pos.distance_to(c["pos"]) <= r:
				c["last_hit_by"] = "__p1_skill__"
				engine.apply_damage_to_creep(c, float(sk["damage"]), "magic")
				engine.apply_status_to_creep(c, "burn", 12.0, 3.0)
				hits += 1
		engine._cleanup_dead_creeps()
	else:
		var snap := _nearest_lane_point(pos)
		if snap.distance_to(pos) > 40.0:
			return {"ok": false, "reason": "援军需要部署在道路附近"}
		for k in range(2):
			var s := engine.spawn_temporary_blocker(snap + Vector2(-8 + 16 * k, 0), float(sk["hp"]), float(sk["atk"]), float(sk["lifetime"]), 1)
			s["owner_tower"] = "__p2_skill__"
			s["source_id"] = "__p2_skill__"
			s["is_reinforcement"] = true
		pos = snap
		hits = 2
	hero_skill_cd[player_id] = float(hero_skill_max[player_id])
	stats[player_id]["skill_casts"] = int(stats[player_id]["skill_casts"]) + 1
	hero_skill_cast.emit(player_id, str(sk["id"]), pos, hits)
	return {"ok": true, "hits": hits, "pos": pos}


func trigger_synchro_ult(player_id: int) -> Dictionary:
	if synchro_charge < 100.0:
		return {"ok": false, "reason": "双星能量未满(%d%%)" % int(synchro_charge)}
	if synchro_pending_by == 0:
		synchro_pending_by = player_id
		synchro_window_timer = SYNCHRO_WINDOW_SEC
		synchro_requested.emit(player_id)
		banner_event.emit("P%d 发起【双星合体】！搭档请在 5 秒内响应！" % player_id, Color(1.0, 0.94, 0.30))
		return {"ok": true, "state": "pending"}
	if synchro_pending_by != player_id:
		var initiator := synchro_pending_by
		synchro_charge = 0.0
		synchro_pending_by = 0
		synchro_window_timer = 0.0
		var hits := 0
		for c in engine.creeps.duplicate():
			c["last_hit_by"] = "__p%d_ult__" % initiator
			var dmg := 140.0 if not bool(c.get("is_boss", false)) else 140.0 + float(c["max_hp"]) * 0.08
			engine.apply_damage_to_creep(c, dmg, "true")
			c["stun_timer"] = maxf(float(c.get("stun_timer", 0.0)), 3.0)
			hits += 1
		for s in engine.soldiers:
			s["hp"] = float(s["max_hp"])
		_suppress_charge = true
		engine._cleanup_dead_creeps()
		_suppress_charge = false
		synchro_unleashed.emit(hits)
		banner_event.emit("【苍穹双星陨落】命中 %d 名敌人 · 全场冰封 3 秒 · 全军满血！" % hits, Color(1.0, 0.52, 0.96))
		return {"ok": true, "state": "unleashed", "hits": hits}
	return {"ok": false, "reason": "等待搭档响应中..."}


func send_ping(player_id: int, pos: Vector2, label: String = "支援这里!") -> void:
	active_pings.append({"player_id": player_id, "pos": pos, "label": label, "ttl": 3.5})
	tactical_pinged.emit(player_id, pos, label)


# ---------------------------------------------------------------- waves

func get_next_wave_def() -> Dictionary:
	var ni := wave_dir.current_wave_index + 1
	if ni < wave_dir.waves.size():
		return wave_dir.waves[ni]
	return {}


func get_early_call_bonus() -> int:
	if wave_dir.current_wave_index < 0:
		return 0
	var base := int(get_next_wave_def().get("early_bonus", 20))
	if wave_countdown > 0.0:
		return int(round(float(base) * clampf(wave_countdown / maxf(1.0, countdown_total), 0.0, 1.0)))
	if wave_dir.is_spawning:
		return base
	return 0


func call_next_wave() -> Dictionary:
	if endless:
		_ensure_endless_queue()
	if not wave_dir.has_next_wave():
		return {"ok": false, "reason": "已无后续波次"}
	var bonus := get_early_call_bonus()
	wave_countdown = -1.0
	var res := wave_dir.start_next_wave()
	if not bool(res["ok"]):
		return res
	res["early_bonus"] = bonus
	if bonus > 0:
		for pid in [1, 2]:
			gold[pid] = int(gold[pid]) + bonus
			stats[pid]["income"] = int(stats[pid]["income"]) + bonus
		banner_event.emit("提前召唤奖励：双方各 +%dG" % bonus, Color(1.0, 0.92, 0.32))
	if endless:
		endless_best_wave = maxi(endless_best_wave, wave_dir.current_wave_index + 1)
		_ensure_endless_queue()
	wave_called.emit(wave_dir.current_wave_index, bonus)
	return res


func _on_wave_spawning_finished(_wi: int) -> void:
	if wave_dir.has_next_wave() or endless:
		wave_countdown = countdown_total
		countdown_started.emit(countdown_total)


func _ensure_endless_queue() -> void:
	while not wave_dir.has_next_wave():
		wave_dir.register_wave(generate_endless_wave(wave_dir.waves.size()))


## Procedural endless wave: rotates themed rosters across all lanes; boss every 5th wave.
func generate_endless_wave(index: int) -> Dictionary:
	var lane_ids: Array[String] = spawn_ids.duplicate()
	var themes := [
		["slime", "wolf"], ["goblin", "shield_bearer"], ["bat", "gargoyle"], ["splitter", "shaman"],
		["assassin", "wolf"], ["shield_bearer", "shaman"], ["gargoyle", "assassin"], ["goblin", "splitter"],
	]
	var theme: Array = themes[index % themes.size()]
	var groups: Array = []
	var count := 4 + int(index / 2)
	for li in range(lane_ids.size()):
		groups.append({"enemy_id": theme[li % theme.size()], "lane_id": lane_ids[li], "count": count, "interval": maxf(0.45, 0.9 - 0.02 * index)})
	if index % 5 == 4:
		var bosses := ["boss_warlord", "boss_frost_colossus", "boss_obsidian"]
		groups.append({"enemy_id": bosses[int(index / 5) % bosses.size()], "lane_id": lane_ids[index % lane_ids.size()], "count": 1, "interval": 1.0, "delay": 2.0})
	return {"name": "无尽 第%d波" % (index + 1), "early_bonus": 20 + index * 2, "groups": groups}


# ---------------------------------------------------------------- commands & tick

func execute_command(cmd: Dictionary) -> Dictionary:
	var pid := int(cmd.get("player_id", 1))
	var act := str(cmd.get("action", ""))
	match act:
		"build_or_upgrade":
			return build_or_upgrade_pad(pid, str(cmd.get("pad_id", "")), str(cmd.get("tower_id", "arrow")), int(cmd.get("branch", -1)))
		"upgrade":
			return upgrade_pad(pid, str(cmd.get("pad_id", "")), int(cmd.get("branch", -1)))
		"sell":
			return sell_pad(pid, str(cmd.get("pad_id", "")))
		"repair":
			return repair_pad(pid, str(cmd.get("pad_id", "")))
		"set_priority":
			return set_tower_priority(pid, str(cmd.get("pad_id", "")), int(cmd.get("priority", 0)))
		"set_rally":
			return set_barracks_rally(pid, str(cmd.get("pad_id", "")), Vector2(float(cmd.get("x", 0.0)), float(cmd.get("y", 0.0))))
		"transfer_gold":
			return {"ok": transfer_gold(pid, 2 if pid == 1 else 1, int(cmd.get("amount", 50)))}
		"rally_hero":
			rally_hero(pid, Vector2(float(cmd.get("x", 340.0)), float(cmd.get("y", 136.0))))
			return {"ok": true}
		"hero_skill":
			return cast_hero_skill(pid, Vector2(float(cmd.get("x", 240.0)), float(cmd.get("y", 136.0))))
		"synchro_ult":
			return trigger_synchro_ult(pid)
		"ping":
			send_ping(pid, Vector2(float(cmd.get("x", 240.0)), float(cmd.get("y", 136.0))), str(cmd.get("label", "支援!")))
			return {"ok": true}
		"call_wave":
			return call_next_wave()
		_:
			return {"ok": false, "reason": "未知指令"}


func tick(delta: float) -> void:
	elapsed += delta
	if wave_countdown > 0.0:
		wave_countdown -= delta
		if wave_countdown <= 0.0:
			wave_countdown = -1.0
			call_next_wave()
	wave_dir.tick(delta)
	commander_p1.tick(delta)
	commander_p2.tick(delta)
	for pid in [1, 2]:
		hero_skill_cd[pid] = maxf(0.0, float(hero_skill_cd[pid]) - delta)
	for t in engine.towers.values():
		if float(t.get("frozen_timer", 0.0)) > 0.0:
			t["frozen_timer"] = maxf(0.0, float(t["frozen_timer"]) - delta)
	_tick_creep_abilities(delta)
	_tick_creep_attacks(delta)
	_tick_combo_passives(delta)
	_tick_soldier_walk(delta)
	_tick_tower_regen(delta)
	engine.tick(delta)
	_tick_reroute()
	if synchro_pending_by != 0:
		synchro_window_timer -= delta
		if synchro_window_timer <= 0.0:
			synchro_pending_by = 0
	for i in range(active_pings.size() - 1, -1, -1):
		active_pings[i]["ttl"] = float(active_pings[i]["ttl"]) - delta
		if float(active_pings[i]["ttl"]) <= 0.0:
			active_pings.remove_at(i)


func is_victory() -> bool:
	return not endless and all_waves_done and engine.creeps.is_empty() and engine.lives > 0


func is_defeat() -> bool:
	return engine.lives <= 0


func get_mvp() -> int:
	var s1 := int(stats[1]["kills"]) * 10 + int(float(stats[1]["damage"]) / 20.0) + int(stats[1]["gold_sent"]) / 5
	var s2 := int(stats[2]["kills"]) * 10 + int(float(stats[2]["damage"]) / 20.0) + int(stats[2]["gold_sent"]) / 5
	return 1 if s1 >= s2 else 2


func _nearest_lane_point(pos: Vector2) -> Vector2:
	var best := pos
	var best_d := INF
	for lane in engine.lanes.values():
		var l := lane as TDPathLane
		if l.lane_id.ends_with("#air"):
			continue
		var steps := maxi(20, int(l.total_length / 6.0))
		for step in range(steps + 1):
			var pt := l.get_point_at_progress(float(step) / float(steps))
			var d := pos.distance_to(pt)
			if d < best_d:
				best_d = d
				best = pt
	return best


func _find_pad(pad_id: String) -> Dictionary:
	for p in pads:
		if str(p["id"]) == pad_id:
			return p
	return {}


func _pcol(pid: int) -> Color:
	return P1_COLOR if pid == 1 else P2_COLOR
