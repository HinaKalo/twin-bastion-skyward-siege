class_name StoryDialogue
extends CanvasLayer
## Story overlay. Narrator lines render as full-screen narration; character lines render in a portrait
## dialogue box (P1 / elder on the left, P2 / bosses on the right) with a typewriter effect.
## Click / Enter / Space / gamepad A advances (finishing the current line first); Esc / Tab / gamepad B skips.
## Pauses the SceneTree while active so the battle waits.

signal finished()

const CHARS_PER_SEC := 34.0

var active: bool = false
var _lines: Array = []
var _idx: int = 0
var _shown: float = 0.0
var _t: float = 0.0
var _done_cb: Callable = Callable()
var _board: _Board
var _text: Label
var _was_paused: bool = false


class _Board extends Control:
	var owner_dialog: StoryDialogue

	func _draw() -> void:
		owner_dialog._draw_board(self)


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_board = _Board.new()
	_board.owner_dialog = self
	_board.set_anchors_preset(Control.PRESET_FULL_RECT)
	_board.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_board)
	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_text.add_theme_constant_override("outline_size", 3)
	_text.add_theme_color_override("font_outline_color", UIKit.INK)
	_text.add_theme_constant_override("line_spacing", 1)
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_text)


func _exit_tree() -> void:
	if active and get_tree() != null:
		get_tree().paused = _was_paused


func play(lines: Array, done: Callable = Callable()) -> void:
	if lines.is_empty():
		if done.is_valid():
			done.call()
		return
	_lines = lines
	_idx = 0
	_shown = 0.0
	_done_cb = done
	active = true
	visible = true
	_was_paused = get_tree().paused
	get_tree().paused = true
	_layout_line()


func _process(delta: float) -> void:
	if not active:
		return
	_t += delta
	var full := _current_text().length()
	_shown = minf(float(full), _shown + delta * CHARS_PER_SEC)
	_text.visible_characters = int(_shown)
	_board.queue_redraw()


func _input(event: InputEvent) -> void:
	if not active:
		return
	var advance := false
	var skip := false
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		advance = true
	elif event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		match (event as InputEventKey).keycode:
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				advance = true
			KEY_ESCAPE, KEY_TAB:
				skip = true
	elif event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
		if (event as InputEventJoypadButton).button_index == JOY_BUTTON_A:
			advance = true
		elif (event as InputEventJoypadButton).button_index == JOY_BUTTON_B or (event as InputEventJoypadButton).button_index == JOY_BUTTON_START:
			skip = true
	if not (advance or skip or event is InputEventMouseButton):
		return
	get_viewport().set_input_as_handled()
	if skip:
		_finish()
	elif advance:
		next()


## Finishes the current line, or moves to the next one.
func next() -> void:
	if not active:
		return
	if int(_shown) < _current_text().length():
		_shown = float(_current_text().length())
		return
	_idx += 1
	if _idx >= _lines.size():
		_finish()
		return
	_shown = 0.0
	var audio := get_node_or_null("/root/AudioManager")
	if audio != null:
		audio.call("play_sfx", "sfx.ui_confirm", -14.0, 0.05)
	_layout_line()


func _finish() -> void:
	active = false
	visible = false
	get_tree().paused = _was_paused
	var cb := _done_cb
	_done_cb = Callable()
	finished.emit()
	if cb.is_valid():
		cb.call()


func _current() -> Dictionary:
	return _lines[clampi(_idx, 0, _lines.size() - 1)]


func _current_text() -> String:
	return str(_current().get("text", ""))


func _is_narration() -> bool:
	return str(_current().get("who", "narrator")) == "narrator"


func _layout_line() -> void:
	_text.text = _current_text()
	_text.visible_characters = 0
	if _is_narration():
		_text.position = Vector2(70, 104)
		_text.size = Vector2(340, 60)
		_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_text.add_theme_font_size_override("font_size", 9)
		_text.add_theme_color_override("font_color", Color(0.92, 0.93, 1.0))
	else:
		var sp := StoryData.speaker(str(_current()["who"]))
		var right := str(sp.get("side", "left")) == "right"
		_text.position = Vector2(26 if right else 66, 206)
		_text.size = Vector2(388, 34)
		_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_text.add_theme_font_size_override("font_size", 8)
		_text.add_theme_color_override("font_color", UIKit.TEXT)


