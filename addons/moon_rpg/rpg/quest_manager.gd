extends Node
## Data-Driven Quest System & Objective Tracking Engine.
## Supports `talk`, `kill`, `collect`, `reach_room`, and `flag` objectives,
## auto-tracking, rewards, and exposing the active objective's target for
## Minimap, WorldMarker2D, and Screen-Edge ObjectiveIndicator.

enum QuestState { AVAILABLE, ACTIVE, READY_TO_TURN_IN, COMPLETED }

var states: Dictionary = {} # quest_id -> QuestState
var progress: Dictionary = {} # quest_id -> { obj_id: int }
var tracked_quest_id: String = ""


func _ready() -> void:
	if EventBus:
		EventBus.enemy_killed.connect(_on_enemy_killed)
		EventBus.item_collected.connect(_on_item_collected)
		EventBus.room_changed.connect(_on_room_changed)
		EventBus.world_flag_changed.connect(_on_world_flag_changed)


func reset_all() -> void:
	states.clear()
	progress.clear()
	tracked_quest_id = ""


func get_state(quest_id: String) -> int:
	return int(states.get(quest_id, QuestState.AVAILABLE))


func start_quest(quest_id: String) -> bool:
	var qdef := DataRegistry.get_quest(quest_id)
	if qdef.is_empty():
		return false
	if get_state(quest_id) != QuestState.AVAILABLE:
		return false
	states[quest_id] = QuestState.ACTIVE
	var p: Dictionary = {}
	for obj in qdef.get("objectives", []):
		var oid := str(obj.get("id", ""))
		var initial := 0
		if str(obj.get("type", "")) == "collect" and InventoryManager:
			initial = InventoryManager.get_item_count(str(obj.get("target", "")))
		p[oid] = initial
	progress[quest_id] = p
	_evaluate_quest_completion_ready(quest_id)
	if tracked_quest_id.is_empty():
		set_tracked_quest(quest_id)
	if EventBus:
		EventBus.quest_started.emit(quest_id)
		EventBus.quest_updated.emit(quest_id)
		var qtitle := LocaleManager.tr_key(str(qdef.get("title_key", quest_id)), {}, quest_id)
		EventBus.toast_requested.emit("接取任务：%s" % qtitle, "quest")
	return true


func set_tracked_quest(quest_id: String) -> void:
	tracked_quest_id = quest_id
	if EventBus:
		EventBus.tracked_quest_changed.emit(quest_id)


func complete_quest(quest_id: String) -> bool:
	var qdef := DataRegistry.get_quest(quest_id)
	if qdef.is_empty():
		return false
	var st := get_state(quest_id)
	if st != QuestState.READY_TO_TURN_IN and st != QuestState.ACTIVE:
		return false
	states[quest_id] = QuestState.COMPLETED
	var rewards: Dictionary = qdef.get("rewards", {})
	if rewards.has("gold") and InventoryManager:
		InventoryManager.add_gold(int(rewards["gold"]))
	if rewards.has("items") and InventoryManager:
		for item_entry in rewards["items"]:
			InventoryManager.add_item(str(item_entry.get("id", "")), int(item_entry.get("count", 1)))
	if rewards.has("set_flag") and SaveManager:
		SaveManager.set_flag(str(rewards["set_flag"]), true)

	if tracked_quest_id == quest_id:
		tracked_quest_id = _find_next_active_quest()
		if EventBus:
			EventBus.tracked_quest_changed.emit(tracked_quest_id)
	if AudioManager:
		AudioManager.play_sfx("sfx.quest_clear")
	if EventBus:
		EventBus.quest_completed.emit(quest_id)
		var qtitle := LocaleManager.tr_key(str(qdef.get("title_key", quest_id)), {}, quest_id)
		EventBus.toast_requested.emit("完成任务：%s" % qtitle, "gold")
	return true


func get_objective_progress(quest_id: String, obj_id: String) -> int:
	return int(progress.get(quest_id, {}).get(obj_id, 0))


func advance_objective(quest_id: String, obj_id: String, delta: int = 1) -> void:
	if get_state(quest_id) != QuestState.ACTIVE:
		return
	var qdef := DataRegistry.get_quest(quest_id)
	var p: Dictionary = progress.get(quest_id, {})
	for obj in qdef.get("objectives", []):
		if str(obj.get("id", "")) == obj_id:
			var req := int(obj.get("required", 1))
			p[obj_id] = mini(req, int(p.get(obj_id, 0)) + delta)
			progress[quest_id] = p
			_evaluate_quest_completion_ready(quest_id)
			if EventBus:
				EventBus.quest_updated.emit(quest_id)
			return


