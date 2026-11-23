class_name TerrainBaker
extends RefCounted
## Bakes each stage's battlefield ground into a single 480x270 pixel-art texture (cached per stage):
## dithered biome ground, distance-field roads (rounded joints, edges, per-biome paving), river / chasm / ice /
## lava cracks, a twin-bastion castle at the lane exit, and seeded decorations that avoid roads and pads.
## Animated layers (water glints, rift glow, braziers, snowfall, embers, flowing lane chevrons, castle banners)
## are drawn on top every frame by draw_ground() / draw_foreground().

const W := 480
const H := 270

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


static func draw_ground(canvas: CanvasItem, stage_def: Dictionary, biome: String, t: float) -> void:
	var c := _stage_cache(stage_def, biome)
	canvas.draw_texture(c["tex"], Vector2.ZERO)
	match biome:
		"bridge":
			var river: PackedVector2Array = c["river"]
			for i in range(18):
				var f := fmod(float(i) / 18.0 + t * 0.035, 1.0)
				var idx := int(f * float(river.size() - 1))
				var p := river[idx] + Vector2(sin(float(i) * 2.3) * 6.0, 0)
				var a := 0.35 + 0.35 * sin(t * 3.0 + float(i))
				canvas.draw_line(p, p + Vector2(4, 0), Color(0.85, 0.97, 1.0, a), 1.0)
		"rift":
			var chasm: PackedVector2Array = c["chasm"]
			var pulse := 0.6 + 0.4 * sin(t * 3.0)
			canvas.draw_polyline(chasm, Color(0.80, 0.35, 1.0, 0.35 * pulse), 5.0)
			canvas.draw_polyline(chasm, Color(1.0, 0.65, 1.0, 0.75 * pulse), 1.0)
			for i in range(8):
				var f := fmod(float(i) * 0.137 + t * 0.06, 1.0)
				var p := chasm[int(f * float(chasm.size() - 1))]
				var rise := fmod(t * 12.0 + float(i) * 7.0, 16.0)
				canvas.draw_rect(Rect2(p + Vector2(sin(t + i) * 3.0, -rise), Vector2(1, 1)), Color(1.0, 0.7, 1.0, 1.0 - rise / 16.0))
		"abyss":
			var pts: Array = c["glow_pts"]
			for i in range(pts.size()):
				var a := 0.25 + 0.35 * maxf(0.0, sin(t * 2.0 + float(i) * 0.7))
				canvas.draw_rect(Rect2(pts[i], Vector2(1, 1)), Color(1.0, 0.45, 0.95, a))
		"snow":
			for i in range(10):
				var p := Vector2(fmod(float(i) * 97.0, 420.0) + 10.0, fmod(float(i) * 53.0, 200.0) + 30.0)
				var a := maxf(0.0, sin(t * 2.0 + float(i) * 1.7))
				canvas.draw_rect(Rect2(p, Vector2(1, 1)), Color(1, 1, 1, a))
	# braziers (siege) / torches
	for bp in c["braziers"]:
		var fl := sin(t * 14.0 + bp.x) * 1.2
		canvas.draw_circle(bp + Vector2(0, -2), 14.0, Color(1.0, 0.55, 0.18, 0.10 + 0.04 * sin(t * 9.0 + bp.y)))
		canvas.draw_colored_polygon(PackedVector2Array([bp + Vector2(-3, -1), bp + Vector2(3, -1), bp + Vector2(0, -8 + fl)]), Color(1.0, 0.48, 0.12))
		canvas.draw_colored_polygon(PackedVector2Array([bp + Vector2(-1.5, -1), bp + Vector2(1.5, -1), bp + Vector2(0, -5 + fl * 0.5)]), Color(1.0, 0.94, 0.40))
	# flowing lane chevrons
	for ldef in stage_def.get("lanes", []):
		var pts := PackedVector2Array(ldef["points"])
		var total := 0.0
		for i in range(pts.size() - 1):
			total += pts[i].distance_to(pts[i + 1])
		var d := fmod(t * 14.0, 40.0)
		while d < total - 30.0:
			var pr := _point_at(pts, d)
			var pr2 := _point_at(pts, d + 3.0)
			var dir := (pr2 - pr).normalized()
			var perp := Vector2(-dir.y, dir.x)
			canvas.draw_polyline(PackedVector2Array([pr - dir * 2.0 + perp * 3.0, pr + dir * 2.0, pr - dir * 2.0 - perp * 3.0]), Color(1, 1, 1, 0.13), 1.0)
			d += 40.0


