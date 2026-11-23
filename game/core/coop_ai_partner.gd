class_name CoopAIPartner
extends RefCounted
## Autonomous co-op AI for one seat (P1 or P2). Solo mode drives P2 with it; the balance sim drives both.
## - Builds on its own / shared pads, best path coverage first, picking combo partners for nearby ally towers
## - Upgrades (and picks Lv3 branches) once its pads are filled
## - Sends gold to a struggling partner, answers (and starts) the Synchro Ultimate
## - Uses its hero skill on clusters / leaking enemies and rallies its hero to the most pressured lane
## Every action goes through `director.execute_command`, exactly like a human player.

var player_id: int = 2
var decision_interval: float = 1.4
var allow_ult_initiate: bool = true
var control_hero: bool = true
var branch_pref: Dictionary = {"arrow": 0, "mage": 1, "frost": 1, "barracks": 0}
var build_cycle: Array[String] = ["barracks", "arrow", "mage", "frost"]
var _timer: float = 0.8
var _pad_cover: Dictionary = {}


func _init(pid: int = 2) -> void:
	player_id = pid
	if pid == 1:
		branch_pref = {"arrow": 1, "mage": 0, "frost": 0, "barracks": 1}
		build_cycle = ["arrow", "frost", "mage", "barracks"]


