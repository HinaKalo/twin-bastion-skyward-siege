class_name BattleVFX
extends RefCounted
## Commercial-Grade Combat Juice, Projectiles, Particles, Floating Text & Cinematics
## for Twin Bastion TD (Zero external plugins, crisp pixel-art CanvasItem rendering).

var projectiles: Array[Dictionary] = []
var particles: Array[Dictionary] = []
var shockwaves: Array[Dictionary] = []
var lightning_arcs: Array[Dictionary] = []
var floating_texts: Array[Dictionary] = []
var ambient_motes: Array[Dictionary] = []

# Screen Shake Trauma (0..1)
var shake_trauma: float = 0.0
var shake_offset: Vector2 = Vector2.ZERO

# Dramatic Cinematics State
var intro_timer: float = 0.0
var intro_title: String = ""
var intro_sub: String = ""

var wave_banner_timer: float = 0.0
var wave_banner_text: String = ""

var boss_cutin_timer: float = 0.0
var boss_cutin_name: String = ""
var boss_cutin_sub: String = ""
var boss_cutin_tex: Texture2D = null
var boss_cutin_quote: String = ""

var ult_cinematic_timer: float = 0.0
var ult_comets: Array[Dictionary] = []
var deaths: Array[Dictionary] = []
var mote_area: Rect2 = Rect2(12, 34, 456, 200)
var meteors: Array[Dictionary] = []
var warnings: Array[Dictionary] = []


func add_warning(kind: String, pos: Vector2, radius: float, duration: float) -> void:
	var col := Color(0.63, 0.91, 1.0) if kind == "frost_roar" else UIKit.BAD
	if kind == "reinforcement":
		col = UIKit.P2
	elif kind == "meteor":
		col = UIKit.P1
	elif kind == "summon" or kind == "bolt":
		col = Color(0.88, 0.56, 1.0)
	warnings.append({"pos": pos, "radius": radius, "total": duration, "left": duration, "color": col})


func init_ambient_motes(biome: String, count: int = 24, area: Rect2 = Rect2(12, 34, 456, 200)) -> void:
	mote_area = area
	ambient_motes.clear()
	var col := Color(1.0, 0.94, 0.45, 0.65)
	if biome == "rift":
		col = Color(1.0, 0.48, 0.25, 0.70)
	elif biome == "siege":
		col = Color(1.0, 0.72, 0.35, 0.62)
	for i in range(count):
		ambient_motes.append({
			"pos": Vector2(randf_range(area.position.x, area.end.x), randf_range(area.position.y, area.end.y)),
			"vel": Vector2(randf_range(-8.0, 10.0), randf_range(-10.0, -3.0)),
			"phase": randf_range(0.0, TAU),
			"size": randf_range(1.0, 2.2),
			"color": col,
		})


func add_shake(amount: float) -> void:
	shake_trauma = minf(1.0, shake_trauma + amount)


func play_stage_intro(title: String, subtitle: String) -> void:
	intro_title = title
	intro_sub = subtitle
	intro_timer = 2.4


func play_wave_banner(text: String) -> void:
	wave_banner_text = text
	wave_banner_timer = 1.7


func play_boss_cutin(bname: String, subtitle: String, portrait: Texture2D, quote: String = "") -> void:
	boss_cutin_quote = quote
	boss_cutin_timer = 2.7
	boss_cutin_name = bname
	boss_cutin_sub = subtitle
	boss_cutin_tex = portrait
	add_shake(0.24)


func play_synchro_ultimate_cinematic(view: Rect2 = Rect2(65, 68, 330, 137)) -> void:
	ult_cinematic_timer = 1.85
	ult_comets.clear()
	add_shake(0.25)
	for i in range(14):
		var is_blue := (i % 2 == 0)
		var target := Vector2(randf_range(view.position.x, view.end.x), randf_range(view.position.y, view.end.y))
		ult_comets.append({
			"from": target + Vector2(-95.0 if is_blue else 95.0, -140.0),
			"to": target,
			"delay": float(i) * 0.08,
			"t": 0.0,
			"dur": 0.36,
			"exploded": false,
			"color": Color(0.38, 0.86, 1.0) if is_blue else Color(1.0, 0.38, 0.56),
		})


