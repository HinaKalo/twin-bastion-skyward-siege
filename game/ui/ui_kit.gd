class_name UIKit
extends RefCounted
## Shared visual language for Twin Bastion's UI: palette, pixel-bevel panels, outlined text, bars and styled buttons.
## Everything draws at the native 480x270 canvas scale.

const P1 := Color(0.36, 0.82, 1.0)
const P2 := Color(1.0, 0.44, 0.50)
const GOLD := Color(1.0, 0.86, 0.38)
const GOLD_DIM := Color(0.78, 0.64, 0.30)
const INK := Color(0.05, 0.06, 0.12)
const PANEL := Color(0.07, 0.09, 0.19, 0.94)
const PANEL_HI := Color(0.12, 0.15, 0.30, 0.96)
const TEXT := Color(0.94, 0.95, 1.0)
const TEXT_DIM := Color(0.66, 0.70, 0.82)
const GOOD := Color(0.48, 0.95, 0.55)
const BAD := Color(1.0, 0.40, 0.36)


static func pcol(pid: int) -> Color:
	return P1 if pid == 1 else P2


static var _font: Font = null


static func get_font() -> Font:
	if _font == null:
		var tree := Engine.get_main_loop() as SceneTree
		var tm: Node = tree.root.get_node_or_null("ThemeManager") if tree != null else null
		_font = tm.call("get_font") if tm != null else ThemeDB.fallback_font
	return _font


## Pixel-bevel panel: dark fill, 1px outer ink line, 1px colored border, top highlight and clipped corners.
static func draw_panel(canvas: CanvasItem, r: Rect2, border: Color = GOLD_DIM, bg: Color = PANEL) -> void:
	r = Rect2(r.position.round(), r.size.round())
	canvas.draw_rect(Rect2(r.position + Vector2(1, 0), r.size - Vector2(2, 0)), bg)
	canvas.draw_rect(Rect2(r.position + Vector2(0, 1), r.size - Vector2(0, 2)), bg)
	var x0 := r.position.x
	var y0 := r.position.y
	var x1 := r.end.x
	var y1 := r.end.y
	# border (clipped corners)
	canvas.draw_line(Vector2(x0 + 1, y0 + 0.5), Vector2(x1 - 1, y0 + 0.5), border, 1.0)
	canvas.draw_line(Vector2(x0 + 1, y1 - 0.5), Vector2(x1 - 1, y1 - 0.5), border.darkened(0.25), 1.0)
	canvas.draw_line(Vector2(x0 + 0.5, y0 + 1), Vector2(x0 + 0.5, y1 - 1), border, 1.0)
	canvas.draw_line(Vector2(x1 - 0.5, y0 + 1), Vector2(x1 - 0.5, y1 - 1), border.darkened(0.25), 1.0)
	# inner highlight
	canvas.draw_line(Vector2(x0 + 2, y0 + 1.5), Vector2(x1 - 2, y0 + 1.5), Color(1, 1, 1, 0.08), 1.0)


static func draw_text(canvas: CanvasItem, pos: Vector2, text: String, size: int = 7, color: Color = TEXT,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0, outline: bool = true) -> void:
	var font := get_font()
	if align == HORIZONTAL_ALIGNMENT_RIGHT and width < 0.0:
		pos.x -= font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		align = HORIZONTAL_ALIGNMENT_LEFT
	if outline:
		canvas.draw_string_outline(font, pos, text, align, width, size, 3, Color(INK.r, INK.g, INK.b, color.a))
	canvas.draw_string(font, pos, text, align, width, size, color)


static func text_width(text: String, size: int = 7) -> float:
	return get_font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


static func draw_bar(canvas: CanvasItem, r: Rect2, pct: float, fill: Color, back: Color = Color(0.04, 0.05, 0.08, 0.9)) -> void:
	canvas.draw_rect(r.grow(1.0), INK)
	canvas.draw_rect(r, back)
	var w := floorf(r.size.x * clampf(pct, 0.0, 1.0))
	if w > 0.0:
		canvas.draw_rect(Rect2(r.position, Vector2(w, r.size.y)), fill)
		canvas.draw_rect(Rect2(r.position, Vector2(w, 1)), fill.lightened(0.35))


## Small key-cap prompt like [Q].
static func draw_keycap(canvas: CanvasItem, center: Vector2, key: String, size: int = 5, col: Color = TEXT_DIM) -> void:
	var w := maxf(7.0, text_width(key, size) + 4.0)
	var r := Rect2(center - Vector2(w * 0.5, 4), Vector2(w, 8)).abs()
	canvas.draw_rect(r, Color(0.02, 0.03, 0.06, 0.9))
	canvas.draw_rect(r, col, false, 1.0)
	draw_text(canvas, Vector2(r.position.x, r.position.y + 6.5), key, size, col, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, false)


static func make_box(bg: Color, border: Color, border_w: int = 1, margin: int = 4) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(1)
	sb.set_content_margin_all(margin)
	sb.anti_aliasing = false
	return sb


static func style_button(btn: Button, accent: Color, font_size: int = 7) -> void:
	btn.add_theme_stylebox_override("normal", make_box(accent.darkened(0.55), accent.darkened(0.05)))
	btn.add_theme_stylebox_override("hover", make_box(accent.darkened(0.35), GOLD))
	btn.add_theme_stylebox_override("pressed", make_box(accent.darkened(0.70), GOLD))
	btn.add_theme_stylebox_override("focus", make_box(accent.darkened(0.30), GOLD, 2))
	btn.add_theme_stylebox_override("disabled", make_box(Color(0.10, 0.11, 0.16, 0.9), Color(0.26, 0.28, 0.36)))
	btn.add_theme_font_size_override("font_size", font_size)
	btn.add_theme_color_override("font_color", TEXT)
	btn.add_theme_color_override("font_hover_color", Color(1.0, 0.97, 0.80))
	btn.add_theme_color_override("font_disabled_color", Color(0.45, 0.47, 0.56))
	btn.add_theme_constant_override("outline_size", 2)
	btn.add_theme_color_override("font_outline_color", INK)


static func make_button(text: String, accent: Color, min_size: Vector2 = Vector2(60, 18), font_size: int = 7) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_ALL
	style_button(b, accent, font_size)
	return b


static func make_label(text: String, font_size: int = 7, color: Color = TEXT, outline: bool = true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	if outline:
		l.add_theme_constant_override("outline_size", 3)
		l.add_theme_color_override("font_outline_color", INK)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func make_panel(bg: Color = PANEL, border: Color = GOLD_DIM, margin: int = 6) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", make_box(bg, border, 1, margin))
	return p
