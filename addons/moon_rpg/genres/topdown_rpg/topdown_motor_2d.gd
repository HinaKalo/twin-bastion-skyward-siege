class_name TopDownMotor2D
extends Node
## RPG Maker MZ / Classic Top-Down 2D Movement Motor.
## Supports smooth 4/8-directional movement OR classic tile-by-tile Grid-Step movement.

@export var move_speed: float = 115.0
@export var eight_directional: bool = true
@export var grid_step_mode: bool = false
@export var tile_size: float = 32.0

var facing_dir: Vector2 = Vector2.DOWN
var _is_stepping: bool = false
var _step_target: Vector2 = Vector2.ZERO


func get_facing_name() -> String:
	if absf(facing_dir.x) > absf(facing_dir.y):
		return "right" if facing_dir.x > 0.0 else "left"
	return "down" if facing_dir.y >= 0.0 else "up"


func step(body: CharacterBody2D, input_vec: Vector2, delta: float) -> bool:
	var dir := input_vec
	if not eight_directional and dir.length_squared() > 0.01:
		if absf(dir.x) >= absf(dir.y):
			dir = Vector2(signf(dir.x), 0.0)
		else:
			dir = Vector2(0.0, signf(dir.y))
	elif dir.length() > 1.0:
		dir = dir.normalized()

	if grid_step_mode:
		return _step_grid(body, dir, delta)

	if dir.length_squared() > 0.01:
		facing_dir = dir.normalized()
		body.velocity = dir * move_speed
	else:
		body.velocity = Vector2.ZERO
	body.move_and_slide()
	return dir.length_squared() > 0.01


func _step_grid(body: CharacterBody2D, dir: Vector2, delta: float) -> bool:
	if not _is_stepping:
		if dir.length_squared() < 0.01:
			body.velocity = Vector2.ZERO
			return false
		var cardinal := Vector2(signf(dir.x), 0.0) if absf(dir.x) >= absf(dir.y) else Vector2(0.0, signf(dir.y))
		facing_dir = cardinal
		_step_target = body.global_position + cardinal * tile_size
		_is_stepping = true

	var to_target := _step_target - body.global_position
	var step_dist := move_speed * delta
	if to_target.length() <= step_dist:
		body.global_position = _step_target
		body.velocity = Vector2.ZERO
		_is_stepping = false
	else:
		body.velocity = to_target.normalized() * move_speed
		body.move_and_slide()
		if body.get_slide_collision_count() > 0:
			_is_stepping = false
	return true