func spawn_projectile(from_pos: Vector2, to_pos: Vector2, kind: String, branch: String = "", shot: Dictionary = {}) -> void:
	projectiles.append({
		"from": from_pos,
		"to": to_pos,
		"pos": from_pos,
		"kind": kind,
		"branch": branch,
		"t": 0.0,
		"dur": float(shot.get("duration", TDTowerEngine.projectile_seconds(from_pos, to_pos, kind, branch))),
		"shot": shot,
	})


func land_projectile(shot_id: int, to: Vector2, kind: String, branch: String, hit: bool) -> void:
	for i in range(projectiles.size()):
		if int(projectiles[i]["shot"].get("id", 0)) == shot_id:
			projectiles.remove_at(i)
			break
	if hit:
		_projectile_burst(to, kind, branch)


func _projectile_burst(pos: Vector2, kind: String, branch: String) -> void:
	var col := Color(0.55, 0.94, 1.0) if kind == "frost" else (Color(0.88, 0.50, 1.0) if kind == "mage" else Color(1.0, 0.90, 0.45))
	if kind == "enemy_arrow" or kind == "axe":
		col = Color(0.85, 0.80, 0.70)
	elif kind == "bolt":
		col = Color(0.75, 0.30, 1.0)
		spawn_shockwave(pos, 16.0, col, 0.25)
	if branch == "inferno":
		col = Color(1.0, 0.55, 0.18)
		spawn_shockwave(pos, 26.0, col, 0.25)
	elif branch == "blizzard":
		spawn_shockwave(pos, 30.0, Color(0.80, 0.96, 1.0), 0.28)
	spawn_burst(pos, col, 6 if branch != "" else 4, 42.0, 20.0)


func spawn_death(pos: Vector2, tex: Texture2D, size: float) -> void:
	deaths.append({"pos": pos, "tex": tex, "size": size, "t": 0.0, "dur": 0.32})


func play_meteor_volley(center: Vector2) -> void:
	for i in range(7):
		var off := Vector2(randf_range(-38.0, 38.0), randf_range(-26.0, 26.0)) if i > 0 else Vector2.ZERO
		var target := center + off
		meteors.append({"from": target + Vector2(-50.0, -110.0), "to": target, "t": 0.0,
			"dur": CoopTDDirector.METEOR_IMPACT, "delay": float(i) * 0.04, "done": false})


func spawn_lightning(from_pos: Vector2, to_pos: Vector2, col: Color = Color(0.76, 0.90, 1.0)) -> void:
	var pts: Array[Vector2] = [from_pos]
	var segs := 5
	for i in range(1, segs):
		var frac := float(i) / float(segs)
		var base := from_pos.lerp(to_pos, frac)
		var perp := (to_pos - from_pos).normalized().rotated(PI * 0.5)
		pts.append(base + perp * randf_range(-7.0, 7.0))
	pts.append(to_pos)
	lightning_arcs.append({"points": pts, "color": col, "ttl": 0.18, "max_ttl": 0.18})


func spawn_burst(pos: Vector2, col: Color, count: int = 8, speed: float = 55.0, gravity: float = 40.0) -> void:
	count = mini(count, maxi(0, 240 - particles.size()))
	for _i in range(count):
		var ang := randf_range(0.0, TAU)
		var spd := randf_range(speed * 0.4, speed)
		particles.append({
			"pos": pos,
			"vel": Vector2(cos(ang), sin(ang)) * spd,
			"gravity": gravity,
			"color": col,
			"size": randf_range(1.6, 3.2),
			"ttl": randf_range(0.22, 0.48),
			"max_ttl": 0.48,
		})


func spawn_shockwave(pos: Vector2, max_r: float, col: Color, dur: float = 0.35) -> void:
	shockwaves.append({"pos": pos, "r": 4.0, "max_r": max_r, "color": col, "t": 0.0, "dur": dur})


func spawn_float_text(pos: Vector2, text: String, col: Color, font_size: int = 7) -> void:
	if floating_texts.size() >= 36:
		return
	floating_texts.append({
		"pos": pos + Vector2(randf_range(-6.0, 6.0), -10.0),
		"vel": Vector2(randf_range(-6.0, 6.0), -26.0),
		"text": text,
		"color": col,
		"size": font_size,
		"ttl": 0.85,
		"max_ttl": 0.85,
	})