## Varies build order and branch picks (used by the balance sim to sample different play styles).
func randomize_style(rng: RandomNumberGenerator) -> void:
	var cycle: Array[String] = ["arrow", "mage", "frost", "barracks"]
	for i in range(cycle.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := cycle[i]
		cycle[i] = cycle[j]
		cycle[j] = tmp
	build_cycle = cycle
	for k in branch_pref.keys():
		branch_pref[k] = rng.randi_range(0, 1)
	decision_interval = rng.randf_range(1.1, 2.2)


func tick(delta: float, director: CoopTDDirector) -> void:
	if director == null or delta <= 0.0:
		return
	var partner := 3 - player_id
	if director.synchro_pending_by == partner and director.synchro_charge >= 100.0:
		director.execute_command({"player_id": player_id, "action": "synchro_ult"})
		return

	_timer -= delta
	if _timer > 0.0:
		return
	_timer = decision_interval

	if control_hero:
		_try_hero_skill(director)
		_rally_hero(director)

	if allow_ult_initiate and director.synchro_pending_by == 0 and director.synchro_charge >= 100.0 and _ult_worth_it(director):
		director.execute_command({"player_id": player_id, "action": "synchro_ult"})
		return

	var mine := int(director.gold.get(player_id, 0))
	var theirs := int(director.gold.get(partner, 0))
	if theirs < 50 and mine >= 140:
		director.execute_command({"player_id": player_id, "action": "transfer_gold", "amount": 50})
		return

	# Repair badly damaged towers first
	for pad in director.pads:
		var rp := str(pad["id"])
		if director.get_pad_owner(rp) != player_id:
			continue
		var tw := director.get_tower_at_pad(rp)
		if float(tw.get("hp", 1.0)) < float(tw.get("max_hp", 1.0)) * 0.55:
			var rc := director.get_repair_cost(rp)
			if rc > 0 and mine >= rc:
				director.execute_command({"player_id": player_id, "action": "repair", "pad_id": rp})
				return

	# Build on the best empty pad we are allowed to use
	for pad in _ordered_pads(director):
		var pid := str(pad["id"])
		if director.pad_to_tower_uid.has(pid):
			continue
		var chosen := _choose_tower(pad["pos"] as Vector2, director)
		if mine >= director.get_build_cost(pid, chosen):
			director.execute_command({"player_id": player_id, "action": "build_or_upgrade", "pad_id": pid, "tower_id": chosen})
		return # wait (save up) for the best pad instead of skipping it

	# All usable pads are filled: upgrade the cheapest available upgrade
	var best_pad := ""
	var best_cost := 1 << 30
	var best_branch := -1
	for pad in director.pads:
		var pid := str(pad["id"])
		if director.get_pad_owner(pid) != player_id:
			continue
		var opts := director.get_upgrade_options(pid)
		if opts.is_empty():
			continue
		var t := director.get_tower_at_pad(pid)
		var bi := 0
		if opts.size() > 1:
			bi = clampi(int(branch_pref.get(str(t["tower_id"]), 0)), 0, opts.size() - 1)
		var cost := int(opts[bi]["cost"])
		if cost < best_cost:
			best_cost = cost
			best_pad = pid
			best_branch = bi if opts.size() > 1 else -1
	if best_pad != "" and mine >= best_cost:
		director.execute_command({"player_id": player_id, "action": "upgrade", "pad_id": best_pad, "branch": best_branch})


func _ordered_pads(director: CoopTDDirector) -> Array[Dictionary]:
	var partner := 3 - player_id
	var own: Array[Dictionary] = []
	var shared: Array[Dictionary] = []
	for pad in director.pads:
		var hint := int(pad.get("owner_hint", 0))
		if hint == partner:
			continue
		if hint == player_id:
			own.append(pad)
		else:
			shared.append(pad)
	var by_cover := func(a: Dictionary, b: Dictionary) -> bool:
		return _coverage(a, director) > _coverage(b, director)
	own.sort_custom(by_cover)
	shared.sort_custom(by_cover)
	var out: Array[Dictionary] = []
	out.append_array(own)
	out.append_array(shared)
	return out


func _coverage(pad: Dictionary, director: CoopTDDirector) -> int:
	var key := str(pad["id"])
	if _pad_cover.has(key):
		return int(_pad_cover[key])
	var pp: Vector2 = pad["pos"]
	var n := 0
	for lane in director.engine.lanes.values():
		var l := lane as TDPathLane
		if l.lane_id.ends_with("#air"):
			continue
		var steps := maxi(10, int(l.total_length / 8.0))
		for s in range(steps + 1):
			if pp.distance_to(l.get_point_at_progress(float(s) / float(steps))) <= 105.0:
				n += 1
	_pad_cover[key] = n
	return n


func _choose_tower(pad_pos: Vector2, director: CoopTDDirector) -> String:
	var partner := 3 - player_id
	for uid in director.engine.towers.keys():
		if int(director.tower_owners.get(uid, 0)) != partner:
			continue
		var t: Dictionary = director.engine.towers[uid]
		if (t["pos"] as Vector2).distance_to(pad_pos) <= CoopTDDirector.COMBO_RADIUS:
			match str(t["tower_id"]):
				"frost": return "mage"
				"mage": return "frost"
				"arrow": return "barracks"
				"barracks": return "arrow"
	var count := 0
	for o in director.tower_owners.values():
		if int(o) == player_id:
			count += 1
	return build_cycle[count % build_cycle.size()]


func _try_hero_skill(director: CoopTDDirector) -> void:
	if float(director.hero_skill_cd.get(player_id, 1.0)) > 0.0 or director.engine.creeps.is_empty():
		return
	if player_id == 1:
		var best_pos := Vector2.ZERO
		var best_n := 0
		for c in director.engine.creeps:
			var n := 0
			for o in director.engine.creeps:
				if (c["pos"] as Vector2).distance_to(o["pos"]) <= 50.0:
					n += 3 if bool(o.get("is_boss", false)) else 1
			if n > best_n:
				best_n = n
				best_pos = c["pos"]
		if best_n >= 4:
			director.execute_command({"player_id": 1, "action": "hero_skill", "x": best_pos.x, "y": best_pos.y})
	else:
		var lead: Dictionary = {}
		for c in director.engine.creeps:
			if bool(c["is_flying"]):
				continue
			if lead.is_empty() or float(c["progress"]) > float(lead["progress"]):
				lead = c
		if not lead.is_empty() and (float(lead["progress"]) > 0.55 or director.engine.creeps.size() >= 8):
			var p: Vector2 = lead["pos"]
			director.execute_command({"player_id": 2, "action": "hero_skill", "x": p.x, "y": p.y})


func _rally_hero(director: CoopTDDirector) -> void:
	var lead: Dictionary = {}
	var best_score := -1.0
	for c in director.engine.creeps:
		if bool(c["is_flying"]):
			continue
		# Prefer threats on lanes passing our side of the map
		var side_ok := ((c["pos"] as Vector2).y < 140.0) == (player_id == 1)
		var score := float(c["progress"]) + (0.25 if side_ok else 0.0)
		if score > best_score:
			lead = c
			best_score = score
	var target: Vector2
	if lead.is_empty():
		target = director.heroes[player_id]["home_pos"]
	else:
		var lane: TDPathLane = director.engine.lanes.get(str(lead["lane_id"]), null)
		if lane == null:
			return
		target = lane.get_point_at_progress(minf(0.9, float(lead["progress"]) + 0.08))
	var hero: Dictionary = director.heroes[player_id]
	if (hero["rally_pos"] as Vector2).distance_to(target) > 12.0:
		director.execute_command({"player_id": player_id, "action": "rally_hero", "x": target.x, "y": target.y})


func _ult_worth_it(director: CoopTDDirector) -> bool:
	if director.engine.creeps.size() >= 10:
		return true
	for c in director.engine.creeps:
		if bool(c.get("is_boss", false)):
			return true
	return false
