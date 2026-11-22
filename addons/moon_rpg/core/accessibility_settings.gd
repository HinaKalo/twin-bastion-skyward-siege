class_name AccessibilitySettings
extends RefCounted
## Per-channel intensity limits for comfort & accessibility.
##
## Each channel is a 0..1 multiplier applied by the systems that produce the effect
## (camera shake, screen flash, chromatic aberration, rumble/haptics, particle density,
## camera lookahead). `low_flash` clamps flashes hard. `readability_floor` guarantees
## that turning effects off never removes the minimum telegraph / danger cue.

const CHANNELS := ["shake", "flash", "chroma", "rumble", "particles", "camera_lookahead"]

var scales: Dictionary = {}
var low_flash: bool = false
var readability_floor: float = 0.35
var perfect_guard_leniency_frames: int = 0
var command_leniency_frames: int = 0
var subtitles: bool = true
var danger_sound_direction: bool = true
var monochrome_telegraph_shapes: bool = false


func _init() -> void:
	reset()


func reset() -> void:
	for c in CHANNELS:
		scales[c] = 1.0
	low_flash = false
	perfect_guard_leniency_frames = 0
	command_leniency_frames = 0


func set_scale(channel: String, value: float) -> void:
	scales[channel] = clampf(value, 0.0, 1.0)


func get_scale(channel: String) -> float:
	var s := float(scales.get(channel, 1.0))
	if channel == "flash" and low_flash:
		s = minf(s, 0.25)
	return s


## Applies a channel multiplier to an effect intensity.
func apply(channel: String, intensity: float) -> float:
	return intensity * get_scale(channel)


## For telegraph / danger cues: never drops below the readability floor of the authored value.
func apply_readable(channel: String, intensity: float) -> float:
	return maxf(intensity * get_scale(channel), intensity * readability_floor)


func serialize() -> Dictionary:
	return {
		"scales": scales.duplicate(),
		"low_flash": low_flash,
		"perfect_guard_leniency_frames": perfect_guard_leniency_frames,
		"command_leniency_frames": command_leniency_frames,
		"subtitles": subtitles,
		"danger_sound_direction": danger_sound_direction,
		"monochrome_telegraph_shapes": monochrome_telegraph_shapes,
	}


func deserialize(data: Dictionary) -> void:
	for c in (data.get("scales", {}) as Dictionary).keys():
		set_scale(str(c), float(data["scales"][c]))
	low_flash = bool(data.get("low_flash", false))
	perfect_guard_leniency_frames = int(data.get("perfect_guard_leniency_frames", 0))
	command_leniency_frames = int(data.get("command_leniency_frames", 0))
	subtitles = bool(data.get("subtitles", true))
	danger_sound_direction = bool(data.get("danger_sound_direction", true))
	monochrome_telegraph_shapes = bool(data.get("monochrome_telegraph_shapes", false))
