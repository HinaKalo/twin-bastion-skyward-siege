class_name TurnPhaseMachine
extends RefCounted
## Tactical SRPG Faction Phase State Machine (PLAYER -> ENEMY -> ALLY -> Turn + 1).

signal phase_changed(turn_number: int, faction: String)

var factions: Array[String] = ["player", "enemy"]
var turn_number: int = 1
var phase_index: int = 0
var _unit_state: Dictionary = {} # unit_id -> { faction, moved, acted }


func _init(faction_order: Array = ["player", "enemy"]) -> void:
	if not faction_order.is_empty():
		factions.clear()
		for f in faction_order:
			factions.append(str(f))


func current_faction() -> String:
	return factions[phase_index] if phase_index < factions.size() else "player"


func register_unit(unit_id: String, faction: String) -> void:
	_unit_state[unit_id] = {"faction": faction, "moved": false, "acted": false}


func unregister_unit(unit_id: String) -> void:
	_unit_state.erase(unit_id)


func mark_moved(unit_id: String) -> void:
	if _unit_state.has(unit_id):
		_unit_state[unit_id]["moved"] = true


func mark_acted(unit_id: String) -> void:
	if _unit_state.has(unit_id):
		_unit_state[unit_id]["moved"] = true
		_unit_state[unit_id]["acted"] = true


func can_act(unit_id: String) -> bool:
	if not _unit_state.has(unit_id):
		return false
	var st: Dictionary = _unit_state[unit_id]
	return str(st["faction"]) == current_faction() and not bool(st["acted"])


func all_acted_in_current_phase() -> bool:
	var fac := current_faction()
	for uid in _unit_state.keys():
		var st: Dictionary = _unit_state[uid]
		if str(st["faction"]) == fac and not bool(st["acted"]):
			return false
	return true


func end_phase() -> String:
	phase_index += 1
	if phase_index >= factions.size():
		phase_index = 0
		turn_number += 1
	var next_fac := current_faction()
	for uid in _unit_state.keys():
		if str(_unit_state[uid]["faction"]) == next_fac:
			_unit_state[uid]["moved"] = false
			_unit_state[uid]["acted"] = false
	phase_changed.emit(turn_number, next_fac)
	return next_fac
