class_name CityManager
extends RefCounted
## Pure-Data 4X City Management System (Civilization VI style).
## Handles city founding, automatic 1-ring border claiming, population growth from food,
## automatic border expansion on growth, per-city ProductionQueue & buildings,
## yield aggregation into ResourceLedger, and city siege/capture.

signal city_founded(city: Dictionary)
signal city_grew(city_id: String, new_population: int, new_tile: Vector2i)
signal city_production_completed(city_id: String, item_id: String, meta: Dictionary)
signal city_captured(city_id: String, old_faction: String, new_faction: String)

const BUILDING_DEFS := {
	"granary":  {"name": "粮仓",   "cost": 24.0, "food": 4.0, "production": 0.0, "gold": 0.0, "science": 0.0},
	"library":  {"name": "图书馆", "cost": 30.0, "food": 0.0, "production": 0.0, "gold": 0.0, "science": 5.0},
	"barracks": {"name": "兵营",   "cost": 28.0, "food": 0.0, "production": 4.0, "gold": 0.0, "science": 0.0},
	"treasury": {"name": "金库",   "cost": 32.0, "food": 0.0, "production": 0.0, "gold": 7.0, "science": 0.0},
}

var cities: Dictionary = {} # city_id -> city dict (with "queue": ProductionQueue)


func found_city(city_id: String, display_name: String, faction_id: String, center: Vector2i, map: HexTerritoryMap, is_capital: bool = false) -> Dictionary:
	if cities.has(city_id) or not map.in_bounds(center):
		return {}
	var territory: Array[Vector2i] = [center]
	map.set_owner(center, faction_id)
	for n in map.get_neighbors(center):
		if map.get_owner(n).is_empty():
			map.set_owner(n, faction_id)
			territory.append(n)
	map.reveal_radius(faction_id, center, 2)

	var q := ProductionQueue.new()
	var city := {
		"id": city_id,
		"name": display_name,
		"faction": faction_id,
		"cell": center,
		"is_capital": is_capital,
		"population": 1,
		"food_stored": 0.0,
		"hp": 100.0,
		"max_hp": 100.0,
		"defense": 12.0,
		"territory": territory,
		"buildings": [] as Array[String],
		"queue": q,
	}
	cities[city_id] = city
	city_founded.emit(city)
	return city


func get_city_at(cell: Vector2i) -> Dictionary:
	for c in cities.values():
		if c["cell"] == cell:
			return c
	return {}