static func draw_foreground(canvas: CanvasItem, stage_def: Dictionary, biome: String, t: float) -> void:
	var _c := _stage_cache(stage_def, biome)
	# castle banners: P1 on the north tower, P2 on the south tower
	for spec in [[Vector2(457, 44), UIKit.P1], [Vector2(457, 156), UIKit.P2]]:
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
	match biome:
		"snow":
			for i in range(40):
				var x := fmod(float(i) * 61.7 + t * (8.0 + float(i % 5) * 2.0) + sin(t + float(i)) * 6.0, 480.0)
				var y := 22.0 + fmod(float(i) * 37.3 + t * (14.0 + float(i % 4) * 4.0), 226.0)
				canvas.draw_rect(Rect2(x, y, 1, 1), Color(1, 1, 1, 0.75))
		"abyss":
			for i in range(18):
				var x := fmod(float(i) * 83.1 + sin(t * 0.7 + float(i)) * 10.0, 480.0)
				var y := 248.0 - fmod(float(i) * 29.0 + t * (10.0 + float(i % 3) * 5.0), 226.0)
				canvas.draw_rect(Rect2(x, y, 1, 1), Color(1.0, 0.5, 0.9, 0.7))
	# soft vignette on the playfield edges
	for k in range(5):
		var a := 0.06 * float(5 - k)
		canvas.draw_rect(Rect2(0, 22 + k, 480, 1), Color(0, 0, 0, a))
		canvas.draw_rect(Rect2(0, 247 - k, 480, 1), Color(0, 0, 0, a))
		canvas.draw_rect(Rect2(k, 22, 1, 226), Color(0, 0, 0, a))


static func _point_at(pts: PackedVector2Array, dist: float) -> Vector2:
	var acc := 0.0
	for i in range(pts.size() - 1):
		var seg := pts[i].distance_to(pts[i + 1])
		if acc + seg >= dist:
			return pts[i].lerp(pts[i + 1], (dist - acc) / maxf(0.001, seg))
		acc += seg
	return pts[pts.size() - 1]


static func _stage_cache(stage_def: Dictionary, biome: String) -> Dictionary:
	var key := "%s|%s" % [str(stage_def.get("id", "?")), biome]
	if not _cache.has(key):
		_cache[key] = _bake(stage_def, biome)
	return _cache[key]


# ------------------------------------------------------------------ baking

static func _seg_field(field: PackedFloat32Array, pts: PackedVector2Array, reach: float) -> void:
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var x0 := maxi(0, int(floor(minf(a.x, b.x) - reach)))
		var x1 := mini(W - 1, int(ceil(maxf(a.x, b.x) + reach)))
		var y0 := maxi(0, int(floor(minf(a.y, b.y) - reach)))
		var y1 := mini(H - 1, int(ceil(maxf(a.y, b.y) + reach)))
		var ab := b - a
		var len2 := maxf(0.0001, ab.length_squared())
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				var p := Vector2(x + 0.5, y + 0.5)
				var tt := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
				var d := p.distance_to(a + ab * tt)
				var idx := y * W + x
				if d < field[idx]:
					field[idx] = d


static func _hash01(x: int, y: int, s: int) -> float:
	var h := (x * 374761393 + y * 668265263 + s * 1442695041) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h & 0xffff) / 65535.0


