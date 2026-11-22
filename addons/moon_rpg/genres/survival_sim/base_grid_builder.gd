class_name BaseGridBuilder
extends RefCounted
## Grid-Snapped Base Building, Resource Harvesting, Farming Plots & Campfire Heat Engine.
## Bridges Don't Starve (campfire fuel/warmth, walls, watchtowers) & Stardew Valley
## (farm plots, watering, multi-stage crop growth & harvesting).

signal resource_harvested(cell: Vector2i, res_type: String, yield_dict: Dictionary)
signal structure_built(cell: Vector2i, struct_id: String)
signal structure_destroyed(cell: Vector2i, struct_id: String)
signal crop_harvested(cell: Vector2i, crop_id: String, yield_qty: int)

var grid_w: int = 18
var grid_h: int = 10
var tile_size: float = 24.0
var origin: Vector2 = Vector2(24.0, 48.0)

var resources: Dictionary = {}  # Vector2i -> {type, hp, max_hp, yield_item, yield_qty}
var structures: Dictionary = {} # Vector2i -> {id, name, hp, max_hp, fuel, max_fuel, heat_radius, heat_bonus, station, crop, growth, watered, attack_cd}
var blueprints: Dictionary = {} # struct_id -> def


func _init() -> void:
	_register_default_blueprints()


func _register_default_blueprints() -> void:
	blueprints = {
		"campfire": {
			"name": "营地篝火", "cost": {"wood": 3, "stone": 2}, "max_hp": 60,
			"max_fuel": 60.0, "heat_radius": 92.0, "heat_bonus": 22.0, "station": "campfire",
		},
		"workbench": {
			"name": "木工台", "cost": {"wood": 4, "stone": 2}, "max_hp": 70, "station": "workbench",
		},
		"farm_plot": {
			"name": "肥沃农田", "cost": {"wood": 2}, "max_hp": 40, "is_farm": true,
		},
		"wall": {
			"name": "木栅栏", "cost": {"wood": 2, "stone": 1}, "max_hp": 110, "blocks": true,
		},
		"watchtower": {
			"name": "营地哨塔", "cost": {"wood": 4, "stone": 3}, "max_hp": 90, "attack_range": 105.0, "attack_dmg": 14.0,
		},
		"beacon": {
			"name": "希望灯塔", "cost": {"wood": 8, "stone": 6}, "max_hp": 150, "heat_radius": 140.0, "heat_bonus": 25.0, "is_victory_goal": true,
		},
	}


func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < grid_w and cell.y >= 0 and cell.y < grid_h


func cell_to_world(cell: Vector2i) -> Vector2:
	return origin + Vector2((cell.x + 0.5) * tile_size, (cell.y + 0.5) * tile_size)


func world_to_cell(pos: Vector2) -> Vector2i:
	var local := pos - origin
	return Vector2i(int(floor(local.x / tile_size)), int(floor(local.y / tile_size)))


func spawn_resource(cell: Vector2i, res_type: String) -> bool:
	if not in_bounds(cell) or resources.has(cell) or structures.has(cell):
		return false
	var def := {"type": res_type, "hp": 3, "max_hp": 3, "yield_item": "wood", "yield_qty": 2}
	match res_type:
		"rock":
			def = {"type": "rock", "hp": 3, "max_hp": 3, "yield_item": "stone", "yield_qty": 2}
		"berry_bush":
			def = {"type": "berry_bush", "hp": 2, "max_hp": 2, "yield_item": "berry", "yield_qty": 2}
	resources[cell] = def
	return true


