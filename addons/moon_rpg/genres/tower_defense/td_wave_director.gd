class_name TDWaveDirector
extends RefCounted
## Data-Driven Multi-Wave Spawner for Tower Defense games.
## Supports staged spawn groups with delays/intervals, early-call bonus gold,
## and full wave lifecycle signals + serialization.

signal wave_started(wave_index: int, wave_name: String)
signal enemy_spawn_requested(enemy_id: String, lane_id: String, wave_index: int)
signal wave_spawning_finished(wave_index: int)
signal all_waves_finished()

var waves: Array[Dictionary] = []
var current_wave_index: int = -1
var is_spawning: bool = false
var _active_groups: Array[Dictionary] = []


## wave_def: { "name": "Wave 1", "early_bonus": 25, "groups": [ { "enemy_id": "goblin", "lane_id": "main", "count": 6, "interval": 0.9, "delay": 0.0 } ] }
func register_wave(wave_def: Dictionary) -> void:
	waves.append(wave_def.duplicate(true))


func get_total_waves() -> int:
	return waves.size()


func has_next_wave() -> bool:
	return current_wave_index + 1 < waves.size()


func start_next_wave() -> Dictionary:
	if not has_next_wave():
		return {"ok": false, "reason": "No more waves"}
	var early_bonus := 0
	if is_spawning and current_wave_index >= 0:
		early_bonus = int(waves[current_wave_index].get("early_bonus", 15))
	current_wave_index += 1
	var w: Dictionary = waves[current_wave_index]
	is_spawning = true
	for g in w.get("groups", []):
		_active_groups.append({
			"enemy_id": str(g.get("enemy_id", "creep")),
			"lane_id": str(g.get("lane_id", "lane_1")),
			"remaining": int(g.get("count", 1)),
			"interval": maxf(0.05, float(g.get("interval", 1.0))),
			"timer": maxf(0.0, float(g.get("delay", 0.0))),
			"started": false,
			"wave_index": current_wave_index,
		})
	wave_started.emit(current_wave_index, str(w.get("name", "Wave %d" % (current_wave_index + 1))))
	return {"ok": true, "wave_index": current_wave_index, "early_bonus": early_bonus}


func tick(delta: float) -> void:
	if _active_groups.is_empty():
		return
	for i in range(_active_groups.size() - 1, -1, -1):
		var g: Dictionary = _active_groups[i]
		g["timer"] = float(g["timer"]) - delta
		while float(g["timer"]) <= 0.0 and int(g["remaining"]) > 0:
			g["started"] = true
			g["remaining"] = int(g["remaining"]) - 1
			enemy_spawn_requested.emit(str(g["enemy_id"]), str(g["lane_id"]), int(g["wave_index"]))
			g["timer"] = float(g["timer"]) + float(g["interval"])
		if int(g["remaining"]) <= 0:
			_active_groups.remove_at(i)
	if _active_groups.is_empty() and is_spawning:
		is_spawning = false
		wave_spawning_finished.emit(current_wave_index)
		if not has_next_wave():
			all_waves_finished.emit()


func pending_arrivals() -> Array[Dictionary]:
	var arrivals: Array[Dictionary] = []
	for g in _active_groups:
		if not bool(g["started"]):
			arrivals.append(g)
	return arrivals


func serialize() -> Dictionary:
	return {
		"current_wave_index": current_wave_index,
		"is_spawning": is_spawning,
	}


func deserialize(data: Dictionary) -> void:
	current_wave_index = int(data.get("current_wave_index", -1))
	is_spawning = false
	_active_groups.clear()