static func _bake(stage_def: Dictionary, biome: String) -> Dictionary:
	var b: Dictionary = BIOMES.get(biome, BIOMES["bridge"])
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

	var road := PackedFloat32Array()
	road.resize(W * H)
	road.fill(99.0)
	for ldef in stage_def.get("lanes", []):
		_seg_field(road, PackedVector2Array(ldef["points"]), 16.0)

	var river_pts := PackedVector2Array()
	var water := PackedFloat32Array()
	if biome == "bridge":
		for ry in range(0, 18):
			var y := 18.0 + float(ry) * 14.0
			river_pts.append(Vector2(184.0 + sin(float(ry) * 0.45) * 6.5, y))
		water.resize(W * H)
		water.fill(99.0)
		_seg_field(water, river_pts, 24.0)
	var chasm_pts := PackedVector2Array()
	var chasm := PackedFloat32Array()
	if biome == "rift":
		chasm_pts = PackedVector2Array([Vector2(205, 18), Vector2(228, 88), Vector2(250, 136), Vector2(224, 186), Vector2(252, 252)])
		chasm.resize(W * H)
		chasm.fill(99.0)
		_seg_field(chasm, chasm_pts, 12.0)

	var ground: Array = b["ground"]
	var rcols: Array = b["road"]
	var edge: Color = b["edge"]
	var speck: Color = b["speck"]
	var paving := str(b["paving"])
	var data := PackedByteArray()
	data.resize(W * H * 4)
	var glow_pts: Array = []

	for y in range(H):
		for x in range(W):
			var i := y * W + x
			var n := noise.get_noise_2d(x, y) * 0.5 + 0.5
			var dn := detail.get_noise_2d(x, y)
			var bay := float(BAYER[(y % 4) * 4 + (x % 4)]) / 16.0
			var tone := clampi(int(n * 4.0 + dn * 0.6 + (bay - 0.5) * 0.9), 0, 3)
			var col: Color = ground[tone]
			var hsh := _hash01(x, y, seed_v)
			# biome ground flavor
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
					if cr > 0.93 and hsh < 0.08:
						glow_pts.append(Vector2(x, y))
			elif biome == "rift" and hsh < 0.01:
				col = speck
			# water
			if biome == "bridge":
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
			if biome == "rift":
				var cd := chasm[i]
				if cd < 7.0:
					col = Color(0.04, 0.02, 0.07) if cd < 5.0 else Color(0.14, 0.05, 0.20)
				elif cd < 9.0:
					col = Color(0.30, 0.12, 0.42)
			# roads
			var rd := road[i]
			if rd < 12.5:
				if rd >= 10.8:
					col = col.darkened(0.25)
				elif rd >= 8.8:
					col = edge
				else:
					var over_water := biome == "bridge" and water[i] < 19.5
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

	var img := Image.create_from_data(W, H, false, Image.FORMAT_RGBA8, data)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var braziers: Array = []
	_place_decor(img, stage_def, biome, road, water, chasm, rng, braziers)
	_paint_castle(img, b["castle"], biome)
	if glow_pts.size() > 160:
		glow_pts = glow_pts.slice(0, 160)
	return {"tex": ImageTexture.create_from_image(img), "braziers": braziers, "glow_pts": glow_pts, "river": river_pts, "chasm": chasm_pts}


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


static func _decor_image(name: String) -> Image:
	var d: Dictionary = DECOR[name]
	return PixelCreepSprites._rasterize(d["rows"], int(d["w"]), d["pal"], d["outline"])


static func _free_spot(p: Vector2, r: float, stage_def: Dictionary, road: PackedFloat32Array, water: PackedFloat32Array, chasm: PackedFloat32Array, taken: Array) -> bool:
	if p.x < 4 or p.x > 428 or p.y < 30 or p.y > 244:
		return false
	var ix := clampi(int(p.x), 0, W - 1)
	var iy := clampi(int(p.y), 0, H - 1)
	for dy in [-r, 0.0, r]:
		for dx in [-r, 0.0, r]:
			var jx := clampi(ix + int(dx), 0, W - 1)
			var jy := clampi(iy + int(dy), 0, H - 1)
			if road[jy * W + jx] < 15.0:
				return false
			if water.size() > 0 and water[jy * W + jx] < 21.0:
				return false
			if chasm.size() > 0 and chasm[jy * W + jx] < 11.0:
				return false
	for pad in stage_def.get("pads", []):
		if p.distance_to(pad["pos"]) < 22.0 + r:
			return false
	for h in stage_def.get("hero_spawns", []):
		if p.distance_to(h) < 14.0 + r:
			return false
	for q in taken:
		if p.distance_to(q) < r + 6.0:
			return false
	return true