func harvest_cell(cell: Vector2i, bag: Dictionary, power: int = 1) -> Dictionary:
	# 1. Harvest mature crop if this cell is a ready farm_plot
	if structures.has(cell):
		var st: Dictionary = structures[cell]
		if bool(st.get("is_farm", false)) and str(st.get("crop", "")) != "" and float(st.get("growth", 0.0)) >= 1.0:
			var crop_id := str(st["crop"])
			var qty := 3
			bag["berry"] = int(bag.get("berry", 0)) + qty
			st["growth"] = 0.0
			st["watered"] = false
			crop_harvested.emit(cell, crop_id, qty)
			return {"ok": true, "kind": "crop", "item": "berry", "qty": qty}
		elif bool(st.get("is_farm", false)):
			if str(st.get("crop", "")) == "":
				st["crop"] = "wheat"
				st["growth"] = 0.0
			st["watered"] = true
			return {"ok": true, "kind": "water", "item": "", "qty": 0}
		elif float(st.get("max_fuel", 0.0)) > 0.0:
			# Refuel campfire with 1 wood!
			if int(bag.get("wood", 0)) >= 1:
				bag["wood"] = int(bag["wood"]) - 1
				st["fuel"] = minf(float(st["max_fuel"]), float(st["fuel"]) + 28.0)
				return {"ok": true, "kind": "refuel", "item": "wood", "qty": 1}
			return {"ok": false, "reason": "需要1木材添柴"}

	# 2. Harvest natural resource node
	if not resources.has(cell):
		return {"ok": false, "reason": "该格无资源"}
	var node: Dictionary = resources[cell]
	node["hp"] = int(node["hp"]) - maxi(1, power)
	var item_id := str(node["yield_item"])
	var gain := 1
	if int(node["hp"]) <= 0:
		gain = int(node["yield_qty"])
		resources.erase(cell)
	bag[item_id] = int(bag.get(item_id, 0)) + gain
	resource_harvested.emit(cell, str(node["type"]), {item_id: gain})
	return {"ok": true, "kind": "resource", "item": item_id, "qty": gain}


func can_build(cell: Vector2i, struct_id: String, bag: Dictionary) -> Dictionary:
	if not in_bounds(cell):
		return {"ok": false, "reason": "超出营地范围"}
	if resources.has(cell) or structures.has(cell):
		return {"ok": false, "reason": "该格已被占用"}
	if not blueprints.has(struct_id):
		return {"ok": false, "reason": "未知建筑"}
	var bp: Dictionary = blueprints[struct_id]
	var cost: Dictionary = bp.get("cost", {})
	for k in cost.keys():
		if int(bag.get(k, 0)) < int(cost[k]):
			return {"ok": false, "reason": "材料不足(%s 需%d)" % [str(k), int(cost[k])]}
	return {"ok": true, "bp": bp}


func build_structure(cell: Vector2i, struct_id: String, bag: Dictionary) -> Dictionary:
	var chk := can_build(cell, struct_id, bag)
	if not bool(chk["ok"]):
		return chk
	var bp: Dictionary = chk["bp"]
	var cost: Dictionary = bp.get("cost", {})
	for k in cost.keys():
		bag[k] = maxi(0, int(bag.get(k, 0)) - int(cost[k]))

	var st := {
		"id": struct_id,
		"name": str(bp.get("name", struct_id)),
		"hp": int(bp.get("max_hp", 50)),
		"max_hp": int(bp.get("max_hp", 50)),
		"fuel": float(bp.get("max_fuel", 0.0)),
		"max_fuel": float(bp.get("max_fuel", 0.0)),
		"heat_radius": float(bp.get("heat_radius", 0.0)),
		"heat_bonus": float(bp.get("heat_bonus", 0.0)),
		"station": str(bp.get("station", "")),
		"is_farm": bool(bp.get("is_farm", false)),
		"crop": "wheat" if bool(bp.get("is_farm", false)) else "",
		"growth": 0.0,
		"watered": bool(bp.get("is_farm", false)),
		"attack_range": float(bp.get("attack_range", 0.0)),
		"attack_dmg": float(bp.get("attack_dmg", 0.0)),
		"attack_cd": 0.0,
		"is_victory_goal": bool(bp.get("is_victory_goal", false)),
	}
	structures[cell] = st
	structure_built.emit(cell, struct_id)
	return {"ok": true, "structure": st}


