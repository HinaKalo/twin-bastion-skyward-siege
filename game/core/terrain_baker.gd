class_name TerrainBaker
extends RefCounted
## Bakes each stage's battlefield ground (any world size) into one pixel-art texture, cached per stage:
## dithered biome ground, distance-field roads (rounded joints, edges, per-biome paving), river / chasm / ice /
## lava cracks, a twin-bastion castle at the lane exit, and seeded decorations that avoid roads and pads.
## Animated layers (water glints, rift glow, braziers, snowfall, embers, flowing lane chevrons, castle banners)
## are drawn on top every frame by draw_ground() / draw_foreground().


static var _cache: Dictionary = {} # stage_id -> {tex, braziers, glow_pts, river, chasm}

const BIOMES: Dictionary = {
	"bridge": {
		"ground": [Color(0.20, 0.37, 0.20), Color(0.25, 0.45, 0.22), Color(0.31, 0.53, 0.25), Color(0.37, 0.60, 0.29)],
		"road": [Color(0.46, 0.34, 0.21), Color(0.54, 0.41, 0.26), Color(0.61, 0.48, 0.31)],
		"edge": Color(0.34, 0.25, 0.16), "speck": Color(0.70, 0.60, 0.44), "paving": "dirt",
		"castle": Color(0.60, 0.62, 0.70),
	},
	"rift": {
		"ground": [Color(0.15, 0.13, 0.21), Color(0.19, 0.17, 0.26), Color(0.23, 0.20, 0.31), Color(0.28, 0.24, 0.36)],
		"road": [Color(0.34, 0.29, 0.40), Color(0.40, 0.34, 0.47), Color(0.46, 0.40, 0.54)],
		"edge": Color(0.21, 0.17, 0.27), "speck": Color(0.62, 0.45, 0.80), "paving": "flag",
		"castle": Color(0.50, 0.46, 0.62),
	},
	"siege": {
		"ground": [Color(0.29, 0.29, 0.33), Color(0.34, 0.34, 0.38), Color(0.39, 0.39, 0.43), Color(0.44, 0.44, 0.48)],
		"road": [Color(0.42, 0.40, 0.37), Color(0.50, 0.47, 0.43), Color(0.58, 0.55, 0.50)],
		"edge": Color(0.24, 0.23, 0.26), "speck": Color(0.36, 0.50, 0.28), "paving": "cobble",
		"castle": Color(0.62, 0.62, 0.68),
	},
	"snow": {
		"ground": [Color(0.78, 0.84, 0.93), Color(0.84, 0.89, 0.96), Color(0.90, 0.94, 0.99), Color(0.96, 0.98, 1.0)],
		"road": [Color(0.60, 0.68, 0.80), Color(0.66, 0.74, 0.86), Color(0.72, 0.80, 0.91)],
		"edge": Color(0.50, 0.58, 0.72), "speck": Color(1.0, 1.0, 1.0), "paving": "snow",
		"castle": Color(0.70, 0.76, 0.86),
	},
	"abyss": {
		"ground": [Color(0.07, 0.05, 0.11), Color(0.10, 0.07, 0.15), Color(0.13, 0.09, 0.19), Color(0.16, 0.11, 0.23)],
		"road": [Color(0.21, 0.16, 0.27), Color(0.26, 0.20, 0.33), Color(0.31, 0.24, 0.39)],
		"edge": Color(0.42, 0.18, 0.60), "speck": Color(0.80, 0.35, 1.0), "paving": "brick",
		"castle": Color(0.42, 0.38, 0.52),
	},
}

const BAYER: Array[int] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]

