class_name HazardZone2D
extends Area2D
## Pitfall / Spikes / Lava Hazard Zone for Platformers & Top-Down Dungeons.
## Deals configurable damage, plays feedback (screen shake + hurt SFX), and
## cleanly teleports the player back to the last safe checkpoint via `MoonRPG.teleport_node()`
## without physics-interpolation smearing.

signal hazard_triggered(body: Node2D, respawn_pos: Vector2)

@export var damage: float = 15.0
@export var respawn_at_safe_point: bool = true
@export var fallback_respawn_pos: Vector2 = Vector2(80, 180)
@export var shake_intensity: float = 4.0
@export var shake_duration: float = 0.16
@export var zone_size: Vector2 = Vector2(120, 32)
## Thorns: a downward pogo strike that reaches the hazard first bounces instead of hurting.
@export var allow_pogo: bool = true
@export var pogo_bounce_velocity: float = -285.0

signal hazard_pogoed(body: Node2D)

var last_safe_pos: Vector2 = Vector2.ZERO
var _has_safe_pos: bool = false


func _ready() -> void:
	collision_layer = 0
	collision_mask = 4 # player layer
	if get_node_or_null("CollisionShape2D") == null:
		var col := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = zone_size
		col.shape = rect
		add_child(col)
	body_entered.connect(_on_body_entered)


func set_safe_respawn(pos: Vector2) -> void:
	last_safe_pos = pos
	_has_safe_pos = true


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player") or not (body is Node2D):
		return
	var p := body as Node2D
	# Contact order: blade (pogo) before body. A live pogo strike bounces and skips damage.
	if allow_pogo and p.has_method("is_pogo_striking") and bool(p.call("is_pogo_striking")):
		if p.has_method("on_pogo_hazard"):
			p.call("on_pogo_hazard", pogo_bounce_velocity)
		hazard_pogoed.emit(p)
		return
	if p.has_method("take_damage"):
		p.call("take_damage", damage, Vector2.ZERO, 0.0)
	elif "stat_block" in p and p.get("stat_block") is StatBlock:
		(p.get("stat_block") as StatBlock).take_damage(damage)

	if AudioManager:
		AudioManager.play_sfx("sfx.hurt")
	if EventBus:
		EventBus.camera_shake_requested.emit(shake_intensity, shake_duration)

	var dest := last_safe_pos if _has_safe_pos else fallback_respawn_pos
	if respawn_at_safe_point:
		if p is CharacterBody2D:
			(p as CharacterBody2D).velocity = Vector2.ZERO
		if MoonRPG:
			MoonRPG.teleport_node(p, dest)
		else:
			p.global_position = dest
			p.reset_physics_interpolation()
	hazard_triggered.emit(p, dest)
