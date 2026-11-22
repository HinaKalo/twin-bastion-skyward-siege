class_name InnService
extends RefCounted
## Traditional JRPG Inn / Tavern Service.
## Restores full party HP/MP, advances Persona-style day/time_of_day in StoryBlackboard,
## triggers autosave, and serves dynamic tavern rumors gated by StoryBlackboard conditions.

const TIME_SLOTS := ["morning", "afternoon", "evening", "night"]

var _rumors: Array[Dictionary] = [] # [{ id, text, condition, grants_tag }]


func rest(party: PartyManager, cost_gold: int = 30, advance_to_morning: bool = true) -> Dictionary:
	if InventoryManager and InventoryManager.gold < cost_gold:
		return {"ok": false, "reason": "金币不足"}
	if InventoryManager and cost_gold > 0:
		InventoryManager.add_gold(-cost_gold)
	if party != null:
		party.heal_all()

	var day := int(StoryBlackboard.get_var("day", 1)) if StoryBlackboard else 1
	var slot := str(StoryBlackboard.get_var("time_of_day", "morning")) if StoryBlackboard else "morning"
	if advance_to_morning:
		day += 1
		slot = "morning"
	else:
		var idx := TIME_SLOTS.find(slot)
		idx = (idx + 1) % TIME_SLOTS.size()
		if idx == 0:
			day += 1
		slot = TIME_SLOTS[idx]

	if StoryBlackboard:
		StoryBlackboard.set_var("day", day, false)
		StoryBlackboard.set_var("time_of_day", slot, true)
	if SaveManager:
		SaveManager.trigger_autosave("inn_rest")
	return {"ok": true, "day": day, "time_of_day": slot}


func register_rumor(rumor_id: String, text: String, condition: String = "", grants_tag: String = "") -> void:
	_rumors.append({
		"id": rumor_id,
		"text": text,
		"condition": condition,
		"grants_tag": grants_tag,
	})


func get_available_rumors() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r in _rumors:
		var cond := str(r["condition"])
		if cond.is_empty() or (StoryBlackboard != null and StoryBlackboard.check(cond)):
			out.append(r)
	return out


func hear_rumor(rumor_id: String) -> String:
	for r in _rumors:
		if str(r["id"]) == rumor_id:
			var tag := str(r["grants_tag"])
			if not tag.is_empty() and StoryBlackboard:
				StoryBlackboard.add_tag(tag)
			return str(r["text"])
	return ""
