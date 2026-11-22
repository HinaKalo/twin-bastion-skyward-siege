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
		# Animated Shimmering Emerald River cutting through x = 165..205
		canvas.draw_rect(Rect2(162, 28, 46, 210), Color(0.32, 0.24, 0.16)) # riverbank
		canvas.draw_rect(Rect2(166, 28, 38, 210), Color(0.14, 0.44, 0.68))
		canvas.draw_rect(Rect2(174, 28, 22, 210), Color(0.20, 0.56, 0.78))
		for ry in range(36, 232, 18):
			var off := fmod(t * 22.0 + float(ry), 18.0)
			var wy := 30.0 + fmod(float(ry) + off, 204.0)
			canvas.draw_line(Vector2(172, wy), Vector2(184, wy), Color(0.75, 0.94, 1.0, 0.55), 1.4)
			canvas.draw_line(Vector2(186, wy + 5), Vector2(198, wy + 5), Color(0.75, 0.94, 1.0, 0.45), 1.2)
		# Decorative Trees, Bushes & Wildflowers
		if tree_tex != null:
			for tp in [Vector2(26, 46), Vector2(138, 44), Vector2(280, 42), Vector2(386, 46), Vector2(44, 224), Vector2(284, 224), Vector2(444, 218)]:
				canvas.draw_texture_rect(tree_tex, Rect2(tp - Vector2(13, 20), Vector2(26, 28)), false)
		if bush_tex != null:
			for bp in [Vector2(66, 126), Vector2(140, 146), Vector2(246, 142), Vector2(364, 218)]:
				canvas.draw_texture_rect(bush_tex, Rect2(bp - Vector2(8, 8), Vector2(16, 14)), false)

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
	# Wooden plank bridges over the Emerald River at North (y=80) & South (y=184) crossings!
	for by in [74.0, 174.0]:
		canvas.draw_rect(Rect2(160, by, 50, 22), Color(0.44, 0.28, 0.14))
		canvas.draw_rect(Rect2(160, by, 50, 22), Color(0.22, 0.12, 0.05), false, 1.4)
		for px in range(166, 208, 7):
			canvas.draw_line(Vector2(px, by + 1), Vector2(px, by + 21), Color(0.28, 0.16, 0.08), 1.0)
		# Top & bottom wooden railings
		canvas.draw_line(Vector2(160, by + 1), Vector2(210, by + 1), Color(0.68, 0.48, 0.24), 2.2)
		canvas.draw_line(Vector2(160, by + 21), Vector2(210, by + 21), Color(0.68, 0.48, 0.24), 2.2)


