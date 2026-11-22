class_name GridBoard
extends RefCounted
## Pure-Data Tactical Grid Board (Supports Square 4-Neighbor & Pointy-Top Odd-R Hex).
## Scales cleanly to thousands of cells with zero per-tile Godot Nodes.

enum Topology { SQUARE, HEX_ODD_R }

var width: int = 16
var height: int = 12
var topology: int = Topology.SQUARE
var _cells: Dictionary = {} # Vector2i -> { terrain, move_cost, def_bonus, avoid_bonus, passable }
var _occupants: Dictionary = {} # Vector2i -> unit_id
var _unit_positions: Dictionary = {} # unit_id -> Vector2i


func _init(w: int = 16, h: int = 12, topo: int = Topology.SQUARE) -> void:
	width = maxi(1, w)
	height = maxi(1, h)
	topology = topo


func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height


func set_cell(cell: Vector2i, terrain: String, move_cost: int = 1, passable: bool = true, def_bonus: int = 0, avoid_bonus: int = 0, elevation: int = 0, heal_per_turn: int = 0, is_seize: bool = false) -> void:
	if not in_bounds(cell):
		return
	_cells[cell] = {
		"terrain": terrain,
		"move_cost": maxi(1, move_cost),
		"passable": passable,
		"def_bonus": def_bonus,
		"avoid_bonus": avoid_bonus,
		"elevation": elevation,
		"heal_per_turn": heal_per_turn,
		"is_seize_point": is_seize,
	}


func get_cell(cell: Vector2i) -> Dictionary:
	return _cells.get(cell, {
		"terrain": "plain",
		"move_cost": 1,
		"passable": true,
		"def_bonus": 0,
		"avoid_bonus": 0,
		"elevation": 0,
		"heal_per_turn": 0,
		"is_seize_point": false,
	})


func get_elevation(cell: Vector2i) -> int:
	return int(get_cell(cell).get("elevation", 0))


func set_elevation(cell: Vector2i, elevation: int) -> void:
	if not in_bounds(cell):
		return
	var c := get_cell(cell).duplicate()
	c["elevation"] = elevation
	_cells[cell] = c


func get_heal_per_turn(cell: Vector2i) -> int:
	return int(get_cell(cell).get("heal_per_turn", 0))


func is_seize_point(cell: Vector2i) -> bool:
	return bool(get_cell(cell).get("is_seize_point", false))


func get_move_cost_for(cell: Vector2i, move_type: String = "infantry") -> int:
	if move_type == "flying":
		return 1
	var c := get_cell(cell)
	var base := int(c.get("move_cost", 1))
	if move_type == "cavalry" and str(c.get("terrain", "")) == "forest":
		return base + 1
	return base


func is_passable_for(cell: Vector2i, unit_id: String, faction: String, unit_factions: Dictionary, move_type: String = "infantry") -> bool:
	if not in_bounds(cell):
		return false
	var c := get_cell(cell)
	if move_type != "flying" and not bool(c.get("passable", true)):
		return false
	var occ := get_unit_at(cell)
	if occ.is_empty() or occ == unit_id:
		return true
	# Allies can pass through allied tiles (classic Fire Emblem / FFT rule), enemies block!
	return str(unit_factions.get(occ, "")) == faction


func can_stop_at(cell: Vector2i, unit_id: String, move_type: String = "infantry") -> bool:
	if not in_bounds(cell):
		return false
	if move_type != "flying" and not bool(get_cell(cell).get("passable", true)):
		return false
	var occ := get_unit_at(cell)
	return occ.is_empty() or occ == unit_id


func is_passable(cell: Vector2i, ignore_unit_id: String = "") -> bool:
	if not in_bounds(cell):
		return false
	if not bool(get_cell(cell).get("passable", true)):
		return false
	var occ := get_unit_at(cell)
	return occ.is_empty() or occ == ignore_unit_id


func get_move_cost(cell: Vector2i) -> int:
	return int(get_cell(cell).get("move_cost", 1))


func place_unit(unit_id: String, cell: Vector2i) -> bool:
	if not in_bounds(cell):
		return false
	if _unit_positions.has(unit_id):
		_occupants.erase(_unit_positions[unit_id])
	_occupants[cell] = unit_id
	_unit_positions[unit_id] = cell
	return true


func move_unit(unit_id: String, to_cell: Vector2i) -> bool:
	if not in_bounds(to_cell):
		return false
	if _occupants.has(to_cell) and str(_occupants[to_cell]) != unit_id:
		return false
	return place_unit(unit_id, to_cell)


func remove_unit(unit_id: String) -> void:
	if _unit_positions.has(unit_id):
		_occupants.erase(_unit_positions[unit_id])
		_unit_positions.erase(unit_id)


func get_unit_at(cell: Vector2i) -> String:
	return str(_occupants.get(cell, ""))


func get_unit_cell(unit_id: String) -> Vector2i:
	return _unit_positions.get(unit_id, Vector2i(-1, -1))


func get_neighbors(cell: Vector2i) -> Array[Vector2i]:
	var dirs: Array[Vector2i] = []
	if topology == Topology.SQUARE:
		dirs = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	else:
		# Pointy-top odd-r hex neighbors
		if (cell.y & 1) == 1:
			dirs = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, -1), Vector2i(0, 1), Vector2i(1, 1)]
		else:
			dirs = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 1), Vector2i(0, 1)]
	var out: Array[Vector2i] = []
	for d in dirs:
		var nxt := cell + d
		if in_bounds(nxt):
			out.append(nxt)
	return out


func distance(a: Vector2i, b: Vector2i) -> int:
	if topology == Topology.SQUARE:
		return absi(a.x - b.x) + absi(a.y - b.y)
	# Convert odd-r offset to cube coordinates for exact hex distance
	var ax := a.x - ((a.y - (a.y & 1)) >> 1)
	var az := a.y
	var ay := -ax - az
	var bx := b.x - ((b.y - (b.y & 1)) >> 1)
	var bz := b.y
	var by := -bx - bz
	return maxi(absi(ax - bx), maxi(absi(ay - by), absi(az - bz)))


func serialize() -> Dictionary:
	var cells_arr: Array = []
	for c in _cells.keys():
		var v: Vector2i = c
		cells_arr.append({"x": v.x, "y": v.y, "data": _cells[c]})
	var units_dict: Dictionary = {}
	for uid in _unit_positions.keys():
		var v: Vector2i = _unit_positions[uid]
		units_dict[uid] = [v.x, v.y]
	return {
		"width": width,
		"height": height,
		"topology": topology,
		"cells": cells_arr,
		"units": units_dict,
	}


func deserialize(data: Dictionary) -> void:
	width = int(data.get("width", width))
	height = int(data.get("height", height))
	topology = int(data.get("topology", Topology.SQUARE))
	_cells.clear()
	_occupants.clear()
	_unit_positions.clear()
	for entry in data.get("cells", []):
		_cells[Vector2i(int(entry["x"]), int(entry["y"]))] = entry["data"].duplicate(true)
	var units: Dictionary = data.get("units", {})
	for uid in units.keys():
		var arr: Array = units[uid]
		place_unit(str(uid), Vector2i(int(arr[0]), int(arr[1])))
