extends Node
## Dynamic Difficulty Adjustment (DDA) & AI Director for MoonRPG Engine.
##
## Combines explicit difficulty presets (`story` / `normal` / `hard` / `nightmare`)
## with continuous adaptive `pressure` (0.0 .. 1.0) driven by player combat telemetry.
##
## Outputs three scaling profiles automatically consumed by EnemyController:
##   1. Stat multipliers    (enemy_hp_mult, enemy_atk_mult, enemy_def_mult)
##   2. Behavior multipliers(aggro_range_mult, windup_time_mult, attack_cooldown_mult, move_speed_mult)
##   3. Loot/Resource mults (drop_chance_mult, healing_drop_mult, gold_mult, xp_mult)

const PRESETS := {
	"story": {
		"hp": 0.72, "atk": 0.65, "def": 0.80,
		"aggro": 0.85, "windup": 1.25, "cooldown": 1.30, "speed": 0.90,
		"drop": 1.25, "heal_drop": 1.60, "gold": 1.20, "xp": 1.15,
		"min_pressure": 0.10, "max_pressure": 0.55,
	},
	"normal": {
		"hp": 1.00, "atk": 1.00, "def": 1.00,
		"aggro": 1.00, "windup": 1.00, "cooldown": 1.00, "speed": 1.00,
		"drop": 1.00, "heal_drop": 1.00, "gold": 1.00, "xp": 1.00,
		"min_pressure": 0.20, "max_pressure": 0.85,
	},
	"hard": {
		"hp": 1.30, "atk": 1.28, "def": 1.15,
		"aggro": 1.15, "windup": 0.88, "cooldown": 0.84, "speed": 1.10,
		"drop": 1.15, "heal_drop": 0.85, "gold": 1.25, "xp": 1.20,
		"min_pressure": 0.40, "max_pressure": 0.95,
	},
	"nightmare": {
		"hp": 1.65, "atk": 1.55, "def": 1.30,
		"aggro": 1.25, "windup": 0.78, "cooldown": 0.72, "speed": 1.18,
		"drop": 1.30, "heal_drop": 0.70, "gold": 1.50, "xp": 1.35,
		"min_pressure": 0.65, "max_pressure": 1.00,
	},
}

var preset: String = "normal"
var dynamic_enabled: bool = true
var pressure: float = 0.50 # 0.0 = easiest adaptive relief, 0.5 = neutral, 1.0 = peak challenge

# Rolling telemetry counters
var kill_streak: int = 0
var death_count: int = 0
var parry_count: int = 0
var _player_ref: Actor2D = null


func _ready() -> void:
	if EventBus:
		EventBus.player_registered.connect(_on_player_registered)
		EventBus.actor_damaged.connect(_on_actor_damaged)
		EventBus.actor_parried.connect(_on_actor_parried)
		EventBus.actor_died.connect(_on_actor_died)
		EventBus.enemy_killed.connect(_on_enemy_killed)


func set_preset(preset_name: String) -> bool:
	if not PRESETS.has(preset_name):
		return false
	preset = preset_name
	var p: Dictionary = PRESETS[preset]
	pressure = clampf(pressure, float(p["min_pressure"]), float(p["max_pressure"]))
	_emit_changed()
	return true


func set_dynamic_enabled(enabled: bool) -> void:
	dynamic_enabled = enabled
	if not enabled:
		pressure = 0.50
	_emit_changed()


func set_pressure(value: float) -> void:
	var p: Dictionary = PRESETS.get(preset, PRESETS["normal"])
	pressure = clampf(value, float(p["min_pressure"]), float(p["max_pressure"]))
	_emit_changed()


func nudge_pressure(delta: float) -> void:
	if not dynamic_enabled:
		return
	set_pressure(pressure + delta)


func reset_telemetry() -> void:
	kill_streak = 0
	death_count = 0
	parry_count = 0
	pressure = 0.50
	_emit_changed()


## Returns enemy stat scaling multipliers based on preset + adaptive pressure.
func get_stat_multipliers() -> Dictionary:
	var p: Dictionary = PRESETS.get(preset, PRESETS["normal"])
	var offset := (pressure - 0.5) if dynamic_enabled else 0.0 # -0.5 .. +0.5
	return {
		"enemy_hp_mult": maxf(0.4, float(p["hp"]) * (1.0 + offset * 0.45)),
		"enemy_atk_mult": maxf(0.4, float(p["atk"]) * (1.0 + offset * 0.40)),
		"enemy_def_mult": maxf(0.5, float(p["def"]) * (1.0 + offset * 0.25)),
	}


## Returns enemy AI behavior scaling multipliers (aggro, windup telegraph, cooldown, chase speed).
func get_behavior_multipliers() -> Dictionary:
	var p: Dictionary = PRESETS.get(preset, PRESETS["normal"])
	var offset := (pressure - 0.5) if dynamic_enabled else 0.0
	return {
		"aggro_range_mult": clampf(float(p["aggro"]) * (1.0 + offset * 0.25), 0.70, 1.50),
		"windup_time_mult": clampf(float(p["windup"]) * (1.0 - offset * 0.28), 0.65, 1.50),
		"attack_cooldown_mult": clampf(float(p["cooldown"]) * (1.0 - offset * 0.30), 0.60, 1.60),
		"move_speed_mult": clampf(float(p["speed"]) * (1.0 + offset * 0.18), 0.75, 1.35),
	}


