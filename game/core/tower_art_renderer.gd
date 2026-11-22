class_name TowerArtRenderer
extends RefCounted
## Commercial-Grade Procedural Pixel-Art Renderer for Twin Bastion TD:
## - 3 Distinct Biome Battlefields (Emerald River & Bridges / Arcane Rift Highlands / Royal Siege Courtyard)
## - Multi-Tier Pixel-Art Tower Architecture (Lv1 -> Lv2 -> Lv3 visual evolution + bobbing crystals + waving banners)
## - Cohesive Fantasy Pixel-RPG UI StyleBox Helpers (eliminates flat default Godot boxes).

static func make_panel_style(bg: Color = Color(0.08, 0.11, 0.22, 0.94), border: Color = Color(0.86, 0.74, 0.40, 0.95), radius: int = 3) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(7)
	sb.shadow_color = Color(0.0, 0.0, 0.0, 0.45)
	sb.shadow_size = 3
	return sb


static func make_button_style(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(2)
	sb.set_content_margin_all(4)
	return sb


static func style_button(btn: Button, accent: Color = Color(0.24, 0.36, 0.62)) -> void:
	btn.add_theme_stylebox_override("normal", make_button_style(accent.darkened(0.45), accent.lightened(0.25)))
	btn.add_theme_stylebox_override("hover", make_button_style(accent.darkened(0.20), Color(1.0, 0.92, 0.45)))
	btn.add_theme_stylebox_override("pressed", make_button_style(accent.darkened(0.60), Color(1.0, 0.85, 0.30)))
	btn.add_theme_stylebox_override("focus", make_button_style(accent.darkened(0.10), Color(1.0, 0.94, 0.32)))


static func get_biome_for_stage(stage_id: String) -> String:
	if stage_id.contains("rift"):
		return "rift"
	if stage_id.contains("siege"):
		return "siege"
	return "bridge"


static func draw_biome_backdrop(canvas: CanvasItem, biome: String, t: float, meadow_tex: Texture2D, stone_tex: Texture2D, tree_tex: Texture2D, bush_tex: Texture2D) -> void:
	if biome == "bridge":
		# 1. Lush Emerald Meadow
		canvas.draw_rect(Rect2(0, 28, 480, 210), Color(0.16, 0.30, 0.18))
		if meadow_tex != null:
			for tx in range(0, 480, 32):
				for ty in range(28, 240, 32):
					canvas.draw_texture_rect(meadow_tex, Rect2(Vector2(tx, ty), Vector2(32, 32)), false)
		# Organic Gently-Winding Shimmering Emerald River (x ~ 170..202)
		var bank_pts := PackedVector2Array()
		var shore_pts := PackedVector2Array()
		var deep_pts := PackedVector2Array()
		for ry_i in range(0, 16):
			var y := 28.0 + float(ry_i) * 14.5
			var cx := 184.0 + sin(float(ry_i) * 0.45) * 6.5
			bank_pts.append(Vector2(cx, y))
			shore_pts.append(Vector2(cx, y))
			deep_pts.append(Vector2(cx, y))
		canvas.draw_polyline(bank_pts, Color(0.14, 0.24, 0.14), 48.0) # lush riverbank moss
		canvas.draw_polyline(bank_pts, Color(0.46, 0.36, 0.22), 42.0) # sandy pebble shore
		canvas.draw_polyline(shore_pts, Color(0.18, 0.56, 0.76), 34.0) # turquoise shallows
		canvas.draw_polyline(deep_pts, Color(0.11, 0.38, 0.62), 20.0) # deep emerald-blue channel
		# Animated pixel water sparkles & lily pads
		for ry in range(36, 232, 16):
			var wy := 32.0 + fmod(float(ry) + t * 18.0, 202.0)
			var cx := 184.0 + sin((wy - 28.0) / 14.5 * 0.45) * 6.5
			canvas.draw_line(Vector2(cx - 10, wy), Vector2(cx - 3, wy), Color(0.76, 0.96, 1.0, 0.55), 1.3)
			canvas.draw_line(Vector2(cx + 2, wy + 5), Vector2(cx + 9, wy + 5), Color(0.76, 0.96, 1.0, 0.45), 1.2)
		for lp in [Vector2(174, 122), Vector2(194, 148), Vector2(178, 212)]:
			canvas.draw_circle(lp, 4.2, Color(0.18, 0.56, 0.24))
			canvas.draw_circle(lp + Vector2(1, -1), 1.4, Color(1.0, 0.68, 0.78)) # tiny lotus flower
		# Decorative Trees, Bushes & Wildflowers
		if tree_tex != null:
			for tp in [Vector2(26, 46), Vector2(138, 44), Vector2(280, 42), Vector2(386, 46), Vector2(44, 224), Vector2(284, 224), Vector2(444, 218)]:
				canvas.draw_texture_rect(tree_tex, Rect2(tp - Vector2(13, 20), Vector2(26, 28)), false)
		if bush_tex != null:
			for bp in [Vector2(66, 126), Vector2(140, 146), Vector2(246, 142), Vector2(364, 218)]:
				canvas.draw_texture_rect(bush_tex, Rect2(bp - Vector2(8, 8), Vector2(16, 14)), false)
		for fp in [Vector2(52, 140), Vector2(118, 128), Vector2(262, 126), Vector2(342, 202), Vector2(78, 206)]:
			canvas.draw_circle(fp, 1.6, Color(1.0, 0.92, 0.36))
			canvas.draw_circle(fp + Vector2(5, 3), 1.4, Color(0.95, 0.52, 0.68))

	elif biome == "rift":
		# 2. Twilight Highlands + Glowing Volcanic/Arcane Rift Fissures!
		canvas.draw_rect(Rect2(0, 28, 480, 210), Color(0.16, 0.15, 0.22))
		if stone_tex != null:
			for tx in range(0, 480, 32):
				for ty in range(28, 240, 32):
					canvas.draw_texture_rect(stone_tex, Rect2(Vector2(tx, ty), Vector2(32, 32)), false, Color(0.68, 0.62, 0.80, 0.85))
		# Glowing Arcane Rift Chasm running under the center crossing
		var pulse := 0.75 + 0.25 * sin(t * 4.5)
		var rift_pts := PackedVector2Array([Vector2(205, 28), Vector2(228, 88), Vector2(248, 136), Vector2(224, 186), Vector2(252, 238)])
		canvas.draw_polyline(rift_pts, Color(0.10, 0.04, 0.16), 24.0)
		canvas.draw_polyline(rift_pts, Color(0.62, 0.20, 0.92, 0.72 * pulse), 12.0)
		canvas.draw_polyline(rift_pts, Color(1.0, 0.56, 0.96, 0.90 * pulse), 4.0)
		# Obsidian Monolith Pillars
		for mp in [Vector2(42, 46), Vector2(170, 46), Vector2(382, 48), Vector2(46, 224), Vector2(394, 220)]:
			canvas.draw_rect(Rect2(mp - Vector2(6, 14), Vector2(12, 20)), Color(0.18, 0.14, 0.28))
			canvas.draw_rect(Rect2(mp - Vector2(6, 14), Vector2(12, 20)), Color(0.70, 0.42, 0.98, 0.7), false, 1.0)
			canvas.draw_circle(mp + Vector2(0, -6), 2.2, Color(0.92, 0.55, 1.0, pulse))

	else:
		# 3. Royal Siege Flagstone Courtyard + Crenellated Walls + Burning Braziers!
		canvas.draw_rect(Rect2(0, 28, 480, 210), Color(0.20, 0.20, 0.24))
		if stone_tex != null:
			for tx in range(0, 480, 32):
				for ty in range(28, 240, 32):
					canvas.draw_texture_rect(stone_tex, Rect2(Vector2(tx, ty), Vector2(32, 32)), false, Color(0.84, 0.82, 0.86, 0.92))
		# Top & Bottom Castle Battlements
		canvas.draw_rect(Rect2(0, 28, 480, 14), Color(0.32, 0.34, 0.40))
		canvas.draw_rect(Rect2(0, 224, 480, 14), Color(0.32, 0.34, 0.40))
		for bx in range(4, 480, 24):
			canvas.draw_rect(Rect2(bx, 28, 12, 6), Color(0.46, 0.48, 0.54))
			canvas.draw_rect(Rect2(bx, 232, 12, 6), Color(0.46, 0.48, 0.54))
		# Burning Braziers lighting the Royal Siege
		var fl := 2.5 * sin(t * 14.0)
		for fp in [Vector2(76, 44), Vector2(268, 44), Vector2(76, 222), Vector2(268, 222), Vector2(396, 78), Vector2(396, 192)]:
			canvas.draw_circle(fp, 18.0, Color(1.0, 0.55, 0.16, 0.16))
			canvas.draw_circle(fp + Vector2(0, 2), 4.5, Color(0.25, 0.22, 0.24))
			canvas.draw_polygon(PackedVector2Array([fp + Vector2(-4, 1), fp + Vector2(4, 1), fp + Vector2(0, -8 + fl)]), PackedColorArray([Color(1.0, 0.48, 0.12)]))
			canvas.draw_polygon(PackedVector2Array([fp + Vector2(-2, 1), fp + Vector2(2, 1), fp + Vector2(0, -4 + fl * 0.5)]), PackedColorArray([Color(1.0, 0.94, 0.38)]))


static func draw_biome_bridges(canvas: CanvasItem, biome: String) -> void:
	if biome != "bridge":
		return
	# Detailed Stone-Pier Timber Bridges with Water Drop Shadow & Warm Corner Lanterns!
	for by in [74.0, 174.0]:
		# Shadow on water below bridge
		canvas.draw_rect(Rect2(160, by + 18, 52, 7), Color(0.04, 0.10, 0.18, 0.45))
		# Stone abutments on left/right shores
		canvas.draw_rect(Rect2(156, by - 1, 7, 24), Color(0.50, 0.52, 0.58))
		canvas.draw_rect(Rect2(209, by - 1, 7, 24), Color(0.50, 0.52, 0.58))
		canvas.draw_rect(Rect2(156, by - 1, 7, 24), Color(0.18, 0.18, 0.22), false, 1.0)
		canvas.draw_rect(Rect2(209, by - 1, 7, 24), Color(0.18, 0.18, 0.22), false, 1.0)
		# Shaded timber deck planks
		canvas.draw_rect(Rect2(162, by, 48, 22), Color(0.48, 0.31, 0.15))
		canvas.draw_rect(Rect2(162, by + 2, 48, 5), Color(0.58, 0.40, 0.20))
		canvas.draw_rect(Rect2(162, by, 48, 22), Color(0.20, 0.11, 0.05), false, 1.2)
		for px in range(167, 208, 6):
			canvas.draw_line(Vector2(px, by + 1), Vector2(px, by + 21), Color(0.26, 0.15, 0.07), 1.0)
		# Top & bottom wooden railings + warm glowing bridge posts
		canvas.draw_line(Vector2(160, by + 1), Vector2(212, by + 1), Color(0.72, 0.52, 0.28), 2.2)
		canvas.draw_line(Vector2(160, by + 21), Vector2(212, by + 21), Color(0.72, 0.52, 0.28), 2.2)
		for lx in [161.0, 211.0]:
			for ly in [by + 1.0, by + 21.0]:
				canvas.draw_circle(Vector2(lx, ly), 4.5, Color(1.0, 0.78, 0.30, 0.28))
				canvas.draw_circle(Vector2(lx, ly), 1.8, Color(1.0, 0.94, 0.50))


static func draw_tower_detailed(canvas: CanvasItem, tid: String, p: Vector2, level: int, owner: int, t: float, font: Font) -> void:
	var ocol := Color(0.32, 0.80, 1.0) if owner == 1 else Color(1.0, 0.40, 0.46)
	var bob := sin(t * 4.5 + p.x * 0.1) * 1.4 if tid == "mage" else 0.0

	# Ground Shadow + Subtle Owner Ring
	canvas.draw_circle(p + Vector2(0, 9), 13.0, Color(0.0, 0.0, 0.0, 0.36))
	canvas.draw_arc(p + Vector2(0, 8), 12.0, 0.0, TAU, 18, Color(ocol.r, ocol.g, ocol.b, 0.65), 1.4)

	# Hand-Crafted 32x36 Pixel-Art Tower Sprite!
	var tex := PixelTowerSprites.get_tower_texture(tid, owner)
	if tex != null:
		canvas.draw_texture_rect(tex, Rect2(p - Vector2(16, 25 - bob), Vector2(32, 36)), false)

	# Tier Lv2 / Lv3 Golden Aura & Orbiting Runes
	if level >= 2:
		var ang := t * 3.2
		var orb_r := 13.5
		canvas.draw_circle(p + Vector2(cos(ang) * orb_r, -10.0 + sin(ang) * 4.5), 2.0, Color(1.0, 0.92, 0.38))
		if level >= 3:
			canvas.draw_circle(p + Vector2(cos(ang + PI) * orb_r, -10.0 + sin(ang + PI) * 4.5), 2.2, ocol)
			canvas.draw_arc(p + Vector2(0, 8), 14.5, 0.0, TAU, 20, Color(1.0, 0.90, 0.35, 0.70), 1.2)

	# Crisp Dark-Pill Nameplate (never clashes with ground ring!)
	var stars := "★".repeat(clampi(level, 1, 3))
	var tag := "P%d %s" % [owner, stars]
	canvas.draw_rect(Rect2(p + Vector2(-18, 12), Vector2(36, 9)), Color(0.05, 0.07, 0.14, 0.85))
	canvas.draw_rect(Rect2(p + Vector2(-18, 12), Vector2(36, 9)), Color(ocol.r, ocol.g, ocol.b, 0.75), false, 0.8)
	canvas.draw_string(font, p + Vector2(-18, 19), tag, HORIZONTAL_ALIGNMENT_CENTER, 36, 6, ocol)
