class_name TacticsObjective
extends RefCounted
## Standard SRPG Victory & Defeat Objective Evaluator.
## Supports: ROUT (defeat all enemies), DEFEAT_BOSS, SEIZE (leader reaches seize cell),
## and SURVIVE_TURNS (hold out for N turns).

enum GoalType { ROUT, DEFEAT_BOSS, SEIZE, SURVIVE_TURNS }

var goal_type: int = GoalType.ROUT
var boss_unit_id: String = ""
var seize_cell: Vector2i = Vector2i(-1, -1)
var target_turns: int = 6
var max_turns: int = 0 # 0 = unlimited
var require_leader_alive: bool = true


func setup_rout(turn_limit: int = 0) -> void:
	goal_type = GoalType.ROUT
	max_turns = turn_limit


func setup_defeat_boss(boss_id: String, turn_limit: int = 0) -> void:
	goal_type = GoalType.DEFEAT_BOSS
	boss_unit_id = boss_id
	max_turns = turn_limit


func setup_seize(cell: Vector2i, turn_limit: int = 0) -> void:
	goal_type = GoalType.SEIZE
	seize_cell = cell
	max_turns = turn_limit


func setup_survive(turns: int) -> void:
	goal_type = GoalType.SURVIVE_TURNS
	target_turns = maxi(1, turns)


func get_goal_text() -> String:
	match goal_type:
		GoalType.ROUT:
			return "胜利条件：全灭所有敌军"
		GoalType.DEFEAT_BOSS:
			return "胜利条件：击破敌军主将"
		GoalType.SEIZE:
			return "胜利条件：主角占领目标据点"
		GoalType.SURVIVE_TURNS:
			return "胜利条件：坚守 %d 回合" % target_turns
	return ""


## Returns "ongoing" | "victory" | "defeat"
func evaluate(board: GridBoard, all_units: Dictionary, turn_number: int) -> String:
	var alive_players := 0
	var alive_enemies := 0
	var leader_alive := false
	var has_leader := false
	var leader_cell := Vector2i(-1, -1)

	for u in all_units.values():
		var unit := u as TacticsUnit
		if unit.faction == "player":
			if unit.is_leader:
				has_leader = true
				if unit.is_alive():
					leader_alive = true
					leader_cell = board.get_unit_cell(unit.unit_id)
			if unit.is_alive():
				alive_players += 1
		elif unit.faction == "enemy" and unit.is_alive():
			alive_enemies += 1

	# Defeat checks first
	if alive_players == 0:
		return "defeat"
	if require_leader_alive and has_leader and not leader_alive:
		return "defeat"
	if max_turns > 0 and turn_number > max_turns:
		return "defeat"

	# Victory checks
	match goal_type:
		GoalType.ROUT:
			if alive_enemies == 0:
				return "victory"
		GoalType.DEFEAT_BOSS:
			if not all_units.has(boss_unit_id) or not (all_units[boss_unit_id] as TacticsUnit).is_alive():
				return "victory"
		GoalType.SEIZE:
			if leader_alive and leader_cell == seize_cell:
				return "victory"
		GoalType.SURVIVE_TURNS:
			if turn_number > target_turns:
				return "victory"
	return "ongoing"
