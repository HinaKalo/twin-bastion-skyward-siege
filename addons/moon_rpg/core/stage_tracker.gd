class_name StageRunTracker
extends RefCounted
## Pure-Data Stage / Level Run Tracker for Arcade, Platformer, and Dungeon Runs.
## Tracks collectibles (idempotent by ID), elapsed time, damage taken (no-hit bonus),
## linear stage progress (0..1), and computes S / A / B / C completion grades.

signal collectible_picked(collected_count: int, total_count: int, collectible_id: String)
signal stage_finished(summary: Dictionary)

var stage_id: String = ""
var total_collectibles: int = 0
var collected_ids: Dictionary = {} # collectible_id -> true
var elapsed_sec: float = 0.0
var damage_taken: float = 0.0
var deaths: int = 0
var start_x: float = 0.0
var goal_x: float = 1000.0
var is_running: bool = false
var is_finished: bool = false
var won: bool = false


func start(id: String, total_items: int = 0, from_x: float = 0.0, to_x: float = 1000.0) -> void:
	stage_id = id
	total_collectibles = maxi(0, total_items)
	collected_ids.clear()
	elapsed_sec = 0.0
	damage_taken = 0.0
	deaths = 0
	start_x = from_x
	goal_x = to_x
	is_running = true
	is_finished = false
	won = false


func tick(delta: float) -> void:
	if is_running and not is_finished:
		elapsed_sec += delta


func collect(collectible_id: String) -> bool:
	if collectible_id.is_empty() or collected_ids.has(collectible_id):
		return false
	collected_ids[collectible_id] = true
	collectible_picked.emit(collected_ids.size(), total_collectibles, collectible_id)
	return true


func get_collected_count() -> int:
	return collected_ids.size()


func get_collectible_ratio() -> float:
	if total_collectibles <= 0:
		return 1.0
	return clampf(float(collected_ids.size()) / float(total_collectibles), 0.0, 1.0)


func record_damage(amount: float) -> void:
	damage_taken += maxf(0.0, amount)


func record_death() -> void:
	deaths += 1


func get_progress(current_x: float) -> float:
	var span := goal_x - start_x
	if absf(span) < 0.001:
		return 0.0
	return clampf((current_x - start_x) / span, 0.0, 1.0)


func is_no_hit() -> bool:
	return damage_taken <= 0.0 and deaths == 0


func compute_grade() -> String:
	if not won:
		return "D"
	var ratio := get_collectible_ratio()
	if ratio >= 0.95 and is_no_hit():
		return "S"
	if ratio >= 0.80 and deaths == 0:
		return "A"
	if ratio >= 0.50:
		return "B"
	return "C"


func finish(did_win: bool) -> Dictionary:
	is_running = false
	is_finished = true
	won = did_win
	var summary := {
		"stage_id": stage_id,
		"won": won,
		"grade": compute_grade(),
		"collected": collected_ids.size(),
		"total_collectibles": total_collectibles,
		"elapsed_sec": snappedf(elapsed_sec, 0.01),
		"damage_taken": damage_taken,
		"deaths": deaths,
		"no_hit": is_no_hit(),
	}
	stage_finished.emit(summary)
	return summary


func serialize() -> Dictionary:
	return {
		"stage_id": stage_id,
		"total_collectibles": total_collectibles,
		"collected_ids": collected_ids.keys(),
		"elapsed_sec": elapsed_sec,
		"damage_taken": damage_taken,
		"deaths": deaths,
		"won": won,
	}


func deserialize(data: Dictionary) -> void:
	stage_id = str(data.get("stage_id", ""))
	total_collectibles = int(data.get("total_collectibles", 0))
	collected_ids.clear()
	for cid in data.get("collected_ids", []):
		collected_ids[str(cid)] = true
	elapsed_sec = float(data.get("elapsed_sec", 0.0))
	damage_taken = float(data.get("damage_taken", 0.0))
	deaths = int(data.get("deaths", 0))
	won = bool(data.get("won", false))
