class_name FrameBody
extends RefCounted
## Kinematic AABB body for the deterministic fixed-tick platformer (FramePlatformer).
## `pos` is the bottom-centre (feet) of the box; y grows downward.

var id: String = ""
var pos: Vector2 = Vector2.ZERO
var half_w: float = 7.0
var height: float = 30.0
var vel: Vector2 = Vector2.ZERO
var facing: int = 1

var grounded: bool = false
var air_ticks: int = 0
var jumped_since_ground: bool = false
var jump_buf: int = 0
var jump_kind: String = ""      # ground / double / wall / follow / ladder / bounce
var air_jump_available: bool = true
var wall_dir: int = 0           # +1 wall on the right, -1 on the left
var wall_grace: int = 0
var wall_lock: int = 0
var drop_timer: int = 0
var on_ladder: bool = false
var ladder_x: float = 0.0
var ladder_rect: Rect2 = Rect2()
var landed_this_tick: bool = false
var nudged_this_tick: float = 0.0
var last_fall_speed: float = 0.0
var abilities: Dictionary = {"double_jump": false, "wall_kick": true, "ladder": true}


func _init(body_id: String = "", at: Vector2 = Vector2.ZERO) -> void:
	id = body_id
	pos = at


func rect() -> Rect2:
	return Rect2(pos.x - half_w, pos.y - height, half_w * 2.0, height)


func center() -> Vector2:
	return pos - Vector2(0.0, height * 0.5)


func snapshot() -> Dictionary:
	return {
		"pos": pos, "vel": vel, "grounded": grounded, "jump_kind": jump_kind, "on_ladder": on_ladder,
		"wall_lock": wall_lock, "air_jump": air_jump_available, "facing": facing,
	}
