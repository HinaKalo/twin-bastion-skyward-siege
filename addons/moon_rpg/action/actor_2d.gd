class_name Actor2D
extends CharacterBody2D
## Base class for Player, Enemies, and animated NPCs.
## Hardcore Combat Features:
## - Poise / Posture system (Super Armor until broken -> 2.0s BREAK! vulnerable window)
## - Dead Cells Rally HP pool (orange recoverable health regained by counter-attacking)
## - Squash & Stretch tactile spring + Dodge Afterimage Ghost Trail spawner

@export var actor_key: String = ""
@export var body_size: Vector2 = Vector2(18, 38)
@export var max_poise: float = 40.0
@export var poise_regen_delay: float = 2.6
@export var poise_regen_rate: float = 18.0
@export var enable_rally: bool = false

var stat_block: StatBlock
var motor: PlatformerMotor2D
var status_effects: StatusEffectManager
var sprite: AnimatedSprite2D
var hitbox: Hitbox2D
var hurtbox: Hurtbox2D
var facing: int = 1
var is_dead: bool = false

# Poise / Posture Break state
var poise: float = 40.0
var is_posture_broken: bool = false
var _poise_regen_timer: float = 0.0
var _posture_break_timer: float = 0.0

# Dead Cells Rally HP pool
var rally_hp: float = 0.0
var rally_timer: float = 0.0

var _flash_timer: float = 0.0
var _hitstop_paused_sprite: bool = false
var _visual_scale: Vector2 = Vector2.ONE


func _ready() -> void:
	if stat_block == null:
		stat_block = StatBlock.new()
	poise = max_poise

	collision_mask = 1 | 2 # world + one_way

	if get_node_or_null("CollisionShape2D") == null:
		var col := CollisionShape2D.new()
		col.name = "CollisionShape2D"
		var rect := RectangleShape2D.new()
		rect.size = body_size
		col.shape = rect
		col.position = Vector2(0, -body_size.y * 0.5)
		add_child(col)

	motor = get_node_or_null("PlatformerMotor2D")
	if motor == null:
		motor = PlatformerMotor2D.new()
		motor.name = "PlatformerMotor2D"
		add_child(motor)

	status_effects = get_node_or_null("StatusEffectManager")
	if status_effects == null:
		status_effects = StatusEffectManager.new()
		status_effects.name = "StatusEffectManager"
		add_child(status_effects)
	status_effects.setup(self, stat_block)

	sprite = get_node_or_null("AnimatedSprite2D")
	if sprite == null:
		sprite = AnimatedSprite2D.new()
		sprite.name = "AnimatedSprite2D"
		sprite.centered = false
		add_child(sprite)
	if ThemeManager:
		ThemeManager.apply_pixel_aa(sprite)

	hitbox = get_node_or_null("Hitbox2D")
	if hitbox == null:
		hitbox = Hitbox2D.new()
		hitbox.name = "Hitbox2D"
		add_child(hitbox)
	hitbox.owner_actor = self

	hurtbox = get_node_or_null("Hurtbox2D")
	if hurtbox == null:
		hurtbox = Hurtbox2D.new()
		hurtbox.name = "Hurtbox2D"
		add_child(hurtbox)
	hurtbox.owner_actor = self
	hurtbox.hit_received.connect(_on_hit_received)
	hurtbox.parried_hit.connect(_on_parried_hit)

	if not actor_key.is_empty():
		apply_actor_assets(actor_key)


func apply_actor_assets(key: String) -> void:
	actor_key = key
	if AssetRegistry == null or sprite == null:
		return
	var sf := AssetRegistry.build_actor_sprite_frames(key)
	if sf != null:
		sprite.sprite_frames = sf
		var pivot := AssetRegistry.get_actor_pivot(key)
		sprite.centered = false
		sprite.offset = -pivot
		play_anim("idle")


func set_facing(dir: int) -> void:
	if dir == 0:
		return
	var next_dir := 1 if dir > 0 else -1
	if next_dir == facing:
		return
	facing = next_dir
	if sprite != null:
		sprite.flip_h = facing < 0
		var fs := AssetRegistry.get_actor_frame_size(actor_key)
		var pivot := AssetRegistry.get_actor_pivot(actor_key)
		if sprite.flip_h:
			sprite.offset = Vector2(-(fs.x - pivot.x), -pivot.y)
		else:
			sprite.offset = -pivot


func play_anim(anim_name: String, force_restart: bool = false) -> void:
	if sprite == null or sprite.sprite_frames == null:
		return
	var resolved := anim_name
	if not sprite.sprite_frames.has_animation(resolved):
		resolved = "idle"
	if not sprite.sprite_frames.has_animation(resolved):
		return
	if force_restart or sprite.animation != resolved or not sprite.is_playing():
		sprite.play(resolved)