static func _place_decor(img: Image, stage_def: Dictionary, biome: String, road: PackedFloat32Array, water: PackedFloat32Array, chasm: PackedFloat32Array, rng: RandomNumberGenerator, braziers: Array) -> void:
	var plan: Array = []
	match biome:
		"bridge": plan = [["tree", 12, 8.0], ["bush", 12, 5.0], ["rock", 6, 4.0]]
		"rift": plan = [["monolith", 6, 5.0], ["crystal", 12, 4.0], ["rock", 10, 4.0]]
		"siege": plan = [["brazier", 6, 5.0], ["crate", 8, 4.0], ["bush", 5, 5.0]]
		"snow": plan = [["pine", 16, 7.0], ["snowrock", 8, 4.0], ["icecrystal", 8, 4.0]]
		"abyss": plan = [["redcrystal", 10, 4.0], ["crystal", 8, 4.0], ["monolith", 5, 5.0], ["rock", 6, 4.0]]
	var taken: Array = []
	for spec in plan:
		var name: String = spec[0]
		var want: int = spec[1]
		var r: float = spec[2]
		var dimg := _decor_image(name)
		var placed := 0
		var tries := 0
		while placed < want and tries < want * 60:
			tries += 1
			var p := Vector2(rng.randf_range(8, 426), rng.randf_range(32, 242))
			if not _free_spot(p, r, stage_def, road, water, chasm, taken):
				continue
			taken.append(p)
			placed += 1
			var dst := Vector2i(int(p.x - dimg.get_width() * 0.5), int(p.y - dimg.get_height()))
			_shadow(img, Vector2i(int(p.x), int(p.y)), int(dimg.get_width() * 0.4))
			img.blend_rect(dimg, Rect2i(Vector2i.ZERO, dimg.get_size()), dst)
			if name == "brazier":
				braziers.append(Vector2(p.x, p.y - 5))
	if biome == "bridge":
		# lily pads on the river
		for k in range(7):
			var ly := 40.0 + float(k) * 30.0 + rng.randf_range(-6, 6)
			var lx := 184.0 + sin((ly - 18.0) / 14.0 * 0.45) * 6.5 + rng.randf_range(-7, 7)
			var li := clampi(int(ly), 0, H - 1) * W + clampi(int(lx), 0, W - 1)
			if road[li] < 16.0:
				continue
			for dy in range(-2, 3):
				for dx in range(-3, 4):
					if dx * dx + dy * dy * 2 <= 9:
						img.set_pixel(clampi(int(lx) + dx, 0, W - 1), clampi(int(ly) + dy, 0, H - 1), Color(0.22, 0.56, 0.26) if dx != 1 else Color(0.16, 0.42, 0.20))
			img.set_pixel(clampi(int(lx) - 1, 0, W - 1), clampi(int(ly) - 1, 0, H - 1), Color(1.0, 0.70, 0.80))


static func _shadow(img: Image, base: Vector2i, rx: int) -> void:
	for dx in range(-rx, rx + 1):
		for dy in range(-1, 2):
			var x := base.x + dx
			var y := base.y + dy
			if x >= 0 and x < W and y >= 0 and y < H:
				img.set_pixel(x, y, img.get_pixel(x, y).darkened(0.25))


