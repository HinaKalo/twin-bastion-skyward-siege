class_name DialogueBox
extends Control
## Nine-Slice Branching Dialogue Window with Portrait, Typewriter Text, and Choices.
## Driven automatically by DialogueRunner signals via EventBus.

var _panel: PanelContainer
var _portrait_rect: TextureRect
var _speaker_label: Label
var _body_label: RichTextLabel
var _choices_box: VBoxContainer
var _hint_label: Label

var _full_text: String = ""
var _visible_chars: float = 0.0
var _typing: bool = false
var _has_choices: bool = false


func _ready() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	offset_left = 18
	offset_right = -18
	offset_top = -114
	offset_bottom = -6

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sb := AssetRegistry.get_ui_stylebox("panel_dialog", 8.0) if AssetRegistry else null
	if sb != null:
		_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	_panel.add_child(hbox)

	_portrait_rect = TextureRect.new()
	_portrait_rect.custom_minimum_size = Vector2(56, 56)
	_portrait_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hbox.add_child(_portrait_rect)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 3)
	hbox.add_child(vbox)

	_speaker_label = Label.new()
	_speaker_label.add_theme_font_size_override("font_size", 10)
	_speaker_label.add_theme_color_override("font_color", Color(0.96, 0.78, 0.25))
	_speaker_label.add_theme_constant_override("outline_size", 2)
	_speaker_label.add_theme_color_override("font_outline_color", Color(0.1, 0.07, 0.05))
	vbox.add_child(_speaker_label)

	_body_label = RichTextLabel.new()
	_body_label.bbcode_enabled = false
	_body_label.fit_content = true
	_body_label.scroll_active = false
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_label.custom_minimum_size = Vector2(0, 26)
	_body_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body_label.add_theme_font_size_override("normal_font_size", 9)
	_body_label.add_theme_color_override("default_color", Color(0.16, 0.12, 0.09))
	vbox.add_child(_body_label)

	_choices_box = VBoxContainer.new()
	_choices_box.add_theme_constant_override("separation", 2)
	vbox.add_child(_choices_box)

	_hint_label = Label.new()
	_hint_label.text = "[E / Space] 继续"
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint_label.add_theme_font_size_override("font_size", 7)
	_hint_label.add_theme_color_override("font_color", Color(0.4, 0.32, 0.24))
	vbox.add_child(_hint_label)

	if EventBus:
		EventBus.dialogue_line_presented.connect(_on_line_presented)
		EventBus.dialogue_ended.connect(_on_dialogue_ended)


func _on_line_presented(payload: Dictionary) -> void:
	visible = true
	_speaker_label.text = str(payload.get("speaker", ""))
	_full_text = str(payload.get("text", ""))
	_body_label.text = _full_text
	_body_label.visible_characters = 0
	_visible_chars = 0.0
	_typing = true

	var pkey := str(payload.get("portrait_key", ""))
	var tex := AssetRegistry.get_portrait(pkey) if (AssetRegistry and not pkey.is_empty()) else null
	_portrait_rect.texture = tex
	_portrait_rect.visible = tex != null

	for c in _choices_box.get_children():
		c.queue_free()
	var choices: Array = payload.get("choices", [])
	_has_choices = not choices.is_empty()
	_choices_box.visible = false
	_hint_label.visible = not _has_choices
	if InputManager != null and InputManager.is_using_gamepad():
		_hint_label.text = "%s 继续" % InputManager.get_prompt("jump")
	else:
		_hint_label.text = "[E / Space] 继续"

	for i in range(choices.size()):
		var btn := Button.new()
		btn.text = "%d. %s" % [i + 1, str(choices[i].get("text", ""))]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 8)
		var idx := i
		btn.pressed.connect(func():
			if AudioManager:
				AudioManager.play_sfx("sfx.ui_confirm")
			DialogueRunner.advance(idx)
		)
		_choices_box.add_child(btn)


func _on_dialogue_ended(_dialogue_id: String) -> void:
	visible = false
	_typing = false


func _process(delta: float) -> void:
	if not visible or not _typing:
		return
	_visible_chars += 42.0 * delta
	_body_label.visible_characters = int(_visible_chars)
	if int(_visible_chars) >= _full_text.length():
		_finish_typing()


func _finish_typing() -> void:
	_typing = false
	_body_label.visible_characters = -1
	if _has_choices:
		_choices_box.visible = true
		if _choices_box.get_child_count() > 0:
			(_choices_box.get_child(0) as Control).grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("jump") or event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		if _typing:
			_finish_typing()
		elif _has_choices:
			_activate_focused_choice()
		else:
			if AudioManager:
				AudioManager.play_sfx("sfx.ui_confirm")
			DialogueRunner.advance(-1)
	elif event.is_action_pressed("ui_cancel") and _typing:
		get_viewport().set_input_as_handled()
		_finish_typing()
	elif _has_choices and not _typing:
		for i in range(mini(4, _choices_box.get_child_count())):
			if event.is_action_pressed("hotbar_%d" % (i + 1)):
				get_viewport().set_input_as_handled()
				if AudioManager:
					AudioManager.play_sfx("sfx.ui_confirm")
				DialogueRunner.advance(i)
				break


func _activate_focused_choice() -> void:
	var count := _choices_box.get_child_count()
	if count == 0:
		return
	var focused := get_viewport().gui_get_focus_owner()
	var idx := 0
	for i in range(count):
		if _choices_box.get_child(i) == focused:
			idx = i
			break
	if AudioManager:
		AudioManager.play_sfx("sfx.ui_confirm")
	DialogueRunner.advance(idx)
