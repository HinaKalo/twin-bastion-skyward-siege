class_name ColonyTaskDirector
extends RefCounted
## Autonomous Camp Villager / Colony Worker AI (RimWorld × Frostpunk style).
## Manages recruited camp helpers (`GATHERER`, `FARMER`, `KEEPER`) who automatically
## move to resource nodes, mature crops, or low-fuel campfires and execute jobs on tick().

signal worker_recruited(worker: Dictionary)
signal worker_completed_job(worker_id: String, job_kind: String, detail: String)

var workers: Array[Dictionary] = []
var _seq: int = 0


func recruit_worker(role: String, spawn_pos: Vector2, display_name: String = "") -> Dictionary:
	_seq += 1
	var wname := display_name if display_name != "" else ("伐木工" if role == "GATHERER" else ("农夫" if role == "FARMER" else "守夜人"))
	var w := {
		"uid": "worker_%d" % _seq,
		"name": wname,
		"role": role, # "GATHERER" | "FARMER" | "KEEPER"
		"pos": spawn_pos,
		"speed": 46.0,
		"state": "IDLE", # "IDLE" | "MOVING" | "WORKING"
		"target_cell": Vector2i(-1, -1),
		"work_timer": 0.0,
	}
	workers.append(w)
	worker_recruited.emit(w)
	return w


func tick(delta: float, builder: BaseGridBuilder, bag: Dictionary) -> void:
	if delta <= 0.0:
		return
	for w in workers:
		var state := str(w["state"])
		if state == "IDLE":
			var cell := _find_job_cell(str(w["role"]), w["pos"] as Vector2, builder, bag)
			if cell.x >= 0:
				w["target_cell"] = cell
				w["state"] = "MOVING"
		elif state == "MOVING":
			var tcell: Vector2i = w["target_cell"]
			if not _is_cell_still_valid(str(w["role"]), tcell, builder):
				w["state"] = "IDLE"
				continue
			var tpos := builder.cell_to_world(tcell)
			var cur: Vector2 = w["pos"]
			var dist := cur.distance_to(tpos)
			if dist <= 12.0:
				w["state"] = "WORKING"
				w["work_timer"] = 0.85
			else:
				w["pos"] = cur + (tpos - cur).normalized() * minf(dist, float(w["speed"]) * delta)
		elif state == "WORKING":
			w["work_timer"] = float(w["work_timer"]) - delta
			if float(w["work_timer"]) <= 0.0:
				var tcell: Vector2i = w["target_cell"]
				var res := builder.harvest_cell(tcell, bag, 1)
				if bool(res["ok"]):
					worker_completed_job.emit(str(w["uid"]), str(res["kind"]), str(res.get("item", "")))
				w["state"] = "IDLE"


func _find_job_cell(role: String, pos: Vector2, builder: BaseGridBuilder, bag: Dictionary) -> Vector2i:
	var best_cell := Vector2i(-1, -1)
	var best_dist := 1e9

	# KEEPER prioritizes refueling low campfires first!
	if role == "KEEPER" and int(bag.get("wood", 0)) >= 1:
		for c in builder.structures.keys():
			var st: Dictionary = builder.structures[c]
			if float(st["max_fuel"]) > 0.0 and float(st["fuel"]) < float(st["max_fuel"]) * 0.55:
				var d := pos.distance_to(builder.cell_to_world(c))
				if d < best_dist:
					best_dist = d
					best_cell = c
		if best_cell.x >= 0:
			return best_cell

	# FARMER prioritizes mature crops or unwatered farm plots
	if role == "FARMER":
		for c in builder.structures.keys():
			var st: Dictionary = builder.structures[c]
			if bool(st["is_farm"]) and (float(st["growth"]) >= 1.0 or not bool(st["watered"])):
				var d := pos.distance_to(builder.cell_to_world(c))
				if d < best_dist:
					best_dist = d
					best_cell = c
		if best_cell.x >= 0:
			return best_cell

	# Fallback / GATHERER: nearest harvestable resource node
	for c in builder.resources.keys():
		var d := pos.distance_to(builder.cell_to_world(c))
		if d < best_dist:
			best_dist = d
			best_cell = c
	return best_cell


func _is_cell_still_valid(role: String, cell: Vector2i, builder: BaseGridBuilder) -> bool:
	if builder.resources.has(cell):
		return true
	if builder.structures.has(cell):
		var st: Dictionary = builder.structures[cell]
		if role == "KEEPER" and float(st["max_fuel"]) > 0.0:
			return true
		if role == "FARMER" and bool(st["is_farm"]):
			return true
	return false
