class_name TowerArtRenderer
extends RefCounted
## Tower rendering for Twin Bastion TD: tiered pixel sprites (PixelTowerSprites) with ground shadow, firing recoil,
## muzzle / crystal glow, Lv3 orbiting spark, owner pennant, level pips and the frozen (Frost Colossus) state.
## Also maps stage ids to biomes for TerrainBaker.

const INK_C := Color(0.06, 0.05, 0.08)


static func get_biome_for_stage(stage_id: String) -> String:
	if stage_id.contains("rift"):
		return "rift"
	if stage_id.contains("siege"):
		return "siege"
	if stage_id.contains("frost"):
		return "snow"
	if stage_id.contains("abyss"):
		return "abyss"
	return "bridge"


static func draw_tower_detailed(canvas: CanvasItem, t: Dictionary, owner: int, now: float) -> void:
	var tid := str(t["tower_id"])
	var p: Vector2 = t["pos"]
	var level := int(t["level"])
	var branch := str(t.get("branch", ""))
	var frozen := float(t.get("frozen_timer", 0.0)) > 0.0
	var fire := float(t.get("fire_anim", 0.0))
	var ocol := UIKit.pcol(owner)
	var hover_bob := sin(now * 4.0 + p.x * 0.1) * 0.8 if (tid == "mage" or branch == "arcane") else 0.0

	# ground shadow
	var sh := PackedVector2Array()
	for i in range(16):
		var a := TAU * float(i) / 16.0
		sh.append(p + Vector2(4, 9) + Vector2(cos(a) * 14.0, sin(a) * 4.0))
	canvas.draw_colored_polygon(sh, Color(0, 0, 0, 0.32))

	var recoil := 1.0 if fire > 0.1 else 0.0
	var mod := Color(0.70, 0.88, 1.25) if frozen else Color.WHITE
	var tex := PixelTowerSprites.get_tower_texture(tid, owner, level, branch)
	canvas.draw_texture_rect(tex, Rect2(p - Vector2(16, 29 - recoil), Vector2(32, 40)), false, mod)

	# muzzle / crystal glow when firing
	if fire > 0.0 and not frozen:
		var top := p + Vector2(0, -20 + hover_bob)
		var gcol := Color(0.75, 0.95, 1.0) if tid == "frost" else (Color(1.0, 0.55, 0.20) if branch == "inferno" else (Color(0.85, 0.55, 1.0) if tid == "mage" else Color(1.0, 0.95, 0.70)))
		canvas.draw_circle(top, 3.0 + fire * 12.0, Color(gcol.r, gcol.g, gcol.b, fire * 2.0))
	elif level >= 3 and (tid == "mage" or tid == "frost"):
		var gc := Color(1.0, 0.55, 0.20, 0.18) if branch == "inferno" else (Color(0.6, 0.9, 1.0, 0.16) if tid == "frost" else Color(0.75, 0.55, 1.0, 0.18))
		canvas.draw_circle(p + Vector2(0, -18 + hover_bob), 7.0 + sin(now * 3.0) * 1.0, gc)

	# Lv3 orbiting spark
	if level >= 3:
		var ang := now * 2.6 + p.x
		canvas.draw_rect(Rect2(p + Vector2(cos(ang) * 13.0, -12.0 + sin(ang) * 4.0), Vector2(2, 2)), UIKit.GOLD)

	# owner pennant + level pips on the plinth
	var pb := p + Vector2(-13, 4)
	canvas.draw_line(pb, pb + Vector2(0, -7), Color(0.30, 0.22, 0.14), 1.0)
	canvas.draw_colored_polygon(PackedVector2Array([pb + Vector2(1, -7), pb + Vector2(6, -5.5 + sin(now * 5.0 + p.x) * 0.6), pb + Vector2(1, -4)]), ocol)
	for i in range(level):
		var q := p + Vector2(-4 + i * 4, 8)
		canvas.draw_rect(Rect2(q, Vector2(3, 2)), INK_C)
		canvas.draw_rect(Rect2(q + Vector2(0.5, 0.5), Vector2(2, 1)), UIKit.GOLD if i < 2 else ocol.lightened(0.3))

	if frozen:
		PixelIcons.draw_icon(canvas, "snow", p + Vector2(10, -24))