func get_anim_duration(anim_name: String) -> float:
	if sprite == null or sprite.sprite_frames == null or not sprite.sprite_frames.has_animation(anim_name):
		return 0.0
	var sf := sprite.sprite_frames
	var fps := maxf(1.0, sf.get_animation_speed(anim_name))
	var total_units := 0.0
	for i in range(sf.get_frame_count(anim_name)):
		total_units += sf.get_frame_duration(anim_name, i)
	return total_units / fps


func apply_status_effect(effect_id: String, spec: Dictionary) -> void:
	if status_effects != null:
		status_effects.apply_effect(effect_id, spec)


func trigger_hit_flash(duration: float = 0.11) -> void:
	_flash_timer = duration
	if sprite != null:
		sprite.modulate = Color(2.5, 2.5, 2.5, 1.0)


func trigger_squash(target_scale: Vector2) -> void:
	_visual_scale = target_scale
	if sprite != null:
		sprite.scale = _visual_scale


func spawn_afterimage(tint: Color = Color(0.45, 0.90, 1.0, 0.55), duration: float = 0.20) -> void:
	if sprite == null or sprite.sprite_frames == null or get_parent() == null:
		return
	var tex := sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	if tex == null:
		return
	var ghost := Sprite2D.new()
	ghost.texture = tex
	ghost.centered = false
	ghost.offset = sprite.offset
	ghost.flip_h = sprite.flip_h
	ghost.global_position = global_position
	ghost.modulate = tint
	ghost.z_index = z_index - 1
	get_parent().add_child(ghost)
	var tw := ghost.create_tween()
	tw.tween_property(ghost, "modulate:a", 0.0, duration)
	tw.tween_callback(ghost.queue_free)


# =============================================================================
# Poise / Posture Break & Dead Cells Rally HP
# =============================================================================

func take_poise_damage(amount: float) -> bool:
	if amount <= 0.0 or max_poise <= 0.0 or is_dead:
		return false
	poise = maxf(0.0, poise - amount)
	_poise_regen_timer = poise_regen_delay
	if poise <= 0.0 and not is_posture_broken:
		is_posture_broken = true
		_posture_break_timer = 2.1
		if EventBus:
			EventBus.floating_text_requested.emit("BREAK!", global_position + Vector2(0, -44), "parry")
			request_scoped_hitstop([self], 5, "posture_break")
			EventBus.camera_shake_requested.emit(4.8, 0.18)
		if MoonRPG:
			MoonRPG.rumble_preset("parry")
		return true
	return false


## Freezes only the given actors through MoonSim (no global Engine.time_scale change).
func request_scoped_hitstop(targets: Array, ticks: int, reason: String = "hitstop") -> void:
	var valid: Array = targets.filter(func(t): return t != null and is_instance_valid(t))
	var sim := Actor2D.autoload("MoonSim")
	if sim != null:
		for t in valid:
			sim.freeze(t, ticks, reason)
	if EventBus:
		EventBus.scoped_hitstop_requested.emit(valid, ticks, reason)


## True while MoonSim has this actor frozen by a scoped hitstop.
func is_hitstop_frozen() -> bool:
	var sim := Actor2D.autoload("MoonSim")
	return sim != null and sim.is_frozen(self)


func recover_rally(amount: float) -> float:
	if not enable_rally or rally_hp <= 0.0 or amount <= 0.0:
		return 0.0
	var heal := minf(rally_hp, amount)
	rally_hp = maxf(0.0, rally_hp - heal)
	var actual := stat_block.modify_hp(heal)
	if actual > 0.0 and EventBus:
		EventBus.actor_healed.emit(self, int(ceil(actual)), global_position + Vector2(0, -34))
		EventBus.player_stats_changed.emit()
	return actual


func _process(delta: float) -> void:
	if sprite != null:
		var frozen := is_hitstop_frozen()
		if frozen and not _hitstop_paused_sprite and sprite.is_playing():
			sprite.pause()
			_hitstop_paused_sprite = true
		elif not frozen and _hitstop_paused_sprite:
			sprite.play()
			_hitstop_paused_sprite = false
	if _flash_timer > 0.0:
		_flash_timer = maxf(0.0, _flash_timer - delta)
		if _flash_timer <= 0.0 and sprite != null:
			sprite.modulate = Color.WHITE

	if sprite != null and _visual_scale.distance_squared_to(Vector2.ONE) > 0.0004:
		_visual_scale = _visual_scale.lerp(Vector2.ONE, clampf(16.0 * delta, 0.0, 1.0))
		sprite.scale = _visual_scale

	# Poise / Posture regeneration
	if is_posture_broken:
		_posture_break_timer -= delta
		if _posture_break_timer <= 0.0:
			is_posture_broken = false
			poise = max_poise
	elif poise < max_poise:
		if _poise_regen_timer > 0.0:
			_poise_regen_timer -= delta
		else:
			poise = minf(max_poise, poise + poise_regen_rate * delta)

	# Rally HP decay
	if rally_hp > 0.0:
		rally_timer -= delta
		if rally_timer <= 0.0:
			rally_hp = maxf(0.0, rally_hp - stat_block.get_stat("max_hp") * 0.35 * delta)
			if is_in_group("player") and EventBus:
				EventBus.player_stats_changed.emit()


