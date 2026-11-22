class_name FloatingText
extends Node2D
## Animated floating combat number (damage, crit, parry, heal, poison).

var _label: Label
var _vel: Vector2 = Vector2(0, -34)
var _life: float = 0.72
var _elapsed: float = 0.0


func setup(text: String, style: String = "damage") -> void:
	z_index = 60
	_label = Label.new()
	_label.text = text
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.position = Vector2(-24, -8)
	_label.custom_minimum_size = Vector2(48, 16)
	_label.add_theme_font_size_override("font_size", 11 if style == "crit" or style == "parry" else 9)
	_label.add_theme_constant_override("outline_size", 2)
	_label.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.08, 0.95))

	match style:
		"crit":
			_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.22))
			_vel = Vector2(0, -46)
		"parry":
			_label.add_theme_color_override("font_color", Color(0.45, 0.95, 1.0))
			_vel = Vector2(0, -42)
		"heal":
			_label.add_theme_color_override("font_color", Color(0.35, 0.95, 0.45))
		"poison":
			_label.add_theme_color_override("font_color", Color(0.75, 0.35, 0.95))
		_:
			_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	add_child(_label)


func _process(delta: float) -> void:
	_elapsed += delta
	position += _vel * delta
	_vel.y *= pow(0.18, delta)
	var t := clampf(_elapsed / _life, 0.0, 1.0)
	modulate.a = 1.0 - maxf(0.0, (t - 0.55) / 0.45)
	if _elapsed >= _life:
		queue_free()
