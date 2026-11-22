class_name StrategyArmy
extends RefCounted
## Pure-Data 4X Overworld Army & Settler Layer.
## Supports unit spawning, hex movement with Fog of War reveal, settler city-founding,
## quick 4X field combat / city siege, and an optional `tactical_battle_requested` signal
## so Total War / Heroes of Might & Magic games can transition into TacticsCombat!

signal unit_spawned(unit: Dictionary)
signal unit_moved(uid: String, from_cell: Vector2i, to_cell: Vector2i)
signal combat_resolved(attacker_uid: String, defender_id: String, summary: Dictionary)
signal tactical_battle_requested(attacker_unit: Dictionary, defender_unit: Dictionary, cell: Vector2i)

const UNIT_DEFS := {
	"settler": {"name": "开拓者", "cost": 26.0, "hp": 40.0, "atk": 0.0,  "def": 4.0,  "mp": 2, "vision": 2, "can_found": true},
	"warrior": {"name": "步兵团", "cost": 20.0, "hp": 100.0,"atk": 26.0, "def": 10.0, "mp": 2, "vision": 2, "can_found": false},
	"archer":  {"name": "弓箭团", "cost": 22.0, "hp": 80.0, "atk": 28.0, "def": 6.0,  "mp": 2, "vision": 3, "can_found": false},
	"knight":  {"name": "重骑兵", "cost": 32.0, "hp": 115.0,"atk": 36.0, "def": 12.0, "mp": 3, "vision": 2, "can_found": false},
}

var units: Dictionary = {} # uid -> unit dict
var _uid_counter: int = 0


func spawn_unit(unit_type: String, faction_id: String, cell: Vector2i, map: HexTerritoryMap) -> Dictionary:
	var def: Dictionary = UNIT_DEFS.get(unit_type, UNIT_DEFS["warrior"])
	_uid_counter += 1
	var uid := "army_%d" % _uid_counter
	var u := {
		"uid": uid,
		"type": unit_type,
		"name": str(def["name"]),
		"faction": faction_id,
		"cell": cell,
		"hp": float(def["hp"]),
		"max_hp": float(def["hp"]),
		"atk": float(def["atk"]),
		"def": float(def["def"]),
		"mp": int(def["mp"]),
		"mp_left": int(def["mp"]),
		"vision": int(def["vision"]),
		"can_found": bool(def["can_found"]),
	}
	units[uid] = u
	map.reveal_radius(faction_id, cell, int(u["vision"]))
	unit_spawned.emit(u)
	return u


func get_unit_at(cell: Vector2i) -> Dictionary:
	for u in units.values():
		if u["cell"] == cell and float(u["hp"]) > 0.0:
			return u
	return {}


