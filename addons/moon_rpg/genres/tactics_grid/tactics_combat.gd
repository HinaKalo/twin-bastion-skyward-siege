class_name TacticsCombat
extends RefCounted
## Studio-Grade SRPG Combat Forecast & Resolution Engine
## (Fire Emblem × Final Fantasy Tactics × Triangle Strategy × Into the Breach).
##
## Features:
## - Configurable Weapon Triangle (sword > axe > lance > sword)
## - Height / Elevation damage modifier (+12% per high level, -10% low)
## - Backstab / Flank facing bonus (+15% dmg, +20% crit)
## - Triangle Strategy Pincer / Flank Follow-Up Attack (ally standing directly behind target!)
## - Fire Emblem Speed-based Double Attack & Range-checked Counterattack
## - AoE Skills (Diamond / Cross / Line), Healing Skills, and Knockback + Wall/Unit Collision Bonus!

var weapon_triangle: Dictionary = {
	"sword": "axe",
	"axe": "lance",
	"lance": "sword",
}

var double_attack_speed_gap: float = 4.0
var collision_bonus_damage: float = 10.0
var _rng := RandomNumberGenerator.new()


func _init(seed_val: int = 0) -> void:
	if seed_val != 0:
		_rng.seed = seed_val
	else:
		_rng.randomize()


func set_seed(seed_val: int) -> void:
	_rng.seed = seed_val


## Returns +1 if `atk_weapon` beats `def_weapon`, -1 if disadvantaged, 0 if neutral.
func get_weapon_advantage(atk_weapon: String, def_weapon: String) -> int:
	if str(weapon_triangle.get(atk_weapon, "")) == def_weapon:
		return 1
	if str(weapon_triangle.get(def_weapon, "")) == atk_weapon:
		return -1
	return 0


func is_backstab(atk_cell: Vector2i, def_cell: Vector2i, defender_facing: Vector2i) -> bool:
	if defender_facing == Vector2i.ZERO:
		return false
	var atk_to_def := def_cell - atk_cell
	var dir := Vector2i(signi(atk_to_def.x), 0) if absi(atk_to_def.x) >= absi(atk_to_def.y) else Vector2i(0, signi(atk_to_def.y))
	# Attacker is striking in the same direction defender is facing -> hitting from behind!
	return dir == defender_facing


## Finds an allied unit standing directly on the opposite side of `def_cell` for a Pincer Follow-Up!
func find_flank_ally(attacker: TacticsUnit, atk_cell: Vector2i, def_cell: Vector2i, board: GridBoard, all_units: Dictionary) -> TacticsUnit:
	var dist := board.distance(atk_cell, def_cell)
	if dist != 1:
		return null
	var step := def_cell - atk_cell
	var opposite_cell := def_cell + step
	var occ := board.get_unit_at(opposite_cell)
	if occ.is_empty() or occ == attacker.unit_id or not all_units.has(occ):
		return null
	var ally: TacticsUnit = all_units[occ]
	if ally.is_alive() and ally.faction == attacker.faction and ally.attack_min_range <= 1:
		return ally
	return null


func _calc_single_strike(
	attacker: TacticsUnit,
	defender: TacticsUnit,
	atk_cell: Vector2i,
	def_cell: Vector2i,
	board: GridBoard,
	skill: Dictionary = {}
) -> Dictionary:
	var w_type := str(skill.get("weapon_type", attacker.weapon_type))
	var power_mult := float(skill.get("power_mult", 1.0))
	var w_adv := get_weapon_advantage(w_type, defender.weapon_type)
	var height_diff := board.get_elevation(atk_cell) - board.get_elevation(def_cell)
	var back := is_backstab(atk_cell, def_cell, defender.facing)
	var def_cell_data := board.get_cell(def_cell)
	var terr_def := float(def_cell_data.get("def_bonus", 0))
	var terr_avo := float(def_cell_data.get("avoid_bonus", 0))

	var raw_atk := attacker.stat_block.get_stat("atk") * power_mult
	var raw_def := defender.stat_block.get_stat("def") + terr_def
	# Magic ignores 40% physical defense
	if w_type == "magic":
		raw_def *= 0.6

	var base_dmg := maxf(2.0, raw_atk - raw_def * 0.75)
	var mult := 1.0
	if w_adv > 0:
		mult *= 1.20
	elif w_adv < 0:
		mult *= 0.82
	if height_diff > 0:
		mult *= 1.0 + 0.12 * float(mini(3, height_diff))
	elif height_diff < 0:
		mult *= 0.90
	if back:
		mult *= 1.15

	var dmg := maxf(1.0, roundf(base_dmg * mult))
	var hit := clampf(0.88 + float(w_adv) * 0.12 + (attacker.get_speed() - defender.get_speed()) * 0.01 - terr_avo * 0.01 + (0.08 if back else 0.0), 0.25, 1.0)
	var crit := clampf(attacker.stat_block.get_stat("crit_rate") + (0.20 if back else 0.0) + (0.05 if w_adv > 0 else 0.0), 0.0, 0.95)
	return {
		"damage": dmg,
		"hit_chance": hit,
		"crit_chance": crit,
		"weapon_advantage": w_adv,
		"height_diff": height_diff,
		"is_backstab": back,
	}