## Returns resource & loot drop rate multipliers.
## Automatically boosts healing item drop rates when the player is at low HP!
func get_loot_multipliers() -> Dictionary:
	var p: Dictionary = PRESETS.get(preset, PRESETS["normal"])
	var offset := (pressure - 0.5) if dynamic_enabled else 0.0
	var hp_ratio := _get_player_hp_ratio()
	var low_hp_relief := 1.0 + (1.0 - clampf(hp_ratio / 0.45, 0.0, 1.0)) * 0.85 if hp_ratio < 0.45 else 1.0
	var struggle_boost := 1.0 + maxf(0.0, 0.5 - pressure) * 0.60 if dynamic_enabled else 1.0
	return {
		"drop_chance_mult": clampf(float(p["drop"]) * struggle_boost, 0.5, 2.5),
		"healing_drop_mult": clampf(float(p["heal_drop"]) * low_hp_relief * struggle_boost, 0.5, 3.0),
		"gold_mult": maxf(0.5, float(p["gold"]) * (1.0 + maxf(0.0, offset) * 0.35)),
		"xp_mult": maxf(0.5, float(p["xp"]) * (1.0 + maxf(0.0, offset) * 0.25)),
	}


func get_full_profile() -> Dictionary:
	return {
		"preset": preset,
		"dynamic_enabled": dynamic_enabled,
		"pressure": snappedf(pressure, 0.01),
		"stats": get_stat_multipliers(),
		"behavior": get_behavior_multipliers(),
		"loot": get_loot_multipliers(),
	}


func _get_player_hp_ratio() -> float:
	if is_instance_valid(_player_ref) and _player_ref.stat_block != null:
		return clampf(_player_ref.stat_block.hp / maxf(1.0, _player_ref.stat_block.get_stat("max_hp")), 0.0, 1.0)
	return 1.0


func _on_player_registered(player: Node) -> void:
	if player is Actor2D:
		_player_ref = player as Actor2D


func _on_actor_damaged(target: Node, _attacker: Node, amount: int, _is_crit: bool, _pos: Vector2) -> void:
	if not dynamic_enabled or target == null or not target.is_in_group("player"):
		return
	kill_streak = 0
	var max_hp := 100.0
	if target is Actor2D and (target as Actor2D).stat_block != null:
		max_hp = maxf(1.0, (target as Actor2D).stat_block.get_stat("max_hp"))
	var frac := float(amount) / max_hp
	nudge_pressure(-clampf(frac * 0.14, 0.015, 0.08))


func _on_actor_parried(defender: Node, _attacker: Node, _pos: Vector2) -> void:
	if not dynamic_enabled or defender == null or not defender.is_in_group("player"):
		return
	parry_count += 1
	nudge_pressure(0.04)


func _on_actor_died(actor: Node, _killer: Node) -> void:
	if not dynamic_enabled or actor == null or not actor.is_in_group("player"):
		return
	death_count += 1
	kill_streak = 0
	nudge_pressure(-0.14)


func _on_enemy_killed(_enemy_id: String, _enemy_node: Node) -> void:
	if not dynamic_enabled:
		return
	kill_streak += 1
	var gain := 0.035 if kill_streak >= 3 else 0.02
	nudge_pressure(gain)


# =============================================================================
# Checkpoint Failure Assist (silent, per segment, opt-out)
# =============================================================================

## Incoming-damage multiplier for players from the checkpoint failure assist
## (default curve: 5 wipes -> 0.92, 10 wipes -> 0.85, reset when the segment is passed).
## Boss HP, moves and phase conditions are never touched.
func assist_damage_scale() -> float:
	if SaveManager == null or SaveManager.checkpoints == null:
		return 1.0
	return SaveManager.checkpoints.assist_damage_scale()


func set_assist_enabled(enabled: bool) -> void:
	if SaveManager != null and SaveManager.checkpoints != null:
		SaveManager.checkpoints.assist_enabled = enabled


func _emit_changed() -> void:
	if EventBus:
		EventBus.difficulty_changed.emit(preset, pressure)


func serialize_state() -> Dictionary:
	return {
		"preset": preset,
		"dynamic_enabled": dynamic_enabled,
		"pressure": pressure,
		"death_count": death_count,
		"parry_count": parry_count,
	}


func deserialize_state(data: Dictionary) -> void:
	if data.is_empty():
		return
	preset = str(data.get("preset", "normal"))
	dynamic_enabled = bool(data.get("dynamic_enabled", true))
	pressure = float(data.get("pressure", 0.50))
	death_count = int(data.get("death_count", 0))
	parry_count = int(data.get("parry_count", 0))
	_emit_changed()