func tick(delta: float, real_delta: float = -1.0) -> void:
	var ui_dt := delta if real_delta < 0.0 else real_delta
	intro_timer = maxf(0.0, intro_timer - ui_dt)
	wave_banner_timer = maxf(0.0, wave_banner_timer - ui_dt)
	boss_cutin_timer = maxf(0.0, boss_cutin_timer - ui_dt)
	if delta <= 0.0:
		return

	# Screen shake decay
	if shake_trauma > 0.0:
		shake_trauma = maxf(0.0, shake_trauma - delta * 1.9)
		var mag := shake_trauma * shake_trauma * 7.5
		shake_offset = Vector2(randf_range(-mag, mag), randf_range(-mag, mag))
	else:
		shake_offset = Vector2.ZERO

	ult_cinematic_timer = maxf(0.0, ult_cinematic_timer - delta)
	for i in range(warnings.size() - 1, -1, -1):
		warnings[i]["left"] = float(warnings[i]["left"]) - delta
		if float(warnings[i]["left"]) <= 0.0:
			warnings.remove_at(i)

	# Ambient motes
	for m in ambient_motes:
		m["phase"] = float(m["phase"]) + delta * 2.5
		var p: Vector2 = (m["pos"] as Vector2) + (m["vel"] as Vector2) * delta
		p.x += sin(float(m["phase"])) * 4.0 * delta
		if p.y < mote_area.position.y: p.y = mote_area.end.y
		if p.x < mote_area.position.x: p.x = mote_area.end.x
		if p.x > mote_area.end.x: p.x = mote_area.position.x
		m["pos"] = p

	# Projectiles
	for i in range(projectiles.size() - 1, -1, -1):
		var pr: Dictionary = projectiles[i]
		var shot: Dictionary = pr["shot"]
		if not shot.is_empty():
			pr["to"] = shot["to"]
		pr["t"] = float(pr["t"]) + delta
		var frac := clampf(float(pr["t"]) / float(pr["dur"]), 0.0, 1.0)
		var base := (pr["from"] as Vector2).lerp(pr["to"] as Vector2, frac)
		if str(pr["kind"]) == "arrow":
			base.y -= sin(frac * PI) * 14.0 # crisp ballistic arc!
		pr["pos"] = base
		if (shot.is_empty() and frac >= 1.0) or float(pr["t"]) > float(pr["dur"]) + 0.4:
			if shot.is_empty():
				_projectile_burst(pr["to"], str(pr["kind"]), str(pr["branch"]))
			projectiles.remove_at(i)

	# Death pops
	for i in range(deaths.size() - 1, -1, -1):
		deaths[i]["t"] = float(deaths[i]["t"]) + delta
		if float(deaths[i]["t"]) >= float(deaths[i]["dur"]):
			deaths.remove_at(i)

	# Meteor volley
	for m in meteors:
		if bool(m["done"]):
			continue
		if float(m["delay"]) > 0.0:
			m["delay"] = float(m["delay"]) - delta
			continue
		m["t"] = float(m["t"]) + delta
		if float(m["t"]) >= float(m["dur"]):
			m["done"] = true
			spawn_shockwave(m["to"], 22.0, Color(1.0, 0.62, 0.22), 0.30)
			spawn_burst(m["to"], Color(1.0, 0.72, 0.30), 9, 70.0, 40.0)
			add_shake(0.12)
	for i in range(meteors.size() - 1, -1, -1):
		if bool(meteors[i]["done"]):
			meteors.remove_at(i)

	# Ult Comets
	for c in ult_comets:
		if float(c["delay"]) > 0.0:
			c["delay"] = float(c["delay"]) - delta
			continue
		if bool(c["exploded"]):
			continue
		c["t"] = float(c["t"]) + delta
		if float(c["t"]) >= float(c["dur"]):
			c["exploded"] = true
			spawn_shockwave(c["to"], 36.0, c["color"], 0.40)
			spawn_burst(c["to"], c["color"], 14, 90.0, 50.0)
			add_shake(0.30)

	# Particles
	for i in range(particles.size() - 1, -1, -1):
		var pt: Dictionary = particles[i]
		pt["ttl"] = float(pt["ttl"]) - delta
		var v: Vector2 = pt["vel"]
		v.y += float(pt["gravity"]) * delta
		pt["vel"] = v
		pt["pos"] = (pt["pos"] as Vector2) + v * delta
		if float(pt["ttl"]) <= 0.0:
			particles.remove_at(i)

	# Shockwaves
	for i in range(shockwaves.size() - 1, -1, -1):
		var sw: Dictionary = shockwaves[i]
		sw["t"] = float(sw["t"]) + delta
		var frac := clampf(float(sw["t"]) / float(sw["dur"]), 0.0, 1.0)
		sw["r"] = lerpf(4.0, float(sw["max_r"]), 1.0 - pow(1.0 - frac, 2.0))
		if frac >= 1.0:
			shockwaves.remove_at(i)

	# Lightning
	for i in range(lightning_arcs.size() - 1, -1, -1):
		lightning_arcs[i]["ttl"] = float(lightning_arcs[i]["ttl"]) - delta
		if float(lightning_arcs[i]["ttl"]) <= 0.0:
			lightning_arcs.remove_at(i)

	# Floating texts
	for i in range(floating_texts.size() - 1, -1, -1):
		var ft: Dictionary = floating_texts[i]
		ft["ttl"] = float(ft["ttl"]) - delta
		ft["pos"] = (ft["pos"] as Vector2) + (ft["vel"] as Vector2) * delta
		ft["vel"] = (ft["vel"] as Vector2) * 0.94
		if float(ft["ttl"]) <= 0.0:
			floating_texts.remove_at(i)


