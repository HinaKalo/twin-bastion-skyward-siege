class_name TurnBattleEngine
extends RefCounted
## Composable Turn-Based JRPG Battle Pipeline (Brick / Plugin Architecture).
##
## Works out of the box as a classic RPG Maker MZ turn-based engine, and lets developers
## snap in BattleModule bricks in any combination:
##   battle.add_module(PersonaOneMoreModule.new()) # Weak/Down/1-More/Baton Pass/All-Out Attack
##   battle.add_module(TrailsATModule.new())       # AT Delay Bar/Turn Bonus/Delay Push/S-Break

enum BattleState { IDLE, SELECT_COMMAND, EXECUTING, VICTORY, DEFEAT, ESCAPED }
enum ActionType { ATTACK, SKILL, DEFEND, ITEM, ESCAPE }
enum EncounterAdvantage { NORMAL, PLAYER_ADVANTAGE, ENEMY_AMBUSH }

signal battle_started(allies: Array, enemies: Array)
signal turn_resolved(log_lines: Array[String])
signal battle_ended(result: int)

var state: int = BattleState.IDLE
var advantage: int = EncounterAdvantage.NORMAL
var turn_number: int = 0
var allies: Array[Dictionary] = []
var enemies: Array[Dictionary] = []
var queued_actions: Array[Dictionary] = []
var battle_log: Array[String] = []
var _modules: Array[BattleModule] = []


# =============================================================================
# Composable BattleModule Plugin API
# =============================================================================

func add_module(mod: BattleModule) -> void:
	if mod == null:
		return
	remove_module(mod.get_module_id())
	_modules.append(mod)


func remove_module(module_id: String) -> void:
	for i in range(_modules.size() - 1, -1, -1):
		if _modules[i].get_module_id() == module_id:
			_modules.remove_at(i)


func get_module(module_id: String) -> BattleModule:
	for m in _modules:
		if m.get_module_id() == module_id:
			return m
	return null


func get_extra_commands(actor_id: String) -> Array[Dictionary]:
	var actor := find_unit(actor_id)
	var out: Array[Dictionary] = []
	for m in _modules:
		out.append_array(m.get_extra_commands(self, actor))
	return out


# =============================================================================
# Battle Lifecycle
# =============================================================================

func start_battle(party_members: Array, enemy_specs: Array, encounter_advantage: int = EncounterAdvantage.NORMAL) -> void:
	allies.clear()
	enemies.clear()
	queued_actions.clear()
	battle_log.clear()
	turn_number = 1
	advantage = encounter_advantage

	for m in party_members:
		allies.append({
			"id": str(m["id"]),
			"name": str(m["name"]),
			"stat_block": m["stat_block"],
			"affinities": m.get("affinities", {}).duplicate(true),
			"cp": float(m.get("cp", 50.0)),
			"is_ally": true,
			"defending": false,
		})
	for e in enemy_specs:
		var sb: StatBlock = e["stat_block"] if e.has("stat_block") else StatBlock.new(e.get("stats", {}))
		enemies.append({
			"id": str(e["id"]),
			"name": str(e.get("name", e["id"])),
			"stat_block": sb,
			"affinities": e.get("affinities", {}).duplicate(true),
			"cp": float(e.get("cp", 0.0)),
			"is_ally": false,
			"defending": false,
		})

	for mod in _modules:
		mod.on_battle_start(self, advantage)

	state = BattleState.SELECT_COMMAND
	battle_started.emit(allies, enemies)


func get_next_actor() -> Dictionary:
	for mod in _modules:
		var picked := mod.select_next_actor(self)
		if not picked.is_empty():
			return picked
	var alive := get_alive_allies()
	return alive[0] if not alive.is_empty() else {}