## Returns a structured descriptor for the currently tracked objective (or turn-in NPC),
## used by HUD, MinimapWidget, WorldMarker2D, and ObjectiveIndicator.
func get_tracked_objective_info() -> Dictionary:
	if tracked_quest_id.is_empty():
		return {}
	var qdef := DataRegistry.get_quest(tracked_quest_id)
	if qdef.is_empty():
		return {}
	var st := get_state(tracked_quest_id)
	if st == QuestState.COMPLETED:
		return {}
	var title := LocaleManager.tr_key(str(qdef.get("title_key", tracked_quest_id)), {}, tracked_quest_id)
	if st == QuestState.READY_TO_TURN_IN:
		return {
			"quest_id": tracked_quest_id,
			"title": title,
			"state": st,
			"room_id": str(qdef.get("turn_in_room", "")),
			"target_id": str(qdef.get("turn_in_npc", "")),
			"description": LocaleManager.tr_key(str(qdef.get("turn_in_key", "")), {}, "返回交付任务"),
			"current": 1,
			"required": 1,
		}
	for obj in qdef.get("objectives", []):
		var oid := str(obj.get("id", ""))
		var cur := get_objective_progress(tracked_quest_id, oid)
		var req := int(obj.get("required", 1))
		if cur < req:
			return {
				"quest_id": tracked_quest_id,
				"title": title,
				"state": st,
				"objective_id": oid,
				"type": str(obj.get("type", "")),
				"room_id": str(obj.get("room_id", "")),
				"target_id": str(obj.get("target", "")),
				"description": LocaleManager.tr_key(str(obj.get("desc_key", oid)), {}, oid),
				"current": cur,
				"required": req,
			}
	return {}


## Returns marker icon hint ("!" / "?" / "") for an NPC in the world.
func get_npc_marker_type(npc_id: String) -> String:
	for qid in DataRegistry.quests.keys():
		var qdef: Dictionary = DataRegistry.quests[qid]
		var st := get_state(str(qid))
		if st == QuestState.READY_TO_TURN_IN and str(qdef.get("turn_in_npc", "")) == npc_id:
			return "?"
	for qid in DataRegistry.quests.keys():
		var qdef: Dictionary = DataRegistry.quests[qid]
		var st := get_state(str(qid))
		if st == QuestState.AVAILABLE and str(qdef.get("giver_npc", "")) == npc_id:
			return "!"
	return ""


func _evaluate_quest_completion_ready(quest_id: String) -> void:
	if get_state(quest_id) != QuestState.ACTIVE:
		return
	var qdef := DataRegistry.get_quest(quest_id)
	var all_done := true
	for obj in qdef.get("objectives", []):
		var oid := str(obj.get("id", ""))
		var req := int(obj.get("required", 1))
		if get_objective_progress(quest_id, oid) < req:
			all_done = false
			break
	if all_done:
		states[quest_id] = QuestState.READY_TO_TURN_IN
		if EventBus:
			EventBus.toast_requested.emit("任务目标达成！请返回交付。", "quest")


func _find_next_active_quest() -> String:
	for qid in states.keys():
		var st := int(states[qid])
		if st == QuestState.ACTIVE or st == QuestState.READY_TO_TURN_IN:
			return str(qid)
	return ""


func _on_enemy_killed(enemy_id: String, _enemy_node: Node) -> void:
	for qid in states.keys():
		if int(states[qid]) != QuestState.ACTIVE:
			continue
		var qdef := DataRegistry.get_quest(str(qid))
		for obj in qdef.get("objectives", []):
			if str(obj.get("type", "")) == "kill" and str(obj.get("target", "")) == enemy_id:
				advance_objective(str(qid), str(obj.get("id", "")), 1)


func _on_item_collected(item_id: String, amount: int) -> void:
	for qid in states.keys():
		if int(states[qid]) != QuestState.ACTIVE:
			continue
		var qdef := DataRegistry.get_quest(str(qid))
		for obj in qdef.get("objectives", []):
			if str(obj.get("type", "")) == "collect" and str(obj.get("target", "")) == item_id:
				advance_objective(str(qid), str(obj.get("id", "")), amount)


func _on_room_changed(room_id: String, _spawn: String) -> void:
	for qid in states.keys():
		if int(states[qid]) != QuestState.ACTIVE:
			continue
		var qdef := DataRegistry.get_quest(str(qid))
		for obj in qdef.get("objectives", []):
			if str(obj.get("type", "")) == "reach_room" and str(obj.get("target", "")) == room_id:
				advance_objective(str(qid), str(obj.get("id", "")), 1)


func _on_world_flag_changed(flag_name: String, value: Variant) -> void:
	if not value:
		return
	for qid in states.keys():
		if int(states[qid]) != QuestState.ACTIVE:
			continue
		var qdef := DataRegistry.get_quest(str(qid))
		for obj in qdef.get("objectives", []):
			if str(obj.get("type", "")) == "flag" and str(obj.get("target", "")) == flag_name:
				advance_objective(str(qid), str(obj.get("id", "")), 1)


func serialize_state() -> Dictionary:
	return {
		"states": states.duplicate(true),
		"progress": progress.duplicate(true),
		"tracked_quest_id": tracked_quest_id,
	}


func deserialize_state(data: Dictionary) -> void:
	if data.is_empty():
		return
	states = data.get("states", {}).duplicate(true)
	progress = data.get("progress", {}).duplicate(true)
	tracked_quest_id = str(data.get("tracked_quest_id", ""))
	if EventBus:
		EventBus.tracked_quest_changed.emit(tracked_quest_id)