## Produces an exact Fire Emblem / Triangle Strategy Combat Forecast before the player commits!
func forecast(
	attacker: TacticsUnit,
	defender: TacticsUnit,
	atk_cell: Vector2i,
	def_cell: Vector2i,
	board: GridBoard,
	all_units: Dictionary,
	skill: Dictionary = {}
) -> Dictionary:
	var strike := _calc_single_strike(attacker, defender, atk_cell, def_cell, board, skill)
	var dist := board.distance(atk_cell, def_cell)
	var is_aoe := str(skill.get("aoe_shape", "SINGLE")).to_upper() != "SINGLE"
	var double_atk := (not is_aoe) and skill.is_empty() and (attacker.get_speed() - defender.get_speed() >= double_attack_speed_gap)
	var can_counter := (not is_aoe) and defender.is_alive() and dist >= defender.attack_min_range and dist <= defender.attack_max_range
	var counter_dmg := 0.0
	var counter_hit := 0.0
	if can_counter:
		var c_strike := _calc_single_strike(defender, attacker, def_cell, atk_cell, board, {})
		counter_dmg = float(c_strike["damage"])
		counter_hit = float(c_strike["hit_chance"])

	var flank_ally := find_flank_ally(attacker, atk_cell, def_cell, board, all_units) if (not is_aoe and skill.is_empty()) else null
	var flank_dmg := 0.0
	if flank_ally != null:
		var f_cell := board.get_unit_cell(flank_ally.unit_id)
		var f_strike := _calc_single_strike(flank_ally, defender, f_cell, def_cell, board, {"power_mult": 0.6})
		flank_dmg = float(f_strike["damage"])

	return {
		"damage": float(strike["damage"]),
		"hit_chance": float(strike["hit_chance"]),
		"crit_chance": float(strike["crit_chance"]),
		"weapon_advantage": int(strike["weapon_advantage"]),
		"height_diff": int(strike["height_diff"]),
		"is_backstab": bool(strike["is_backstab"]),
		"double_attack": double_atk,
		"can_counter": can_counter,
		"counter_damage": counter_dmg,
		"counter_hit": counter_hit,
		"flank_ally_id": flank_ally.unit_id if flank_ally != null else "",
		"flank_ally_name": flank_ally.display_name if flank_ally != null else "",
		"flank_damage": flank_dmg,
		"knockback": int(skill.get("knockback", 0)),
	}


## Executes a complete tactical combat exchange and returns ordered event records for animation/VFX.
func resolve_combat(
	attacker: TacticsUnit,
	defender: TacticsUnit,
	board: GridBoard,
	all_units: Dictionary,
	skill: Dictionary = {},
	deterministic_hit: bool = false
) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var atk_cell := board.get_unit_cell(attacker.unit_id)
	var def_cell := board.get_unit_cell(defender.unit_id)
	attacker.face_toward(atk_cell, def_cell)

	var mp_cost := float(skill.get("mp_cost", 0.0))
	if mp_cost > 0.0:
		attacker.stat_block.spend_mp(mp_cost)

	var fc := forecast(attacker, defender, atk_cell, def_cell, board, all_units, skill)

	# 1. Attacker Primary Strike
	events.append(_roll_and_apply(attacker, defender, float(fc["damage"]), float(fc["hit_chance"]), float(fc["crit_chance"]), "strike", deterministic_hit))

	# 1b. Knockback + Wall/Unit Collision Bonus (Into the Breach / Triangle Strategy!)
	var kb := int(fc["knockback"])
	if kb > 0 and defender.is_alive():
		var kb_ev := _apply_knockback(attacker, defender, atk_cell, def_cell, kb, board, all_units)
		if not kb_ev.is_empty():
			events.append(kb_ev)
			def_cell = board.get_unit_cell(defender.unit_id)

	# 2. Pincer / Flank Follow-Up Attack by Ally behind defender
	if defender.is_alive() and not str(fc["flank_ally_id"]).is_empty():
		var ally: TacticsUnit = all_units.get(str(fc["flank_ally_id"]), null)
		if ally != null and ally.is_alive():
			events.append(_roll_and_apply(ally, defender, float(fc["flank_damage"]), 0.95, 0.10, "flank", deterministic_hit))

	# 3. Defender Counterattack (if still alive and in range)
	if defender.is_alive() and bool(fc["can_counter"]):
		defender.face_toward(def_cell, atk_cell)
		events.append(_roll_and_apply(defender, attacker, float(fc["counter_damage"]), float(fc["counter_hit"]), 0.06, "counter", deterministic_hit))

	# 4. Attacker Speed Double-Attack
	if attacker.is_alive() and defender.is_alive() and bool(fc["double_attack"]):
		events.append(_roll_and_apply(attacker, defender, float(fc["damage"]), float(fc["hit_chance"]), float(fc["crit_chance"]), "double", deterministic_hit))

	# Remove defeated units from board
	if not defender.is_alive():
		board.remove_unit(defender.unit_id)
	if not attacker.is_alive():
		board.remove_unit(attacker.unit_id)
	return events