## Executes one individual unit's action immediately (used by AT timeline, 1 MORE!, and S-Break).
func execute_single_action(actor_id: String, spec: Dictionary) -> Array[String]:
	if state != BattleState.SELECT_COMMAND and state != BattleState.EXECUTING:
		return []
	var actor := find_unit(actor_id)
	if actor.is_empty() or (actor["stat_block"] as StatBlock).hp <= 0.0:
		return []

	var lines: Array[String] = []
	actor["defending"] = false
	var act_type := int(spec.get("type", ActionType.ATTACK))

	match act_type:
		ActionType.DEFEND:
			actor["defending"] = true
			lines.append("%s 进入防御架势！" % actor["name"])
		ActionType.ESCAPE:
			state = BattleState.ESCAPED
			lines.append("%s 成功脱离战斗！" % actor["name"])
		ActionType.ITEM:
			var heal := float(spec.get("heal_amount", 40.0))
			var target := find_unit(str(spec.get("target_id", "")))
			if target.is_empty():
				target = actor
			var actual := (target["stat_block"] as StatBlock).modify_hp(heal)
			lines.append("%s 恢复了 %d 点生命！" % [target["name"], int(round(actual))])
		ActionType.ATTACK, ActionType.SKILL:
			var target := _resolve_target(actor, str(spec.get("target_id", "")))
			if not target.is_empty():
				var ctx := {
					"actor": actor,
					"target": target,
					"element": str(spec.get("element", "physical")),
					"mult": float(spec.get("skill_mult", 1.0)),
					"mp_cost": float(spec.get("mp_cost", 0.0)),
					"delay_push": float(spec.get("delay_push", 0.0)),
					"is_crit": bool(spec.get("is_crit", false)),
					"affinity": "normal",
					"absorb": false,
					"log": lines,
				}
				for mod in _modules:
					mod.modify_damage(self, ctx)

				var asb: StatBlock = actor["stat_block"]
				var mp_cost := float(ctx["mp_cost"])
				if mp_cost > 0.0 and asb.mp < mp_cost:
					lines.append("%s 魔力不足！" % actor["name"])
				else:
					if mp_cost > 0.0:
						asb.modify_mp(-mp_cost)
					var tsb: StatBlock = target["stat_block"]
					var mult := float(ctx["mult"])
					if mult <= 0.0:
						lines.append("%s 未受到伤害！" % target["name"])
					else:
						var dmg := _compute_damage(asb, tsb, mult, bool(target["defending"]))
						if bool(ctx["absorb"]):
							tsb.modify_hp(float(dmg))
							lines.append("%s 吸收恢复了 %d HP！" % [target["name"], dmg])
						else:
							tsb.modify_hp(-float(dmg))
							lines.append("%s 攻击 %s，造成 %d 点伤害！" % [actor["name"], target["name"], dmg])
					for mod in _modules:
						mod.on_action_resolved(self, ctx)

	for mod in _modules:
		mod.on_turn_end(self, actor)

	battle_log.append_array(lines)
	turn_resolved.emit(lines)
	check_and_emit_battle_end()
	return lines


## Classic whole-round queueing API (100% compatible with RPG Maker MZ round flow).
func queue_action(actor_id: String, action_type: int, target_id: String = "", skill_mult: float = 1.0, mp_cost: float = 0.0, heal_amount: float = 0.0, element: String = "physical", delay_push: float = 0.0) -> void:
	queued_actions.append({
		"actor_id": actor_id,
		"type": action_type,
		"target_id": target_id,
		"skill_mult": skill_mult,
		"mp_cost": mp_cost,
		"heal_amount": heal_amount,
		"element": element,
		"delay_push": delay_push,
	})


func execute_round(auto_enemy_ai: bool = true) -> Array[String]:
	if state != BattleState.SELECT_COMMAND:
		return []
	state = BattleState.EXECUTING
	var round_log: Array[String] = []

	if auto_enemy_ai:
		var alive_allies := get_alive_allies()
		for en in get_alive_enemies():
			if not alive_allies.is_empty():
				var pick: Dictionary = alive_allies[randi() % alive_allies.size()]
				queue_action(str(en["id"]), ActionType.ATTACK, str(pick["id"]), 1.0)

	queued_actions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["type"]) == ActionType.DEFEND and int(b["type"]) != ActionType.DEFEND:
			return true
		if int(b["type"]) == ActionType.DEFEND and int(a["type"]) != ActionType.DEFEND:
			return false
		var ua := find_unit(str(a["actor_id"]))
		var ub := find_unit(str(b["actor_id"]))
		var sp_a := (ua["stat_block"] as StatBlock).get_stat("move_spd") if not ua.is_empty() else 0.0
		var sp_b := (ub["stat_block"] as StatBlock).get_stat("move_spd") if not ub.is_empty() else 0.0
		return sp_a > sp_b
	)

	for act in queued_actions:
		if state != BattleState.EXECUTING:
			break
		var lines := execute_single_action(str(act["actor_id"]), act)
		round_log.append_array(lines)

	queued_actions.clear()
	if state == BattleState.EXECUTING:
		turn_number += 1
		state = BattleState.SELECT_COMMAND
	return round_log


func _compute_damage(attacker: StatBlock, defender: StatBlock, mult: float, defending: bool) -> int:
	var raw := maxf(1.0, attacker.get_stat("atk") * mult - defender.get_stat("def") * 0.5)
	if defending:
		raw *= 0.5
	return maxi(1, int(round(raw)))


func _resolve_target(actor: Dictionary, target_id: String) -> Dictionary:
	var t := find_unit(target_id)
	if not t.is_empty() and (t["stat_block"] as StatBlock).hp > 0.0:
		return t
	var pool := get_alive_enemies() if bool(actor["is_ally"]) else get_alive_allies()
	return pool[0] if not pool.is_empty() else {}


func find_unit(uid: String) -> Dictionary:
	for u in allies + enemies:
		if str(u["id"]) == uid:
			return u
	return {}


func get_alive_allies() -> Array[Dictionary]:
	return _filter_alive(allies)


func get_alive_enemies() -> Array[Dictionary]:
	return _filter_alive(enemies)


func _filter_alive(list: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for u in list:
		if (u["stat_block"] as StatBlock).hp > 0.0:
			out.append(u)
	return out


func check_and_emit_battle_end() -> bool:
	if state == BattleState.ESCAPED:
		battle_ended.emit(state)
		return true
	if get_alive_enemies().is_empty():
		state = BattleState.VICTORY
		battle_ended.emit(state)
		return true
	if get_alive_allies().is_empty():
		state = BattleState.DEFEAT
		battle_ended.emit(state)
		return true
	return false