const DECOR: Dictionary = {
	"tree": {"w": 14, "outline": Color(0.06, 0.12, 0.06), "pal": {"L": Color(0.27, 0.52, 0.24), "l": Color(0.18, 0.38, 0.17), "B": Color(0.40, 0.66, 0.32), "T": Color(0.44, 0.29, 0.16), "t": Color(0.30, 0.20, 0.11)},
		"rows": ["....LLBLL.....", "..LLBBLLLLL...", ".LLBLLLLLlLL..", "LLBLLLLlLLLLL.", "LlLLLLLLLLlLL.", "LLLLlLLLLLLLl.", ".LLLLLLLlLLL..", "..lLLLLLLLl...", "....llTTll....", "......TT......", "......TT......", ".....tTTt....."]},
	"pine": {"w": 12, "outline": Color(0.05, 0.12, 0.12), "pal": {"P": Color(0.16, 0.38, 0.32), "p": Color(0.10, 0.26, 0.24), "S": Color(0.94, 0.97, 1.0), "T": Color(0.40, 0.28, 0.18)},
		"rows": [".....S......", "....SPS.....", "...SPPpS....", "....PPp.....", "...SPPPpS...", "..SPPPPPpS..", "....PPPp....", "..SPPPPPPpS.", ".SPPPPPPPPpS", "SPPPPPPPPPpS", ".....TT.....", ".....TT....."]},
	"bush": {"w": 10, "outline": Color(0.06, 0.12, 0.06), "pal": {"L": Color(0.26, 0.50, 0.24), "l": Color(0.18, 0.36, 0.17), "B": Color(0.40, 0.64, 0.32), "F": Color(1.0, 0.70, 0.80)},
		"rows": ["..LBLL....", ".LBLLFL...", "LLLLLlLL..", "LlLFLLLLL.", ".lllllll.."]},
	"rock": {"w": 8, "outline": Color(0.10, 0.10, 0.12), "pal": {"R": Color(0.56, 0.56, 0.60), "r": Color(0.38, 0.38, 0.44), "W": Color(0.72, 0.72, 0.76)},
		"rows": ["..RWR...", ".RWRRR..", "RRRRrRR.", "rrrrrrr."]},
	"snowrock": {"w": 8, "outline": Color(0.20, 0.26, 0.36), "pal": {"R": Color(0.52, 0.58, 0.68), "r": Color(0.38, 0.44, 0.54), "W": Color(0.98, 1.0, 1.0)},
		"rows": ["..WWW...", ".WWWWR..", "RRWRrRR.", "rrrrrrr."]},
	"crystal": {"w": 7, "outline": Color(0.10, 0.04, 0.16), "pal": {"P": Color(0.78, 0.46, 1.0), "p": Color(0.50, 0.22, 0.78), "W": Color(0.96, 0.86, 1.0)},
		"rows": ["...W...", "..PWp..", "..PPp..", ".PPPpp.", ".PWPpp.", ".PPPpp.", "..Ppp.."]},
	"redcrystal": {"w": 7, "outline": Color(0.14, 0.02, 0.04), "pal": {"P": Color(1.0, 0.42, 0.30), "p": Color(0.70, 0.16, 0.14), "W": Color(1.0, 0.86, 0.70)},
		"rows": ["...W...", "..PWp..", "..PPp..", ".PPPpp.", ".PWPpp.", ".PPPpp.", "..Ppp.."]},
	"icecrystal": {"w": 7, "outline": Color(0.10, 0.20, 0.34), "pal": {"P": Color(0.70, 0.92, 1.0), "p": Color(0.42, 0.68, 0.92), "W": Color(1.0, 1.0, 1.0)},
		"rows": ["...W...", "..PWp..", "..PPp..", ".PPPpp.", ".PWPpp.", ".PPPpp.", "..Ppp.."]},
	"monolith": {"w": 8, "outline": Color(0.06, 0.04, 0.10), "pal": {"O": Color(0.22, 0.18, 0.32), "o": Color(0.14, 0.11, 0.22), "P": Color(0.85, 0.50, 1.0)},
		"rows": ["..OOOo..", ".OOOOoo.", ".OOPOoo.", ".OOOOoo.", ".OOPOoo.", ".OOOOoo.", ".OOOOoo.", ".OOOOoo.", "OOOOOooo", "oooooooo"]},
	"brazier": {"w": 8, "outline": Color(0.08, 0.06, 0.06), "pal": {"I": Color(0.40, 0.38, 0.40), "i": Color(0.24, 0.22, 0.24), "E": Color(1.0, 0.55, 0.20)},
		"rows": [".EEEEEE.", "IIIIIIII", ".iIIIIi.", "..iIIi..", "..iIIi..", ".iiiiii."]},
	"crate": {"w": 8, "outline": Color(0.10, 0.06, 0.04), "pal": {"W": Color(0.62, 0.44, 0.24), "w": Color(0.44, 0.30, 0.16)},
		"rows": ["WWWWWWW.", "WwWWWwW.", "WWwWwWW.", "WWWwWWW.", "WwWWWwW.", "wwwwwww."]},
}


static func world_size(stage_def: Dictionary) -> Vector2i:
	var w: Vector2 = stage_def.get("world", Vector2(480, 270))
	return Vector2i(int(w.x), int(w.y))


static func road_polylines(stage_def: Dictionary) -> Array:
	if stage_def.has("graph"):
		return MapGraph.all_edge_polylines(stage_def["graph"])
	var out: Array = []
	for ldef in stage_def.get("lanes", []):
		out.append(PackedVector2Array(ldef["points"]))
	return out


