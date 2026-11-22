class_name CraftingRecipeEngine
extends RefCounted
## Data-Driven Crafting & Timed Production Queue Engine (Don't Starve / Stardew / RimWorld).
## Supports workstation proximity requirements ("hand", "campfire", "workbench", "furnace"),
## instant crafting, and timed cooking/smelting queues.

signal recipe_crafted(recipe_id: String, outputs: Dictionary)
signal job_started(job: Dictionary)
signal job_completed(job: Dictionary)

var recipes: Dictionary = {} # recipe_id -> Dictionary
var active_jobs: Array[Dictionary] = []
var _job_seq: int = 0


func register_recipe(recipe_id: String, def: Dictionary) -> void:
	var d := def.duplicate(true)
	d["id"] = recipe_id
	if not d.has("station"):
		d["station"] = "hand"
	if not d.has("craft_time"):
		d["craft_time"] = 0.0
	recipes[recipe_id] = d


func can_craft(recipe_id: String, bag: Dictionary, nearby_stations: Array[String] = []) -> Dictionary:
	if not recipes.has(recipe_id):
		return {"ok": false, "reason": "未知配方"}
	var r: Dictionary = recipes[recipe_id]
	var req_station := str(r.get("station", "hand"))
	if req_station != "hand" and not nearby_stations.has(req_station):
		return {"ok": false, "reason": "需要靠近【%s】" % req_station}
	var inputs: Dictionary = r.get("inputs", {})
	for item_id in inputs.keys():
		var need := int(inputs[item_id])
		if int(bag.get(item_id, 0)) < need:
			return {"ok": false, "reason": "材料不足(%s 需%d)" % [str(item_id), need]}
	return {"ok": true, "recipe": r}


func craft_instant(recipe_id: String, bag: Dictionary, nearby_stations: Array[String] = []) -> Dictionary:
	var chk := can_craft(recipe_id, bag, nearby_stations)
	if not bool(chk["ok"]):
		return chk
	var r: Dictionary = chk["recipe"]
	_consume_inputs(r.get("inputs", {}), bag)
	var outputs: Dictionary = r.get("outputs", {})
	_grant_outputs(outputs, bag)
	recipe_crafted.emit(recipe_id, outputs.duplicate(true))
	return {"ok": true, "outputs": outputs.duplicate(true)}


func enqueue_craft(recipe_id: String, bag: Dictionary, nearby_stations: Array[String] = []) -> Dictionary:
	var chk := can_craft(recipe_id, bag, nearby_stations)
	if not bool(chk["ok"]):
		return chk
	var r: Dictionary = chk["recipe"]
	var ctime := float(r.get("craft_time", 0.0))
	if ctime <= 0.001:
		return craft_instant(recipe_id, bag, nearby_stations)
	_consume_inputs(r.get("inputs", {}), bag)
	_job_seq += 1
	var job := {
		"uid": "job_%d" % _job_seq,
		"recipe_id": recipe_id,
		"name": str(r.get("name", recipe_id)),
		"elapsed": 0.0,
		"duration": ctime,
		"outputs": (r.get("outputs", {}) as Dictionary).duplicate(true),
	}
	active_jobs.append(job)
	job_started.emit(job)
	return {"ok": true, "job": job}


func tick_jobs(delta: float, bag: Dictionary) -> Array[Dictionary]:
	var done: Array[Dictionary] = []
	if delta <= 0.0:
		return done
	for i in range(active_jobs.size() - 1, -1, -1):
		var j: Dictionary = active_jobs[i]
		j["elapsed"] = float(j["elapsed"]) + delta
		if float(j["elapsed"]) >= float(j["duration"]):
			active_jobs.remove_at(i)
			var outputs: Dictionary = j.get("outputs", {})
			_grant_outputs(outputs, bag)
			done.append(j)
			job_completed.emit(j)
			recipe_crafted.emit(str(j["recipe_id"]), outputs.duplicate(true))
	return done


func _consume_inputs(inputs: Dictionary, bag: Dictionary) -> void:
	for item_id in inputs.keys():
		bag[item_id] = maxi(0, int(bag.get(item_id, 0)) - int(inputs[item_id]))


func _grant_outputs(outputs: Dictionary, bag: Dictionary) -> void:
	for item_id in outputs.keys():
		bag[item_id] = int(bag.get(item_id, 0)) + int(outputs[item_id])