func compute_damage_against(defender: Actor2D, skill_mult: float = 1.0, formula_override: String = "") -> Dictionary:
	var atk := stat_block.get_stat("atk")
	var def := defender.stat_block.get_stat("def") if defender != null else 0.0
	var crit_rate := stat_block.get_stat("crit_rate")
	var crit_dmg := stat_block.get_stat("crit_dmg")
	var is_exec := defender != null and defender.is_posture_broken
	var is_crit := is_exec or (randf() < crit_rate)
	var expr := formula_override if not formula_override.is_empty() else "max(1.0, (atk * mult) - (def * 0.65))"
	var raw := ScriptBridge.eval_formula(expr, {
		"atk": atk,
		"def": def,
		"mult": skill_mult,
		"level": stat_block.level,
	})
	if raw <= 0.0:
		raw = maxf(1.0, atk * skill_mult - def * 0.65)
	if is_exec:
		raw *= maxf(crit_dmg, 1.8)
	elif is_crit:
		raw *= crit_dmg
	return {
		"damage": maxi(1, int(round(raw * randf_range(0.95, 1.05)))),
		"is_crit": is_crit,
		"is_execution": is_exec,
	}


func _on_hit_received(payload: Dictionary) -> void:
	if is_dead:
		return
	var dmg := maxi(1, int(payload.get("damage", 1)))
	if is_in_group("player") and DifficultyManager != null and DifficultyManager.has_method("assist_damage_scale"):
		dmg = maxi(1, int(round(float(dmg) * DifficultyManager.assist_damage_scale())))
	var is_crit := bool(payload.get("is_crit", false))
	var guarded := bool(payload.get("guarded", false))
	var attacker: Node = payload.get("attacker", null)
	var hit_pos: Vector2 = payload.get("hit_pos", global_position + Vector2(0, -24))
	var kb: Vector2 = payload.get("knockback", Vector2.ZERO)

	stat_block.modify_hp(-float(dmg))
	if enable_rally and not guarded:
		rally_hp = minf(stat_block.get_stat("max_hp") - stat_block.hp, rally_hp + float(dmg) * 0.65)
		rally_timer = 3.2

	var poise_dmg := float(payload.get("poise_dmg", 14.0)) * (0.25 if guarded else 1.0)
	var broke := take_poise_damage(poise_dmg)
	if broke or max_poise <= 0.0:
		motor.apply_knockback(kb)
	else:
		motor.apply_knockback(kb * 0.35) # Super armor dampens knockback until broken

	trigger_hit_flash()
	trigger_squash(Vector2(1.18, 0.86))

	if AudioManager:
		AudioManager.play_sfx("sfx.block" if guarded else "sfx.hurt")
	if EventBus:
		EventBus.actor_damaged.emit(self, attacker, dmg, is_crit, hit_pos)
		var hs := float(payload.get("hitstop", 0.035))
		if hs > 0.0:
			# Scoped hitstop: only the attacker and this target freeze; UI / input / others keep running.
			request_scoped_hitstop([self, attacker], maxi(1, int(round(hs * 60.0))), "hitstop")
		EventBus.camera_shake_requested.emit(4.2 if is_crit else 2.2, 0.14)

	if stat_block.hp <= 0.0:
		_die(attacker)


func _on_parried_hit(payload: Dictionary) -> void:
	var attacker: Node = payload.get("attacker", null)
	var hit_pos: Vector2 = payload.get("hit_pos", global_position + Vector2(0, -24))
	stat_block.modify_st(28.0)
	hurtbox.start_iframes(0.40)
	trigger_squash(Vector2(0.88, 1.15))
	if attacker is Actor2D:
		(attacker as Actor2D).take_poise_damage(999.0) # Perfect Parry instantly breaks enemy posture!
	if attacker != null and attacker.has_method("apply_stagger"):
		attacker.apply_stagger(1.6)
	if AudioManager:
		AudioManager.play_sfx("sfx.block")
	if EventBus:
		EventBus.actor_parried.emit(self, attacker, hit_pos)
		request_scoped_hitstop([self, attacker], 5, "parry")
		EventBus.camera_shake_requested.emit(5.2, 0.20)


func _die(killer: Node) -> void:
	is_dead = true
	rally_hp = 0.0
	if hitbox != null:
		hitbox.deactivate()
	if EventBus:
		EventBus.actor_died.emit(self, killer)


## Autoload lookup that also works for actors not yet inside the scene tree (headless tests).
static func autoload(name: String) -> Node:
	var loop := Engine.get_main_loop()
	if loop is SceneTree and (loop as SceneTree).root != null:
		return (loop as SceneTree).root.get_node_or_null(name)
	return null