static func gate_pos(stage_def: Dictionary) -> Vector2:
	if stage_def.has("graph"):
		return stage_def["graph"]["nodes"][stage_def["graph"]["gate"]]
	return Vector2(435, 136)


static func draw_ground(canvas: CanvasItem, stage_def: Dictionary, biome: String, t: float, portal_active: bool = false) -> void:
	var c := _stage_cache(stage_def, biome)
	canvas.draw_texture(c["tex"], Vector2.ZERO)
	var ws := world_size(stage_def)
	match biome:
		"bridge":
			var river: PackedVector2Array = c["river"]
			if river.size() > 1:
				for i in range(40):
					var f := fmod(float(i) / 40.0 + t * 0.02, 1.0)
					var idx := int(f * float(river.size() - 1))
					var p := river[idx] + Vector2(sin(float(i) * 2.3) * 7.0, 0)
					var a := 0.35 + 0.35 * sin(t * 3.0 + float(i))
					canvas.draw_line(p, p + Vector2(4, 0), Color(0.85, 0.97, 1.0, a), 1.0)
		"rift":
			var chasm: PackedVector2Array = c["chasm"]
			if chasm.size() > 1:
				var pulse := 0.6 + 0.4 * sin(t * 3.0)
				canvas.draw_polyline(chasm, Color(0.80, 0.35, 1.0, 0.35 * pulse), 5.0)
				canvas.draw_polyline(chasm, Color(1.0, 0.65, 1.0, 0.75 * pulse), 1.0)
				for i in range(16):
					var f := fmod(float(i) * 0.137 + t * 0.06, 1.0)
					var p := _point_at(chasm, f * _poly_len(chasm))
					var rise := fmod(t * 12.0 + float(i) * 7.0, 16.0)
					canvas.draw_rect(Rect2(p + Vector2(sin(t + i) * 3.0, -rise), Vector2(1, 1)), Color(1.0, 0.7, 1.0, 1.0 - rise / 16.0))
		"abyss":
			var pts: Array = c["glow_pts"]
			for i in range(pts.size()):
				var a := 0.25 + 0.35 * maxf(0.0, sin(t * 2.0 + float(i) * 0.7))
				canvas.draw_rect(Rect2(pts[i], Vector2(1, 1)), Color(1.0, 0.45, 0.95, a))
		"snow":
			for i in range(36):
				var p := Vector2(fmod(float(i) * 197.0, float(ws.x) - 80.0) + 10.0, fmod(float(i) * 113.0, float(ws.y) - 40.0) + 20.0)
				var a := maxf(0.0, sin(t * 2.0 + float(i) * 1.7))
				canvas.draw_rect(Rect2(p, Vector2(1, 1)), Color(1, 1, 1, a))
	for bp in c["braziers"]:
		var fl := sin(t * 14.0 + bp.x) * 1.2
		canvas.draw_circle(bp + Vector2(0, -2), 14.0, Color(1.0, 0.55, 0.18, 0.10 + 0.04 * sin(t * 9.0 + bp.y)))
		canvas.draw_colored_polygon(PackedVector2Array([bp + Vector2(-3, -1), bp + Vector2(3, -1), bp + Vector2(0, -8 + fl)]), Color(1.0, 0.48, 0.12))
		canvas.draw_colored_polygon(PackedVector2Array([bp + Vector2(-1.5, -1), bp + Vector2(1.5, -1), bp + Vector2(0, -5 + fl * 0.5)]), Color(1.0, 0.94, 0.40))
	# The interior gate stays sealed until the authored breach.
	if portal_active and stage_def.has("graph"):
		var g: Dictionary = stage_def["graph"]
		for sp in (g["spawns"] as Dictionary).keys():
			var p: Vector2 = g["nodes"][g["spawns"][sp]]
			if sp == "portal":
				for k in range(3):
					var r := 6.0 + float(k) * 4.0 + sin(t * 3.0 + float(k)) * 1.5
					canvas.draw_arc(p, r, t * (1.5 + k) , t * (1.5 + k) + TAU * 0.7, 18, Color(0.85, 0.40, 1.0, 0.7 - float(k) * 0.18), 1.5)
				canvas.draw_circle(p, 4.0, Color(0.10, 0.02, 0.16))
	# flowing chevrons toward the gate
	for pts in c["roads"]:
		var poly: PackedVector2Array = pts
		var total := _poly_len(poly)
		var d := fmod(t * 14.0, 40.0)
		while d < total - 12.0:
			var pr := _point_at(poly, d)
			var pr2 := _point_at(poly, d + 3.0)
			var dir := (pr2 - pr).normalized()
			var perp := Vector2(-dir.y, dir.x)
			canvas.draw_polyline(PackedVector2Array([pr - dir * 2.0 + perp * 3.0, pr + dir * 2.0, pr - dir * 2.0 - perp * 3.0]), Color(1, 1, 1, 0.12), 1.0)
			d += 40.0