func get_faction_units(faction_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for u in units.values():
		if str(u["faction"]) == faction_id and float(u["hp"]) > 0.0:
			out.append(u)
	return out


func refresh_faction_movement(faction_id: String, map: HexTerritoryMap) -> void:
	for u in units.values():
		if str(u["faction"]) == faction_id and float(u["hp"]) > 0.0:
			u["mp_left"] = int(u["mp"])
			map.reveal_radius(faction_id, u["cell"], int(u["vision"]))


func get_reachable_hexes(uid: String, map: HexTerritoryMap) -> Array[Vector2i]:
	if not units.has(uid):
		return []
	var u: Dictionary = units[uid]
	var mp_left := int(u["mp_left"])
	if mp_left <= 0:
		return []
	var start: Vector2i = u["cell"]
	var res := GridPathfinder.compute_reachable(map.board, start, mp_left)
	var out: Array[Vector2i] = []
	for c in (res["costs"] as Dictionary).keys():
		if c != start:
			out.append(c)
	return out


func move_or_attack(uid: String, target_cell: Vector2i, map: HexTerritoryMap, city_mgr: CityManager, diplo: DiplomacyEngine) -> Dictionary:
	if not units.has(uid) or not map.in_bounds(target_cell):
		return {"ok": false, "reason": "Invalid move"}
	var u: Dictionary = units[uid]
	if int(u["mp_left"]) <= 0:
		return {"ok": false, "reason": "本回合移动力耗尽"}
	var from_cell: Vector2i = u["cell"]
	var dist := map.distance(from_cell, target_cell)
	if dist > int(u["mp_left"]) or dist <= 0:
		return {"ok": false, "reason": "超出移动范围"}
	var fac := str(u["faction"])

	# Check enemy unit at target
	var target_u := get_unit_at(target_cell)
	if not target_u.is_empty():
		if str(target_u["faction"]) == fac:
			return {"ok": false, "reason": "已有己方单位"}
		if not diplo.are_at_war(fac, str(target_u["faction"])):
			diplo.declare_war(fac, str(target_u["faction"]))
		return _resolve_unit_combat(u, target_u, map)

	# Check enemy city at target
	var target_city := city_mgr.get_city_at(target_cell)
	if not target_city.is_empty() and str(target_city["faction"]) != fac:
		if not diplo.are_at_war(fac, str(target_city["faction"])):
			diplo.declare_war(fac, str(target_city["faction"]))
		return _resolve_city_siege(u, target_city, map, city_mgr)

	# Regular move
	if not bool(map.board.get_cell(target_cell).get("passable", true)):
		return {"ok": false, "reason": "不可通行地形"}
	u["cell"] = target_cell
	u["mp_left"] = maxi(0, int(u["mp_left"]) - dist)
	map.reveal_radius(fac, target_cell, int(u["vision"]))
	unit_moved.emit(uid, from_cell, target_cell)
	return {"ok": true, "action": "move", "to": target_cell}


func found_city_with_settler(uid: String, city_name: String, map: HexTerritoryMap, city_mgr: CityManager) -> Dictionary:
	if not units.has(uid):
		return {"ok": false, "reason": "Unit not found"}
	var u: Dictionary = units[uid]
	if not bool(u["can_found"]):
		return {"ok": false, "reason": "仅开拓者可建城"}
	var cell: Vector2i = u["cell"]
	if not city_mgr.get_city_at(cell).is_empty():
		return {"ok": false, "reason": "此处已有城市"}
	for c in city_mgr.cities.values():
		if map.distance(c["cell"], cell) < 2:
			return {"ok": false, "reason": "距现有城市过近"}
	var cid := "city_%s_%d_%d" % [u["faction"], cell.x, cell.y]
	var city := city_mgr.found_city(cid, city_name, str(u["faction"]), cell, map, false)
	if city.is_empty():
		return {"ok": false, "reason": "建城失败"}
	units.erase(uid)
	return {"ok": true, "city": city}


func _resolve_unit_combat(atk: Dictionary, def: Dictionary, map: HexTerritoryMap) -> Dictionary:
	var def_cell: Vector2i = def["cell"]
	var terr_def := float(map.board.get_cell(def_cell).get("def_bonus", 0))
	var dmg_to_def := maxf(8.0, float(atk["atk"]) - (float(def["def"]) + terr_def) * 0.5)
	var dmg_to_atk := maxf(4.0, float(def["atk"]) * 0.65 - float(atk["def"]) * 0.5)
	def["hp"] = maxf(0.0, float(def["hp"]) - dmg_to_def)
	atk["mp_left"] = 0
	var killed := float(def["hp"]) <= 0.0
	if killed:
		units.erase(str(def["uid"]))
		atk["cell"] = def_cell
		map.reveal_radius(str(atk["faction"]), def_cell, int(atk["vision"]))
	else:
		atk["hp"] = maxf(0.0, float(atk["hp"]) - dmg_to_atk)
		if float(atk["hp"]) <= 0.0:
			units.erase(str(atk["uid"]))
	var sum := {"ok": true, "action": "combat", "dmg_to_def": dmg_to_def, "dmg_to_atk": 0.0 if killed else dmg_to_atk, "killed_def": killed}
	combat_resolved.emit(str(atk["uid"]), str(def["uid"]), sum)
	return sum


func _resolve_city_siege(atk: Dictionary, city: Dictionary, map: HexTerritoryMap, city_mgr: CityManager) -> Dictionary:
	var dmg := maxf(18.0, float(atk["atk"]) * 1.35)
	atk["mp_left"] = 0
	var captured := city_mgr.damage_city(str(city["id"]), dmg, str(atk["faction"]), map)
	if captured:
		atk["cell"] = city["cell"]
	else:
		atk["hp"] = maxf(0.0, float(atk["hp"]) - 12.0)
		if float(atk["hp"]) <= 0.0:
			units.erase(str(atk["uid"]))
	var sum := {"ok": true, "action": "siege", "dmg": dmg, "captured": captured, "city_id": str(city["id"])}
	combat_resolved.emit(str(atk["uid"]), str(city["id"]), sum)
	return sum
