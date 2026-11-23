class_name MapGraph
extends RefCounted
## Road-network maps for Twin Bastion TD.
## A stage's "graph" is a directed acyclic road network: nodes, edges (with optional via points), named spawns
## and one gate node. From it we derive:
##   - every ground route from each spawn to the gate (one TDPathLane each, id "<spawn>#<n>"),
##   - one flight route per spawn ("<spawn>#air", a gentle arc straight at the gate),
##   - fork tables so a creep can switch to another route that shares its path so far,
##   - auto-placed build pads (off-road, high road coverage, spaced out) with owner hints and rally points.

const PAD_ROAD_MIN := 27.0
const PAD_ROAD_MAX := 46.0
const PAD_SPACING := 46.0
const MAX_ROUTES_PER_SPAWN := 16


static func edge_points(graph: Dictionary, e: Array) -> PackedVector2Array:
	var nodes: Dictionary = graph["nodes"]
	var pts := PackedVector2Array([nodes[e[0]]])
	if e.size() > 2:
		for v in e[2]:
			pts.append(v)
	pts.append(nodes[e[1]])
	return pts


static func all_edge_polylines(graph: Dictionary) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	for e in graph["edges"]:
		out.append(edge_points(graph, e))
	return out


## Returns {"routes": [{id, spawn, nodes, points, node_dist, total}], "air": {spawn: {id, points}}}
static func build_routes(graph: Dictionary) -> Dictionary:
	var adj: Dictionary = {}
	for e in graph["edges"]:
		if not adj.has(e[0]):
			adj[e[0]] = []
		(adj[e[0]] as Array).append(e)
	var gate := str(graph["gate"])
	var routes: Array = []
	var air: Dictionary = {}
	var nodes: Dictionary = graph["nodes"]
	for spawn in (graph["spawns"] as Dictionary).keys():
		var start := str(graph["spawns"][spawn])
		var found: Array = []
		_dfs(start, gate, adj, [start], [], found)
		found.sort_custom(func(a, b): return (a[0] as Array).size() < (b[0] as Array).size())
		for i in range(mini(found.size(), MAX_ROUTES_PER_SPAWN)):
			var node_list: Array = found[i][0]
			var edge_list: Array = found[i][1]
			var pts := PackedVector2Array([nodes[node_list[0]]])
			var node_dist: Array[float] = [0.0]
			var acc := 0.0
			for e in edge_list:
				var ep := edge_points(graph, e)
				for k in range(1, ep.size()):
					acc += pts[pts.size() - 1].distance_to(ep[k])
					pts.append(ep[k])
				node_dist.append(acc)
			routes.append({"id": "%s#%d" % [spawn, i], "spawn": spawn, "nodes": node_list, "points": pts, "node_dist": node_dist, "total": acc})
		var s: Vector2 = nodes[start]
		var g: Vector2 = nodes[gate]
		var mid := s.lerp(g, 0.5) + (g - s).orthogonal().normalized() * (s.distance_to(g) * 0.12 * (1.0 if hash(spawn) % 2 == 0 else -1.0))
		var apts := PackedVector2Array()
		for k in range(13):
			var t := float(k) / 12.0
			apts.append(s.lerp(mid, t).lerp(mid.lerp(g, t), t))
		air[spawn] = {"id": "%s#air" % spawn, "points": apts}
	return {"routes": routes, "air": air}


static func _dfs(cur: String, gate: String, adj: Dictionary, path_nodes: Array, path_edges: Array, out: Array) -> void:
	if out.size() >= MAX_ROUTES_PER_SPAWN * 2:
		return
	if cur == gate:
		out.append([path_nodes.duplicate(), path_edges.duplicate()])
		return
	for e in adj.get(cur, []):
		var nxt := str(e[1])
		if path_nodes.has(nxt):
			continue
		path_nodes.append(nxt)
		path_edges.append(e)
		_dfs(nxt, gate, adj, path_nodes, path_edges, out)
		path_nodes.pop_back()
		path_edges.pop_back()


## For route r and node index k: other routes that share r's node prefix [0..k] (so a creep can switch there).
static func fork_alternatives(routes: Array, r_index: int, k: int) -> Array[int]:
	var out: Array[int] = []
	var rn: Array = routes[r_index]["nodes"]
	for j in range(routes.size()):
		if j == r_index or str(routes[j]["spawn"]) != str(routes[r_index]["spawn"]):
			continue
		var jn: Array = routes[j]["nodes"]
		if jn.size() <= k + 1:
			continue
		var same := true
		for q in range(k + 1):
			if jn[q] != rn[q]:
				same = false
				break
		if same and jn[k + 1] != rn[k + 1]:
			out.append(j)
	return out


