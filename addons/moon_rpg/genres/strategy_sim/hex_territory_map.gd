class_name HexTerritoryMap
extends RefCounted
## Pure-Data 4X Hexagonal World Map (Civilization VI / Stellaris / Polytopia style).
## Scales to thousands of tiles with zero per-tile Godot Nodes.
## Features:
## - Pointy-top Odd-R hex topology (reusing GridBoard)
## - Biome yields (food / production / gold / science)
## - Tile Improvements & Districts with Adjacency Bonuses (e.g. Campus +2 science per Mountain, Farm +1 food per adjacent Farm!)
## - Territory ownership & 3-state per-faction Fog of War (UNEXPLORED / EXPLORED / VISIBLE)
## - Full `serialize()` / `deserialize()`.

enum Visibility { UNEXPLORED, EXPLORED, VISIBLE }

const BIOME_YIELDS := {
	"grassland": {"food": 2.0, "production": 0.0, "gold": 0.0, "science": 0.0, "move_cost": 1, "passable": true, "def_bonus": 0},
	"plains":    {"food": 1.0, "production": 1.0, "gold": 0.0, "science": 0.0, "move_cost": 1, "passable": true, "def_bonus": 0},
	"forest":    {"food": 1.0, "production": 2.0, "gold": 0.0, "science": 0.0, "move_cost": 2, "passable": true, "def_bonus": 2},
	"hills":     {"food": 0.0, "production": 2.0, "gold": 1.0, "science": 0.0, "move_cost": 2, "passable": true, "def_bonus": 3},
	"desert":    {"food": 0.0, "production": 0.0, "gold": 2.0, "science": 0.0, "move_cost": 1, "passable": true, "def_bonus": 0},
	"mountain":  {"food": 0.0, "production": 0.0, "gold": 0.0, "science": 0.0, "move_cost": 99, "passable": false, "def_bonus": 0},
	"water":     {"food": 1.0, "production": 0.0, "gold": 1.0, "science": 0.0, "move_cost": 99, "passable": false, "def_bonus": 0},
}

const IMPROVEMENT_DEFS := {
	"farm":   {"name": "农田", "cost": 25, "food": 2.0, "production": 0.0, "gold": 0.0, "science": 0.0, "allowed": ["grassland", "plains"]},
	"mine":   {"name": "矿场", "cost": 30, "food": 0.0, "production": 2.0, "gold": 1.0, "science": 0.0, "allowed": ["hills", "plains", "desert"]},
	"campus": {"name": "学院", "cost": 45, "food": 0.0, "production": 0.0, "gold": 0.0, "science": 2.0, "allowed": ["grassland", "plains", "hills", "forest"]},
	"market": {"name": "市集", "cost": 35, "food": 0.0, "production": 0.0, "gold": 3.0, "science": 0.0, "allowed": ["grassland", "plains", "desert"]},
	"fort":   {"name": "要塞", "cost": 35, "food": 0.0, "production": 0.0, "gold": 0.0, "science": 0.0, "def_bonus": 4, "allowed": ["grassland", "plains", "hills", "forest"]},
}

var board: GridBoard
var width: int = 12
var height: int = 8
var tiles: Dictionary = {} # Vector2i -> { biome, owner, improvement, resource }
var _fog: Dictionary = {} # faction_id -> { Vector2i: Visibility }


func _init(w: int = 12, h: int = 8) -> void:
	width = maxi(2, w)
	height = maxi(2, h)
	board = GridBoard.new(width, height, GridBoard.Topology.HEX_ODD_R)
	for x in range(width):
		for y in range(height):
			set_biome(Vector2i(x, y), "grassland")


func in_bounds(cell: Vector2i) -> bool:
	return board.in_bounds(cell)


func set_biome(cell: Vector2i, biome: String, strategic_res: String = "") -> void:
	if not in_bounds(cell):
		return
	var bdef: Dictionary = BIOME_YIELDS.get(biome, BIOME_YIELDS["grassland"])
	board.set_cell(cell, biome, int(bdef["move_cost"]), bool(bdef["passable"]), int(bdef["def_bonus"]), 0)
	if not tiles.has(cell):
		tiles[cell] = {"biome": biome, "owner": "", "improvement": "", "resource": strategic_res}
	else:
		tiles[cell]["biome"] = biome
		if not strategic_res.is_empty():
			tiles[cell]["resource"] = strategic_res


func get_tile(cell: Vector2i) -> Dictionary:
	return tiles.get(cell, {"biome": "grassland", "owner": "", "improvement": "", "resource": ""})


func set_owner(cell: Vector2i, faction_id: String) -> void:
	if in_bounds(cell) and tiles.has(cell):
		tiles[cell]["owner"] = faction_id


func get_owner(cell: Vector2i) -> String:
	return str(get_tile(cell).get("owner", ""))


func can_build_improvement(cell: Vector2i, imp_id: String, faction_id: String) -> bool:
	if not in_bounds(cell) or not IMPROVEMENT_DEFS.has(imp_id):
		return false
	var t := get_tile(cell)
	if str(t["owner"]) != faction_id or not str(t["improvement"]).is_empty():
		return false
	var allowed: Array = IMPROVEMENT_DEFS[imp_id]["allowed"]
	return allowed.has(str(t["biome"]))


