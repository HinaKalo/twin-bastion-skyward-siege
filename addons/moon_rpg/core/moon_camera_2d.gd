class_name MoonCamera2D
extends Camera2D
## Core Engine Zero-Jitter 2D Camera (shared across ARPG, Top-Down JRPG, SRPG, etc.).
##
## Eliminates BOTH causes of 2D walking screen jitter across 60Hz/120Hz/144Hz/240Hz displays:
## 1. Runs `_physics_process` at `process_physics_priority = 100` (strictly AFTER all
##    `CharacterBody2D` controllers) to sample the target's exact previous/current physics positions.
## 2. Disables `Camera2D`'s own physics interpolation (`PHYSICS_INTERPOLATION_MODE_OFF`) and runs
##    in `_process` (`CAMERA2D_PROCESS_IDLE`, `process_priority = 100`), interpolating the target via
##    `Engine.get_physics_interpolation_fraction()` and damping smoothly at the display's native
##    refresh rate — zero 1-frame lag, zero physics-tick stutter, zero limit-clamp fighting.
## 3. Aligns the final camera position to exact screen-pixel boundaries (`snap_to_screen_pixel`)
##    so Nearest-filtered pixel tiles never shimmer or crawl while scrolling.

@export var follow_smoothing: float = 10.0
@export var follow_offset: Vector2 = Vector2.ZERO
@export var snap_to_screen_pixel: bool = false

var target_node: Node2D = null
var pause_follow: bool = false

var _prev_desired: Vector2 = Vector2.ZERO
var _curr_desired: Vector2 = Vector2.ZERO
var _smooth_pos: Vector2 = Vector2.ZERO
var _desired_zoom: float = 1.0
var _smooth_zoom: float = 1.0
var _has_sampled: bool = false

var _shake_intensity: float = 0.0
var _shake_timer: float = 0.0


func _init() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	process_callback = Camera2D.CAMERA2D_PROCESS_IDLE
	position_smoothing_enabled = false
	process_physics_priority = 100
	process_priority = 100


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	process_callback = Camera2D.CAMERA2D_PROCESS_IDLE
	position_smoothing_enabled = false
	process_physics_priority = 100
	process_priority = 100
	_smooth_pos = global_position
	_prev_desired = global_position
	_curr_desired = global_position
	make_current()
	if EventBus and not EventBus.camera_shake_requested.is_connected(_on_camera_shake_requested):
		EventBus.camera_shake_requested.connect(_on_camera_shake_requested)


func set_follow_target(node: Node2D, snap: bool = true) -> void:
	target_node = node
	if snap and is_instance_valid(target_node):
		snap_to(target_node.global_position + follow_offset)


func snap_to(pos: Vector2) -> void:
	_prev_desired = pos
	_curr_desired = pos
	_smooth_pos = pos
	_has_sampled = true
	global_position = _align_to_screen_pixel(pos)
	if is_inside_tree():
		force_update_scroll()


func set_world_bounds(bounds: Rect2) -> void:
	limit_left = int(bounds.position.x)
	limit_top = int(bounds.position.y)
	limit_right = int(bounds.position.x + bounds.size.x)
	limit_bottom = int(bounds.position.y + bounds.size.y)


func clear_world_bounds() -> void:
	limit_left = -10000000
	limit_top = -10000000
	limit_right = 10000000
	limit_bottom = 10000000


func shake(intensity: float, duration: float) -> void:
	var api := get_node_or_null("/root/MoonRPG")
	if api != null and "accessibility" in api and api.accessibility != null:
		intensity = api.accessibility.apply("shake", intensity)
	if intensity <= 0.0:
		return
	_shake_intensity = maxf(_shake_intensity, intensity)
	_shake_timer = maxf(_shake_timer, duration)


func _on_camera_shake_requested(intensity: float, duration: float) -> void:
	shake(intensity, duration)


## Virtual hook: subclasses (e.g. SmartCamera2D) can override for lookahead / boss lock / 2P framing.
func _compute_desired_position() -> Vector2:
	if is_instance_valid(target_node):
		return target_node.global_position + follow_offset
	return _smooth_pos


## Virtual hook: subclasses can override for dynamic zoom.
func _compute_desired_zoom() -> float:
	return 1.0


func _align_to_screen_pixel(pos: Vector2) -> Vector2:
	if not snap_to_screen_pixel or not is_inside_tree():
		return pos
	var vp := get_viewport()
	if vp == null:
		return pos
	var sx := maxf(1.0, vp.get_final_transform().get_scale().x)
	var sy := maxf(1.0, vp.get_final_transform().get_scale().y)
	return Vector2(roundf(pos.x * sx) / sx, roundf(pos.y * sy) / sy)


func _physics_process(_delta: float) -> void:
	if pause_follow:
		_prev_desired = global_position
		_curr_desired = global_position
		_smooth_pos = global_position
		return
	var next_desired := _compute_desired_position()
	if not _has_sampled:
		_prev_desired = next_desired
		_curr_desired = next_desired
		_smooth_pos = next_desired
		_has_sampled = true
	else:
		_prev_desired = _curr_desired
		_curr_desired = next_desired
	_desired_zoom = _compute_desired_zoom()


func _process(delta: float) -> void:
	if not pause_follow and _has_sampled:
		var use_interp := is_inside_tree() and get_tree().physics_interpolation
		var interp_desired := _prev_desired.lerp(_curr_desired, Engine.get_physics_interpolation_fraction()) if use_interp else _curr_desired
		if follow_smoothing <= 0.0:
			_smooth_pos = interp_desired
		else:
			var weight := 1.0 - exp(-follow_smoothing * delta)
			_smooth_pos = _smooth_pos.lerp(interp_desired, weight)
		global_position = _align_to_screen_pixel(_smooth_pos)

		var z_weight := 1.0 - exp(-5.0 * delta)
		_smooth_zoom = lerpf(_smooth_zoom, _desired_zoom, z_weight)
		zoom = Vector2(_smooth_zoom, _smooth_zoom)

	if _shake_timer > 0.0:
		_shake_timer = maxf(0.0, _shake_timer - delta)
		offset = Vector2(
			randf_range(-_shake_intensity, _shake_intensity),
			randf_range(-_shake_intensity, _shake_intensity)
		)
		if _shake_timer <= 0.0:
			_shake_intensity = 0.0
			offset = Vector2.ZERO

	# CRITICAL: Push updated global_position/zoom/offset to Viewport immediately in this
	# render frame so Camera2D is NEVER 1 frame behind the physics-interpolated player!
	if is_inside_tree():
		force_update_scroll()
