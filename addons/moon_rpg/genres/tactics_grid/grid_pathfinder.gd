class_name GridPathfinder
extends RefCounted
## Dijkstra Movement Range, Attack Range Ring, and A* Shortest Path on GridBoard.


## Returns { "costs": {Vector2i: int}, "came_from": {Vector2i: Vector2i} } for all cells reachable within `move_points`.
static func compute_reachable(board: GridBoard, start: Vector2i, move_points: int, ignore_unit_id: String = "") -> Dictionary:
	var costs: Dictionary = {start: 0}
	var came_from: Dictionary = {}
	var frontier: Array[Dictionary] = [{"cell": start, "cost": 0}]

	while not frontier.is_empty():
		frontier.sort_custom(func(a: Dictionary, b: Dictionary): return int(a["cost"]) < int(b["cost"]))
		var cur: Dictionary = frontier.pop_front()
		var cell: Vector2i = cur["cell"]
		var cur_cost := int(cur["cost"])
		if cur_cost > int(costs.get(cell, 999999)):
			continue
		for nxt in board.get_neighbors(cell):
			if not board.is_passable(nxt, ignore_unit_id):
				continue
			var next_cost := cur_cost + board.get_move_cost(nxt)
			if next_cost <= move_points and next_cost < int(costs.get(nxt, 999999)):
				costs[nxt] = next_cost
				came_from[nxt] = cell
				frontier.append({"cell": nxt, "cost": next_cost})

	return {"costs": costs, "came_from": came_from}


## Advanced SRPG Dijkstra reachability with:
## - Ally pass-through (can walk through allies, cannot stop on occupied cells)
## - Flying movement (ignores terrain cost and elevation climb limits)
## - Elevation climb limit (`jump_height`)
## - Optional Enemy Zone of Control (`enable_zoc`: entering enemy-adjacent cell ends movement)
## Returns { "costs": {Vector2i: int}, "stoppable": Array[Vector2i], "came_from": {Vector2i: Vector2i} }
static func compute_reachable_ex(
	board: GridBoard,
	start: Vector2i,
	move_points: int,
	unit_id: String,
	faction: String,
	unit_factions: Dictionary,
	move_type: String = "infantry",
	jump_height: int = 1,
	enable_zoc: bool = false
) -> Dictionary:
	var costs: Dictionary = {start: 0}
	var came_from: Dictionary = {}
	var frontier: Array[Dictionary] = [{"cell": start, "cost": 0}]

	while not frontier.is_empty():
		frontier.sort_custom(func(a: Dictionary, b: Dictionary): return int(a["cost"]) < int(b["cost"]))
		var cur: Dictionary = frontier.pop_front()
		var cell: Vector2i = cur["cell"]
		var cur_cost := int(cur["cost"])
		if cur_cost > int(costs.get(cell, 999999)):
			continue
		var cur_elev := board.get_elevation(cell)
		for nxt in board.get_neighbors(cell):
			if not board.is_passable_for(nxt, unit_id, faction, unit_factions, move_type):
				continue
			if move_type != "flying" and absi(board.get_elevation(nxt) - cur_elev) > jump_height:
				continue
			var step_cost := board.get_move_cost_for(nxt, move_type)
			var next_cost := cur_cost + step_cost
			if next_cost > move_points:
				continue
			# Zone of Control: stepping adjacent to an enemy consumes remaining MP (cannot continue further)
			var effective_cost := next_cost
			if enable_zoc and move_type != "flying" and _is_adjacent_to_enemy(board, nxt, faction, unit_factions):
				effective_cost = move_points
			if effective_cost < int(costs.get(nxt, 999999)):
				costs[nxt] = effective_cost
				came_from[nxt] = cell
				if effective_cost < move_points:
					frontier.append({"cell": nxt, "cost": effective_cost})

	var stoppable: Array[Vector2i] = []
	for c in costs.keys():
		if board.can_stop_at(c, unit_id, move_type):
			stoppable.append(c)
	return {"costs": costs, "stoppable": stoppable, "came_from": came_from}


static func _is_adjacent_to_enemy(board: GridBoard, cell: Vector2i, faction: String, unit_factions: Dictionary) -> bool:
	for n in board.get_neighbors(cell):
		var occ := board.get_unit_at(n)
		if not occ.is_empty() and str(unit_factions.get(occ, "")) != faction:
			return true
	return false


