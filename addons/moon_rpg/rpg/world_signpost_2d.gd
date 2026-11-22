class_name WorldSignpost2D
extends Area2D
## Non-Blocking In-World Wooden Signpost (inspired by Duskwood Trail / Classic JRPGs).
## Smoothly displays a crisp readable sign tooltip when the player walks nearby,
## without interrupting gameplay or requiring a button press.

@export var sign_text: String = "前方向导 →"
@export var detect_radius: float = 42.0
@export var post_texture: Texture2D = null

var _bubble: PanelContainer = null
var _label: Label = null
var _player_near: bool = false


func _ready() -> void:
	collision_layer = 0
	collision_mask = 4 # player
	var col := CollisionShape2D.new()
	var circ := CircleShape2D.new()
	circ.radius = detect_radius
	col.shape = circ
	add_child(col)

	if post_texture != null:
		var spr := Sprite2D.new()
		spr.texture = post_texture
		spr.centered = true
		spr.offset = Vector2(0, -12)
		if ThemeManager:
			ThemeManager.apply_pixel_aa(spr)
		add_child(spr)

	_bubble = PanelContainer.new()
	_bubble.position = Vector2(-58, -44)
	_bubble.custom_minimum_size = Vector2(116, 18)
	_bubble.modulate.a = 0.0
	_bubble.z_index = 18
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.16, 0.11, 0.07, 0.92)
	sb.border_color = Color(0.86, 0.72, 0.45, 0.95)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(2)
	sb.set_content_margin_all(3)
	_bubble.add_theme_stylebox_override("panel", sb)
	add_child(_bubble)

	_label = Label.new()
	_label.text = sign_text
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 8)
	_label.add_theme_color_override("font_color", Color(1.0, 0.94, 0.74))
	_bubble.add_child(_label)

	body_entered.connect(func(b):
		if b.is_in_group("player"):
			_player_near = true
	)
	body_exited.connect(func(b):
		if b.is_in_group("player"):
			_player_near = false
	)


func _process(delta: float) -> void:
	if _bubble == null:
		return
	var target_a := 1.0 if _player_near else 0.0
	_bubble.modulate.a = move_toward(_bubble.modulate.a, target_a, delta * 5.0)


func _draw() -> void:
	if post_texture != null:
		return
	# Clean procedural wooden signpost fallback when no external texture is assigned
	draw_rect(Rect2(-2, -16, 4, 18), Color(0.45, 0.29, 0.16))
	draw_rect(Rect2(-10, -22, 20, 10), Color(0.62, 0.42, 0.24))
	draw_rect(Rect2(-10, -22, 20, 10), Color(0.24, 0.15, 0.08), false, 1.5)
