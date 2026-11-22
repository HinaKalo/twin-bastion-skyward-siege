extends Node
## Unified UI Font & Theme Manager for MoonRPG Engine.
##
## Works together with `window/stretch/mode = "canvas_items"` so pixel art stays
## razor-sharp Nearest-Neighbor while CJK / Latin UI text renders at full native
## window resolution (720p / 1080p / 4K).
##
## Font resolution priority:
##   1. Explicit runtime call: `MoonRPG.set_font("res://.../font.ttf", pixel_sharp)`
##   2. Active Asset Pack manifest: `pack.json -> "font"` (string path or {file, pixel_sharp})
##   3. Built-in crisp System CJK fallback (`Microsoft YaHei UI` / `PingFang SC` / `Noto Sans CJK SC`)

const SIZE_XS := 8
const SIZE_SM := 9
const SIZE_MD := 10
const SIZE_LG := 12

const DEFAULT_CJK_FAMILIES := [
	"Microsoft YaHei UI",
	"Microsoft YaHei",
	"PingFang SC",
	"Noto Sans CJK SC",
	"Source Han Sans SC",
	"SimHei",
]

var active_font: Font = null
var active_theme: Theme = null
var _pixel_aa_mat: ShaderMaterial = null


func get_pixel_aa_material() -> ShaderMaterial:
	if _pixel_aa_mat == null:
		var sh_path := "res://addons/moon_rpg/core/shaders/pixel_art_aa.gdshader"
		if ResourceLoader.exists(sh_path):
			_pixel_aa_mat = ShaderMaterial.new()
			_pixel_aa_mat.shader = ResourceLoader.load(sh_path)
	return _pixel_aa_mat


## Applies Sharp-Bilinear Pixel-Art AA to a Sprite2D / AnimatedSprite2D / TileMapLayer,
## eliminating pixel shimmer & mixel crawl while keeping pixel art razor-sharp at any resolution.
func apply_pixel_aa(item: CanvasItem) -> void:
	if item == null:
		return
	var mat := get_pixel_aa_material()
	if mat != null:
		item.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		item.material = mat


## Applies a high-contrast golden focus ring and circular D-Pad/Stick focus neighbors
## across a list of enabled Buttons, and grabs focus on the first enabled button.
func apply_gamepad_focus_chain(buttons: Array, horizontal: bool = false, auto_focus: bool = true) -> Button:
	var focus_sb := StyleBoxFlat.new()
	focus_sb.bg_color = Color(0.20, 0.34, 0.62, 0.95)
	focus_sb.border_color = Color(1.0, 0.90, 0.28, 1.0)
	focus_sb.set_border_width_all(2)
	focus_sb.set_corner_radius_all(2)

	var enabled: Array[Button] = []
	for item in buttons:
		if item is Button and not item.is_queued_for_deletion() and not (item as Button).disabled:
			var b := item as Button
			b.focus_mode = Control.FOCUS_ALL
			b.add_theme_stylebox_override("focus", focus_sb)
			enabled.append(b)

	var n := enabled.size()
	for i in range(n):
		var prev_b := enabled[(i - 1 + n) % n]
		var next_b := enabled[(i + 1) % n]
		if horizontal:
			enabled[i].focus_neighbor_left = enabled[i].get_path_to(prev_b)
			enabled[i].focus_neighbor_right = enabled[i].get_path_to(next_b)
		else:
			enabled[i].focus_neighbor_top = enabled[i].get_path_to(prev_b)
			enabled[i].focus_neighbor_bottom = enabled[i].get_path_to(next_b)

	if auto_focus and not enabled.is_empty():
		enabled[0].call_deferred("grab_focus")
		return enabled[0]
	return enabled[0] if not enabled.is_empty() else null


func _ready() -> void:
	active_theme = Theme.new()
	apply_from_pack()


func get_font() -> Font:
	if active_font != null:
		return active_font
	return ThemeDB.fallback_font


func apply_from_pack() -> void:
	if AssetRegistry != null:
		var font_meta: Variant = AssetRegistry.get_font_meta()
		if typeof(font_meta) == TYPE_STRING and not str(font_meta).is_empty():
			if load_font_file(AssetRegistry.resolve_path(str(font_meta)), false):
				return
		elif typeof(font_meta) == TYPE_DICTIONARY and font_meta.has("file"):
			var fpath := AssetRegistry.resolve_path(str(font_meta["file"]))
			var is_pixel := bool(font_meta.get("pixel_sharp", false))
			if load_font_file(fpath, is_pixel):
				return
	use_system_cjk_font()


func load_font_file(path: String, pixel_sharp: bool = false) -> bool:
	var font_res: Font = null
	if ResourceLoader.exists(path):
		var loaded := ResourceLoader.load(path)
		if loaded is Font:
			font_res = loaded
	if font_res == null:
		var abs_path := ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(abs_path):
			var ff := FontFile.new()
			if ff.load_dynamic_font(abs_path) == OK:
				font_res = ff
	if font_res == null:
		push_warning("[ThemeManager] Failed to load font: %s" % path)
		return false

	if font_res is FontFile:
		var ff := font_res as FontFile
		if pixel_sharp:
			ff.antialiasing = TextServer.FONT_ANTIALIASING_NONE
			ff.hinting = TextServer.HINTING_NONE
			ff.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
		else:
			ff.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
			ff.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO

	_apply_font(font_res)
	return true


func use_system_cjk_font(families: PackedStringArray = PackedStringArray(DEFAULT_CJK_FAMILIES)) -> void:
	var sf := SystemFont.new()
	sf.font_names = families
	sf.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	sf.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	sf.hinting = TextServer.HINTING_LIGHT
	_apply_font(sf)


func _apply_font(font: Font) -> void:
	active_font = font
	if active_theme == null:
		active_theme = Theme.new()
	active_theme.default_font = font
	active_theme.default_font_size = SIZE_SM

	for ctrl_type in ["Label", "Button", "RichTextLabel"]:
		active_theme.set_font("font", ctrl_type, font)
	active_theme.set_font("normal_font", "RichTextLabel", font)
	active_theme.set_font("bold_font", "RichTextLabel", font)

	var root_vp := get_tree().root if get_tree() != null else null
	if root_vp != null:
		root_vp.theme = active_theme


func _exit_tree() -> void:
	var root_vp := get_tree().root if get_tree() != null else null
	if root_vp != null and root_vp.theme == active_theme:
		root_vp.theme = null
	active_font = null
	active_theme = null