static func dist_to_polylines(p: Vector2, polys: Array) -> float:
	var best := INF
	for poly in polys:
		var pts: PackedVector2Array = poly
		for i in range(pts.size() - 1):
			best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1])))
	return best


static func nearest_on_polylines(p: Vector2, polys: Array) -> Vector2:
	var best := p
	var best_d := INF
	for poly in polys:
		var pts: PackedVector2Array = poly
		for i in range(pts.size() - 1):
			var q := Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1])
			var d := p.distance_to(q)
			if d < best_d:
				best_d = d
				best = q
	return best


static func sample_polylines(polys: Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for poly in polys:
		var pts: PackedVector2Array = poly
		for i in range(pts.size() - 1):
			var a := pts[i]
			var b := pts[i + 1]
			var n := maxi(1, int(a.distance_to(b) / step))
			for k in range(n):
				out.append(a.lerp(b, float(k) / float(n)))
	return out


## Deterministic pad placement: candidates beside every road, scored by road coverage and junction bonus,
## picked greedily with spacing. Owner hint by map half (north = P1, south = P2, middle band = shared).
static func auto_pads(stage: Dictionary) -> Array[Dictionary]:
	var graph: Dictionary = stage["graph"]
	var world: Vector2 = stage["world"]
	var gate: Vector2 = graph["nodes"][graph["gate"]]
	var polys := all_edge_polylines(graph)
	var avoid: Array = stage.get("avoid", []) # [{"points": [...], "r": radius}]
	var samples := sample_polylines(polys, 12.0)
	var junctions: Array[Vector2] = []
	var degree := {}
	for e in graph["edges"]:
		degree[e[0]] = int(degree.get(e[0], 0)) + 1
		degree[e[1]] = int(degree.get(e[1], 0)) + 1
	for nid in degree.keys():
		if int(degree[nid]) >= 3 and nid != graph["gate"]:
			junctions.append(graph["nodes"][nid])
	var cands: Array = []
	for poly in polys:
		var pts: PackedVector2Array = poly
		for i in range(pts.size() - 1):
			var a := pts[i]
			var b := pts[i + 1]
			var dir := (b - a).normalized()
			var perp := dir.orthogonal()
			var n := maxi(1, int(a.distance_to(b) / 22.0))
			for k in range(n + 1):
				var base := a.lerp(b, float(k) / float(n))
				for side in [-1.0, 1.0]:
					for off in [34.0, 40.0]:
						var c: Vector2 = base + perp * float(off) * float(side)
						if c.x < 40.0 or c.y < 56.0 or c.x > gate.x - 76.0 or c.y > world.y - 40.0:
							continue
						var rd := dist_to_polylines(c, polys)
						if rd < PAD_ROAD_MIN or rd > PAD_ROAD_MAX:
							continue
						var blocked := false
						for av in avoid:
							if dist_to_polylines(c, [PackedVector2Array(av["points"])]) < float(av["r"]):
								blocked = true
								break
						if blocked:
							continue
						var cover := 0
						for sp in samples:
							if c.distance_to(sp) <= 108.0:
								cover += 1
						var bonus := 0.0
						for j in junctions:
							if c.distance_to(j) < 90.0:
								bonus += 14.0
						cands.append({"pos": c.round(), "score": float(cover) + bonus})
	cands.sort_custom(func(x, y): return float(x["score"]) > float(y["score"]))
	var want := int(stage.get("pad_count", 22))
	var chosen: Array[Dictionary] = []
	for c in cands:
		if chosen.size() >= want:
			break
		var ok := true
		for q in chosen:
			if (c["pos"] as Vector2).distance_to(q["pos"]) < PAD_SPACING:
				ok = false
				break
		if ok:
			chosen.append(c)
	chosen.sort_custom(func(x, y): return (x["pos"] as Vector2).x < (y["pos"] as Vector2).x)
	var out: Array[Dictionary] = []
	for i in range(chosen.size()):
		var p: Vector2 = chosen[i]["pos"]
		var hint := 0
		if p.y < world.y * 0.43:
			hint = 1
		elif p.y > world.y * 0.57:
			hint = 2
		out.append({"id": "p%d" % (i + 1), "owner_hint": hint, "pos": p, "rally": nearest_on_polylines(p, polys).round()})
	return out


static func hero_spawns(stage: Dictionary) -> Array:
	var graph: Dictionary = stage["graph"]
	var gate: Vector2 = graph["nodes"][graph["gate"]]
	var polys := all_edge_polylines(graph)
	var a := nearest_on_polylines(gate + Vector2(-80, -40), polys)
	var b := nearest_on_polylines(gate + Vector2(-80, 40), polys)
	if a.distance_to(b) < 16.0:
		b = a + Vector2(0, 18)
	return [a, b]
