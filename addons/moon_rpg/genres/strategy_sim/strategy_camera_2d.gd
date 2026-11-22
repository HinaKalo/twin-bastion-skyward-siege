class_name StrategyCamera2D
extends Camera2D
## Top-Down Strategy / Tactics / Sim Camera with WASD Pan, Right/Middle Mouse Drag,
## Smooth Mouse-Wheel Zoom, and World Bounds Clamping.

@export var pan_speed: float = 260.0
@export var min_zoom: float = 0.5
@export var max_zoom: float = 2.0
@export var zoom_step: float = 0.12
@export var world_bounds: Rect2 = Rect2(0, 0, 1600, 1200)

var _target_zoom: float = 1.0
var _dragging: bool = false


func _init() -> void:
	process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	position_smoothing_enabled = false


func _ready() -> void:
	process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	position_smoothing_enabled = false
	make_current()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_target_zoom = clampf(_target_zoom + zoom_step, min_zoom, max_zoom)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_target_zoom = clampf(_target_zoom - zoom_step, min_zoom, max_zoom)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE or mb.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = mb.pressed
	elif event is InputEventMouseMotion and _dragging:
		global_position -= (event as InputEventMouseMotion).relative / maxf(0.1, zoom.x)


func _physics_process(delta: float) -> void:
	var dir := InputManager.get_move_vector() if InputManager else Vector2.ZERO
	if dir.length_squared() > 0.01:
		global_position += dir.normalized() * (pan_speed / maxf(0.25, zoom.x)) * delta

	zoom = zoom.lerp(Vector2(_target_zoom, _target_zoom), 1.0 - exp(-10.0 * delta))

	if world_bounds.size.x > 0.0 and world_bounds.size.y > 0.0:
		global_position.x = clampf(global_position.x, world_bounds.position.x, world_bounds.position.x + world_bounds.size.x)
		global_position.y = clampf(global_position.y, world_bounds.position.y, world_bounds.position.y + world_bounds.size.y)
