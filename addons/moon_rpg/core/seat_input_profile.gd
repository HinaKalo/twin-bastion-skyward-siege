class_name SeatInputProfile
extends RefCounted
## Per-seat analog stick profile: deadzone, press / release thresholds (hysteresis),
## and digital direction extraction that does not chatter around the threshold.
##
## A stick crossing `press_threshold` registers a direction; it only releases once it falls
## back under `release_threshold`. Separate profiles per seat let P1 and P2 tune independently.

var seat: int = 1
var deadzone: float = 0.22
var press_threshold: float = 0.5
var release_threshold: float = 0.3
var invert_y: bool = false
var hold_to_toggle: Dictionary = {} # action -> true when the seat prefers toggle over hold

var _held_x: int = 0
var _held_y: int = 0


func _init(seat_index: int = 1) -> void:
	seat = seat_index


func configure(dz: float, press: float, release: float) -> void:
	deadzone = clampf(dz, 0.0, 0.9)
	press_threshold = clampf(press, deadzone, 1.0)
	release_threshold = clampf(release, deadzone, press_threshold)


## Radial deadzone with rescale to 0..1 outside the deadzone.
func apply_deadzone(v: Vector2) -> Vector2:
	var len := v.length()
	if len <= deadzone:
		return Vector2.ZERO
	var scaled := (len - deadzone) / maxf(0.0001, 1.0 - deadzone)
	return v.normalized() * minf(1.0, scaled)


func _axis_with_hysteresis(value: float, held: int) -> int:
	if held != 0 and signf(value) == float(held) and absf(value) >= release_threshold:
		return held
	if absf(value) >= press_threshold:
		return 1 if value > 0.0 else -1
	return 0


## Digital (-1/0/1, -1/0/1) direction for a raw stick vector, honouring hysteresis.
func digital(raw: Vector2) -> Vector2i:
	var y := -raw.y if invert_y else raw.y
	_held_x = _axis_with_hysteresis(raw.x, _held_x)
	_held_y = _axis_with_hysteresis(y, _held_y)
	return Vector2i(_held_x, _held_y)


func reset() -> void:
	_held_x = 0
	_held_y = 0


func serialize() -> Dictionary:
	return {
		"seat": seat, "deadzone": deadzone, "press_threshold": press_threshold,
		"release_threshold": release_threshold, "invert_y": invert_y, "hold_to_toggle": hold_to_toggle.duplicate(),
	}


func deserialize(data: Dictionary) -> void:
	seat = int(data.get("seat", seat))
	configure(float(data.get("deadzone", deadzone)), float(data.get("press_threshold", press_threshold)), float(data.get("release_threshold", release_threshold)))
	invert_y = bool(data.get("invert_y", false))
	hold_to_toggle = (data.get("hold_to_toggle", {}) as Dictionary).duplicate()
