class_name SimTickScheduler
extends Node
## Dual-Mode Strategy & Simulation Time Scheduler.
## - Mode.TURN_BASED:     Discrete turns (`next_turn()`) like Civilization / SRPG
## - Mode.REALTIME_TICKS: Pausable real-time ticks with 1x / 2x / 4x speed like RimWorld / Paradox

enum Mode { TURN_BASED, REALTIME_TICKS }

signal tick_advanced(tick_number: int)

@export var mode: int = Mode.TURN_BASED
@export var base_tick_interval_sec: float = 1.0

var tick_number: int = 1
var speed_multiplier: float = 1.0
var is_paused: bool = false
var _accum: float = 0.0


func set_mode(new_mode: int) -> void:
	mode = new_mode
	_accum = 0.0


func set_speed(mult: float) -> void:
	speed_multiplier = clampf(mult, 0.25, 8.0)


func set_paused(paused: bool) -> void:
	is_paused = paused


func next_turn() -> int:
	tick_number += 1
	tick_advanced.emit(tick_number)
	return tick_number


func _process(delta: float) -> void:
	if mode != Mode.REALTIME_TICKS or is_paused:
		return
	_accum += delta * speed_multiplier
	var interval := maxf(0.05, base_tick_interval_sec)
	while _accum >= interval:
		_accum -= interval
		next_turn()


func serialize() -> Dictionary:
	return {
		"mode": mode,
		"tick_number": tick_number,
		"speed_multiplier": speed_multiplier,
		"is_paused": is_paused,
	}


func deserialize(data: Dictionary) -> void:
	if data.is_empty():
		return
	mode = int(data.get("mode", Mode.TURN_BASED))
	tick_number = int(data.get("tick_number", 1))
	speed_multiplier = float(data.get("speed_multiplier", 1.0))
	is_paused = bool(data.get("is_paused", false))
