extends Node
## Inventory, Equipment Slots, Quick-Use Hotbar, and ASTLIBRA-Style Equipment Mastery Manager.
## Equipping gear and defeating enemies earns Mastery XP on equipped items; reaching max Mastery
## permanently unlocks the item's passive stat bonus even after unequipping.

const EQUIP_SLOTS := ["weapon", "sub_weapon", "armor", "accessory_1", "accessory_2"]
const HOTBAR_SIZE := 4

var gold: int = 100
var bag: Dictionary = {} # item_id -> count
var equipment: Dictionary = {
	"weapon": "",
	"sub_weapon": "",
	"armor": "",
	"accessory_1": "",
	"accessory_2": "",
}
var hotbar: Array[String] = ["", "", "", ""]
var mastery_xp: Dictionary = {} # item_id -> int
var mastery_unlocked: Dictionary = {} # item_id -> bool

var _bound_stat_block: StatBlock = null
var _bound_actor: Node = null


func _ready() -> void:
	if EventBus:
		EventBus.enemy_killed.connect(_on_enemy_killed)


func bind_player(actor: Node, stat_block: StatBlock) -> void:
	_bound_actor = actor
	_bound_stat_block = stat_block
	reapply_all_stat_modifiers()


func reset_starter_kit() -> void:
	gold = 120
	bag.clear()
	for s in EQUIP_SLOTS:
		equipment[s] = ""
	hotbar = ["", "", "", ""]
	mastery_xp.clear()
	mastery_unlocked.clear()

	add_item("iron_sword", 1, true)
	add_item("leather_boots", 1, true)
	add_item("hp_potion", 3, true)
	add_item("apple_snack", 2, true)
	equip_item("iron_sword")
	equip_item("leather_boots")
	assign_hotbar(0, "hp_potion")
	assign_hotbar(1, "apple_snack")


func add_gold(amount: int) -> void:
	gold = maxi(0, gold + amount)
	if EventBus:
		EventBus.gold_changed.emit(gold)


func add_item(item_id: String, amount: int = 1, silent: bool = false) -> bool:
	if amount <= 0 or item_id.is_empty():
		return false
	var item_def := DataRegistry.get_item(item_id)
	var max_stack := int(item_def.get("max_stack", 99))
	var current := int(bag.get(item_id, 0))
	var next_val := mini(max_stack, current + amount)
	bag[item_id] = next_val
	if not silent and EventBus:
		EventBus.item_collected.emit(item_id, next_val - current)
		EventBus.inventory_changed.emit()
	return true


func remove_item(item_id: String, amount: int = 1) -> bool:
	if amount <= 0:
		return false
	var current := int(bag.get(item_id, 0))
	if current < amount:
		return false
	var remaining := current - amount
	if remaining <= 0:
		bag.erase(item_id)
	else:
		bag[item_id] = remaining
	if EventBus:
		EventBus.inventory_changed.emit()
	return true


func get_item_count(item_id: String) -> int:
	return int(bag.get(item_id, 0))


func has_item(item_id: String, amount: int = 1) -> bool:
	return get_item_count(item_id) >= amount


func equip_item(item_id: String, explicit_slot: String = "") -> bool:
	var item_def := DataRegistry.get_item(item_id)
	if item_def.is_empty():
		return false
	if not has_item(item_id, 1):
		return false
	var slot := explicit_slot if not explicit_slot.is_empty() else str(item_def.get("slot", ""))
	if slot == "accessory":
		slot = "accessory_1" if str(equipment["accessory_1"]).is_empty() else "accessory_2"
	if not equipment.has(slot):
		return false
	equipment[slot] = item_id
	reapply_all_stat_modifiers()
	if EventBus:
		EventBus.equipment_changed.emit(slot, item_id)
		EventBus.inventory_changed.emit()
	return true


func unequip_slot(slot_name: String) -> void:
	if not equipment.has(slot_name):
		return
	equipment[slot_name] = ""
	reapply_all_stat_modifiers()
	if EventBus:
		EventBus.equipment_changed.emit(slot_name, "")
		EventBus.inventory_changed.emit()


func assign_hotbar(slot_index: int, item_id: String) -> void:
	if slot_index < 0 or slot_index >= HOTBAR_SIZE:
		return
	hotbar[slot_index] = item_id
	if EventBus:
		EventBus.hotbar_changed.emit(slot_index, item_id)


