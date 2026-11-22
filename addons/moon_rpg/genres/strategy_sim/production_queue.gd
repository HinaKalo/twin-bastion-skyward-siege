class_name ProductionQueue
extends RefCounted
## Per-City / Per-Workshop Build & Production Queue with Overflow Rollover.

signal item_completed(item_id: String, meta: Dictionary)

var queue: Array[Dictionary] = [] # [{ id, name, cost, progress, meta }]


func enqueue(item_id: String, display_name: String, cost: float, meta: Dictionary = {}) -> void:
	queue.append({
		"id": item_id,
		"name": display_name,
		"cost": maxf(1.0, cost),
		"progress": 0.0,
		"meta": meta.duplicate(true),
	})


func cancel(index: int) -> Dictionary:
	if index < 0 or index >= queue.size():
		return {}
	return queue.pop_at(index)


func current_item() -> Dictionary:
	return queue[0] if not queue.is_empty() else {}


func is_empty() -> bool:
	return queue.is_empty()


## Advances queue by `production_points`; overflow rolls cleanly into subsequent queued items.
func advance_production(production_points: float) -> Array[String]:
	var completed: Array[String] = []
	var remaining := production_points
	while remaining > 0.0 and not queue.is_empty():
		var head: Dictionary = queue[0]
		var needed := float(head["cost"]) - float(head["progress"])
		if remaining >= needed:
			remaining -= needed
			var done: Dictionary = queue.pop_front()
			var cid := str(done["id"])
			completed.append(cid)
			item_completed.emit(cid, done.get("meta", {}))
		else:
			head["progress"] = float(head["progress"]) + remaining
			remaining = 0.0
	return completed


func serialize() -> Dictionary:
	return {"queue": queue.duplicate(true)}


func deserialize(data: Dictionary) -> void:
	queue.clear()
	for entry in data.get("queue", []):
		queue.append((entry as Dictionary).duplicate(true))
