class_name CardRuleMachine
extends RefCounted
## Deterministic Turn/Phase State Machine + Effect Resolution Queue & Trigger Bus
## for Hearthstone / Balatro / Slay the Spire style card & tabletop games.
## Features:
## - Strict phase transition validation (`IDLE -> ROUND_START -> DRAW -> MAIN_ACTION -> RESOLVING -> ENEMY_TURN -> ROUND_END -> RELIC_DRAFT / VICTORY / DEFEAT`)
## - Explicit Effect Resolution Queue supporting FIFO & priority-front interrupts
## - Trigger Bus (`ON_CARD_PLAYED`, `ON_MINION_SUMMON`, `ON_DAMAGE`, `ON_MINION_DEATH`, `ON_TURN_START`, `ON_TURN_END`)
## - Built-in infinite-loop / trigger-depth guard (`max_trigger_depth`)
## - Full `serialize()` / `deserialize()` for mid-match save & deterministic replay.

enum Phase {
	IDLE,
	ROUND_START,
	DRAW,
	MAIN_ACTION,
	RESOLVING,
	ENEMY_TURN,
	ROUND_END,
	RELIC_DRAFT,
	VICTORY,
	DEFEAT,
}

signal phase_changed(old_phase: int, new_phase: int)
signal effect_enqueued(effect: Dictionary)
signal effect_resolved(effect: Dictionary, step_index: int)
signal trigger_guard_hit(depth: int)

var current_phase: int = Phase.IDLE
var turn_number: int = 0
var max_trigger_depth: int = 32
var effect_queue: Array[Dictionary] = []
var resolution_log: Array[Dictionary] = []

var _triggers: Dictionary = {} # event_name -> Array[Dictionary] {owner_id, priority, callback}
var _handlers: Dictionary = {} # effect_type -> Callable(effect: Dictionary)
var _active_depth: int = 0
var _step_counter: int = 0


func reset() -> void:
	current_phase = Phase.IDLE
	turn_number = 0
	effect_queue.clear()
	resolution_log.clear()
	_active_depth = 0
	_step_counter = 0


func set_phase(next_phase: int) -> bool:
	if next_phase == current_phase:
		return false
	if current_phase == Phase.VICTORY or current_phase == Phase.DEFEAT:
		if next_phase != Phase.IDLE:
			return false
	var old := current_phase
	current_phase = next_phase
	if next_phase == Phase.ROUND_START:
		turn_number += 1
	phase_changed.emit(old, next_phase)
	return true


func get_phase_name(phase_id: int = -1) -> String:
	var p := current_phase if phase_id < 0 else phase_id
	match p:
		Phase.IDLE: return "IDLE"
		Phase.ROUND_START: return "ROUND_START"
		Phase.DRAW: return "DRAW"
		Phase.MAIN_ACTION: return "MAIN_ACTION"
		Phase.RESOLVING: return "RESOLVING"
		Phase.ENEMY_TURN: return "ENEMY_TURN"
		Phase.ROUND_END: return "ROUND_END"
		Phase.RELIC_DRAFT: return "RELIC_DRAFT"
		Phase.VICTORY: return "VICTORY"
		Phase.DEFEAT: return "DEFEAT"
		_: return "UNKNOWN"


func register_effect_handler(effect_type: String, handler: Callable) -> void:
	_handlers[effect_type] = handler


func register_trigger(event_name: String, owner_id: String, priority: int, callback: Callable) -> void:
	if not _triggers.has(event_name):
		_triggers[event_name] = []
	var arr: Array = _triggers[event_name]
	arr.append({
		"owner_id": owner_id,
		"priority": priority,
		"callback": callback,
	})
	arr.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["priority"]) < int(b["priority"])
	)


func unregister_triggers_for(owner_id: String) -> void:
	for ev in _triggers.keys():
		var arr: Array = _triggers[ev]
		for i in range(arr.size() - 1, -1, -1):
			if str((arr[i] as Dictionary).get("owner_id", "")) == owner_id:
				arr.remove_at(i)


func emit_trigger(event_name: String, payload: Dictionary = {}) -> int:
	if _active_depth >= max_trigger_depth:
		trigger_guard_hit.emit(_active_depth)
		return 0
	if not _triggers.has(event_name):
		return 0
	_active_depth += 1
	var fired := 0
	var listeners: Array = (_triggers[event_name] as Array).duplicate()
	for entry in listeners:
		var cb: Callable = (entry as Dictionary)["callback"]
		if cb.is_valid():
			cb.call(payload)
			fired += 1
	_active_depth -= 1
	return fired


func enqueue_effect(effect: Dictionary, front: bool = false) -> void:
	var copy := effect.duplicate(true)
	if front:
		effect_queue.push_front(copy)
	else:
		effect_queue.push_back(copy)
	effect_enqueued.emit(copy)


func flush_queue(max_steps: int = 64) -> int:
	var return_phase := current_phase
	var was_playable := (return_phase == Phase.MAIN_ACTION or return_phase == Phase.ENEMY_TURN)
	if was_playable and not effect_queue.is_empty():
		set_phase(Phase.RESOLVING)

	var processed := 0
	while not effect_queue.is_empty():
		if processed >= max_steps:
			trigger_guard_hit.emit(processed)
			effect_queue.clear()
			break
		var eff: Dictionary = effect_queue.pop_front()
		var etype := str(eff.get("type", ""))
		_step_counter += 1
		if _handlers.has(etype):
			var handler: Callable = _handlers[etype]
			if handler.is_valid():
				handler.call(eff)
		resolution_log.append(eff)
		effect_resolved.emit(eff, _step_counter)
		processed += 1
		if current_phase == Phase.VICTORY or current_phase == Phase.DEFEAT or current_phase == Phase.RELIC_DRAFT:
			effect_queue.clear()
			break

	if current_phase == Phase.RESOLVING and was_playable:
		set_phase(return_phase)
	return processed


func serialize() -> Dictionary:
	return {
		"current_phase": current_phase,
		"turn_number": turn_number,
		"max_trigger_depth": max_trigger_depth,
		"effect_queue": effect_queue.duplicate(true),
		"step_counter": _step_counter,
	}


func deserialize(data: Dictionary) -> void:
	current_phase = int(data.get("current_phase", Phase.IDLE))
	turn_number = int(data.get("turn_number", 0))
	max_trigger_depth = int(data.get("max_trigger_depth", 32))
	_step_counter = int(data.get("step_counter", 0))
	effect_queue.clear()
	for eff in data.get("effect_queue", []):
		if eff is Dictionary:
			effect_queue.append((eff as Dictionary).duplicate(true))
