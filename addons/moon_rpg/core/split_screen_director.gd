class_name SplitScreenDirector
extends Control
## Dynamic Split-Screen / Shared-Screen Controller (DOS2 / BG3 couch co-op style).
## Automatically splits into Left/Right views when P1 and P2 move farther than `split_distance`,
## and seamlessly merges back into a single shared screen when closer than `merge_distance`.

signal split_mode_changed(is_split: bool)

@export var split_distance: float = 220.0
@export var merge_distance: float = 170.0

var is_split: bool = false
var target_a: Node2D = null
var target_b: Node2D = null


func set_targets(p1: Node2D, p2: Node2D) -> void:
	target_a = p1
	target_b = p2


## Evaluates current separation with hysteresis to prevent flickering at the threshold boundary.
func evaluate_separation(dist: float) -> bool:
	var prev := is_split
	if not is_split and dist >= split_distance:
		is_split = true
	elif is_split and dist <= merge_distance:
		is_split = false
	if is_split != prev:
		split_mode_changed.emit(is_split)
	return is_split


func _process(_delta: float) -> void:
	if not is_instance_valid(target_a) or not is_instance_valid(target_b):
		if is_split:
			is_split = false
			split_mode_changed.emit(false)
		return
	evaluate_separation(target_a.global_position.distance_to(target_b.global_position))