static func draw_foreground(canvas: CanvasItem, stage_def: Dictionary, biome: String, t: float) -> void:
	var _c := _stage_cache(stage_def, biome)
	var ws := world_size(stage_def)
	var gate := gate_pos(stage_def)
	for spec in [[gate + Vector2(22, -92), UIKit.P1], [gate + Vector2(22, 20), UIKit.P2]]:
		var base: Vector2 = spec[0]
		var col: Color = spec[1]
		canvas.draw_line(base, base + Vector2(0, -12), Color(0.85, 0.72, 0.36), 1.0)
		var pts := PackedVector2Array()
		for k in range(6):
			var x := float(k) * 2.0
			pts.append(base + Vector2(1 + x, -12 + sin(t * 6.0 - x * 0.6) * 1.2))
		for k in range(5, -1, -1):
			var x := float(k) * 2.0
			pts.append(base + Vector2(1 + x, -7 + sin(t * 6.0 - x * 0.6) * 1.2))
		canvas.draw_colored_polygon(pts, col)
	var area_k := float(ws.x * ws.y) / (480.0 * 270.0)
	match biome:
		"snow":
			for i in range(int(40 * area_k)):
				var x := fmod(float(i) * 61.7 + t * (8.0 + float(i % 5) * 2.0) + sin(t + float(i)) * 6.0, float(ws.x))
				var y := fmod(float(i) * 37.3 + t * (14.0 + float(i % 4) * 4.0), float(ws.y))
				canvas.draw_rect(Rect2(x, y, 1, 1), Color(1, 1, 1, 0.75))
		"abyss":
			for i in range(int(18 * area_k)):
				var x := fmod(float(i) * 83.1 + sin(t * 0.7 + float(i)) * 10.0, float(ws.x))
				var y := float(ws.y) - fmod(float(i) * 29.0 + t * (10.0 + float(i % 3) * 5.0), float(ws.y))
				canvas.draw_rect(Rect2(x, y, 1, 1), Color(1.0, 0.5, 0.9, 0.7))