static func draw_tower_detailed(canvas: CanvasItem, tid: String, p: Vector2, level: int, owner: int, t: float, font: Font) -> void:
	var ocol := Color(0.32, 0.78, 1.0) if owner == 1 else Color(1.0, 0.38, 0.44)
	var ocol_dark := ocol.darkened(0.42)
	var lvl_scale := 1.0 + float(maxi(0, level - 1)) * 0.08

	# Soft ground shadow + Owner Heraldic Pedestal Ring
	canvas.draw_circle(p + Vector2(0, 9), 13.0 * lvl_scale, Color(0.0, 0.0, 0.0, 0.35))
	canvas.draw_circle(p + Vector2(0, 8), 11.5 * lvl_scale, Color(ocol.r, ocol.g, ocol.b, 0.28))
	canvas.draw_arc(p + Vector2(0, 8), 11.5 * lvl_scale, 0.0, TAU, 18, ocol, 1.6)

	match tid:
		"arrow":
			# Multi-tier Wooden/Stone Watchtower with Battlements & Roof Pennant
			var base_col := Color(0.56, 0.38, 0.20) if level == 1 else (Color(0.54, 0.56, 0.62) if level == 2 else Color(0.72, 0.64, 0.46))
			canvas.draw_rect(Rect2(p + Vector2(-9, -6), Vector2(18, 16)), base_col)
			canvas.draw_rect(Rect2(p + Vector2(-11, -11), Vector2(22, 6)), base_col.lightened(0.14))
			for bx in [-11, -5, 1, 7]:
				canvas.draw_rect(Rect2(p + Vector2(bx, -14), Vector2(4, 3)), base_col.lightened(0.22))
			canvas.draw_rect(Rect2(p + Vector2(-9, -6), Vector2(18, 16)), Color(0.16, 0.10, 0.06), false, 1.2)
			# Owner-colored pointed archer roof + fluttering pennant on Lv2+
			canvas.draw_polygon(PackedVector2Array([p + Vector2(-8, -14), p + Vector2(8, -14), p + Vector2(0, -22 - level)]), PackedColorArray([ocol_dark]))
			canvas.draw_polygon(PackedVector2Array([p + Vector2(0, -14), p + Vector2(8, -14), p + Vector2(0, -22 - level)]), PackedColorArray([ocol]))
			if level >= 2:
				var wave := sin(t * 8.0) * 2.0
				canvas.draw_line(p + Vector2(0, -22 - level), p + Vector2(0, -28 - level), Color(1.0, 0.92, 0.55), 1.2)
				canvas.draw_polygon(PackedVector2Array([p + Vector2(0, -28 - level), p + Vector2(8, -26 - level + wave), p + Vector2(0, -24 - level)]), PackedColorArray([Color(1.0, 0.88, 0.25)]))

		"mage":
			# Arcane Spire with Orbiting/Bobbing Crystal Orb (Lv3 adds twin orbiting runes!)
			var bob := sin(t * 5.0 + p.x * 0.1) * 2.2
			canvas.draw_rect(Rect2(p + Vector2(-8, -8), Vector2(16, 18)), Color(0.22, 0.18, 0.36))
			canvas.draw_rect(Rect2(p + Vector2(-10, 4), Vector2(20, 6)), Color(0.32, 0.26, 0.48))
			canvas.draw_rect(Rect2(p + Vector2(-8, -8), Vector2(16, 18)), ocol, false, 1.3)
			# Glowing Violet Crystal Core
			var orb_p := p + Vector2(0, -15 + bob)
			canvas.draw_circle(orb_p, 7.0 + level, Color(0.76, 0.32, 1.0, 0.32))
			canvas.draw_circle(orb_p, 4.2 + float(level) * 0.6, Color(0.92, 0.56, 1.0))
			canvas.draw_circle(orb_p + Vector2(-1.2, -1.2), 1.6, Color.WHITE)
			if level >= 2:
				var ang := t * 3.5
				canvas.draw_circle(orb_p + Vector2(cos(ang), sin(ang)) * 8.0, 1.8, ocol)
				if level >= 3:
					canvas.draw_circle(orb_p + Vector2(cos(ang + PI), sin(ang + PI)) * 8.0, 1.8, Color(1.0, 0.92, 0.35))

		"frost":
			# Faceted Glacier Obelisk with Shimmering Cyan Aura
			var shimmer := 0.75 + 0.25 * sin(t * 6.0)
			canvas.draw_polygon(PackedVector2Array([p + Vector2(-10, 10), p + Vector2(10, 10), p + Vector2(6, -9), p + Vector2(0, -20 - level * 2), p + Vector2(-6, -9)]), PackedColorArray([Color(0.30, 0.70, 0.94)]))
			canvas.draw_polygon(PackedVector2Array([p + Vector2(0, 10), p + Vector2(10, 10), p + Vector2(6, -9), p + Vector2(0, -20 - level * 2)]), PackedColorArray([Color(0.64, 0.94, 1.0)]))
			canvas.draw_circle(p + Vector2(0, -17 - level * 2), 3.2 + level * 0.5, Color(0.85, 1.0, 1.0, shimmer))
			canvas.draw_rect(Rect2(p + Vector2(-4, 2), Vector2(8, 5)), ocol)

		"barracks":
			# Fortified Stone Garrison with Archway, Gold Trim & Fluttering Owner Banner
			var wave := sin(t * 7.5) * 2.0
			canvas.draw_rect(Rect2(p + Vector2(-11, -7), Vector2(22, 17)), Color(0.56, 0.58, 0.64))
			canvas.draw_rect(Rect2(p + Vector2(-11, -7), Vector2(22, 17)), Color(0.95, 0.80, 0.32) if level >= 2 else ocol, false, 1.6)
			canvas.draw_rect(Rect2(p + Vector2(-4, 1), Vector2(8, 9)), Color(0.18, 0.12, 0.08))
			canvas.draw_line(p + Vector2(0, -7), p + Vector2(0, -21 - level), Color(0.95, 0.88, 0.65), 1.5)
			canvas.draw_polygon(PackedVector2Array([p + Vector2(0, -21 - level), p + Vector2(11, -18 - level + wave), p + Vector2(0, -14 - level)]), PackedColorArray([ocol]))

	# Crisp Level Stars / Owner Tag
	var stars := "★".repeat(clampi(level, 1, 3))
	canvas.draw_string(font, p + Vector2(-21, 19), "P%d %s" % [owner, stars], HORIZONTAL_ALIGNMENT_CENTER, 42, 6, Color(0.05, 0.04, 0.08))
	canvas.draw_string(font, p + Vector2(-22, 18), "P%d %s" % [owner, stars], HORIZONTAL_ALIGNMENT_CENTER, 42, 6, ocol)