static func _paint_castle(img: Image, stone: Color, biome: String) -> void:
	var ink := Color(0.07, 0.06, 0.09)
	var st_hi := stone.lightened(0.18)
	var st_dk := stone.darkened(0.30)
	var st_face := stone.darkened(0.45)
	# Curtain wall along the right edge
	for y in range(30, 244):
		for x in range(446, 480):
			var c := stone
			if (x + ((y / 4) % 2) * 3) % 7 == 0 or y % 4 == 0:
				c = st_dk
			img.set_pixel(x, y, c)
		for x in range(440, 446):
			img.set_pixel(x, y, st_face if y % 4 != 0 else st_face.darkened(0.2))
		img.set_pixel(439, y, ink)
	# Crenellations
	for y in range(30, 244, 8):
		for yy in range(y, y + 4):
			for xx in range(436, 440):
				img.set_pixel(xx, yy, st_hi)
			img.set_pixel(435, yy, ink)
	# Twin bastion towers (P1 north / P2 south) with conical roofs
	var roof_cols := [UIKit.P1.darkened(0.25), UIKit.P2.darkened(0.25)]
	var towers := [Vector2i(457, 76), Vector2i(457, 188)]
	for ti in range(2):
		var tc: Vector2i = towers[ti]
		for y in range(tc.y - 18, tc.y + 16):
			for x in range(tc.x - 14, tc.x + 15):
				var edge := absi(x - tc.x) >= 13 or y == tc.y + 15
				var c := st_hi if x < tc.x - 6 else (stone if x < tc.x + 6 else st_dk)
				if (y % 5 == 0) or ((x + (y / 5) * 4) % 9 == 0):
					c = c.darkened(0.18)
				img.set_pixel(x, y, ink if edge else c)
		# window
		for y in range(tc.y - 4, tc.y + 3):
			for x in range(tc.x - 2, tc.x + 2):
				img.set_pixel(x, y, Color(1.0, 0.80, 0.40) if y > tc.y - 4 else ink)
		# roof
		var rc: Color = roof_cols[ti]
		for row in range(14):
			var half := 1 + row
			var y := tc.y - 32 + row
			for x in range(tc.x - half, tc.x + half + 1):
				var c := rc.lightened(0.25) if x < tc.x else rc
				if (x + row) % 4 == 0:
					c = c.darkened(0.15)
				img.set_pixel(clampi(x, 0, W - 1), y, c)
			img.set_pixel(clampi(tc.x - half - 1, 0, W - 1), y, ink)
			img.set_pixel(clampi(tc.x + half + 1, 0, W - 1), y, ink)
	# Gatehouse
	var gy := 136
	for y in range(gy - 26, gy + 26):
		for x in range(430, 470):
			var edge := x == 430 or x == 469 or y == gy - 26 or y == gy + 25
			var c := stone if (y % 5 != 0 and (x + (y / 5) * 3) % 8 != 0) else st_dk
			if x < 438:
				c = st_face
			img.set_pixel(x, y, ink if edge else c)
	for x in range(428, 470, 6):
		for y in range(gy - 30, gy - 26):
			for xx in range(x, x + 4):
				img.set_pixel(clampi(xx, 0, W - 1), y, st_hi)
	# Arched gate (dark) with portcullis
	for y in range(gy - 13, gy + 14):
		for x in range(430, 448):
			var arch := y > gy - 9 or (float(x - 439) * float(x - 439) + float(y - (gy - 9)) * float(y - (gy - 9)) * 2.0) < 64.0
			if arch:
				var c := Color(0.06, 0.05, 0.08)
				if x % 3 == 0 or y % 4 == 0:
					c = Color(0.30, 0.28, 0.30)
				img.set_pixel(x, y, c)
	# Torches flanking the gate
	for ty in [gy - 18, gy + 18]:
		img.set_pixel(432, ty, Color(1.0, 0.85, 0.40))
		img.set_pixel(432, ty + 1, Color(1.0, 0.50, 0.15))
	if biome == "snow":
		for x in range(436, 480):
			for y in [30, 31, 110, 111]:
				img.set_pixel(x, y, Color(0.96, 0.98, 1.0))