static func _poly_len(pts: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(pts.size() - 1):
		total += pts[i].distance_to(pts[i + 1])
	return total


static func _point_at(pts: PackedVector2Array, dist: float) -> Vector2:
	var acc := 0.0
	for i in range(pts.size() - 1):
		var seg := pts[i].distance_to(pts[i + 1])
		if acc + seg >= dist:
			return pts[i].lerp(pts[i + 1], (dist - acc) / maxf(0.001, seg))
		acc += seg
	return pts[pts.size() - 1]


static func _stage_cache(stage_def: Dictionary, biome: String) -> Dictionary:
	var key := "%s|%s|%s" % [str(stage_def.get("id", "?")), biome, str(stage_def.get("world", ""))]
	if not _cache.has(key):
		_cache[key] = _bake(stage_def, biome)
	return _cache[key]


# ------------------------------------------------------------------ baking

static func _seg_field(field: PackedFloat32Array, pts: PackedVector2Array, reach: float, w: int, h: int) -> void:
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var x0 := maxi(0, int(floor(minf(a.x, b.x) - reach)))
		var x1 := mini(w - 1, int(ceil(maxf(a.x, b.x) + reach)))
		var y0 := maxi(0, int(floor(minf(a.y, b.y) - reach)))
		var y1 := mini(h - 1, int(ceil(maxf(a.y, b.y) + reach)))
		var ab := b - a
		var len2 := maxf(0.0001, ab.length_squared())
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				var p := Vector2(x + 0.5, y + 0.5)
				var tt := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
				var d := p.distance_to(a + ab * tt)
				var idx := y * w + x
				if d < field[idx]:
					field[idx] = d


static func _hash01(x: int, y: int, s: int) -> float:
	var hh := (x * 374761393 + y * 668265263 + s * 1442695041) & 0x7fffffff
	hh = ((hh ^ (hh >> 13)) * 1274126177) & 0x7fffffff
	return float(hh & 0xffff) / 65535.0


static func _bake(stage_def: Dictionary, biome: String) -> Dictionary:
	var b: Dictionary = BIOMES.get(biome, BIOMES["bridge"])
	var ws := world_size(stage_def)
	var w := ws.x
	var h := ws.y
	var sid := str(stage_def.get("id", "stage"))
	var seed_v := absi(hash(sid))
	var noise := FastNoiseLite.new()
	noise.seed = seed_v
	noise.frequency = 0.035
	noise.fractal_octaves = 3
	var detail := FastNoiseLite.new()
	detail.seed = seed_v + 7
	detail.frequency = 0.22
	var crack := FastNoiseLite.new()
	crack.seed = seed_v + 13
	crack.frequency = 0.02
	crack.fractal_type = FastNoiseLite.FRACTAL_RIDGED

	var roads := road_polylines(stage_def)
	var road := PackedFloat32Array()
	road.resize(w * h)
	road.fill(99.0)
	for poly in roads:
		_seg_field(road, poly, 16.0, w, h)

	var features: Dictionary = stage_def.get("features", {})
	var river_pts := PackedVector2Array()
	var water := PackedFloat32Array()
	if biome == "bridge":
		if features.has("river"):
			river_pts = PackedVector2Array(features["river"])
		elif not stage_def.has("graph"):
			for ry in range(0, 18):
				river_pts.append(Vector2(184.0 + sin(float(ry) * 0.45) * 6.5, 18.0 + float(ry) * 14.0))
		if river_pts.size() > 1:
			water.resize(w * h)
			water.fill(99.0)
			_seg_field(water, river_pts, 24.0, w, h)
	var chasm_pts := PackedVector2Array()
	var chasm := PackedFloat32Array()
	if biome == "rift":
		chasm_pts = PackedVector2Array(features.get("chasm", [Vector2(205, 18), Vector2(228, 88), Vector2(250, 136), Vector2(224, 186), Vector2(252, 252)]))
		chasm.resize(w * h)
		chasm.fill(99.0)
		_seg_field(chasm, chasm_pts, 12.0, w, h)

	var ground: Array = b["ground"]
	var rcols: Array = b["road"]
	var edge: Color = b["edge"]
	var speck: Color = b["speck"]
	var paving := str(b["paving"])
	var data := PackedByteArray()
	data.resize(w * h * 4)
	var glow_pts: Array = []
	var has_water := water.size() > 0
	var has_chasm := chasm.size() > 0

	for y in range(h):
		for x in range(w):
			var i := y * w + x
			var n := noise.get_noise_2d(x, y) * 0.5 + 0.5
			var dn := detail.get_noise_2d(x, y)
			var bay := float(BAYER[(y % 4) * 4 + (x % 4)]) / 16.0
			var tone := clampi(int(n * 4.0 + dn * 0.6 + (bay - 0.5) * 0.9), 0, 3)
			var col: Color = ground[tone]
			var hsh := _hash01(x, y, seed_v)
			if biome == "siege":
				var bx := (x + ((y / 10) % 2) * 9) % 18
				if y % 10 == 0 or bx == 0:
					col = col.darkened(0.22)
				elif hsh < 0.02:
					col = speck
			elif biome == "bridge" and hsh < 0.012:
				col = Color(1.0, 0.90, 0.40) if hsh < 0.006 else Color(0.95, 0.60, 0.72)
			elif biome == "snow":
				if dn > 0.45 and n > 0.55:
					col = Color(0.72, 0.86, 0.97) if (x + y) % 9 != 0 else Color(0.95, 1.0, 1.0)
			elif biome == "abyss":
				var cr := crack.get_noise_2d(x, y)
				if cr > 0.86:
					col = Color(0.55, 0.18, 0.70) if cr > 0.93 else Color(0.30, 0.10, 0.40)
					if cr > 0.93 and hsh < 0.06:
						glow_pts.append(Vector2(x, y))
			elif biome == "rift" and hsh < 0.01:
				col = speck
			if has_water:
				var wd := water[i]
				if wd < 19.5:
					if wd < 9.0:
						col = Color(0.11, 0.31, 0.53) if (x + y * 2) % 7 != 0 else Color(0.13, 0.36, 0.58)
					elif wd < 14.0:
						col = Color(0.16, 0.43, 0.65)
					elif wd < 17.0:
						col = Color(0.29, 0.60, 0.76)
					else:
						col = Color(0.62, 0.55, 0.38) if tone % 2 == 0 else Color(0.56, 0.49, 0.33)
			if has_chasm:
				var cd := chasm[i]
				if cd < 7.0:
					col = Color(0.04, 0.02, 0.07) if cd < 5.0 else Color(0.14, 0.05, 0.20)
				elif cd < 9.0:
					col = Color(0.30, 0.12, 0.42)
			var rd := road[i]
			if rd < 12.5:
				if rd >= 10.8:
					col = col.darkened(0.25)
				elif rd >= 8.8:
					col = edge
				else:
					var over_water := has_water and water[i] < 19.5
					if over_water:
						col = Color(0.56, 0.37, 0.19) if x % 4 != 0 else Color(0.34, 0.21, 0.10)
						if rd > 7.5:
							col = Color(0.70, 0.50, 0.26)
					else:
						col = _paving(paving, rcols, x, y, dn, hsh)
			var o := i * 4
			data[o] = int(clampf(col.r, 0.0, 1.0) * 255.0)
			data[o + 1] = int(clampf(col.g, 0.0, 1.0) * 255.0)
			data[o + 2] = int(clampf(col.b, 0.0, 1.0) * 255.0)
			data[o + 3] = 255

	var img := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var braziers: Array = []
	var gate := gate_pos(stage_def)
	_place_decor(img, stage_def, biome, road, water, chasm, rng, braziers, w, h, gate)
	_paint_landmarks(img, stage_def)
	_paint_castle(img, b["castle"], biome, Vector2i(int(gate.x), int(gate.y)), w, h)
	if glow_pts.size() > 400:
		glow_pts = glow_pts.slice(0, 400)
	return {"tex": ImageTexture.create_from_image(img), "braziers": braziers, "glow_pts": glow_pts, "river": river_pts, "chasm": chasm_pts, "roads": roads}


static func _paint_landmarks(img: Image, stage: Dictionary) -> void:
	var sprites := {}
	for mark in stage.get("landmarks", []):
		var id := str(mark[0])
		if not sprites.has(id):
			var tex := load("res://game/art/battlefield/%s.png" % id) as Texture2D
			if tex == null:
				continue
			var sprite := tex.get_image()
			sprite.convert(Image.FORMAT_RGBA8)
			sprites[id] = sprite
		var sprite: Image = sprites[id]
		var extent := sprite.get_size()
		var foot := Vector2i(mark[1])
		img.blend_rect(sprite, Rect2i(Vector2i.ZERO, extent), foot - Vector2i(extent.x / 2, extent.y - 3))


static func _paving(kind: String, rc: Array, x: int, y: int, dn: float, hsh: float) -> Color:
	match kind:
		"dirt":
			var c: Color = rc[clampi(int(dn * 1.5 + 1.5), 0, 2)]
			if hsh < 0.05:
				c = c.lightened(0.18)
			elif hsh > 0.96:
				c = c.darkened(0.18)
			return c
		"cobble":
			var cx := (x + ((y / 5) % 2) * 3) / 6
			var cy := y / 5
			if (x + ((y / 5) % 2) * 3) % 6 == 0 or y % 5 == 0:
				return (rc[0] as Color).darkened(0.25)
			return rc[clampi(int(_hash01(cx, cy, 3) * 3.0), 0, 2)]
		"flag":
			var cx2 := (x + ((y / 8) % 2) * 4) / 8
			var cy2 := y / 8
			if (x + ((y / 8) % 2) * 4) % 8 == 0 or y % 8 == 0:
				return (rc[0] as Color).darkened(0.3)
			return rc[clampi(int(_hash01(cx2, cy2, 5) * 3.0), 0, 2)]
		"brick":
			if (x + ((y / 4) % 2) * 4) % 8 == 0 or y % 4 == 0:
				return Color(0.36, 0.12, 0.48)
			return rc[clampi(int(_hash01((x + ((y / 4) % 2) * 4) / 8, y / 4, 9) * 3.0), 0, 2)]
		"snow":
			var c2: Color = rc[clampi(int(dn * 1.5 + 1.5), 0, 2)]
			if hsh < 0.03:
				c2 = Color(1, 1, 1)
			return c2
	return rc[1]


static func _decor_image(dname: String) -> Image:
	var d: Dictionary = DECOR[dname]
	return PixelCreepSprites._rasterize(d["rows"], int(d["w"]), d["pal"], d["outline"])


static func _free_spot(p: Vector2, r: float, stage_def: Dictionary, road: PackedFloat32Array, water: PackedFloat32Array, chasm: PackedFloat32Array, taken: Array, w: int, h: int, gate: Vector2) -> bool:
	if p.x < 4 or p.x > gate.x - 14.0 or p.y < 10 or p.y > float(h) - 4.0:
		return false
	var ix := clampi(int(p.x), 0, w - 1)
	var iy := clampi(int(p.y), 0, h - 1)
	for dy in [-r, 0.0, r]:
		for dx in [-r, 0.0, r]:
			var jx := clampi(ix + int(dx), 0, w - 1)
			var jy := clampi(iy + int(dy), 0, h - 1)
			if road[jy * w + jx] < 15.0:
				return false
			if water.size() > 0 and water[jy * w + jx] < 21.0:
				return false
			if chasm.size() > 0 and chasm[jy * w + jx] < 11.0:
				return false
	for pad in stage_def.get("pads", []):
		if p.distance_to(pad["pos"]) < 22.0 + r:
			return false
	for hs in stage_def.get("hero_spawns", []):
		if p.distance_to(hs) < 14.0 + r:
			return false
	for q in taken:
		if p.distance_to(q) < r + 6.0:
			return false
	return true


static func _place_decor(img: Image, stage_def: Dictionary, biome: String, road: PackedFloat32Array, water: PackedFloat32Array, chasm: PackedFloat32Array, rng: RandomNumberGenerator, braziers: Array, w: int, h: int, gate: Vector2) -> void:
	var plan: Array = []
	match biome:
		"bridge": plan = [["tree", 12, 8.0], ["bush", 12, 5.0], ["rock", 6, 4.0]]
		"rift": plan = [["monolith", 6, 5.0], ["crystal", 12, 4.0], ["rock", 10, 4.0]]
		"siege": plan = [["brazier", 6, 5.0], ["crate", 8, 4.0], ["bush", 5, 5.0]]
		"snow": plan = [["pine", 16, 7.0], ["snowrock", 8, 4.0], ["icecrystal", 8, 4.0]]
		"abyss": plan = [["redcrystal", 10, 4.0], ["crystal", 8, 4.0], ["monolith", 5, 5.0], ["rock", 6, 4.0]]
	var area_k := maxf(1.0, float(w * h) / (480.0 * 270.0) * 0.8)
	var taken: Array = []
	for spec in plan:
		var dname: String = spec[0]
		var want: int = int(float(spec[1]) * area_k)
		var r: float = spec[2]
		var dimg := _decor_image(dname)
		var placed := 0
		var tries := 0
		while placed < want and tries < want * 40:
			tries += 1
			var p := Vector2(rng.randf_range(8, float(w) - 8.0), rng.randf_range(12, float(h) - 6.0))
			if not _free_spot(p, r, stage_def, road, water, chasm, taken, w, h, gate):
				continue
			taken.append(p)
			placed += 1
			var dst := Vector2i(int(p.x - dimg.get_width() * 0.5), int(p.y - dimg.get_height()))
			_shadow(img, Vector2i(int(p.x), int(p.y)), int(dimg.get_width() * 0.4), w, h)
			img.blend_rect(dimg, Rect2i(Vector2i.ZERO, dimg.get_size()), dst)
			if dname == "brazier":
				braziers.append(Vector2(p.x, p.y - 5))
	if biome == "bridge" and water.size() > 0:
		var river: PackedVector2Array = PackedVector2Array(stage_def.get("features", {}).get("river", []))
		for k in range(int(10 * area_k * 0.5)):
			if river.size() < 2:
				break
			var base := _point_at(river, rng.randf() * _poly_len(river))
			var lx := base.x + rng.randf_range(-7, 7)
			var ly := base.y + rng.randf_range(-6, 6)
			var li := clampi(int(ly), 0, h - 1) * w + clampi(int(lx), 0, w - 1)
			if road[li] < 16.0:
				continue
			for dy in range(-2, 3):
				for dx in range(-3, 4):
					if dx * dx + dy * dy * 2 <= 9:
						img.set_pixel(clampi(int(lx) + dx, 0, w - 1), clampi(int(ly) + dy, 0, h - 1), Color(0.22, 0.56, 0.26) if dx != 1 else Color(0.16, 0.42, 0.20))
			img.set_pixel(clampi(int(lx) - 1, 0, w - 1), clampi(int(ly) - 1, 0, h - 1), Color(1.0, 0.70, 0.80))


static func _shadow(img: Image, base: Vector2i, rx: int, w: int, h: int) -> void:
	for dx in range(-rx, rx + 1):
		for dy in range(-1, 2):
			var x := base.x + dx
			var y := base.y + dy
			if x >= 0 and x < w and y >= 0 and y < h:
				img.set_pixel(x, y, img.get_pixel(x, y).darkened(0.25))


static func _px(img: Image, x: int, y: int, c: Color, w: int, h: int) -> void:
	if x >= 0 and x < w and y >= 0 and y < h:
		img.set_pixel(x, y, c)


static func _paint_castle(img: Image, stone: Color, biome: String, g: Vector2i, w: int, h: int) -> void:
	var ink := Color(0.07, 0.06, 0.09)
	var st_hi := stone.lightened(0.18)
	var st_dk := stone.darkened(0.30)
	var st_face := stone.darkened(0.45)
	var top := maxi(0, g.y - 200)
	var bottom := mini(h, g.y + 200)
	for y in range(top, bottom):
		for x in range(g.x + 11, w):
			var c := stone
			if (x + ((y / 4) % 2) * 3) % 7 == 0 or y % 4 == 0:
				c = st_dk
			_px(img, x, y, c, w, h)
		for x in range(g.x + 5, g.x + 11):
			_px(img, x, y, st_face if y % 4 != 0 else st_face.darkened(0.2), w, h)
		_px(img, g.x + 4, y, ink, w, h)
	for y in range(top, bottom, 8):
		for yy in range(y, y + 4):
			for xx in range(g.x + 1, g.x + 5):
				_px(img, xx, yy, st_hi, w, h)
			_px(img, g.x, yy, ink, w, h)
	var roof_cols := [UIKit.P1.darkened(0.25), UIKit.P2.darkened(0.25)]
	var towers := [Vector2i(g.x + 22, g.y - 60), Vector2i(g.x + 22, g.y + 52)]
	for ti in range(2):
		var tc: Vector2i = towers[ti]
		for y in range(tc.y - 18, tc.y + 16):
			for x in range(tc.x - 14, tc.x + 15):
				var is_edge := absi(x - tc.x) >= 13 or y == tc.y + 15
				var c := st_hi if x < tc.x - 6 else (stone if x < tc.x + 6 else st_dk)
				if (y % 5 == 0) or ((x + (y / 5) * 4) % 9 == 0):
					c = c.darkened(0.18)
				_px(img, x, y, ink if is_edge else c, w, h)
		for y in range(tc.y - 4, tc.y + 3):
			for x in range(tc.x - 2, tc.x + 2):
				_px(img, x, y, Color(1.0, 0.80, 0.40) if y > tc.y - 4 else ink, w, h)
		var rc: Color = roof_cols[ti]
		for row in range(14):
			var half := 1 + row
			var y := tc.y - 32 + row
			for x in range(tc.x - half, tc.x + half + 1):
				var c := rc.lightened(0.25) if x < tc.x else rc
				if (x + row) % 4 == 0:
					c = c.darkened(0.15)
				_px(img, x, y, c, w, h)
			_px(img, tc.x - half - 1, y, ink, w, h)
			_px(img, tc.x + half + 1, y, ink, w, h)
	for y in range(g.y - 26, g.y + 26):
		for x in range(g.x - 5, g.x + 35):
			var is_edge := x == g.x - 5 or x == g.x + 34 or y == g.y - 26 or y == g.y + 25
			var c := stone if (y % 5 != 0 and (x + (y / 5) * 3) % 8 != 0) else st_dk
			if x < g.x + 3:
				c = st_face
			_px(img, x, y, ink if is_edge else c, w, h)
	for x in range(g.x - 7, g.x + 35, 6):
		for y in range(g.y - 30, g.y - 26):
			for xx in range(x, x + 4):
				_px(img, xx, y, st_hi, w, h)
	for y in range(g.y - 13, g.y + 14):
		for x in range(g.x - 5, g.x + 13):
			var arch := y > g.y - 9 or (float(x - (g.x + 4)) * float(x - (g.x + 4)) + float(y - (g.y - 9)) * float(y - (g.y - 9)) * 2.0) < 64.0
			if arch:
				var c := Color(0.06, 0.05, 0.08)
				if x % 3 == 0 or y % 4 == 0:
					c = Color(0.30, 0.28, 0.30)
				_px(img, x, y, c, w, h)
	for ty in [g.y - 18, g.y + 18]:
		_px(img, g.x - 3, ty, Color(1.0, 0.85, 0.40), w, h)
		_px(img, g.x - 3, ty + 1, Color(1.0, 0.50, 0.15), w, h)
	if biome == "snow":
		for x in range(g.x + 1, w):
			for y in [top, top + 1, g.y - 26, g.y - 25]:
				_px(img, x, y, Color(0.96, 0.98, 1.0), w, h)