func get_faction_cities(faction_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c in cities.values():
		if str(c["faction"]) == faction_id:
			out.append(c)
	return out


func get_city_yields(city_id: String, map: HexTerritoryMap) -> Dictionary:
	var out := {"food": 2.0, "production": 2.0, "gold": 3.0, "science": 2.0}
	if not cities.has(city_id):
		return out
	var city: Dictionary = cities[city_id]
	# Base city center + worked territory tiles (up to population + 2 tiles)
	var tiles_arr: Array = city["territory"]
	for c in tiles_arr:
		var y := map.get_tile_yields(c)
		out["food"] = float(out["food"]) + float(y["food"])
		out["production"] = float(out["production"]) + float(y["production"])
		out["gold"] = float(out["gold"]) + float(y["gold"])
		out["science"] = float(out["science"]) + float(y["science"])

	# Buildings
	for bid in city["buildings"]:
		if BUILDING_DEFS.has(bid):
			var b: Dictionary = BUILDING_DEFS[bid]
			out["food"] = float(out["food"]) + float(b["food"])
			out["production"] = float(out["production"]) + float(b["production"])
			out["gold"] = float(out["gold"]) + float(b["gold"])
			out["science"] = float(out["science"]) + float(b["science"])

	# Population bonus
	var pop := int(city["population"])
	out["science"] = float(out["science"]) + float(pop) * 1.0
	out["gold"] = float(out["gold"]) + float(pop) * 1.5
	return out


func enqueue_building(city_id: String, building_id: String) -> bool:
	if not cities.has(city_id) or not BUILDING_DEFS.has(building_id):
		return false
	var city: Dictionary = cities[city_id]
	if (city["buildings"] as Array).has(building_id):
		return false
	var b: Dictionary = BUILDING_DEFS[building_id]
	(city["queue"] as ProductionQueue).enqueue(building_id, str(b["name"]), float(b["cost"]), {"kind": "building"})
	return true


func enqueue_unit(city_id: String, unit_type: String, display_name: String, prod_cost: float) -> bool:
	if not cities.has(city_id):
		return false
	var city: Dictionary = cities[city_id]
	(city["queue"] as ProductionQueue).enqueue(unit_type, display_name, prod_cost, {"kind": "unit", "unit_type": unit_type})
	return true


## Processes one turn of yields, population growth, border expansion, and production for a faction.
func process_turn_for_faction(faction_id: String, map: HexTerritoryMap, ledger: ResourceLedger) -> Array[Dictionary]:
	var completed_items: Array[Dictionary] = []
	for cid in cities.keys():
		var city: Dictionary = cities[cid]
		if str(city["faction"]) != faction_id:
			continue
		# Passive city HP regen
		city["hp"] = minf(float(city["max_hp"]), float(city["hp"]) + 8.0)

		var yields := get_city_yields(cid, map)
		ledger.set_yield_source("city_" + cid, yields)

		# Population growth & border expansion
		var growth_need := 18.0 + float(int(city["population"])) * 12.0
		city["food_stored"] = float(city["food_stored"]) + float(yields["food"])
		if float(city["food_stored"]) >= growth_need:
			city["food_stored"] = float(city["food_stored"]) - growth_need
			city["population"] = int(city["population"]) + 1
			var new_tile := _expand_border(city, map)
			city_grew.emit(cid, int(city["population"]), new_tile)

		# Advance city ProductionQueue
		var q: ProductionQueue = city["queue"]
		var head_meta: Dictionary = q.current_item().get("meta", {}) if not q.is_empty() else {}
		var done_ids := q.advance_production(float(yields["production"]))
		for item_id in done_ids:
			if str(head_meta.get("kind", "")) == "building":
				if not (city["buildings"] as Array).has(item_id):
					(city["buildings"] as Array).append(item_id)
			completed_items.append({"city_id": cid, "item_id": item_id, "meta": head_meta})
			city_production_completed.emit(cid, item_id, head_meta)
	return completed_items


func _expand_border(city: Dictionary, map: HexTerritoryMap) -> Vector2i:
	var faction_id := str(city["faction"])
	for tcell in city["territory"]:
		for n in map.get_neighbors(tcell):
			if map.get_owner(n).is_empty() and str(map.get_tile(n)["biome"]) != "water":
				map.set_owner(n, faction_id)
				(city["territory"] as Array).append(n)
				map.reveal_radius(faction_id, n, 1)
				return n
	return Vector2i(-1, -1)


func damage_city(city_id: String, dmg: float, attacker_faction: String, map: HexTerritoryMap) -> bool:
	if not cities.has(city_id):
		return false
	var city: Dictionary = cities[city_id]
	city["hp"] = maxf(0.0, float(city["hp"]) - dmg)
	if float(city["hp"]) <= 0.0:
		capture_city(city_id, attacker_faction, map)
		return true
	return false


func capture_city(city_id: String, new_faction: String, map: HexTerritoryMap) -> void:
	if not cities.has(city_id):
		return
	var city: Dictionary = cities[city_id]
	var old_fac := str(city["faction"])
	city["faction"] = new_faction
	city["hp"] = float(city["max_hp"]) * 0.5
	for c in city["territory"]:
		map.set_owner(c, new_faction)
	map.reveal_radius(new_faction, city["cell"], 2)
	city_captured.emit(city_id, old_fac, new_faction)


func serialize() -> Dictionary:
	var arr: Array = []
	for c in cities.values():
		var terr_s: Array = []
		for tc in c["territory"]:
			var v: Vector2i = tc
			terr_s.append([v.x, v.y])
		var center: Vector2i = c["cell"]
		arr.append({
			"id": c["id"], "name": c["name"], "faction": c["faction"],
			"cell": [center.x, center.y], "is_capital": c["is_capital"],
			"population": c["population"], "food_stored": c["food_stored"],
			"hp": c["hp"], "max_hp": c["max_hp"],
			"territory": terr_s, "buildings": (c["buildings"] as Array).duplicate(),
			"queue": (c["queue"] as ProductionQueue).serialize(),
		})
	return {"cities": arr}