## Executes an AoE damage or healing skill across all affected cells.
func resolve_aoe_skill(
	caster: TacticsUnit,
	target_cell: Vector2i,
	board: GridBoard,
	all_units: Dictionary,
	skill: Dictionary,
	deterministic_hit: bool = false
) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var origin := board.get_unit_cell(caster.unit_id)
	caster.face_toward(origin, target_cell)
	var mp_cost := float(skill.get("mp_cost", 0.0))
	if mp_cost > 0.0:
		caster.stat_block.spend_mp(mp_cost)

	var shape := str(skill.get("aoe_shape", "SINGLE"))
	var radius := int(skill.get("aoe_radius", 1))
	var cells := GridPathfinder.compute_aoe_cells(board, origin, target_cell, shape, radius)
	var is_heal := bool(skill.get("target_allies", false))

	for c in cells:
		var uid := board.get_unit_at(c)
		if uid.is_empty() or not all_units.has(uid):
			continue
		var unit: TacticsUnit = all_units[uid]
		if not unit.is_alive():
			continue
		if is_heal and unit.faction == caster.faction:
			var amt := float(skill.get("heal_amount", 35.0))
			var before := unit.stat_block.hp
			unit.stat_block.heal(amt)
			var healed := unit.stat_block.hp - before
			events.append({"kind": "heal", "actor": caster.unit_id, "target": unit.unit_id, "amount": healed, "cell": c})
		elif not is_heal and unit.faction != caster.faction:
			var s := _calc_single_strike(caster, unit, origin, c, board, skill)
			events.append(_roll_and_apply(caster, unit, float(s["damage"]), float(s["hit_chance"]), float(s["crit_chance"]), "skill", deterministic_hit))
			if not unit.is_alive():
				board.remove_unit(unit.unit_id)
	return events


func _roll_and_apply(actor: TacticsUnit, target: TacticsUnit, dmg: float, hit_chance: float, crit_chance: float, kind: String, deterministic_hit: bool) -> Dictionary:
	var hit := true if deterministic_hit else (_rng.randf() <= hit_chance)
	if not hit:
		return {"kind": kind, "actor": actor.unit_id, "target": target.unit_id, "hit": false, "crit": false, "damage": 0.0, "killed": false}
	var crit := false if deterministic_hit else (_rng.randf() <= crit_chance)
	var final_dmg := roundf(dmg * (actor.stat_block.get_stat("crit_dmg") if crit else 1.0))
	target.stat_block.take_damage(final_dmg)
	return {
		"kind": kind,
		"actor": actor.unit_id,
		"target": target.unit_id,
		"hit": true,
		"crit": crit,
		"damage": final_dmg,
		"killed": not target.is_alive(),
	}


func _apply_knockback(attacker: TacticsUnit, defender: TacticsUnit, atk_cell: Vector2i, def_cell: Vector2i, dist: int, board: GridBoard, all_units: Dictionary) -> Dictionary:
	var d := def_cell - atk_cell
	var dir := Vector2i(signi(d.x), 0) if absi(d.x) >= absi(d.y) else Vector2i(0, signi(d.y))
	if dir == Vector2i.ZERO:
		return {}
	var cur := def_cell
	for _step in range(dist):
		var nxt := cur + dir
		if not board.in_bounds(nxt) or not bool(board.get_cell(nxt).get("passable", true)):
			# Slammed into wall / mountain!
			defender.stat_block.take_damage(collision_bonus_damage)
			return {"kind": "knockback_crash", "actor": attacker.unit_id, "target": defender.unit_id, "to": cur, "crash_damage": collision_bonus_damage, "killed": not defender.is_alive()}
		var occ := board.get_unit_at(nxt)
		if not occ.is_empty() and all_units.has(occ):
			# Slammed into another unit -> BOTH take collision damage!
			defender.stat_block.take_damage(collision_bonus_damage)
			(all_units[occ] as TacticsUnit).stat_block.take_damage(collision_bonus_damage)
			if not (all_units[occ] as TacticsUnit).is_alive():
				board.remove_unit(occ)
			return {"kind": "knockback_crash", "actor": attacker.unit_id, "target": defender.unit_id, "bumped_unit": occ, "to": cur, "crash_damage": collision_bonus_damage, "killed": not defender.is_alive()}
		board.move_unit(defender.unit_id, nxt)
		cur = nxt
	return {"kind": "knockback", "actor": attacker.unit_id, "target": defender.unit_id, "to": cur, "crash_damage": 0.0, "killed": false}
