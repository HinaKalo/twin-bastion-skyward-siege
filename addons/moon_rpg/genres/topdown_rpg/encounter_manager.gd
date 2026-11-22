class_name EncounterManager
extends RefCounted
## Unified JRPG Encounter Director (Visible Field Enemies + Random Step Zones).
## Tracks random-encounter danger gauge (0.0..1.0), repel safe steps (驱魔香),
## and weighted troop table selection.

signal encounter_triggered(troop_specs: Array, advantage_mode: int, source: Node)
signal danger_changed(danger_ratio: float)

var danger: float = 0.0 # 0.0 = safe (green), 0.5 = warning (yellow), 1.0 = triggers battle (red)
var repel_steps: float = 0.0 # remaining pixels of repel immunity
var step_threshold: float = 240.0 # pixels walked in normal danger zone before battle triggers


func add_repel_steps(pixels: float) -> void:
	repel_steps = maxf(0.0, repel_steps + pixels)


func reset_danger() -> void:
	danger = 0.0
	danger_changed.emit(danger)


## Accumulates walking distance inside a random encounter zone. Returns true if a battle triggers.
func accumulate_steps(distance_px: float, rate_multiplier: float, troop_table: Array, source: Node = null) -> bool:
	if distance_px <= 0.0 or troop_table.is_empty():
		return false
	var effective_dist := distance_px
	if repel_steps > 0.0:
		var absorbed := minf(repel_steps, effective_dist)
		repel_steps -= absorbed
		effective_dist -= absorbed
		if effective_dist <= 0.0:
			return false
	danger = clampf(danger + (effective_dist / maxf(32.0, step_threshold)) * rate_multiplier, 0.0, 1.0)
	danger_changed.emit(danger)
	if danger >= 1.0:
		danger = 0.0
		danger_changed.emit(danger)
		var troop := roll_troop(troop_table)
		encounter_triggered.emit(troop, TurnBattleEngine.EncounterAdvantage.NORMAL, source)
		return true
	return false


## Triggers an immediate encounter from a visible FieldEnemy2D (Normal / Advantage / Ambush).
func trigger_field_encounter(troop_specs: Array, advantage_mode: int, source: Node = null) -> void:
	danger = 0.0
	danger_changed.emit(danger)
	encounter_triggered.emit(troop_specs, advantage_mode, source)


## Weighted random pick from troop_table: [{ "weight": 3, "troop": [enemy_spec, ...] }]
func roll_troop(troop_table: Array) -> Array:
	var total_weight := 0.0
	for entry in troop_table:
		total_weight += maxf(0.1, float(entry.get("weight", 1.0)))
	var r := randf() * total_weight
	var acc := 0.0
	for entry in troop_table:
		acc += maxf(0.1, float(entry.get("weight", 1.0)))
		if r <= acc:
			return (entry.get("troop", []) as Array).duplicate(true)
	return (troop_table[0].get("troop", []) as Array).duplicate(true) if not troop_table.is_empty() else []
