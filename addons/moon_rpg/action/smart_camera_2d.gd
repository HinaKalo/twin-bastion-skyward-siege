class_name SmartCamera2D
extends MoonCamera2D
## Side-Scrolling ARPG Smart Camera (built on Core MoonCamera2D).
## Adds directional lookahead, automatic room bounds clamping from WorldManager,
## 2P co-op midpoint framing with dynamic zoom, and optional boss arena lock.

@export var lookahead_x: float = 28.0
@export var vertical_offset: float = -24.0

var boss_lock_pos: Vector2 = Vector2.ZERO
var is_boss_locked: bool = false


func _ready() -> void:
	follow_smoothing = 8.0
	follow_offset = Vector2(0.0, vertical_offset)
	super._ready()
	if EventBus:
		EventBus.player_registered.connect(_on_player_registered)
		EventBus.room_changed.connect(_on_room_changed)
	_try_acquire_player()


func _try_acquire_player() -> void:
	if is_instance_valid(target_node):
		return
	var p: Node = MoonRPG.player if MoonRPG != null else null
	if p == null:
		var list := get_tree().get_nodes_in_group("player")
		if not list.is_empty():
			p = list[0]
	if p is Node2D:
		set_follow_target(p as Node2D, true)


func _on_player_registered(player: Node) -> void:
	if player is Node2D:
		set_follow_target(player as Node2D, true)


func _on_room_changed(_room_id: String, _spawn: String) -> void:
	is_boss_locked = false
	if WorldManager:
		set_world_bounds(WorldManager.get_current_room_bounds())
	if is_instance_valid(target_node):
		snap_to(target_node.global_position + Vector2(0.0, vertical_offset))


func lock_to_boss_arena(center: Vector2) -> void:
	boss_lock_pos = center
	is_boss_locked = true


func unlock_boss_arena() -> void:
	is_boss_locked = false


func _compute_desired_position() -> Vector2:
	if not is_instance_valid(target_node):
		_try_acquire_player()
	var active_players := CoopManager.get_players() if CoopManager != null else []
	if is_boss_locked:
		return boss_lock_pos
	if active_players.size() >= 2 and active_players[0] is Node2D and active_players[1] is Node2D:
		var p1 := (active_players[0] as Node2D).global_position
		var p2 := (active_players[1] as Node2D).global_position
		return (p1 + p2) * 0.5 + Vector2(0.0, vertical_offset)
	if is_instance_valid(target_node):
		var facing_offset := 0.0
		if "facing" in target_node:
			facing_offset = float(target_node.get("facing")) * lookahead_x
		return target_node.global_position + Vector2(facing_offset, vertical_offset)
	return global_position


func _compute_desired_zoom() -> float:
	if is_boss_locked:
		return 1.0
	var active_players := CoopManager.get_players() if CoopManager != null else []
	if active_players.size() >= 2 and active_players[0] is Node2D and active_players[1] is Node2D:
		var dist := (active_players[0] as Node2D).global_position.distance_to((active_players[1] as Node2D).global_position)
		if dist > 200.0:
			return clampf(1.0 - (dist - 200.0) / 700.0, 0.78, 1.0)
	return 1.0
