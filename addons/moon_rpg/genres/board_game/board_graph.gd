class_name BoardGraph
extends RefCounted
## Pure-Data Tabletop Board Topology & Turn/Token Engine
## (Monopoly / Mario Party / Catan / Gloomhaven / For The King style).
##
## Features:
## - Directed or bidirectional board spaces (`start`, `event`, `shop`, `battle`, `chance`, `property`, `goal`)
## - Exact-step branching pathfinder (`get_reachable_spaces(start_id, steps)`) for dice rolls
## - Multi-player turn rotation + piece token tracking + landing event signals
## - Full `serialize()` / `deserialize()` for SaveManager / CoopManager integration.

signal token_moved(player_id: String, from_space: String, to_space: String)
signal token_landed(player_id: String, space_id: String, space_data: Dictionary)
signal turn_changed(player_id: String, round_number: int)

var spaces: Dictionary = {} # space_id -> { id, pos: Vector2, type, label, next: Array[String], meta: Dictionary }
var tokens: Dictionary = {} # player_id -> { player_id, space_id, name, meta }
var turn_order: Array[String] = []
var current_turn_index: int = 0
var round_number: int = 1


func add_space(space_id: String, pos: Vector2, space_type: String = "normal", label: String = "", meta: Dictionary = {}) -> void:
	spaces[space_id] = {
		"id": space_id,
		"pos": pos,
		"type": space_type,
		"label": label if not label.is_empty() else space_id,
		"next": [] as Array[String],
		"meta": meta.duplicate(true),
	}


func connect_spaces(from_id: String, to_id: String, bidirectional: bool = false) -> void:
	if not spaces.has(from_id) or not spaces.has(to_id):
		return
	var nxt: Array = spaces[from_id]["next"]
	if not nxt.has(to_id):
		nxt.append(to_id)
	if bidirectional:
		var rev: Array = spaces[to_id]["next"]
		if not rev.has(from_id):
			rev.append(from_id)


func register_player(player_id: String, display_name: String, start_space_id: String, meta: Dictionary = {}) -> void:
	tokens[player_id] = {
		"player_id": player_id,
		"name": display_name,
		"space_id": start_space_id,
		"meta": meta.duplicate(true),
	}
	if not turn_order.has(player_id):
		turn_order.append(player_id)


func get_current_player_id() -> String:
	if turn_order.is_empty():
		return ""
	return turn_order[current_turn_index % turn_order.size()]


func next_turn() -> String:
	if turn_order.is_empty():
		return ""
	current_turn_index += 1
	if current_turn_index >= turn_order.size():
		current_turn_index = 0
		round_number += 1
	var pid := get_current_player_id()
	turn_changed.emit(pid, round_number)
	return pid


## Returns all unique space IDs reachable in EXACTLY `steps` moves (supports branching forks & loops).
func get_reachable_spaces(start_space_id: String, steps: int) -> Array[String]:
	if not spaces.has(start_space_id) or steps <= 0:
		return [start_space_id] if spaces.has(start_space_id) else ([] as Array[String])
	var frontier: Dictionary = {start_space_id: true}
	for _s in range(steps):
		var next_frontier: Dictionary = {}
		for sid in frontier.keys():
			for nxt in spaces[sid]["next"]:
				next_frontier[str(nxt)] = true
		frontier = next_frontier
		if frontier.is_empty():
			break
	var out: Array[String] = []
	for sid in frontier.keys():
		out.append(str(sid))
	return out


func move_token(player_id: String, target_space_id: String) -> bool:
	if not tokens.has(player_id) or not spaces.has(target_space_id):
		return false
	var from_id := str(tokens[player_id]["space_id"])
	tokens[player_id]["space_id"] = target_space_id
	token_moved.emit(player_id, from_id, target_space_id)
	token_landed.emit(player_id, target_space_id, spaces[target_space_id])
	return true


func get_token_position(player_id: String) -> Vector2:
	if not tokens.has(player_id):
		return Vector2.ZERO
	var sid := str(tokens[player_id]["space_id"])
	return spaces[sid]["pos"] if spaces.has(sid) else Vector2.ZERO


func serialize() -> Dictionary:
	return {
		"tokens": tokens.duplicate(true),
		"turn_order": turn_order.duplicate(),
		"current_turn_index": current_turn_index,
		"round_number": round_number,
	}


func deserialize(data: Dictionary) -> void:
	tokens = (data.get("tokens", {}) as Dictionary).duplicate(true)
	turn_order.clear()
	for p in data.get("turn_order", []):
		turn_order.append(str(p))
	current_turn_index = int(data.get("current_turn_index", 0))
	round_number = int(data.get("round_number", 1))
