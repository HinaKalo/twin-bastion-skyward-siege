class_name EmoteBubble2D
extends Node2D
## Classic JRPG Overhead Emote Bubble (! / ? / ♥ / ... / 💢 / 💧).
## Attach temporarily above any NPC or Party member during cutscenes or field aggro.

const EMOTE_TABLE := {
	"alert": ["!", Color(1.0, 0.28, 0.22)],
	"question": ["?", Color(0.35, 0.78, 1.0)],
	"heart": ["♥", Color(1.0, 0.42, 0.62)],
	"sweat": ["💧", Color(0.45, 0.85, 1.0)],
	"silence": ["...", Color(0.85, 0.85, 0.90)],
	"anger": ["💢", Color(1.0, 0.35, 0.20)],
}

var _label: Label
var _life: float = 1.2
var _elapsed: float = 0.0


func setup(emote_type: String = "alert", duration: float = 1.2) -> void:
	z_index = 55
	_life = maxf(0.15, duration)
	var spec: Array = EMOTE_TABLE.get(emote_type, [emote_type, Color.WHITE])

	_label = Label.new()
	_label.text = str(spec[0])
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.position = Vector2(-12, -14)
	_label.custom_minimum_size = Vector2(24, 16)
	_label.add_theme_font_size_override("font_size", 10)
	_label.add_theme_color_override("font_color", spec[1])
	_label.add_theme_constant_override("outline_size", 2)
	_label.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.08))
	add_child(_label)
	scale = Vector2(0.4, 0.4)


func _draw() -> void:
	draw_circle(Vector2(0, -6), 9.0, Color(0.98, 0.96, 0.90, 0.94))
	draw_arc(Vector2(0, -6), 9.0, 0.0, TAU, 16, Color(0.18, 0.14, 0.12), 1.2)


func _process(delta: float) -> void:
	_elapsed += delta
	scale = scale.lerp(Vector2.ONE, clampf(16.0 * delta, 0.0, 1.0))
	if _elapsed >= _life:
		queue_free()
