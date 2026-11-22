class_name StrategyAI
extends RefCounted
## Autonomous Rival Civilization 4X AI Brain.
## Drives research selection, city production queuing, tile improvements,
## and army movement / siege against hostile factions each turn.


static func execute_turn(
	faction_id: String,
	map: HexTerritoryMap,
	city_mgr: CityManager,
	army: StrategyArmy,
	tech: TechTree,
	ledger: ResourceLedger,
	diplo: DiplomacyEngine
) -> void:
	# 1. Pick next tech if idle
	if tech.current_tech_id.is_empty():
		var avail := tech.get_available_techs()
		if not avail.is_empty():
			tech.start_research(avail[0])

	# 2. City build queue decisions
	var my_cities := city_mgr.get_faction_cities(faction_id)
	var my_units := army.get_faction_units(faction_id)
	for city in my_cities:
		var cid := str(city["id"])
		var q: ProductionQueue = city["queue"]
		if not q.is_empty():
			continue
		if not (city["buildings"] as Array).has("granary"):
			city_mgr.enqueue_building(cid, "granary")
		elif my_units.size() < my_cities.size() + 2:
			city_mgr.enqueue_unit(cid, "warrior", "黑曜步兵", 20.0)
		elif not (city["buildings"] as Array).has("library"):
			city_mgr.enqueue_building(cid, "library")
		else:
			city_mgr.enqueue_unit(cid, "knight", "黑曜重骑", 32.0)

	# 3. Improve owned tiles if gold permits
	if ledger.get_amount("gold") >= 50.0:
		for city in my_cities:
			for c in city["territory"]:
				if map.can_build_improvement(c, "campus", faction_id) and ledger.spend({"gold": 45.0}):
					map.set_improvement(c, "campus")
					break
				elif map.can_build_improvement(c, "farm", faction_id) and ledger.spend({"gold": 25.0}):
					map.set_improvement(c, "farm")
					break

	# 4. Move armies toward enemy units or enemy cities if at war
	for u in army.get_faction_units(faction_id):
		if bool(u["can_found"]):
			continue
		var uid := str(u["uid"])
		var target_cell := _find_hostile_target(faction_id, u["cell"], map, city_mgr, army, diplo)
		if target_cell == Vector2i(-1, -1):
			continue
		var reach := army.get_reachable_hexes(uid, map)
		if reach.has(target_cell):
			army.move_or_attack(uid, target_cell, map, city_mgr, diplo)
			continue
		# Step closer to target
		var best_c: Vector2i = u["cell"]
		var best_d := map.distance(best_c, target_cell)
		for rc in reach:
			if army.get_unit_at(rc).is_empty() and city_mgr.get_city_at(rc).is_empty():
				var d := map.distance(rc, target_cell)
				if d < best_d:
					best_d = d
					best_c = rc
		if best_c != u["cell"]:
			army.move_or_attack(uid, best_c, map, city_mgr, diplo)


static func _find_hostile_target(faction_id: String, from: Vector2i, map: HexTerritoryMap, city_mgr: CityManager, army: StrategyArmy, diplo: DiplomacyEngine) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := 999999
	for u in army.units.values():
		if str(u["faction"]) != faction_id and float(u["hp"]) > 0.0 and diplo.are_at_war(faction_id, str(u["faction"])):
			var d := map.distance(from, u["cell"])
			if d < best_d:
				best_d = d
				best = u["cell"]
	for c in city_mgr.cities.values():
		if str(c["faction"]) != faction_id and diplo.are_at_war(faction_id, str(c["faction"])):
			var d := map.distance(from, c["cell"])
			if d < best_d:
				best_d = d
				best = c["cell"]
	return best
