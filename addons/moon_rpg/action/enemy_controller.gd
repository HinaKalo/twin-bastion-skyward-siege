class_name EnemyController
extends Actor2D
## Data-Driven Side-Scrolling ARPG Enemy AI.
## Loads stats, aggro range, attack telegraph windup, and loot table from DataRegistry.

enum AIState { PATROL, CHASE, WINDUP, ATTACK, STAGGER, DEAD }

@export var enemy_id: String = "weaver_spider"
@export var patrol_distance: float = 72.0

var ai_state: int = AIState.PATROL
var _home_x: float = 0.0
var _patrol_dir: int = 1
var _state_timer: float = 0.0
var _attack_cooldown: float = 0.0
var _enemy_def: Dictionary = {}
var _hp_bar_bg: ColorRect = null
var _hp_bar_fill: ColorRect = null
var _poise_bar_fill: ColorRect = null
var _telegraph_label: Label = null
## fodder / soldier / rival / elite (enemies.json "tier"); drives attack-token precedence.
var tier: String = "fodder"
var _token_id: String = ""


func _ready() -> void:
	add_to_group("enemies")
	_enemy_def = DataRegistry.get_enemy(enemy_id) if DataRegistry else {}
	if actor_key.is_empty():
		actor_key = str(_enemy_def.get("actor_key", "enemy.weaver_spider"))
	max_poise = float(_enemy_def.get("max_poise", 35.0))
	tier = str(_enemy_def.get("tier", "fodder"))
	_token_id = "enemy:%d" % get_instance_id()

	var stat_mults := DifficultyManager.get_stat_multipliers() if DifficultyManager else {}
	var beh_mults := DifficultyManager.get_behavior_multipliers() if DifficultyManager else {}
	stat_block = StatBlock.new({
		"max_hp": float(_enemy_def.get("max_hp", 60.0)) * float(stat_mults.get("enemy_hp_mult", 1.0)),
		"atk": float(_enemy_def.get("atk", 12.0)) * float(stat_mults.get("enemy_atk_mult", 1.0)),
		"def": float(_enemy_def.get("def", 3.0)) * float(stat_mults.get("enemy_def_mult", 1.0)),
		"move_spd": float(_enemy_def.get("move_spd", 62.0)) * float(beh_mults.get("move_speed_mult", 1.0)),
	})
	super._ready()

	collision_layer = 8 # layer 4: enemy
	hitbox.collision_layer = 32 # layer 6: enemy_hitbox
	hitbox.collision_mask = 4 # layer 3: player hurtbox
	hurtbox.collision_layer = 8
	hurtbox.collision_mask = 16 # layer 5: player_hitbox

	_home_x = global_position.x
	_build_mini_hp_bar()
	if WorldManager:
		WorldManager.register_room_entity(enemy_id, self)


func _exit_tree() -> void:
	_release_token()
	if WorldManager:
		WorldManager.unregister_room_entity(enemy_id, self)


func _build_mini_hp_bar() -> void:
	_hp_bar_bg = ColorRect.new()
	_hp_bar_bg.size = Vector2(30, 7)
	_hp_bar_bg.position = Vector2(-15, -54)
	_hp_bar_bg.color = Color(0.08, 0.08, 0.10, 0.88)
	_hp_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_bar_bg.visible = false
	add_child(_hp_bar_bg)

	_hp_bar_fill = ColorRect.new()
	_hp_bar_fill.size = Vector2(28, 3)
	_hp_bar_fill.position = Vector2(1, 1)
	_hp_bar_fill.color = Color(0.92, 0.24, 0.24, 1.0)
	_hp_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_bar_bg.add_child(_hp_bar_fill)

	_poise_bar_fill = ColorRect.new()
	_poise_bar_fill.size = Vector2(28, 2)
	_poise_bar_fill.position = Vector2(1, 4)
	_poise_bar_fill.color = Color(0.96, 0.78, 0.20, 1.0)
	_poise_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_bar_bg.add_child(_poise_bar_fill)

	_telegraph_label = Label.new()
	_telegraph_label.text = "!"
	_telegraph_label.visible = false
	_telegraph_label.position = Vector2(-5, -72)
	_telegraph_label.add_theme_font_size_override("font_size", 11)
	_telegraph_label.add_theme_color_override("font_color", Color(1.0, 0.28, 0.22))
	_telegraph_label.add_theme_constant_override("outline_size", 2)
	_telegraph_label.add_theme_color_override("font_outline_color", Color(1.0, 0.92, 0.35))
	add_child(_telegraph_label)