func set_improvement(cell: Vector2i, imp_id: String) -> bool:
	if not in_bounds(cell) or not IMPROVEMENT_DEFS.has(imp_id):
		return false
	tiles[cell]["improvement"] = imp_id
	if imp_id == "fort":
		var c := board.get_cell(cell).duplicate()
		c["def_bonus"] = int(c.get("def_bonus", 0)) + 4
		board.set_cell(cell, str(c["terrain"]), int(c["move_cost"]), bool(c["passable"]), int(c["def_bonus"]))
	return true


## Calculates total yields of a hex cell INCLUDING Civilization VI-style adjacency bonuses!
func get_tile_yields(cell: Vector2i) -> Dictionary:
	var t := get_tile(cell)
	var bdef: Dictionary = BIOME_YIELDS.get(str(t["biome"]), BIOME_YIELDS["grassland"])
	var out := {
		"food": float(bdef["food"]),
		"production": float(bdef["production"]),
		"gold": float(bdef["gold"]),
		"science": float(bdef["science"]),
	}
	var imp := str(t["improvement"])
	if not imp.is_empty() and IMPROVEMENT_DEFS.has(imp):
		var idef: Dictionary = IMPROVEMENT_DEFS[imp]
		out["food"] = float(out["food"]) + float(idef["food"])
		out["production"] = float(out["production"]) + float(idef["production"])
		out["gold"] = float(out["gold"]) + float(idef["gold"])
		out["science"] = float(out["science"]) + float(idef["science"])

		# Adjacency bonuses!
		var adj_mountains := 0
		var adj_farms := 0
		var adj_forests := 0
		for n in board.get_neighbors(cell):
			var nt := get_tile(n)
			if str(nt["biome"]) == "mountain":
				adj_mountains += 1
			if str(nt["improvement"]) == "farm":
				adj_farms += 1
			if str(nt["biome"]) == "forest":
				adj_forests += 1
		if imp == "campus":
			out["science"] = float(out["science"]) + float(adj_mountains) * 2.0 + float(adj_forests) * 0.5
		elif imp == "farm" and adj_farms > 0:
			out["food"] = float(out["food"]) + 1.0
		elif imp == "mine" and adj_mountains > 0:
			out["production"] = float(out["production"]) + 1.0

	var res := str(t["resource"])
	if res == "wheat":
		out["food"] = float(out["food"]) + 1.0
	elif res == "iron":
		out["production"] = float(out["production"]) + 2.0
	elif res == "gems":
		out["gold"] = float(out["gold"]) + 3.0
	return out


func get_neighbors(cell: Vector2i) -> Array[Vector2i]:
	return board.get_neighbors(cell)


func distance(a: Vector2i, b: Vector2i) -> int:
	return board.distance(a, b)


# --- 3-State Fog of War ---

func reset_visibility(faction_id: String) -> void:
	if not _fog.has(faction_id):
		_fog[faction_id] = {}
		return
	var fdict: Dictionary = _fog[faction_id]
	for cell in fdict.keys():
		if int(fdict[cell]) == Visibility.VISIBLE:
			fdict[cell] = Visibility.EXPLORED


func reveal_radius(faction_id: String, center: Vector2i, radius: int = 2) -> void:
	if not _fog.has(faction_id):
		_fog[faction_id] = {}
	var fdict: Dictionary = _fog[faction_id]
	for x in range(maxi(0, center.x - radius - 1), mini(width, center.x + radius + 2)):
		for y in range(maxi(0, center.y - radius - 1), mini(height, center.y + radius + 2)):
			var c := Vector2i(x, y)
			if distance(center, c) <= radius:
				fdict[c] = Visibility.VISIBLE


func get_visibility(faction_id: String, cell: Vector2i) -> int:
	if not _fog.has(faction_id):
		return Visibility.UNEXPLORED
	return int((_fog[faction_id] as Dictionary).get(cell, Visibility.UNEXPLORED))


## Converts odd-r hex cell to 2D pixel center for clean rendering & picking.
static func hex_to_pixel(cell: Vector2i, radius: float, origin: Vector2 = Vector2.ZERO) -> Vector2:
	var w := sqrt(3.0) * radius
	var h := 1.5 * radius
	var x := float(cell.x) * w + (w * 0.5 if (cell.y & 1) == 1 else 0.0)
	var y := float(cell.y) * h
	return origin + Vector2(x, y)


func pixel_to_hex(pos: Vector2, radius: float, origin: Vector2 = Vector2.ZERO) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := radius * 1.15
	for x in range(width):
		for y in range(height):
			var c := Vector2i(x, y)
			var d := pos.distance_to(hex_to_pixel(c, radius, origin))
			if d < best_d:
				best_d = d
				best = c
	return best


func serialize() -> Dictionary:
	var t_arr: Array = []
	for c in tiles.keys():
		var v: Vector2i = c
		t_arr.append({"x": v.x, "y": v.y, "data": tiles[c]})
	return {"width": width, "height": height, "tiles": t_arr}


func deserialize(data: Dictionary) -> void:
	width = int(data.get("width", width))
	height = int(data.get("height", height))
	board = GridBoard.new(width, height, GridBoard.Topology.HEX_ODD_R)
	tiles.clear()
	for entry in data.get("tiles", []):
		var c := Vector2i(int(entry["x"]), int(entry["y"]))
		var d: Dictionary = entry["data"]
		set_biome(c, str(d.get("biome", "grassland")), str(d.get("resource", "")))
		set_owner(c, str(d.get("owner", "")))
		var imp := str(d.get("improvement", ""))
		if not imp.is_empty():
			set_improvement(c, imp)
