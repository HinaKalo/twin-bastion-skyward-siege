class_name FieldEnemy2D
extends CharacterBody2D
## Visible Overworld Roaming Enemy (明雷 — Persona 5 / Trails style).
## Patrols, detects player with EmoteBubble2D `!`, chases, and distinguishes:
## - Player Field Strike (`receive_field_strike`) -> PLAYER_ADVANTAGE (先制奇袭)
## - Enemy hits Player from behind -> ENEMY_AMBUSH (被偷袭)
## - Frontal collision -> NORMAL encounter

signal field_encounter_requested(troop_specs: Array, advantage_mode: int, field_enemy: FieldEnemy2D)

@export var troop_specs: Array = []
@export var move_speed: float = 68.0
@export var aggro_radius: float = 110.0
@export var patrol_radius: float = 48.0
@export var respawn_cooldown: float = 15.0

var is_defeated: bool = false
var _home_pos: Vector2 = Vector2.ZERO
var _patrol_angle: float = 0.0
var _alerted: bool = false
var _respawn_timer: float = 0.0
var _sprite_node: Sprite2D = null
var _bob_t: float = 0.0


func set_sprite_texture(tex: Texture2D, sc: Vector2 = Vector2(0.5, 0.5)) -> void:
	if tex == null:
		return
	if _sprite_node == null:
		_sprite_node = Sprite2D.new()
		_sprite_node.name = "EnemySprite"
		_sprite_node.centered = true
		_sprite_node.offset = Vector2(0, -12)
		add_child(_sprite_node)
	_sprite_node.texture = tex
	_sprite_node.scale = sc
	queue_redraw()


func _ready() -> void:
	_home_pos = global_position
	collision_layer = 8
	collision_mask = 1
	if get_node_or_null("CollisionShape2D") == null:
		var col := CollisionShape2D.new()
		var circ := CircleShape2D.new()
		circ.radius = 10.0
		col.shape = circ
		add_child(col)

	var touch := Area2D.new()
	touch.name = "TouchArea"
	var tcol := CollisionShape2D.new()
	var tcirc := CircleShape2D.new()
	tcirc.radius = 15.0
	tcol.shape = tcirc
	touch.add_child(tcol)
	add_child(touch)
	touch.body_entered.connect(_on_body_touched)


func receive_field_strike(_player: Node) -> void:
	if is_defeated:
		return
	field_encounter_requested.emit(troop_specs.duplicate(true), TurnBattleEngine.EncounterAdvantage.PLAYER_ADVANTAGE, self)


func mark_defeated() -> void:
	is_defeated = true
	visible = false
	_respawn_timer = respawn_cooldown


func _physics_process(delta: float) -> void:
	if is_defeated:
		if respawn_cooldown > 0.0:
			_respawn_timer -= delta
			if _respawn_timer <= 0.0:
				is_defeated = false
				visible = true
				global_position = _home_pos
		return

	var player := _find_player()
	if player != null and global_position.distance_to(player.global_position) <= aggro_radius:
		if not _alerted:
			_alerted = true
			var em := EmoteBubble2D.new()
			em.position = Vector2(0, -24)
			add_child(em)
			em.setup("alert", 0.9)
		var dir := (player.global_position - global_position).normalized()
		velocity = dir * move_speed
	else:
		_alerted = false
		_patrol_angle += delta * 1.1
		var target := _home_pos + Vector2(cos(_patrol_angle), sin(_patrol_angle)) * patrol_radius
		var diff := target - global_position
		velocity = diff.normalized() * (move_speed * 0.45) if diff.length() > 4.0 else Vector2.ZERO

	move_and_slide()
	if _sprite_node != null:
		_bob_t += delta * (9.0 if velocity.length_squared() > 4.0 else 3.0)
		_sprite_node.position.y = -absf(sin(_bob_t)) * (2.2 if velocity.length_squared() > 4.0 else 0.8)


func _on_body_touched(body: Node) -> void:
	if is_defeated or not body.is_in_group("player"):
		return
	var advantage := TurnBattleEngine.EncounterAdvantage.NORMAL
	# Check if enemy collided from behind the player -> ENEMY_AMBUSH!
	if body is Node2D and body.get_node_or_null("TopDownMotor2D") != null:
		var m := body.get_node("TopDownMotor2D") as TopDownMotor2D
		var to_enemy := (global_position - (body as Node2D).global_position).normalized()
		if m.facing_dir.dot(to_enemy) < -0.35:
			advantage = TurnBattleEngine.EncounterAdvantage.ENEMY_AMBUSH
	field_encounter_requested.emit(troop_specs.duplicate(true), advantage, self)


func _draw() -> void:
	if is_defeated:
		return
	if _sprite_node != null:
		draw_circle(Vector2(0, 6), 8.0, Color(0.0, 0.0, 0.0, 0.30))
		return
	draw_circle(Vector2.ZERO, 10.0, Color(0.90, 0.26, 0.26, 0.92))
	draw_arc(Vector2.ZERO, 10.0, 0.0, TAU, 16, Color(1.0, 0.85, 0.4), 1.5)


func _find_player() -> Node2D:
	var list := get_tree().get_nodes_in_group("player")
	return list[0] as Node2D if (not list.is_empty() and list[0] is Node2D) else null