func _update_hp_bar() -> void:
	if _hp_bar_bg == null:
		return
	var ratio := clampf(stat_block.hp / maxf(1.0, stat_block.get_stat("max_hp")), 0.0, 1.0)
	var poise_ratio := clampf(poise / maxf(1.0, max_poise), 0.0, 1.0)
	_hp_bar_bg.visible = (ratio < 0.999 or poise_ratio < 0.999) and not is_dead
	_hp_bar_fill.size.x = 28.0 * ratio
	if _poise_bar_fill != null:
		_poise_bar_fill.size.x = 28.0 * poise_ratio
		_poise_bar_fill.color = Color(0.45, 0.95, 1.0) if is_posture_broken else Color(0.96, 0.78, 0.20)


func apply_stagger(duration: float) -> void:
	if is_dead:
		return
	hitbox.deactivate()
	_release_token()
	ai_state = AIState.STAGGER
	_state_timer = duration
	play_anim("hurt", true)


func _token_pool() -> AttackTokenPool:
	var sim := Actor2D.autoload("MoonSim")
	return sim.attack_tokens if sim != null and "attack_tokens" in sim else null


## Group coordination: only token holders may commit to a telegraphed attack.
func _request_token() -> bool:
	var pool := _token_pool()
	if pool == null:
		return true
	var sim := Actor2D.autoload("MoonSim")
	var kind := "ranged" if bool(_enemy_def.get("ranged", false)) else "melee"
	return pool.request(_token_id, kind, AttackTokenPool.tier_of(tier), sim.current_tick() if sim != null else 0)


func _release_token() -> void:
	var pool := _token_pool()
	if pool != null:
		pool.release(_token_id)


func _physics_process(delta: float) -> void:
	if DialogueRunner != null and DialogueRunner.is_active:
		motor.step(self, 0.0, 0.0, delta, false)
		return
	if is_hitstop_frozen():
		return

	if _attack_cooldown > 0.0:
		_attack_cooldown = maxf(0.0, _attack_cooldown - delta)

	var player := _get_player()
	var beh := DifficultyManager.get_behavior_multipliers() if DifficultyManager else {}
	var aggro_range := float(_enemy_def.get("aggro_range", 150.0)) * float(beh.get("aggro_range_mult", 1.0))
	var attack_range := float(_enemy_def.get("attack_range", 36.0))
	var move_spd := stat_block.get_stat("move_spd")

	match ai_state:
		AIState.PATROL:
			var dist_home := global_position.x - _home_x
			if absf(dist_home) > patrol_distance:
				_patrol_dir = -1 if dist_home > 0.0 else 1
			set_facing(_patrol_dir)
			motor.step(self, float(_patrol_dir), move_spd * 0.6, delta, true)
			play_anim("run")
			if player != null and global_position.distance_to(player.global_position) <= aggro_range:
				ai_state = AIState.CHASE
		AIState.CHASE:
			if player == null or global_position.distance_to(player.global_position) > aggro_range * 1.4:
				ai_state = AIState.PATROL
				return
			var dx := player.global_position.x - global_position.x
			set_facing(1 if dx >= 0.0 else -1)
			if absf(dx) <= attack_range and _attack_cooldown <= 0.0 and _request_token():
				ai_state = AIState.WINDUP
				_state_timer = float(_enemy_def.get("windup_time", 0.35)) * float(beh.get("windup_time_mult", 1.0))
				sprite.modulate = Color(1.6, 0.75, 0.75, 1.0)
				if _telegraph_label != null:
					_telegraph_label.visible = true
				play_anim("idle")
			else:
				motor.step(self, float(facing), move_spd, delta, true)
				play_anim("run")
		AIState.WINDUP:
			motor.step(self, 0.0, 0.0, delta, false)
			_state_timer -= delta
			if _state_timer <= 0.0:
				sprite.modulate = Color.WHITE
				if _telegraph_label != null:
					_telegraph_label.visible = false
				ai_state = AIState.ATTACK
				_state_timer = 0.40
				_attack_cooldown = float(_enemy_def.get("attack_cooldown", 1.25)) * float(beh.get("attack_cooldown_mult", 1.0))
				play_anim("attack", true)
				var res := compute_damage_against(player as Actor2D, 1.0)
				hitbox.activate({
					"damage": res["damage"],
					"is_crit": res["is_crit"],
					"knockback": Vector2(facing * 120.0, -75.0),
					"hitstop": 0.03,
				}, Vector2(36, 30), Vector2(facing * 22.0, -20.0))
		AIState.ATTACK:
			motor.step(self, 0.0, 0.0, delta, false)
			_state_timer -= delta
			if _state_timer <= 0.16 and hitbox.monitoring:
				hitbox.deactivate()
			if _state_timer <= 0.0:
				hitbox.deactivate()
				_release_token()
				ai_state = AIState.CHASE
		AIState.STAGGER:
			motor.step(self, 0.0, 0.0, delta, false)
			_state_timer -= delta
			if _state_timer <= 0.0:
				ai_state = AIState.CHASE
		AIState.DEAD:
			motor.step(self, 0.0, 0.0, delta, false)


