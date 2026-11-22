class_name PersonaOneMoreModule
extends BattleModule
## Persona-Style Battle Brick:
## - Elemental Affinities: weak (1.5x), resist (0.5x), null (0x), absorb (heal)
## - Knockdown (DOWN) + "1 MORE!" Extra Turn on Weakness or Critical Hit
## - Baton Pass (`baton_pass`): pass 1 MORE to an ally with stacking +25% damage boost
## - All-Out Attack (`execute_all_out_attack`): massive party finisher when all enemies are DOWN

var one_more_actor_id: String = ""
var baton_pass_chain: int = 0
var baton_pass_bonus_by_actor: Dictionary = {} # actor_id -> float multiplier


func get_module_id() -> String:
	return "persona_one_more"


func on_battle_start(engine: Object, advantage_mode: int) -> void:
	one_more_actor_id = ""
	baton_pass_chain = 0
	baton_pass_bonus_by_actor.clear()
	for u in engine.allies + engine.enemies:
		u["down"] = false
		if not u.has("affinities"):
			u["affinities"] = {}
	# Field Ambush Advantage starts enemies slightly off-balance
	if advantage_mode == 1: # PLAYER_ADVANTAGE
		baton_pass_chain = 0


func select_next_actor(engine: Object) -> Dictionary:
	if not one_more_actor_id.is_empty():
		var u: Dictionary = engine.find_unit(one_more_actor_id)
		if not u.is_empty() and (u["stat_block"] as StatBlock).hp > 0.0:
			return u
		one_more_actor_id = ""
	return {}


func modify_damage(_engine: Object, ctx: Dictionary) -> void:
	var actor: Dictionary = ctx["actor"]
	var target: Dictionary = ctx["target"]
	var element := str(ctx.get("element", "physical"))
	var aff_map: Dictionary = target.get("affinities", {})
	var aff := str(aff_map.get(element, "normal"))
	ctx["affinity"] = aff

	match aff:
		"weak":
			ctx["mult"] = float(ctx["mult"]) * 1.5
			(ctx["log"] as Array).append("【WEAK!】命中 %s 的 %s 弱点！" % [target["name"], element])
		"resist":
			ctx["mult"] = float(ctx["mult"]) * 0.5
			(ctx["log"] as Array).append("【RESIST】%s 抵抗了 %s 攻击。" % [target["name"], element])
		"null":
			ctx["mult"] = 0.0
			(ctx["log"] as Array).append("【NULL】%s 无效化了 %s 攻击！" % [target["name"], element])
		"absorb":
			ctx["absorb"] = true
			(ctx["log"] as Array).append("【ABSORB】%s 吸收了 %s 能量！" % [target["name"], element])

	# Apply Baton Pass damage boost if active on actor
	var aid := str(actor["id"])
	if baton_pass_bonus_by_actor.has(aid):
		ctx["mult"] = float(ctx["mult"]) * float(baton_pass_bonus_by_actor[aid])


func on_action_resolved(_engine: Object, ctx: Dictionary) -> void:
	var actor: Dictionary = ctx["actor"]
	var target: Dictionary = ctx["target"]
	var aid := str(actor["id"])
	var aff := str(ctx.get("affinity", "normal"))
	var is_crit := bool(ctx.get("is_crit", false))

	# Clear consumed 1-More & Baton Pass bonus for this action
	if one_more_actor_id == aid:
		one_more_actor_id = ""
	baton_pass_bonus_by_actor.erase(aid)

	# Trigger DOWN + 1 MORE! if target wasn't already down and took weakness/crit damage
	if (aff == "weak" or is_crit) and not bool(target.get("down", false)) and (target["stat_block"] as StatBlock).hp > 0.0:
		target["down"] = true
		one_more_actor_id = aid
		(ctx["log"] as Array).append("★ %s 倒地(DOWN)！%s 获得【1 MORE!】额外行动！" % [target["name"], actor["name"]])


func has_one_more(actor_id: String = "") -> bool:
	if actor_id.is_empty():
		return not one_more_actor_id.is_empty()
	return one_more_actor_id == actor_id


## Passes an active 1 MORE! turn to another alive ally with stacking +25% damage bonus.
func baton_pass(engine: Object, from_id: String, to_id: String) -> bool:
	if one_more_actor_id != from_id or from_id == to_id:
		return false
	var target_ally: Dictionary = engine.find_unit(to_id)
	if target_ally.is_empty() or not bool(target_ally["is_ally"]) or (target_ally["stat_block"] as StatBlock).hp <= 0.0:
		return false
	baton_pass_chain += 1
	one_more_actor_id = to_id
	baton_pass_bonus_by_actor[to_id] = 1.0 + 0.25 * float(baton_pass_chain)
	(target_ally["stat_block"] as StatBlock).modify_mp(8.0)
	engine.battle_log.append("⚡ 换手(Baton Pass x%d)！行动权移交给 %s（伤害 +%.0f%%）！" % [
		baton_pass_chain, target_ally["name"], 25.0 * float(baton_pass_chain)
	])
	return true


func can_all_out_attack(engine: Object) -> bool:
	var alive_enemies: Array = engine.get_alive_enemies()
	if alive_enemies.is_empty():
		return false
	for en in alive_enemies:
		if not bool(en.get("down", false)):
			return false
	return true


## Massive party-wide finisher when every living enemy is DOWN!
func execute_all_out_attack(engine: Object) -> Array[String]:
	var lines: Array[String] = []
	if not can_all_out_attack(engine):
		return lines
	var alive_allies: Array = engine.get_alive_allies()
	var total_atk := 0.0
	for a in alive_allies:
		total_atk += (a["stat_block"] as StatBlock).get_stat("atk")
	var dmg := maxi(10, int(round(total_atk * 1.45)))
	lines.append("🔥 【总攻击 ALL-OUT ATTACK!】全员一齐突袭，对敌方全体造成 %d 点终结伤害！" % dmg)
	for en in engine.get_alive_enemies():
		(en["stat_block"] as StatBlock).modify_hp(-float(dmg))
		en["down"] = false
	one_more_actor_id = ""
	baton_pass_chain = 0
	engine.battle_log.append_array(lines)
	engine.check_and_emit_battle_end()
	return lines


func get_extra_commands(engine: Object, actor: Dictionary) -> Array[Dictionary]:
	var cmds: Array[Dictionary] = []
	if can_all_out_attack(engine) and bool(actor.get("is_ally", false)):
		cmds.append({"id": "all_out_attack", "label": "🔥 总攻击 (All-Out Attack)"})
	if has_one_more(str(actor.get("id", ""))):
		cmds.append({"id": "baton_pass", "label": "⚡ 换手 (Baton Pass)"})
	return cmds
