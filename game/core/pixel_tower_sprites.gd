class_name PixelTowerSprites
extends RefCounted
## Hand-Crafted Procedural 32x32 Pixel-Art Sprite Sheet Generator for Twin Bastion TD.
## Generates authentic 1px-outlined, multi-tone shaded pixel-art ImageTextures (matching
## KOEI / Kingdom Rush pixel density) for:
## - 4 Tower Types × 2 Owners (P1 Sapphire / P2 Crimson) with brick masonry, timber grain,
##   shingled roofs, glowing arcane crystals, glacier facets, and iron-bound fortress gates!
## - Carved Stone Build Pad Pedestals (Blue / Crimson / Gold)
## - Wooden Lantern Bridge Tiles & Lily Pads.

static var _cache: Dictionary = {}


## Tiered tower sprite (32x40): base art + Lv2 gold trims + a distinct Lv3 silhouette per branch.
static func get_tower_texture(tid: String, owner: int, level: int = 1, branch: String = "") -> ImageTexture:
	var key := "tier_%s_%d_%d_%s" % [tid, owner, level, branch]
	if _cache.has(key):
		return _cache[key]
	var base := _get_base_image(tid, owner)
	var img := Image.create(32, 40, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	img.blit_rect(base, Rect2i(0, 0, 32, 36), Vector2i(0, 4))
	var accent := Color(0.24, 0.72, 1.0) if owner == 1 else Color(0.96, 0.30, 0.36)
	if level >= 2:
		_paint_lv2(img, tid, accent)
	if level >= 3:
		_paint_branch(img, branch, accent)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


static func _get_base_image(tid: String, owner: int) -> Image:
	var key := "base_%s_%d" % [tid, owner]
	if _cache.has(key):
		return _cache[key]
	var img := Image.create(32, 36, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var accent := Color(0.24, 0.72, 1.0) if owner == 1 else Color(0.96, 0.30, 0.36)
	var accent_hi := accent.lightened(0.32)
	var accent_dk := accent.darkened(0.38)

	match tid:
		"arrow":
			_paint_arrow_tower(img, accent, accent_hi, accent_dk)
		"mage":
			_paint_mage_tower(img, accent, accent_hi, accent_dk)
		"frost":
			_paint_frost_tower(img, accent, accent_hi, accent_dk)
		"barracks":
			_paint_barracks_tower(img, accent, accent_hi, accent_dk)
	_cache[key] = img
	return img


const GOLD := Color(0.98, 0.80, 0.30)
const GOLD_HI := Color(1.0, 0.95, 0.62)
const INK := Color(0.08, 0.06, 0.10)


static func _paint_lv2(img: Image, tid: String, accent: Color) -> void:
	# gold trim band on the plinth + corner studs
	for x in range(7, 25):
		_px(img, x, 31, GOLD if x % 3 != 0 else GOLD_HI)
	_px(img, 6, 32, GOLD_HI)
	_px(img, 25, 32, GOLD_HI)
	match tid:
		"arrow":
			for y in range(6, 13):
				_px(img, 16, y, GOLD)
			_rect_px(img, 14, 4, 4, 2, GOLD_HI)
		"mage":
			_rect_px(img, 8, 12, 2, 6, GOLD)
			_rect_px(img, 22, 12, 2, 6, GOLD)
			_px(img, 8, 11, GOLD_HI)
			_px(img, 23, 11, GOLD_HI)
		"frost":
			for sx in [10, 22]:
				for y in range(14, 22):
					_px(img, sx, y, Color(0.80, 0.96, 1.0))
				_px(img, sx, 13, Color.WHITE)
		"barracks":
			for mx in [4, 10, 16, 22]:
				_rect_px(img, mx, 13, 5, 1, GOLD)
			_rect_px(img, 6, 6, 1, 8, GOLD)
			_rect_px(img, 7, 6, 5, 3, accent)


static func _diamond(img: Image, cx: int, cy: int, r: int, light: Color, dark: Color, edge: Color) -> void:
	for dy in range(-r, r + 1):
		var w: int = r - absi(dy)
		for dx in range(-w, w + 1):
			var c := light if dx < 0 else dark
			if absi(dx) == w:
				c = edge
			_px(img, cx + dx, cy + dy, c)


static func _paint_branch(img: Image, branch: String, accent: Color) -> void:
	match branch:
		"sniper":
			# needle spire + long ballista arms across the parapet + eagle crest
			for y in range(0, 6):
				_px(img, 15, y, INK)
				_px(img, 16, y, GOLD if y > 0 else GOLD_HI)
				_px(img, 17, y, INK)
			for x in range(1, 31):
				_px(img, x, 15, Color(0.30, 0.18, 0.08))
				_px(img, x, 16, INK if x < 3 or x > 28 else Color(0.48, 0.30, 0.14))
			for k in range(3):
				_px(img, 1, 13 + k, INK)
				_px(img, 30, 13 + k, INK)
			_rect_px(img, 14, 21, 4, 3, GOLD)
			_px(img, 13, 21, GOLD_HI)
			_px(img, 18, 21, GOLD_HI)
		"repeater":
			# twin crossbow boxes on the parapet + bolt racks
			for bx in [0, 26]:
				_rect_px(img, bx, 13, 6, 6, accent.darkened(0.2))
				_outline(img, bx, 13, 6, 6, INK)
				for k in range(3):
					_px(img, bx + 1 + k * 2, 15, Color(0.92, 0.92, 0.96))
					_px(img, bx + 1 + k * 2, 16, Color(0.60, 0.40, 0.20))
			_rect_px(img, 13, 3, 6, 2, GOLD)
		"arcane":
			_diamond(img, 16, 10, 7, Color(0.80, 0.90, 1.0), Color(0.45, 0.40, 1.0), Color(0.16, 0.10, 0.42))
			_px(img, 14, 7, Color.WHITE)
			_px(img, 14, 8, Color.WHITE)
			_diamond(img, 4, 8, 2, Color(0.85, 0.75, 1.0), Color(0.55, 0.35, 0.95), Color(0.20, 0.10, 0.40))
			_diamond(img, 27, 8, 2, Color(0.85, 0.75, 1.0), Color(0.55, 0.35, 0.95), Color(0.20, 0.10, 0.40))
		"inferno":
			_diamond(img, 16, 10, 6, Color(1.0, 0.92, 0.45), Color(1.0, 0.42, 0.12), Color(0.45, 0.10, 0.04))
			_px(img, 15, 7, Color.WHITE)
			_rect_px(img, 7, 29, 18, 2, Color(0.95, 0.45, 0.12))
			for ex in [9, 13, 19, 23]:
				_px(img, ex, 28, Color(1.0, 0.85, 0.30))
		"glacier":
			for y in range(0, 12):
				var half: int = 1 + y / 3
				for x in range(16 - half, 16 + half):
					_px(img, x, y, Color(0.92, 1.0, 1.0) if x < 16 else Color(0.55, 0.85, 1.0))
				_px(img, 16 - half - 1, y, Color(0.08, 0.20, 0.34))
				_px(img, 16 + half, y, Color(0.08, 0.20, 0.34))
			for sx in [4, 27]:
				for y in range(12, 22):
					_px(img, sx, y, Color(0.80, 0.96, 1.0))
					_px(img, sx + 1, y, Color(0.45, 0.78, 0.98))
		"blizzard":
			var cx := 16
			var cy := 5
			for k in range(-4, 5):
				_px(img, cx + k, cy, Color.WHITE)
				_px(img, cx, cy + k, Color.WHITE)
				_px(img, cx + k, cy + k, Color(0.70, 0.92, 1.0))
				_px(img, cx + k, cy - k, Color(0.70, 0.92, 1.0))
			for sx in [2, 28]:
				for y in range(16, 26):
					_px(img, sx, y, Color(0.70, 0.92, 1.0))
					_px(img, sx + 1, y, Color(0.40, 0.70, 0.95))
		"paladin":
			for mx in [4, 10, 16, 22]:
				_rect_px(img, mx, 13, 5, 4, GOLD)
				_outline(img, mx, 13, 5, 4, INK)
			_rect_px(img, 12, 17, 8, 7, Color(0.98, 0.96, 0.86))
			_rect_px(img, 15, 18, 2, 5, GOLD)
			_rect_px(img, 13, 20, 6, 1, GOLD)
			_outline(img, 12, 17, 8, 7, GOLD)
		"ranger":
			for sx in range(3, 29, 3):
				_rect_px(img, sx, 10, 2, 4, Color(0.50, 0.32, 0.16))
				_px(img, sx, 9, INK)
			_rect_px(img, 17, 6, 9, 5, Color(0.26, 0.58, 0.30))
			_rect_px(img, 17, 6, 9, 1, Color(0.50, 0.80, 0.45))
			for k in range(6):
				_px(img, 13 + k, 18 + k, Color(0.62, 0.42, 0.20))
				_px(img, 18 - k, 18 + k, Color(0.62, 0.42, 0.20))


static func get_pad_texture(owner_hint: int) -> ImageTexture:
	var key := "pad_%d" % owner_hint
	if _cache.has(key):
		return _cache[key]
	var img := Image.create(28, 22, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rune := Color(0.36, 0.80, 1.0) if owner_hint == 1 else (Color(1.0, 0.42, 0.46) if owner_hint == 2 else Color(1.0, 0.88, 0.36))
	var cx := 14.0
	var cy := 11.0
	for y in range(22):
		for x in range(28):
			var dx := (float(x) - cx) / 12.5
			var dy := (float(y) - cy) / 8.8
			var d := dx * dx + dy * dy
			if d > 1.0:
				continue
			if d > 0.82:
				img.set_pixel(x, y, Color(0.14, 0.14, 0.18, 0.95)) # dark pixel outline
			elif d > 0.66:
				var rim := Color(0.42, 0.44, 0.50) if y < 11 else Color(0.28, 0.30, 0.36)
				img.set_pixel(x, y, rim)
			else:
				# Carved flagstone brick pattern
				var brick := ((x / 5) + (y / 4)) % 2 == 0
				var base := Color(0.34, 0.36, 0.42) if brick else Color(0.29, 0.31, 0.37)
				if y == 11 and absf(float(x) - cx) < 9.0:
					base = base.darkened(0.18)
				img.set_pixel(x, y, base)
	# Glowing center build cross rune
	for i in range(-3, 4):
		img.set_pixel(14 + i, 11, rune)
		img.set_pixel(14, 11 + i, rune)
	img.set_pixel(14, 11, Color.WHITE)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


static func _px(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and x < img.get_width() and y >= 0 and y < img.get_height():
		img.set_pixel(x, y, c)


static func _rect_px(img: Image, x0: int, y0: int, w: int, h: int, c: Color) -> void:
	for y in range(y0, y0 + h):
		for x in range(x0, x0 + w):
			_px(img, x, y, c)


static func _outline(img: Image, x0: int, y0: int, w: int, h: int, c: Color) -> void:
	for x in range(x0, x0 + w):
		_px(img, x, y0, c)
		_px(img, x, y0 + h - 1, c)
	for y in range(y0, y0 + h):
		_px(img, x0, y, c)
		_px(img, x0 + w - 1, y, c)


static func _paint_arrow_tower(img: Image, ac: Color, ac_hi: Color, ac_dk: Color) -> void:
	var ink := Color(0.11, 0.08, 0.06)
	var wood_dk := Color(0.36, 0.22, 0.11)
	var wood_md := Color(0.54, 0.35, 0.18)
	var wood_hi := Color(0.72, 0.50, 0.26)
	var stone_dk := Color(0.36, 0.38, 0.44)
	var stone_md := Color(0.52, 0.55, 0.62)

	# Stone foundation plinth (y = 27..33)
	_rect_px(img, 6, 27, 20, 6, stone_md)
	for x in range(7, 25, 4):
		_px(img, x, 28, stone_dk)
		_px(img, x + 2, 30, stone_dk)
	_outline(img, 6, 27, 20, 6, ink)

	# Timber tower shaft with vertical wood planks & cross-bracing (y = 14..27)
	_rect_px(img, 8, 14, 16, 14, wood_md)
	for x in [10, 14, 18, 21]:
		_rect_px(img, x, 15, 1, 12, wood_dk)
	_rect_px(img, 9, 15, 2, 12, wood_hi)
	# Arrow slit window
	_rect_px(img, 15, 18, 2, 5, Color(0.10, 0.08, 0.12))
	_outline(img, 8, 14, 16, 14, ink)

	# Overhanging crenelated archer parapet (y = 9..15)
	_rect_px(img, 5, 10, 22, 5, wood_hi)
	_rect_px(img, 6, 13, 20, 2, wood_dk)
	_outline(img, 5, 10, 22, 5, ink)
	for mx in [5, 11, 17, 23]:
		_rect_px(img, mx, 8, 4, 3, wood_hi)
		_outline(img, mx, 8, 4, 3, ink)

	# Shingled pointed roof in owner heraldic color (y = 1..9)
	for row in range(8):
		var half := 1 + row
		var y := 2 + row
		for x in range(16 - half, 16 + half):
			var c := ac_hi if x < 15 else (ac if x < 17 else ac_dk)
			if row % 2 == 1 and (x + row) % 3 == 0:
				c = c.darkened(0.16)
			_px(img, x, y, c)
		_px(img, 16 - half, y, ink)
		_px(img, 16 + half - 1, y, ink)
	_px(img, 15, 1, Color(1.0, 0.92, 0.42))
	_px(img, 16, 1, Color(1.0, 0.92, 0.42))


static func _paint_mage_tower(img: Image, ac: Color, ac_hi: Color, _ac_dk: Color) -> void:
	var ink := Color(0.08, 0.06, 0.14)
	var st_dk := Color(0.18, 0.15, 0.28)
	var st_md := Color(0.28, 0.24, 0.44)
	var st_hi := Color(0.42, 0.36, 0.62)
	var gold := Color(0.95, 0.80, 0.32)

	# Stepped obsidian pedestal
	_rect_px(img, 5, 28, 22, 5, st_dk)
	_outline(img, 5, 28, 22, 5, ink)

	# Tapered arcane stone spire (y = 12..28)
	for y in range(12, 28):
		var inset := 7 if y > 22 else (8 if y > 16 else 9)
		for x in range(inset, 32 - inset):
			var c := st_hi if x < inset + 3 else (st_md if x < 29 - inset else st_dk)
			if (y % 4 == 0) or ((x + (y / 4) * 3) % 5 == 0):
				c = c.darkened(0.14)
			_px(img, x, y, c)
		_px(img, inset, y, ink)
		_px(img, 31 - inset, y, ink)

	# Glowing owner rune band & arched window
	_rect_px(img, 14, 17, 4, 7, ac)
	_rect_px(img, 15, 18, 2, 5, ac_hi)
	_rect_px(img, 8, 25, 16, 2, gold)

	# Arcane cradle prongs holding floating violet crystal (y = 2..12)
	_rect_px(img, 9, 9, 2, 4, gold)
	_rect_px(img, 21, 9, 2, 4, gold)
	# Faceted glowing crystal diamond
	for dy in range(-5, 6):
		var w: int = 5 - absi(dy)
		for dx in range(-w, w + 1):
			var col := Color(0.96, 0.70, 1.0) if dx < 0 else Color(0.70, 0.28, 0.96)
			if absi(dx) == w:
				col = Color(0.28, 0.10, 0.44)
			_px(img, 16 + dx, 6 + dy, col)
	_px(img, 15, 4, Color.WHITE)
	_px(img, 15, 5, Color.WHITE)


static func _paint_frost_tower(img: Image, ac: Color, ac_hi: Color, _ac_dk: Color) -> void:
	var ink := Color(0.08, 0.16, 0.26)
	var ice_dk := Color(0.20, 0.54, 0.80)
	var ice_md := Color(0.42, 0.82, 0.96)
	var ice_hi := Color(0.78, 0.96, 1.0)

	# Snow-dusted stone base
	_rect_px(img, 6, 27, 20, 6, Color(0.44, 0.52, 0.62))
	_rect_px(img, 7, 27, 18, 2, Color(0.88, 0.95, 1.0))
	_outline(img, 6, 27, 20, 6, ink)

	# Main crystalline glacier obelisk (y = 3..27)
	for y in range(3, 27):
		var half := mini(8, 1 + (y - 3) / 3 + (2 if y > 14 else 0))
		for x in range(16 - half, 16 + half):
			var c := ice_hi if x < 15 else (ice_md if x < 18 else ice_dk)
			if (x - y) % 6 == 0:
				c = c.lightened(0.18)
			_px(img, x, y, c)
		_px(img, 16 - half, y, ink)
		_px(img, 16 + half - 1, y, ink)

	# Side ice shards + owner emblem crystal
	for y in range(15, 27):
		_px(img, 6, y, ice_md)
		_px(img, 7, y, ice_hi)
		_px(img, 24, y, ice_dk)
		_px(img, 25, y, ice_md)
	_rect_px(img, 13, 19, 6, 6, ac)
	_rect_px(img, 14, 20, 3, 3, ac_hi)
	_px(img, 16, 4, Color.WHITE)
	_px(img, 16, 5, Color.WHITE)


static func _paint_barracks_tower(img: Image, ac: Color, ac_hi: Color, ac_dk: Color) -> void:
	var ink := Color(0.10, 0.10, 0.14)
	var st_dk := Color(0.36, 0.38, 0.44)
	var st_md := Color(0.56, 0.58, 0.65)
	var st_hi := Color(0.74, 0.76, 0.82)
	var gold := Color(0.96, 0.80, 0.30)

	# Heavy stone bastion body (y = 12..33)
	_rect_px(img, 4, 12, 24, 21, st_md)
	_rect_px(img, 5, 13, 3, 19, st_hi)
	_rect_px(img, 24, 13, 3, 19, st_dk)
	# Brick courses
	for y in range(15, 32, 4):
		for x in range(5, 27):
			_px(img, x, y, st_dk)
		for x in range(6 + ((y / 4) % 2) * 3, 26, 6):
			_rect_px(img, x, y - 3, 1, 3, st_dk)
	_outline(img, 4, 12, 24, 21, ink)

	# Crenellations on roof
	for mx in [4, 10, 16, 22]:
		_rect_px(img, mx, 9, 5, 4, st_hi)
		_outline(img, mx, 9, 5, 4, ink)

	# Iron-bound arched wooden garrison gate (y = 21..32)
	_rect_px(img, 11, 22, 10, 10, Color(0.30, 0.18, 0.10))
	_rect_px(img, 12, 21, 8, 1, Color(0.30, 0.18, 0.10))
	for gx in [13, 16, 19]:
		_rect_px(img, gx, 22, 1, 10, Color(0.18, 0.10, 0.06))
	_rect_px(img, 11, 25, 10, 1, Color(0.24, 0.26, 0.32))
	_rect_px(img, 11, 29, 10, 1, Color(0.24, 0.26, 0.32))
	_outline(img, 11, 21, 10, 12, ink)

	# Heraldic Shield Emblem above gate
	_rect_px(img, 13, 14, 6, 5, ac)
	_rect_px(img, 14, 15, 2, 2, ac_hi)
	_outline(img, 13, 14, 6, 5, gold)

	# Tall Flagpole & Owner Pennant on top (y = 1..9)
	_rect_px(img, 15, 1, 2, 10, gold)
	_rect_px(img, 17, 2, 9, 5, ac)
	_rect_px(img, 17, 2, 9, 2, ac_hi)
	_rect_px(img, 17, 6, 7, 1, ac_dk)