func _on_hit_received(payload: Dictionary) -> void:
	# Recompute damage with defender's DEF if attacker passed mult
	var attacker: Node = payload.get("attacker", null)
	if attacker is Actor2D and payload.has("damage_mult"):
		var res := (attacker as Actor2D).compute_damage_against(self, float(payload["damage_mult"]))
		payload["damage"] = res["damage"]
		payload["is_crit"] = res["is_crit"]
	super._on_hit_received(payload)
	_update_hp_bar()
	if attacker is Actor2D and payload.has("st_gain"):
		(attacker as Actor2D).stat_block.modify_st(float(payload["st_gain"]))
		if EventBus:
			EventBus.player_stats_changed.emit()
	# Hardcore poise rule: elites with Super Armor resist stagger until posture breaks!
	if not is_dead:
		if is_posture_broken:
			if _telegraph_label != null:
				_telegraph_label.visible = false
			apply_stagger(1.8)
		elif max_poise <= 30.0 and ai_state != AIState.ATTACK:
			apply_stagger(0.22)


func _die(killer: Node) -> void:
	super._die(killer)
	ai_state = AIState.DEAD
	hurtbox.monitorable = false
	_update_hp_bar()
	play_anim("death", true)

	# Grant XP, gold, and item drops (scaled by DifficultyManager loot multipliers)
	var loot_m := DifficultyManager.get_loot_multipliers() if DifficultyManager else {}
	var xp_reward := int(round(float(_enemy_def.get("xp_reward", 30)) * float(loot_m.get("xp_mult", 1.0))))
	var gold_reward := int(round(float(_enemy_def.get("gold_reward", 18)) * float(loot_m.get("gold_mult", 1.0))))
	if killer is Actor2D:
		var leveled := (killer as Actor2D).stat_block.add_xp(xp_reward)
		if leveled and EventBus:
			EventBus.toast_requested.emit("升级！当前等级 Lv.%d" % (killer as Actor2D).stat_block.level, "gold")
		if EventBus:
			EventBus.player_stats_changed.emit()
	if InventoryManager:
		InventoryManager.add_gold(gold_reward)
		for drop in _enemy_def.get("drops", []):
			var drop_id := str(drop.get("item_id", ""))
			var idef := DataRegistry.get_item(drop_id) if DataRegistry else {}
			var eff_dict: Dictionary = idef.get("effect", {})
			var is_heal: bool = eff_dict.has("heal_hp")
			var mult := float(loot_m.get("healing_drop_mult", 1.0)) if is_heal else float(loot_m.get("drop_chance_mult", 1.0))
			if randf() <= clampf(float(drop.get("chance", 1.0)) * mult, 0.0, 1.0):
				InventoryManager.add_item(drop_id, int(drop.get("count", 1)))
	if EventBus:
		EventBus.enemy_killed.emit(enemy_id, self)

	await get_tree().create_timer(0.75).timeout
	queue_free()


func _get_player() -> Node2D:
	var players := get_tree().get_nodes_in_group("player")
	var nearest: Node2D = null
	var best_dist := INF
	for p in players:
		if p is Node2D:
			if "is_dead" in p and bool(p.get("is_dead")):
				continue
			var d := global_position.distance_squared_to((p as Node2D).global_position)
			if d < best_dist:
				best_dist = d
				nearest = p as Node2D
	return nearest
