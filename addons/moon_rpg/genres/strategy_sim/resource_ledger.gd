class_name ResourceLedger
extends RefCounted
## Pure-Data Multi-Resource Economy Ledger (4X Civilization / Management Sim).
## Tracks stockpiles, caps, named yield/upkeep sources, net rate forecasts, and turn settlement.

signal resources_changed()

var stocks: Dictionary = {} # resource_id -> float
var caps: Dictionary = {} # resource_id -> float (0 or absent = uncapped)
var _yield_sources: Dictionary = {} # source_id -> { resource_id: float }


func _init(initial_stocks: Dictionary = {}) -> void:
	for k in initial_stocks.keys():
		stocks[str(k)] = float(initial_stocks[k])


func set_cap(resource_id: String, max_amount: float) -> void:
	caps[resource_id] = maxf(0.0, max_amount)


func get_amount(resource_id: String) -> float:
	return float(stocks.get(resource_id, 0.0))


func add(resource_id: String, delta: float) -> float:
	var next_val := maxf(0.0, get_amount(resource_id) + delta)
	var cap := float(caps.get(resource_id, 0.0))
	if cap > 0.0:
		next_val = minf(cap, next_val)
	stocks[resource_id] = next_val
	resources_changed.emit()
	return next_val


func can_afford(cost: Dictionary) -> bool:
	for res_id in cost.keys():
		if get_amount(str(res_id)) < float(cost[res_id]):
			return false
	return true


func spend(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	for res_id in cost.keys():
		stocks[str(res_id)] = maxf(0.0, get_amount(str(res_id)) - float(cost[res_id]))
	resources_changed.emit()
	return true


## Registers or updates a recurring yield/upkeep source (e.g., "city_capital": {"gold": 8, "food": 5, "science": 4}).
func set_yield_source(source_id: String, deltas: Dictionary) -> void:
	_yield_sources[source_id] = deltas.duplicate(true)


func remove_yield_source(source_id: String) -> void:
	_yield_sources.erase(source_id)


func get_net_rates() -> Dictionary:
	var net: Dictionary = {}
	for src in _yield_sources.values():
		for res_id in (src as Dictionary).keys():
			net[str(res_id)] = float(net.get(str(res_id), 0.0)) + float(src[res_id])
	return net


func apply_turn_yields() -> Dictionary:
	var net := get_net_rates()
	for res_id in net.keys():
		add(str(res_id), float(net[res_id]))
	return net


func serialize() -> Dictionary:
	return {
		"stocks": stocks.duplicate(true),
		"caps": caps.duplicate(true),
		"yield_sources": _yield_sources.duplicate(true),
	}


func deserialize(data: Dictionary) -> void:
	if data.is_empty():
		return
	stocks = data.get("stocks", {}).duplicate(true)
	caps = data.get("caps", {}).duplicate(true)
	_yield_sources = data.get("yield_sources", {}).duplicate(true)
	resources_changed.emit()