## Reconstructs shortest path from `came_from` map produced by `compute_reachable*`.
static func reconstruct_path(came_from: Dictionary, start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	if start == goal:
		return [start]
	if not came_from.has(goal):
		return []
	var path: Array[Vector2i] = []
	var cur := goal
	while cur != start:
		path.push_front(cur)
		if not came_from.has(cur):
			return []
		cur = came_from[cur]
	path.push_front(start)
	return path


## Computes AoE affected cells for a skill ("SINGLE", "DIAMOND", "CROSS", "LINE").
static func compute_aoe_cells(board: GridBoard, origin: Vector2i, target: Vector2i, shape: String = "SINGLE", radius: int = 1) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not board.in_bounds(target):
		return out
	match shape.to_upper():
		"DIAMOND":
			for x in range(maxi(0, target.x - radius), mini(board.width, target.x + radius + 1)):
				for y in range(maxi(0, target.y - radius), mini(board.height, target.y + radius + 1)):
					var c := Vector2i(x, y)
					if board.distance(target, c) <= radius:
						out.append(c)
		"CROSS":
			out.append(target)
			var cross_dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
			for d in cross_dirs:
				for r in range(1, radius + 1):
					var c: Vector2i = target + d * r
					if board.in_bounds(c):
						out.append(c)
		"LINE":
			var delta := target - origin
			var dir := Vector2i(signi(delta.x), 0) if absi(delta.x) >= absi(delta.y) else Vector2i(0, signi(delta.y))
			if dir == Vector2i.ZERO:
				out.append(target)
			else:
				for r in range(0, radius + 1):
					var c := target + dir * r
					if board.in_bounds(c):
						out.append(c)
		_:
			out.append(target)
	return out


## Computes all cells within [min_range, max_range] of any origin cell (for red attack range overlay).
static func compute_attack_range(board: GridBoard, origins: Array[Vector2i], min_range: int = 1, max_range: int = 1) -> Array[Vector2i]:
	var visited: Dictionary = {}
	var origin_set: Dictionary = {}
	for o in origins:
		origin_set[o] = true
	for o in origins:
		for x in range(maxi(0, o.x - max_range), mini(board.width, o.x + max_range + 1)):
			for y in range(maxi(0, o.y - max_range), mini(board.height, o.y + max_range + 1)):
				var c := Vector2i(x, y)
				var d := board.distance(o, c)
				if d >= min_range and d <= max_range and not origin_set.has(c):
					visited[c] = true
	var out: Array[Vector2i] = []
	for c in visited.keys():
		out.append(c)
	return out


## A* shortest path from `start` to `goal` (returns empty array if unreachable).
static func find_path(board: GridBoard, start: Vector2i, goal: Vector2i, ignore_unit_id: String = "") -> Array[Vector2i]:
	if start == goal:
		return [start]
	if not board.in_bounds(goal):
		return []

	var came_from: Dictionary = {}
	var g_score: Dictionary = {start: 0}
	var open_list: Array[Dictionary] = [{"cell": start, "f": board.distance(start, goal)}]

	while not open_list.is_empty():
		open_list.sort_custom(func(a: Dictionary, b: Dictionary): return int(a["f"]) < int(b["f"]))
		var cur: Vector2i = open_list.pop_front()["cell"]
		if cur == goal:
			var path: Array[Vector2i] = []
			var step := goal
			while step != start:
				path.push_front(step)
				step = came_from[step]
			path.push_front(start)
			return path

		var cur_g := int(g_score.get(cur, 999999))
		for nxt in board.get_neighbors(cur):
			if nxt != goal and not board.is_passable(nxt, ignore_unit_id):
				continue
			if nxt == goal and not bool(board.get_cell(goal).get("passable", true)):
				continue
			var tentative_g := cur_g + board.get_move_cost(nxt)
			if tentative_g < int(g_score.get(nxt, 999999)):
				came_from[nxt] = cur
				g_score[nxt] = tentative_g
				open_list.append({"cell": nxt, "f": tentative_g + board.distance(nxt, goal)})
	return []
