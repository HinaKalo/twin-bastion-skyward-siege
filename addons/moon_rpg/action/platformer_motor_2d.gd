class_name PlatformerMotor2D
extends Node
## Hollow Knight / Dead Cells grade 2D Side-Scrolling Physics Motor.
## Features:
## - Coyote time, Jump buffering, Variable jump height cut
## - Jump Apex Hang (reduced gravity near velocity.y == 0 for crisp air precision)
## - Double Jump (`max_air_jumps`) & Air Reset (for Pogo / Wall Jump)
## - Wall Slide (capped descent) & Wall Jump (horizontal kick-off)
## - One-way platform drop-through & Knockback velocity blending

@export var gravity: float = 960.0
@export var apex_gravity_mult: float = 0.52
@export var apex_velocity_threshold: float = 38.0
@export var fall_gravity_mult: float = 1.22
@export var max_fall_speed: float = 430.0

@export var jump_velocity: float = -365.0
@export var air_jump_velocity: float = -325.0
@export var jump_cut_multiplier: float = 0.48
@export var max_air_jumps: int = 1

@export var enable_wall_jump: bool = true
@export var wall_slide_max_speed: float = 95.0
@export var wall_jump_velocity: Vector2 = Vector2(215.0, -295.0)

@export var ground_accel: float = 1850.0
@export var ground_friction: float = 1750.0
@export var air_accel: float = 1280.0
@export var air_friction: float = 340.0
@export var coyote_time: float = 0.11
@export var jump_buffer_time: float = 0.13

var coyote_timer: float = 0.0
var jump_buffer_timer: float = 0.0
var air_jumps_left: int = 1
var is_wall_sliding: bool = false
var wall_normal_x: float = 0.0
var knockback_velocity: Vector2 = Vector2.ZERO
var was_on_floor: bool = false
var just_jumped: bool = false
var last_fall_speed: float = 0.0


func request_jump() -> void:
	jump_buffer_timer = jump_buffer_time


func cut_jump(body: CharacterBody2D) -> void:
	if body.velocity.y < 0.0:
		body.velocity.y *= jump_cut_multiplier


func reset_air_mobility() -> void:
	air_jumps_left = max_air_jumps


func apply_knockback(impulse: Vector2) -> void:
	knockback_velocity = impulse


func apply_pogo_bounce(body: CharacterBody2D, bounce_velocity: float = -275.0) -> void:
	body.velocity.y = bounce_velocity
	reset_air_mobility()


func drop_through_one_way(body: CharacterBody2D) -> void:
	if body.is_on_floor():
		body.position.y += 2.0


func step(body: CharacterBody2D, move_dir: float, max_speed: float, delta: float, allow_move: bool = true) -> bool:
	var landed := false
	just_jumped = false
	is_wall_sliding = false
	wall_normal_x = 0.0

	if body.is_on_floor():
		if not was_on_floor and last_fall_speed > 85.0:
			landed = true
		coyote_timer = coyote_time
		air_jumps_left = max_air_jumps
		last_fall_speed = 0.0
		# Keep subtle downward floor-stick pressure so is_on_floor() never flickers while running
		if body.velocity.y >= 0.0:
			body.velocity.y = 12.0
	else:
		coyote_timer = maxf(0.0, coyote_timer - delta)
		# Wall slide detection (pressing toward wall while descending)
		if enable_wall_jump and body.is_on_wall() and body.velocity.y > 0.0:
			var wn := body.get_wall_normal()
			if absf(wn.x) > 0.5 and (move_dir == 0.0 or signf(move_dir) == -signf(wn.x)):
				is_wall_sliding = true
				wall_normal_x = signf(wn.x)

		# Hollow Knight apex hang + crisp faster fall gravity
		var g := gravity
		if absf(body.velocity.y) < apex_velocity_threshold:
			g *= apex_gravity_mult
		elif body.velocity.y > 0.0:
			g *= fall_gravity_mult
		var cap := wall_slide_max_speed if is_wall_sliding else max_fall_speed
		body.velocity.y = minf(cap, body.velocity.y + g * delta)
		if body.velocity.y > last_fall_speed:
			last_fall_speed = body.velocity.y

	was_on_floor = body.is_on_floor()
	body.floor_snap_length = 4.0

	if jump_buffer_timer > 0.0:
		jump_buffer_timer = maxf(0.0, jump_buffer_timer - delta)
		if allow_move:
			if coyote_timer > 0.0:
				body.velocity.y = jump_velocity
				coyote_timer = 0.0
				jump_buffer_timer = 0.0
				just_jumped = true
			elif is_wall_sliding and wall_normal_x != 0.0:
				body.velocity.x = wall_normal_x * wall_jump_velocity.x
				body.velocity.y = wall_jump_velocity.y
				jump_buffer_timer = 0.0
				air_jumps_left = max_air_jumps
				just_jumped = true
			elif air_jumps_left > 0:
				body.velocity.y = air_jump_velocity
				air_jumps_left -= 1
				jump_buffer_timer = 0.0
				just_jumped = true

			if just_jumped and AudioManager and body.is_in_group("player"):
				AudioManager.play_sfx("sfx.jump")

	if allow_move:
		var accel := ground_accel if body.is_on_floor() else air_accel
		var fric := ground_friction if body.is_on_floor() else air_friction
		if absf(move_dir) > 0.01:
			body.velocity.x = move_toward(body.velocity.x, move_dir * max_speed, accel * delta)
		else:
			body.velocity.x = move_toward(body.velocity.x, 0.0, fric * delta)
	else:
		var brake := ground_friction * 0.75 if body.is_on_floor() else air_friction
		body.velocity.x = move_toward(body.velocity.x, 0.0, brake * delta)

	if knockback_velocity.length_squared() > 1.0:
		body.velocity += knockback_velocity
		knockback_velocity = knockback_velocity.move_toward(Vector2.ZERO, 1050.0 * delta)

	body.move_and_slide()
	return landed
