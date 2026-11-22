class_name TacticsAI
extends RefCounted
## Utility-Scoring Tactical SRPG AI Brain.
## Evaluates all (reachable_cell × target/skill) combinations:
## - Lethal kill bonus (+120)
## - Expected damage minus expected counterattack risk
## - High-ground & defensive terrain bonus
## - Healer AI prioritizes wounded allies (<75% HP)
## - Approaches nearest enemy via A* when no target is in immediate attack range.


static func decide_turn(unit: TacticsUnit, board: GridBoard, all_units: Dictionary, combat: TacticsCombat) -> Dictionary:
	var start := board.get_unit_cell(unit.unit_id)
	var unit_factions: Dictionary = {}
	for uid in all_units.keys():
		unit_factions[uid] = (all_units[uid] as TacticsUnit).faction

	var reach := GridPathfinder.compute_reachable_ex(
		board, start, unit.move_range, unit.unit_id, unit.faction, unit_factions, unit.move_type, unit.jump_height, false
	)
	var stoppable: Array[Vector2i] = reach["stoppable"]
	if stoppable.is_empty():
		stoppable = [start]

	# Boss guard stays on fortress unless an enemy is already in range
	if unit.ai_profile == "boss_guard":
		stoppable = [start]

	var best_score := -999999.0
	var best_plan := {"move_to": start, "action": "wait", "target_id": "", "target_cell": start, "skill": {}}

	# 1. Healer priority: check wounded allies first
	if unit.ai_profile == "healer":
		for sk in unit.skills:
			if not bool(sk.get("target_allies", false)) or not unit.can_afford_skill(sk):
				continue
			var s_min := int(sk.get("min_range", 1))
			var s_max := int(sk.get("max_range", 2))
			for cell in stoppable:
				for other in all_units.values():
					var ally := other as TacticsUnit
					if not ally.is_alive() or ally.faction != unit.faction:
						continue
					var hp_ratio := ally.stat_block.hp / maxf(1.0, ally.stat_block.get_stat("max_hp"))
					if hp_ratio >= 0.78:
						continue
					var acell := board.get_unit_cell(ally.unit_id)
					var d := board.distance(cell, acell)
					if d >= s_min and d <= s_max:
						var score := (1.0 - hp_ratio) * 140.0 + float(board.get_cell(cell).get("def_bonus", 0)) * 3.0
						if score > best_score:
							best_score = score
							best_plan = {"move_to": cell, "action": "skill", "target_id": ally.unit_id, "target_cell": acell, "skill": sk}
		if best_plan["action"] == "skill":
			return best_plan

	# 2. Evaluate all offensive attacks from every stoppable cell
	for cell in stoppable:
		var terr_bonus := float(board.get_cell(cell).get("def_bonus", 0)) * 3.0 + float(board.get_elevation(cell)) * 4.0
		for other in all_units.values():
			var enemy := other as TacticsUnit
			if not enemy.is_alive() or enemy.faction == unit.faction:
				continue
			var ecell := board.get_unit_cell(enemy.unit_id)
			var d := board.distance(cell, ecell)
			if d >= unit.attack_min_range and d <= unit.attack_max_range:
				var fc := combat.forecast(unit, enemy, cell, ecell, board, all_units, {})
				var exp_dmg := float(fc["damage"]) * float(fc["hit_chance"]) * (2.0 if bool(fc["double_attack"]) else 1.0)
				var lethal := 120.0 if exp_dmg >= enemy.stat_block.hp else 0.0
				var counter_pen := float(fc["counter_damage"]) * float(fc["counter_hit"]) * (0.35 if unit.ai_profile == "aggressive" else 0.75)
				var score := exp_dmg * 2.2 + lethal - counter_pen + terr_bonus + float(fc["weapon_advantage"]) * 10.0
				if score > best_score:
					best_score = score
					best_plan = {"move_to": cell, "action": "attack", "target_id": enemy.unit_id, "target_cell": ecell, "skill": {}}

			# Also evaluate offensive skills
			for sk in unit.skills:
				if bool(sk.get("target_allies", false)) or not unit.can_afford_skill(sk):
					continue
				var s_min := int(sk.get("min_range", 1))
				var s_max := int(sk.get("max_range", 2))
				if d >= s_min and d <= s_max:
					var fc_s := combat.forecast(unit, enemy, cell, ecell, board, all_units, sk)
					var exp_s := float(fc_s["damage"]) * float(fc_s["hit_chance"])
					var lethal_s := 125.0 if exp_s >= enemy.stat_block.hp else 0.0
					var score_s := exp_s * 2.4 + lethal_s + terr_bonus + 8.0
					if score_s > best_score:
						best_score = score_s
						best_plan = {"move_to": cell, "action": "skill", "target_id": enemy.unit_id, "target_cell": ecell, "skill": sk}

	if best_plan["action"] != "wait":
		return best_plan

	# 3. No enemy in immediate range -> advance toward nearest enemy (unless boss_guard)
	if unit.ai_profile == "boss_guard":
		return best_plan
	var nearest_enemy_cell := Vector2i(-1, -1)
	var nearest_dist := 999999
	for other in all_units.values():
		var enemy := other as TacticsUnit
		if enemy.is_alive() and enemy.faction != unit.faction:
			var ecell := board.get_unit_cell(enemy.unit_id)
			var d := board.distance(start, ecell)
			if d < nearest_dist:
				nearest_dist = d
				nearest_enemy_cell = ecell

	if nearest_enemy_cell != Vector2i(-1, -1):
		var best_approach := start
		var best_d := nearest_dist
		for cell in stoppable:
			var d := board.distance(cell, nearest_enemy_cell)
			if d < best_d:
				best_d = d
				best_approach = cell
		best_plan["move_to"] = best_approach
	return best_plan