func use_hotbar(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= HOTBAR_SIZE:
		return false
	var item_id := hotbar[slot_index]
	if item_id.is_empty():
		return false
	return use_item(item_id)


func use_item(item_id: String) -> bool:
	var item_def := DataRegistry.get_item(item_id)
	if item_def.is_empty() or not has_item(item_id, 1):
		return false
	var item_type := str(item_def.get("type", ""))
	if item_type == "equipment":
		return equip_item(item_id)
	if item_type != "consumable":
		return false

	var effect: Dictionary = item_def.get("effect", {})
	if _bound_stat_block != null:
		if effect.has("heal_hp"):
			var healed := _bound_stat_block.modify_hp(float(effect["heal_hp"]))
			if _bound_actor is Node2D and EventBus and healed > 0.0:
				EventBus.actor_healed.emit(_bound_actor, int(healed), (_bound_actor as Node2D).global_position + Vector2(0, -36))
		if effect.has("heal_mp"):
			_bound_stat_block.modify_mp(float(effect["heal_mp"]))
		if effect.has("heal_st"):
			_bound_stat_block.modify_st(float(effect["heal_st"]))
		if effect.has("buff") and _bound_actor != null and _bound_actor.has_method("apply_status_effect"):
			var b: Dictionary = effect["buff"]
			_bound_actor.apply_status_effect(str(b.get("id", "item_buff")), b)

	remove_item(item_id, 1)
	if AudioManager:
		AudioManager.play_sfx("sfx.collect")
	if EventBus:
		EventBus.player_stats_changed.emit()
	return true


func add_mastery_xp_to_equipped(amount: int) -> void:
	if amount <= 0:
		return
	var unlocked_any := false
	for slot_name in EQUIP_SLOTS:
		var item_id: String = str(equipment.get(slot_name, ""))
		if item_id.is_empty():
			continue
		var item_def := DataRegistry.get_item(item_id)
		var max_xp := int(item_def.get("mastery_max_xp", 0))
		if max_xp <= 0:
			continue
		var cur := int(mastery_xp.get(item_id, 0))
		var next_xp := mini(max_xp, cur + amount)
		mastery_xp[item_id] = next_xp
		var now_unlocked := next_xp >= max_xp
		if now_unlocked and not bool(mastery_unlocked.get(item_id, false)):
			mastery_unlocked[item_id] = true
			unlocked_any = true
			if EventBus:
				var title := LocaleManager.tr_key(str(item_def.get("name_key", item_id)), {}, item_id)
				EventBus.toast_requested.emit("装备精通解锁：%s" % title, "gold")
		if EventBus:
			EventBus.mastery_updated.emit(item_id, next_xp, max_xp, bool(mastery_unlocked.get(item_id, false)))
	if unlocked_any:
		reapply_all_stat_modifiers()


func reapply_all_stat_modifiers() -> void:
	if _bound_stat_block == null:
		return
	for slot_name in EQUIP_SLOTS:
		_bound_stat_block.remove_modifiers_by_source("equip:" + slot_name)
		var item_id: String = str(equipment.get(slot_name, ""))
		if item_id.is_empty():
			continue
		var item_def := DataRegistry.get_item(item_id)
		var stats: Dictionary = item_def.get("stats", {})
		for stat_name in stats.keys():
			_bound_stat_block.add_modifier("equip:" + slot_name, str(stat_name), float(stats[stat_name]), StatBlock.ModOp.ADD)

	for item_id in mastery_unlocked.keys():
		if not bool(mastery_unlocked[item_id]):
			continue
		var src := "mastery:" + str(item_id)
		_bound_stat_block.remove_modifiers_by_source(src)
		var item_def := DataRegistry.get_item(str(item_id))
		var bonus: Dictionary = item_def.get("mastery_bonus", {})
		for stat_name in bonus.keys():
			_bound_stat_block.add_modifier(src, str(stat_name), float(bonus[stat_name]), StatBlock.ModOp.ADD)

	_bound_stat_block.recalculate()
	if EventBus:
		EventBus.player_stats_changed.emit()


func _on_enemy_killed(enemy_id: String, _enemy_node: Node) -> void:
	var edef := DataRegistry.get_enemy(enemy_id)
	var m_xp := int(edef.get("mastery_xp", 25))
	add_mastery_xp_to_equipped(m_xp)


func serialize_state() -> Dictionary:
	return {
		"gold": gold,
		"bag": bag.duplicate(true),
		"equipment": equipment.duplicate(true),
		"hotbar": hotbar.duplicate(),
		"mastery_xp": mastery_xp.duplicate(true),
		"mastery_unlocked": mastery_unlocked.duplicate(true),
	}


func deserialize_state(data: Dictionary) -> void:
	if data.is_empty():
		return
	gold = int(data.get("gold", 0))
	bag = data.get("bag", {}).duplicate(true)
	var eq: Dictionary = data.get("equipment", {})
	for s in EQUIP_SLOTS:
		equipment[s] = str(eq.get(s, ""))
	var hb: Array = data.get("hotbar", [])
	for i in range(HOTBAR_SIZE):
		hotbar[i] = str(hb[i]) if i < hb.size() else ""
	mastery_xp = data.get("mastery_xp", {}).duplicate(true)
	mastery_unlocked = data.get("mastery_unlocked", {}).duplicate(true)
	reapply_all_stat_modifiers()
	if EventBus:
		EventBus.inventory_changed.emit()
		EventBus.gold_changed.emit(gold)
