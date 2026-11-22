class_name StatusEffectManager
extends Node
## Manages timed & stacked Buffs / Debuffs on an Actor2D.
## Automatically applies and cleans up StatBlock modifiers and periodic ticks.

var _owner_actor: Node = null
var _stat_block: StatBlock = null
var _active: Dictionary = {} # effect_id -> Dictionary


func setup(owner_actor: Node, stat_block: StatBlock) -> void:
	_owner_actor = owner_actor
	_stat_block = stat_block


func _process(delta: float) -> void:
	if _active.is_empty():
		return
	var expired: Array[String] = []
	for eid in _active.keys():
		var eff: Dictionary = _active[eid]
		eff["remaining"] = float(eff["remaining"]) - delta
		var tick_interval := float(eff.get("tick_interval", 0.0))
		if tick_interval > 0.0:
			eff["tick_timer"] = float(eff.get("tick_timer", tick_interval)) - delta
			if float(eff["tick_timer"]) <= 0.0:
				eff["tick_timer"] = tick_interval
				_apply_tick(eff)
		if float(eff["remaining"]) <= 0.0:
			expired.append(str(eid))
	for eid in expired:
		remove_effect(eid)


func apply_effect(effect_id: String, spec: Dictionary) -> void:
	var duration := float(spec.get("duration", 5.0))
	var max_stacks := int(spec.get("max_stacks", 1))
	var stacks := 1
	if _active.has(effect_id):
		stacks = mini(max_stacks, int(_active[effect_id].get("stacks", 1)) + 1)
	var entry := {
		"id": effect_id,
		"label": str(spec.get("label", effect_id)),
		"duration": duration,
		"remaining": duration,
		"stacks": stacks,
		"modifiers": spec.get("modifiers", {}),
		"tick_interval": float(spec.get("tick_interval", 0.0)),
		"tick_timer": float(spec.get("tick_interval", 0.0)),
		"tick_hp": float(spec.get("tick_hp", 0.0)),
		"is_debuff": bool(spec.get("is_debuff", false)),
	}
	_active[effect_id] = entry
	_sync_modifiers(effect_id, entry)
	_emit_changed()


func remove_effect(effect_id: String) -> void:
	if not _active.has(effect_id):
		return
	_active.erase(effect_id)
	if _stat_block != null:
		_stat_block.remove_modifiers_by_source("buff:" + effect_id)
	_emit_changed()


func has_effect(effect_id: String) -> bool:
	return _active.has(effect_id)


func get_active_effects() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for eid in _active.keys():
		list.append(_active[eid])
	return list


func _sync_modifiers(effect_id: String, entry: Dictionary) -> void:
	if _stat_block == null:
		return
	var src := "buff:" + effect_id
	_stat_block.remove_modifiers_by_source(src)
	var stacks := int(entry.get("stacks", 1))
	var mods: Dictionary = entry.get("modifiers", {})
	for stat_name in mods.keys():
		var val := float(mods[stat_name]) * float(stacks)
		var op := StatBlock.ModOp.MUL if str(stat_name).ends_with("_mul") else StatBlock.ModOp.ADD
		var clean_stat := str(stat_name).trim_suffix("_mul")
		_stat_block.add_modifier(src, clean_stat, val, op)


func _apply_tick(entry: Dictionary) -> void:
	if _stat_block == null:
		return
	var hp_delta := float(entry.get("tick_hp", 0.0)) * float(entry.get("stacks", 1))
	if hp_delta != 0.0:
		_stat_block.modify_hp(hp_delta)
		if _owner_actor != null and _owner_actor is Node2D and EventBus:
			var pos: Vector2 = (_owner_actor as Node2D).global_position + Vector2(0, -32)
			if hp_delta > 0.0:
				EventBus.actor_healed.emit(_owner_actor, int(hp_delta), pos)
			else:
				EventBus.floating_text_requested.emit(str(int(abs(hp_delta))), pos, "poison")


func _emit_changed() -> void:
	if EventBus and _owner_actor != null:
		EventBus.status_effects_changed.emit(_owner_actor)
		if _owner_actor.is_in_group("player"):
			EventBus.player_stats_changed.emit()