func tick(delta: float, is_raining: bool = false, crop_mult: float = 1.0) -> void:
	if delta <= 0.0:
		return
	for cell in structures.keys():
		var st: Dictionary = structures[cell]
		if float(st["max_fuel"]) > 0.0 and float(st["fuel"]) > 0.0:
			st["fuel"] = maxf(0.0, float(st["fuel"]) - 1.15 * delta)
		if bool(st["is_farm"]) and str(st["crop"]) != "":
			if is_raining:
				st["watered"] = true
			if bool(st["watered"]) and float(st["growth"]) < 1.0:
				st["growth"] = minf(1.0, float(st["growth"]) + 0.065 * crop_mult * delta)
		if float(st["attack_cd"]) > 0.0:
			st["attack_cd"] = maxf(0.0, float(st["attack_cd"]) - delta)


func damage_structure(cell: Vector2i, amount: int) -> bool:
	if not structures.has(cell):
		return false
	var st: Dictionary = structures[cell]
	st["hp"] = int(st["hp"]) - maxi(1, amount)
	if int(st["hp"]) <= 0:
		var sid := str(st["id"])
		structures.erase(cell)
		structure_destroyed.emit(cell, sid)
		return true
	return false


func get_heat_at(world_pos: Vector2) -> float:
	var best := 0.0
	for cell in structures.keys():
		var st: Dictionary = structures[cell]
		var r := float(st["heat_radius"])
		if r <= 0.0:
			continue
		if float(st["max_fuel"]) > 0.0 and float(st["fuel"]) <= 0.0:
			continue
		var d := world_pos.distance_to(cell_to_world(cell))
		if d <= r:
			var factor := clampf(1.0 - (d / r) * 0.4, 0.4, 1.0)
			best = maxf(best, float(st["heat_bonus"]) * factor)
	return best


func get_nearby_stations(world_pos: Vector2, radius: float = 72.0) -> Array[String]:
	var found: Array[String] = []
	for cell in structures.keys():
		var st: Dictionary = structures[cell]
		var sname := str(st["station"])
		if sname == "" or found.has(sname):
			continue
		if float(st["max_fuel"]) > 0.0 and float(st["fuel"]) <= 0.0:
			continue
		if world_pos.distance_to(cell_to_world(cell)) <= radius:
			found.append(sname)
	return found


func has_structure_type(struct_id: String) -> bool:
	for st in structures.values():
		if str((st as Dictionary)["id"]) == struct_id:
			return true
	return false


func serialize() -> Dictionary:
	var res_arr: Array[Dictionary] = []
	for c in resources.keys():
		var d: Dictionary = (resources[c] as Dictionary).duplicate(true)
		d["x"] = (c as Vector2i).x
		d["y"] = (c as Vector2i).y
		res_arr.append(d)
	var st_arr: Array[Dictionary] = []
	for c in structures.keys():
		var d: Dictionary = (structures[c] as Dictionary).duplicate(true)
		d["x"] = (c as Vector2i).x
		d["y"] = (c as Vector2i).y
		st_arr.append(d)
	return {"resources": res_arr, "structures": st_arr}


func deserialize(data: Dictionary) -> void:
	resources.clear()
	structures.clear()
	for r in data.get("resources", []):
		if r is Dictionary:
			var d := (r as Dictionary).duplicate(true)
			var cell := Vector2i(int(d["x"]), int(d["y"]))
			d.erase("x")
			d.erase("y")
			resources[cell] = d
	for s in data.get("structures", []):
		if s is Dictionary:
			var d := (s as Dictionary).duplicate(true)
			var cell := Vector2i(int(d["x"]), int(d["y"]))
			d.erase("x")
			d.erase("y")
			structures[cell] = d