func draw_world_fx(canvas: CanvasItem, font: Font) -> void:
	for warning in warnings:
		var ratio := clampf(float(warning["left"]) / float(warning["total"]), 0.0, 1.0)
		var r := float(warning["radius"])
		var col: Color = warning["color"]
		canvas.draw_circle(warning["pos"], r, Color(col, 0.08 + (1.0 - ratio) * 0.07))
		canvas.draw_arc(warning["pos"], r, 0.0, TAU, 40, Color(0.06, 0.09, 0.16, 0.70), 3.0)
		canvas.draw_arc(warning["pos"], r, 0.0, TAU, 40, Color(col, 0.45), 1.0)
		canvas.draw_arc(warning["pos"], r, -PI * 0.5, -PI * 0.5 + TAU * (1.0 - ratio), 40, col, 2.0)
	# Ambient motes
	for m in ambient_motes:
		var a := 0.35 + 0.45 * absf(sin(float(m["phase"])))
		var c: Color = m["color"]
		canvas.draw_circle(m["pos"], float(m["size"]), Color(c.r, c.g, c.b, a))

	# Shockwaves
	for sw in shockwaves:
		var frac := 1.0 - clampf(float(sw["t"]) / float(sw["dur"]), 0.0, 1.0)
		var c: Color = sw["color"]
		canvas.draw_arc(sw["pos"], float(sw["r"]), 0.0, TAU, 24, Color(c.r, c.g, c.b, frac * 0.9), 2.4 * frac + 0.6)

	# Synchro comets (world space)
	if ult_cinematic_timer > 0.0:
		for c in ult_comets:
			if float(c["delay"]) > 0.0 or bool(c["exploded"]):
				continue
			var frac := clampf(float(c["t"]) / float(c["dur"]), 0.0, 1.0)
			var cur := (c["from"] as Vector2).lerp(c["to"] as Vector2, frac)
			var tail := (c["from"] as Vector2).lerp(c["to"] as Vector2, maxf(0.0, frac - 0.28))
			var col: Color = c["color"]
			canvas.draw_line(tail, cur, Color(col.r, col.g, col.b, 0.65), 6.0)
			canvas.draw_line(tail, cur, Color.WHITE, 2.2)
			canvas.draw_circle(cur, 5.5, col)
			canvas.draw_circle(cur, 2.6, Color.WHITE)

	# Death pops (white flash, then puff up and fade)
	for d in deaths:
		var f := clampf(float(d["t"]) / float(d["dur"]), 0.0, 1.0)
		var tex: Texture2D = d["tex"]
		if tex != null:
			var s := float(d["size"]) * (1.0 + 0.35 * f)
			var mod := Color(3.0, 3.0, 3.0, 1.0 - f) if f < 0.25 else Color(1.0, 1.0, 1.0, (1.0 - f) * 0.9)
			canvas.draw_texture_rect(tex, Rect2((d["pos"] as Vector2) - Vector2(s * 0.5, s - 2.0 + f * 4.0), Vector2(s, s)), false, mod)
		canvas.draw_arc(d["pos"], 3.0 + f * 9.0, 0.0, TAU, 14, Color(1, 1, 1, (1.0 - f) * 0.5), 1.0)

	# Meteor volley
	for m in meteors:
		if float(m["delay"]) > 0.0:
			continue
		var mf := clampf(float(m["t"]) / float(m["dur"]), 0.0, 1.0)
		var cur := (m["from"] as Vector2).lerp(m["to"], mf)
		var tail := (m["from"] as Vector2).lerp(m["to"], maxf(0.0, mf - 0.3))
		canvas.draw_line(tail, cur, Color(1.0, 0.55, 0.20, 0.6), 3.0)
		canvas.draw_line(tail, cur, Color(1.0, 0.92, 0.55), 1.0)
		canvas.draw_circle(cur, 2.5, Color(1.0, 0.85, 0.40))
		canvas.draw_arc(m["to"], 6.0 * (1.0 - mf) + 2.0, 0.0, TAU, 12, Color(1.0, 0.5, 0.2, 0.6 * mf), 1.0)

	# Projectiles with crisp trails
	for pr in projectiles:
		var p: Vector2 = pr["pos"]
		var dir := ((pr["to"] as Vector2) - (pr["from"] as Vector2)).normalized()
		var k := str(pr["kind"])
		var br := str(pr.get("branch", ""))
		if k == "enemy_arrow":
			canvas.draw_line(p - dir * 6.0, p + dir * 2.0, Color(0.30, 0.18, 0.10), 1.5)
			canvas.draw_line(p + dir * 1.0, p + dir * 3.0, Color(0.85, 0.85, 0.90), 1.5)
			continue
		if k == "axe":
			var ang := float(pr["t"]) * 22.0
			var ax := Vector2(cos(ang), sin(ang)) * 3.0
			canvas.draw_line(p - ax, p + ax, Color(0.45, 0.30, 0.15), 1.5)
			canvas.draw_rect(Rect2(p + ax - Vector2(1.5, 1.5), Vector2(3, 3)), Color(0.85, 0.86, 0.92))
			continue
		if k == "bolt":
			canvas.draw_line(p - dir * 9.0, p, Color(0.55, 0.15, 0.85, 0.55), 3.5)
			canvas.draw_circle(p, 3.0, Color(0.70, 0.30, 1.0))
			canvas.draw_circle(p, 1.3, Color(1.0, 0.80, 1.0))
			continue
		if br == "sniper":
			canvas.draw_line(p - dir * 16.0, p, Color(1.0, 0.95, 0.70, 0.45), 1.0)
			canvas.draw_line(p - dir * 4.0, p + dir * 2.0, Color.WHITE, 1.5)
			continue
		if br == "inferno":
			canvas.draw_line(p - dir * 9.0, p, Color(1.0, 0.45, 0.10, 0.5), 4.0)
			canvas.draw_circle(p, 3.5, Color(1.0, 0.55, 0.15))
			canvas.draw_circle(p, 1.8, Color(1.0, 0.95, 0.60))
			continue
		if br == "arcane":
			canvas.draw_line(p - dir * 8.0, p, Color(0.55, 0.65, 1.0, 0.5), 3.0)
			canvas.draw_circle(p, 3.0, Color(0.70, 0.80, 1.0))
			canvas.draw_circle(p, 1.4, Color.WHITE)
			continue
		if k == "arrow":
			canvas.draw_line(p - dir * 8.0, p + dir * 3.0, Color(0.95, 0.88, 0.58), 1.8)
			canvas.draw_line(p + dir * 1.0, p + dir * 4.0, Color.WHITE, 2.0)
		elif k == "frost":
			canvas.draw_line(p - dir * 7.0, p, Color(0.45, 0.88, 1.0, 0.45), 3.0)
			canvas.draw_circle(p, 3.0, Color(0.72, 0.96, 1.0))
			canvas.draw_circle(p, 1.4, Color.WHITE)
		else:
			canvas.draw_line(p - dir * 8.0, p, Color(0.75, 0.35, 1.0, 0.5), 3.5)
			canvas.draw_circle(p, 3.5, Color(0.92, 0.52, 1.0))
			canvas.draw_circle(p, 1.5, Color.WHITE)

	# Jagged Lightning Arcs
	for arc in lightning_arcs:
		var pts: Array = arc["points"]
		var a := clampf(float(arc["ttl"]) / float(arc["max_ttl"]), 0.0, 1.0)
		var c: Color = arc["color"]
		for i in range(pts.size() - 1):
			canvas.draw_line(pts[i], pts[i + 1], Color(c.r, c.g, c.b, a * 0.45), 4.2)
			canvas.draw_line(pts[i], pts[i + 1], Color(1.0, 1.0, 1.0, a), 1.5)

	# Particles
	for pt in particles:
		var a := clampf(float(pt["ttl"]) / float(pt["max_ttl"]), 0.0, 1.0)
		var c: Color = pt["color"]
		var sz := float(pt["size"]) * (0.4 + 0.6 * a)
		canvas.draw_rect(Rect2((pt["pos"] as Vector2) - Vector2(sz * 0.5, sz * 0.5), Vector2(sz, sz)), Color(c.r, c.g, c.b, a))

	# Floating Combat Numbers & Labels
	for ft in floating_texts:
		var a := clampf(float(ft["ttl"]) / float(ft["max_ttl"]) * 1.4, 0.0, 1.0)
		var c: Color = ft["color"]
		var pos: Vector2 = ft["pos"]
		var txt := str(ft["text"])
		var fsz := int(ft["size"])
		canvas.draw_string(font, pos + Vector2(-39, 1), txt, HORIZONTAL_ALIGNMENT_CENTER, 80, fsz, Color(0.05, 0.04, 0.08, a))
		canvas.draw_string(font, pos + Vector2(-40, 0), txt, HORIZONTAL_ALIGNMENT_CENTER, 80, fsz, Color(c.r, c.g, c.b, a))