func _draw_board(c: Control) -> void:
	if not active:
		return
	var blink := 0.5 + 0.5 * sin(_t * 6.0)
	var done_typing := int(_shown) >= _current_text().length()
	if _is_narration():
		c.draw_rect(Rect2(0, 0, 480, 270), Color(0.01, 0.01, 0.04, 0.92))
		# twin stars motif
		var dim := 1.0 if _idx != 3 else (0.45 + 0.4 * absf(sin(_t * 2.5)))
		c.draw_circle(Vector2(226, 74), 5.0, Color(UIKit.P1.r, UIKit.P1.g, UIKit.P1.b, 0.25))
		c.draw_circle(Vector2(226, 74), 2.0, UIKit.P1.lightened(0.3))
		c.draw_circle(Vector2(254, 70), 5.0, Color(UIKit.P2.r, UIKit.P2.g, UIKit.P2.b, 0.25 * dim))
		c.draw_circle(Vector2(254, 70), 2.0, Color(UIKit.P2.lightened(0.3).r, UIKit.P2.lightened(0.3).g, UIKit.P2.lightened(0.3).b, dim))
		c.draw_rect(Rect2(140, 92, 200, 1), Color(UIKit.GOLD_DIM.r, UIKit.GOLD_DIM.g, UIKit.GOLD_DIM.b, 0.6))
		for i in range(_lines.size()):
			c.draw_rect(Rect2(240 - _lines.size() * 4 + i * 8, 180, 4, 2), UIKit.GOLD if i == _idx else Color(0.4, 0.4, 0.5))
		if done_typing:
			UIKit.draw_text(c, Vector2(0, 200), "点击继续", 6, Color(UIKit.TEXT_DIM.r, UIKit.TEXT_DIM.g, UIKit.TEXT_DIM.b, blink), HORIZONTAL_ALIGNMENT_CENTER, 480)
		UIKit.draw_text(c, Vector2(472, 262), "Esc / B 跳过", 6, UIKit.TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
		return
	var sp := StoryData.speaker(str(_current()["who"]))
	var right := str(sp.get("side", "left")) == "right"
	var col: Color = sp["color"]
	c.draw_rect(Rect2(0, 0, 480, 270), Color(0.0, 0.0, 0.03, 0.30))
	var box := Rect2(12, 192, 456, 52)
	UIKit.draw_panel(c, box, col)
	var pr := Rect2(Vector2(422 if right else 18, 186), Vector2(40, 40))
	c.draw_rect(pr, Color(0.03, 0.04, 0.08))
	var sprite := str(sp.get("sprite", ""))
	if sprite != "":
		var w := float(PixelCreepSprites.get_width(sprite))
		var scale := 2.0 if w <= 16 else 1.5
		var tex := PixelCreepSprites.get_frame(sprite, 0, int(sp.get("owner", 0)), right)
		var size := Vector2(w, w) * scale
		var bob := sin(_t * 3.0) * 1.0 if not done_typing else 0.0
		c.draw_texture_rect(tex, Rect2(pr.get_center() - size * 0.5 + Vector2(0, 2 + bob), size), false)
	c.draw_rect(pr, col, false, 1.0)
	var name := str(sp.get("name", ""))
	var nw := UIKit.text_width(name, 7) + 12.0
	var nx := pr.position.x - nw - 6.0 if right else pr.end.x + 6.0
	var nr := Rect2(nx, 187, nw, 12)
	c.draw_rect(nr, Color(0.03, 0.04, 0.08))
	c.draw_rect(nr, col, false, 1.0)
	UIKit.draw_text(c, nr.position + Vector2(6, 9), name, 7, col)
	if done_typing:
		var ax := 408.0 if not right else 36.0
		c.draw_colored_polygon(PackedVector2Array([Vector2(ax - 3, 236), Vector2(ax + 3, 236), Vector2(ax, 239 + blink)]), UIKit.GOLD)
	var hint := "点击 / Enter / A 继续 · Esc 跳过"
	if right:
		UIKit.draw_text(c, Vector2(box.position.x + 6, box.position.y + 9), hint, 5, UIKit.TEXT_DIM)
	else:
		UIKit.draw_text(c, Vector2(box.end.x - 6, box.position.y + 9), hint, 5, UIKit.TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
