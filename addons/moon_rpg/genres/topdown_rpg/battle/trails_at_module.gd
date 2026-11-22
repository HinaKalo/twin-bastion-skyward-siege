class_name TrailsATModule
extends BattleModule
## Trails in the Sky (空之轨迹) Style Battle Brick:
## - AT Delay Action Order Timeline (`at_delay` — lower acts sooner)
## - Turn Bonus Slots (`CRIT`, `HEAL_HP`, `ZERO_MP`, `ATK_UP`, `CP_UP`) attached to timeline positions
## - Delay Push skills (`delay_push`) to knock enemies off bonus slots
## - 100 CP `S-Break` (`trigger_s_break`) to cut in at position #0 and steal the current Turn Bonus!

const BONUS_POOL := ["NONE", "NONE", "NONE", "CRIT", "HEAL_HP", "ZERO_MP", "ATK_UP", "CP_UP"]

var bonus_queue: Array[String] = [] # upcoming turn bonus for slot 0, 1, 2...
var _s_break_actor_id: String = ""


func get_module_id() -> String:
	return "trails_at"


func on_battle_start(engine: Object, advantage_mode: int) -> void:
	_s_break_actor_id = ""
	bonus_queue.clear()
	for i in range(10):
		bonus_queue.append("NONE" if i == 0 else BONUS_POOL[i % BONUS_POOL.size()])

	for u in engine.allies + engine.enemies:
		var spd := maxf(5.0, (u["stat_block"] as StatBlock).get_stat("move_spd"))
		var base_at := 100.0 / spd * 10.0
		if advantage_mode == 1: # PLAYER_ADVANTAGE
			u["at_delay"] = 0.0 if bool(u["is_ally"]) else base_at + 35.0
		elif advantage_mode == 2: # ENEMY_AMBUSH
			u["at_delay"] = base_at + 35.0 if bool(u["is_ally"]) else 0.0
		else:
			u["at_delay"] = base_at
		if not u.has("cp"):
			u["cp"] = 40.0 if bool(u["is_ally"]) else 0.0


func get_current_bonus() -> String:
	return bonus_queue[0] if not bonus_queue.is_empty() else "NONE"


func set_upcoming_bonus(slot_index: int, bonus_name: String) -> void:
	while bonus_queue.size() <= slot_index:
		bonus_queue.append("NONE")
	bonus_queue[slot_index] = bonus_name


func select_next_actor(engine: Object) -> Dictionary:
	if not _s_break_actor_id.is_empty():
		var sb_u: Dictionary = engine.find_unit(_s_break_actor_id)
		if not sb_u.is_empty() and (sb_u["stat_block"] as StatBlock).hp > 0.0:
			return sb_u
		_s_break_actor_id = ""

	var best: Dictionary = {}
	var best_at := INF
	for u in engine.get_alive_allies() + engine.get_alive_enemies():
		var at := float(u.get("at_delay", 50.0))
		if at < best_at:
			best_at = at
			best = u
	if not best.is_empty() and best_at > 0.0:
		# Advance timeline so best unit reaches AT 0
		for u in engine.get_alive_allies() + engine.get_alive_enemies():
			u["at_delay"] = maxf(0.0, float(u.get("at_delay", 0.0)) - best_at)
	return best


## Returns preview of next `count` turns: [{ id, name, is_ally, at_delay, bonus }]
func get_turn_order_preview(engine: Object, count: int = 8) -> Array[Dictionary]:
	var alive: Array = engine.get_alive_allies() + engine.get_alive_enemies()
	if alive.is_empty():
		return []
	var sim: Array[Dictionary] = []
	for u in alive:
		sim.append({
			"id": str(u["id"]),
			"name": str(u["name"]),
			"is_ally": bool(u["is_ally"]),
			"at": float(u.get("at_delay", 20.0)),
			"step": 100.0 / maxf(5.0, (u["stat_block"] as StatBlock).get_stat("move_spd")) * 10.0,
		})
	var preview: Array[Dictionary] = []
	for i in range(count):
		sim.sort_custom(func(a: Dictionary, b: Dictionary): return float(a["at"]) < float(b["at"]))
		var head := sim[0]
		var bname := bonus_queue[i] if i < bonus_queue.size() else "NONE"
		preview.append({
			"id": head["id"],
			"name": head["name"],
			"is_ally": head["is_ally"],
			"at_delay": int(round(float(head["at"]))),
			"bonus": bname,
		})
		head["at"] = float(head["at"]) + float(head["step"])
	return preview


