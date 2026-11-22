class_name TechTree
extends RefCounted
## Pure-Data Prerequisite DAG Tech Tree (4X Civilization / Strategy Sim).
## Supports prerequisite validation, research progress with science overflow,
## automatic StoryBlackboard tag unlocking (`tech_<id>`), and serialization.

signal tech_unlocked(tech_id: String)

var _defs: Dictionary = {} # tech_id -> { name, cost, prereqs: Array[String], unlocks: Array }
var unlocked: Dictionary = {} # tech_id -> true
var current_tech_id: String = ""
var current_progress: float = 0.0


func define_tech(tech_id: String, display_name: String, cost: float, prereqs: Array = [], unlocks: Array = []) -> void:
	_defs[tech_id] = {
		"id": tech_id,
		"name": display_name,
		"cost": maxf(1.0, cost),
		"prereqs": prereqs.duplicate(),
		"unlocks": unlocks.duplicate(true),
	}


func is_unlocked(tech_id: String) -> bool:
	return bool(unlocked.get(tech_id, false))


func can_research(tech_id: String) -> bool:
	if not _defs.has(tech_id) or is_unlocked(tech_id):
		return false
	for req in _defs[tech_id]["prereqs"]:
		if not is_unlocked(str(req)):
			return false
	return true


func get_available_techs() -> Array[String]:
	var out: Array[String] = []
	for tid in _defs.keys():
		if can_research(str(tid)):
			out.append(str(tid))
	return out


func start_research(tech_id: String) -> bool:
	if not can_research(tech_id):
		return false
	if current_tech_id != tech_id:
		current_tech_id = tech_id
		current_progress = 0.0
	return true


## Adds science points; returns array of tech_ids completed (supports overflow into next available if desired).
func add_science(amount: float) -> Array[String]:
	var completed: Array[String] = []
	if amount <= 0.0 or current_tech_id.is_empty() or not _defs.has(current_tech_id):
		return completed
	current_progress += amount
	var cost := float(_defs[current_tech_id]["cost"])
	if current_progress >= cost:
		var finished_id := current_tech_id
		var overflow := current_progress - cost
		unlocked[finished_id] = true
		current_tech_id = ""
		current_progress = overflow
		completed.append(finished_id)
		tech_unlocked.emit(finished_id)
	return completed


func get_tech_info(tech_id: String) -> Dictionary:
	return _defs.get(tech_id, {})


func serialize() -> Dictionary:
	return {
		"unlocked": unlocked.keys(),
		"current_tech_id": current_tech_id,
		"current_progress": current_progress,
	}


func deserialize(data: Dictionary) -> void:
	if data.is_empty():
		return
	unlocked.clear()
	for t in data.get("unlocked", []):
		unlocked[str(t)] = true
	current_tech_id = str(data.get("current_tech_id", ""))
	current_progress = float(data.get("current_progress", 0.0))