func draw_cinematic_overlays(canvas: CanvasItem, font: Font) -> void:
	if ult_cinematic_timer > 0.0:
		var a := minf(0.25, ult_cinematic_timer * 0.25)
		canvas.draw_rect(Rect2(0, 22, 480, 2), Color(0.40, 0.68, 1.0, a + 0.1))
		canvas.draw_rect(Rect2(0, 246, 480, 2), Color(1.0, 0.45, 0.68, a + 0.1))
	if boss_cutin_timer > 0.0:
		var a := clampf(minf(boss_cutin_timer * 3.0, (2.7 - boss_cutin_timer) * 7.0), 0.0, 1.0)
		var r := Rect2(7, 26, 214 if boss_cutin_quote != "" else 151, 34)
		canvas.draw_rect(r, Color(0.10, 0.04, 0.09, 0.94 * a))
		canvas.draw_rect(r, Color(1.0, 0.30, 0.34, a), false, 1.0)
		if boss_cutin_tex != null:
			canvas.draw_texture_rect(boss_cutin_tex, Rect2(12, 29, 27, 27), false, Color(1, 1, 1, a))
		canvas.draw_string(font, Vector2(44, 39), boss_cutin_name, HORIZONTAL_ALIGNMENT_LEFT, 166, 9, Color(1, 0.87, 0.68, a))
		var sub := boss_cutin_quote if boss_cutin_quote != "" else boss_cutin_sub
		canvas.draw_string(font, Vector2(44, 51), sub, HORIZONTAL_ALIGNMENT_LEFT, 166, 6, Color(0.95, 0.77, 0.77, a))
	elif wave_banner_timer > 0.0:
		var a := clampf(minf(wave_banner_timer * 3.0, (1.7 - wave_banner_timer) * 7.0), 0.0, 1.0)
		var r := Rect2(7, 26, 151, 16)
		canvas.draw_rect(r, Color(0.05, 0.07, 0.14, 0.90 * a))
		canvas.draw_rect(r, Color(1.0, 0.86, 0.43, 0.65 * a), false, 1.0)
		canvas.draw_string(font, Vector2(13, 37), wave_banner_text, HORIZONTAL_ALIGNMENT_LEFT, 139, 7, Color(1, 0.94, 0.6, a))
	elif intro_timer > 0.0:
		var a := clampf(intro_timer / 0.45, 0.0, 1.0)
		canvas.draw_rect(Rect2(7, 26, 161, 27), Color(0.04, 0.07, 0.16, 0.9 * a))
		canvas.draw_string(font, Vector2(14, 37), intro_title, HORIZONTAL_ALIGNMENT_LEFT, 148, 9, Color(1, 0.94, 0.4, a))
		canvas.draw_string(font, Vector2(14, 47), intro_sub, HORIZONTAL_ALIGNMENT_LEFT, 148, 6, Color(0.76, 0.88, 1, a))