func modify_damage(_engine: Object, ctx: Dictionary) -> void:
	var actor: Dictionary = ctx["actor"]
	var bonus := get_current_bonus()
	match bonus:
		"CRIT":
			ctx["is_crit"] = true
			ctx["mult"] = float(ctx["mult"]) * 1.5
			(ctx["log"] as Array).append("✦ 【AT奖励: 必杀 CRIT】%s 触发必杀一击！" % actor["name"])
		"ATK_UP":
			ctx["mult"] = float(ctx["mult"]) * 1.3
			(ctx["log"] as Array).append("✦ 【AT奖励: 强攻 ATK+30%】")
		"ZERO_MP":
			ctx["mp_cost"] = 0.0
			(ctx["log"] as Array).append("✦ 【AT奖励: 零消耗 ZERO MP】")
		"HEAL_HP":
			var sb: StatBlock = actor["stat_block"]
			var heal := sb.get_stat("max_hp") * 0.25
			sb.modify_hp(heal)
			(ctx["log"] as Array).append("✦ 【AT奖励: 治愈】%s 回复 %d HP！" % [actor["name"], int(round(heal))])
		"CP_UP":
			actor["cp"] = minf(200.0, float(actor.get("cp", 0.0)) + 30.0)


func on_action_resolved(_engine: Object, ctx: Dictionary) -> void:
	var actor: Dictionary = ctx["actor"]
	var target: Dictionary = ctx["target"]
	# Charge CP on attacking and taking damage
	actor["cp"] = minf(200.0, float(actor.get("cp", 0.0)) + 15.0)
	target["cp"] = minf(200.0, float(target.get("cp", 0.0)) + 12.0)

	# Optional AT delay push (knocks enemy further back on the timeline!)
	var push := float(ctx.get("delay_push", 0.0))
	if push > 0.0 and (target["stat_block"] as StatBlock).hp > 0.0:
		target["at_delay"] = float(target.get("at_delay", 0.0)) + push
		(ctx["log"] as Array).append("⏱ 延迟推条！%s 行动顺位延后 +%.0f AT！" % [target["name"], push])


func on_turn_end(_engine: Object, actor: Dictionary) -> void:
	var spd := maxf(5.0, (actor["stat_block"] as StatBlock).get_stat("move_spd"))
	actor["at_delay"] = 100.0 / spd * 10.0
	if not bonus_queue.is_empty():
		bonus_queue.pop_front()
		bonus_queue.append(BONUS_POOL[randi() % BONUS_POOL.size()])


## Consumes 100 CP to immediately cut in at Turn #0 (stealing the current Turn Bonus!) and unleash an S-Craft.
func trigger_s_break(engine: Object, ally_id: String, target_id: String = "", skill_mult: float = 2.4) -> Array[String]:
	var ally: Dictionary = engine.find_unit(ally_id)
	if ally.is_empty() or not bool(ally["is_ally"]) or (ally["stat_block"] as StatBlock).hp <= 0.0:
		return []
	if float(ally.get("cp", 0.0)) < 100.0:
		return []
	ally["cp"] = float(ally["cp"]) - 100.0
	_s_break_actor_id = ally_id
	var lines: Array[String] = ["⚡ 【S-BREAK 抢回合!】%s 消耗 100 CP 强行插队释放 S-Craft！" % ally["name"]]
	var act_lines: Array[String] = engine.execute_single_action(ally_id, {
		"type": engine.ActionType.SKILL,
		"target_id": target_id,
		"skill_mult": skill_mult,
		"element": "physical",
		"delay_push": 20.0,
	})
	_s_break_actor_id = ""
	lines.append_array(act_lines)
	return lines


func get_extra_commands(_engine: Object, actor: Dictionary) -> Array[Dictionary]:
	if bool(actor.get("is_ally", false)) and float(actor.get("cp", 0.0)) >= 100.0:
		return [{"id": "s_break", "label": "⚡ S-Break 抢回合奥义 (100 CP)"}]
	return []
