class_name PixelCreepSprites
extends RefCounted
## Authored pixel-art unit sprites (enemies, heroes, soldiers) as ASCII fill maps.
## The loader auto-adds a 1px dark outline around every silhouette, so the art stays crisp and consistent.
## Frames may be literal row arrays or {"from": i, "dy": n, "rows": {row_index: "..."}} derived frames.
## Owner-colored units use palette keys c / C / d which are replaced by the seat color at load time.

static var _cache: Dictionary = {}

const SPRITES: Dictionary = {
	"slime": {
		"w": 16, "outline": Color(0.07, 0.16, 0.07),
		"pal": {"G": Color(0.42, 0.86, 0.36), "g": Color(0.24, 0.60, 0.24), "W": Color(0.86, 1.0, 0.80), "e": Color(0.06, 0.14, 0.06)},
		"frames": [
			["................", "................", "................", "................", "................", "................",
			 "......GGGG......", "....GWWGGGGG....", "...GWWGGGGGGG...", "...GWGGeGGeGG...", "..GGGGGeGGeGGG..", "..GGGGGGGGGGGg..",
			 "..gGGGGGGGGGgg..", "..gggggggggggg..", "................", "................"],
			["................", "................", "................", "................", "................", "................",
			 "................", "......GGGG......", "...GGWWGGGGGG...", "..GWWGGeGGeGGG..", ".GGGGGGeGGeGGGG.", ".GGGGGGGGGGGGGg.",
			 ".gGGGGGGGGGGGgg.", ".gggggggggggggg.", "................", "................"],
		],
	},
	"slimelet": {
		"w": 16, "outline": Color(0.12, 0.18, 0.05),
		"pal": {"G": Color(0.74, 0.92, 0.38), "g": Color(0.46, 0.66, 0.20), "W": Color(0.95, 1.0, 0.85), "e": Color(0.10, 0.14, 0.04)},
		"frames": [
			["................", "................", "................", "................", "................", "................",
			 "................", "................", "................", "......GGG.......", ".....GWGGG......", "....GGeGeGG.....",
			 "....GGGGGGg.....", "....ggggggg.....", "................", "................"],
			{"from": 0, "dy": -2},
		],
	},
	"splitter": {
		"w": 16, "outline": Color(0.20, 0.18, 0.04),
		"pal": {"G": Color(0.82, 0.88, 0.30), "g": Color(0.56, 0.60, 0.16), "W": Color(1.0, 1.0, 0.80), "e": Color(0.15, 0.12, 0.04), "o": Color(0.96, 0.52, 0.20)},
		"frames": [
			["................", "................", "................", "......GGGG......", "....GGWWGGGG....", "...GWWGGGGoGG...",
			 "..GWGGoGGGGGGG..", "..GGGGGGeGGeGG..", ".GGGGGGGeGGeGGG.", ".GGoGGGGGGGGGGG.", ".GGGGGGGGGGoGGg.", ".gGGGGGGGGGGGgg.",
			 ".gggggggggggggg.", "................", "................", "................"],
			{"from": 0, "dy": 1},
		],
	},
	"goblin": {
		"w": 16, "outline": Color(0.08, 0.08, 0.06),
		"pal": {"S": Color(0.48, 0.72, 0.30), "s": Color(0.32, 0.52, 0.22), "A": Color(0.62, 0.64, 0.72), "a": Color(0.40, 0.42, 0.50),
			"H": Color(0.56, 0.58, 0.66), "e": Color(1.0, 0.30, 0.20), "W": Color(0.90, 0.90, 0.95), "m": Color(0.52, 0.34, 0.16), "L": Color(0.30, 0.24, 0.18)},
		"frames": [
			["................", ".............W..", "............WWW.", ".....HHHH....m..", "....HHHHHH...m..", "....SSeSeS...m..",
			 "....SSSSSs...m..", ".....ssss...Sm..", "...AAAAAAAaSSm..", "..SAAAAAAAa..m..", "..SaAAAAAAa..m..", "...aAAAAAa...m..",
			 "....AAAAA....m..", "....LL.LL.......", "...LL...LL......", "................"],
			{"from": 0, "rows": {13: ".....LLL........", 14: "....LL.LL......."}},
		],
	},
	"shield_bearer": {
		"w": 16, "outline": Color(0.07, 0.07, 0.10),
		"pal": {"A": Color(0.64, 0.68, 0.78), "a": Color(0.42, 0.46, 0.56), "I": Color(0.52, 0.54, 0.60), "i": Color(0.33, 0.35, 0.42),
			"Y": Color(0.96, 0.78, 0.30), "e": Color(1.0, 0.30, 0.25), "L": Color(0.30, 0.26, 0.24)},
		"frames": [
			["................", "................", "................", ".....AAAA.......", "....AAAAAa......", "....aeaaea......",
			 "....AAAAAa..IIi.", "...aAAAAAAa.IIIi", "..aAAAAAAAAaIYIi", "..aAAAAAAAAaIIIi", "...aAAAAAAa.IIIi", "....AAAAAa..IIi.",
			 "....aa..aa......", "....LL..LL......", "...LL...LL......", "................"],
			{"from": 0, "rows": {12: ".....aaa........", 13: ".....LLL........", 14: "....LL.LL......."}},
		],
	},
	"shaman": {
		"w": 16, "outline": Color(0.08, 0.06, 0.10),
		"pal": {"S": Color(0.48, 0.72, 0.30), "s": Color(0.32, 0.52, 0.22), "O": Color(0.52, 0.30, 0.58), "o": Color(0.34, 0.18, 0.40),
			"F": Color(0.96, 0.76, 0.30), "m": Color(0.52, 0.34, 0.16), "G": Color(0.50, 1.0, 0.60), "e": Color(1.0, 0.85, 0.20)},
		"frames": [
			["................", "................", "............GG..", "....F......GGGG.", "....FF......GG..", "....SSSS....m...",
			 "...SSeSeS...m...", "....SSSS....m...", "...OOOOOO..Sm...", "..OOOOOOOOSSm...", "..OOOOOOOO..m...", "..oOOOOOOo..m...",
			 "..oOOOOOOo..m...", "...oOOOOo...m...", "...oo..oo.......", "................"],
			{"from": 0, "rows": {14: "....oo.oo......."}},
		],
	},
	"wolf": {
		"w": 16, "outline": Color(0.08, 0.08, 0.10),
		"pal": {"F": Color(0.62, 0.64, 0.70), "f": Color(0.40, 0.42, 0.50), "W": Color(0.86, 0.88, 0.93), "e": Color(1.0, 0.85, 0.20), "n": Color(0.10, 0.10, 0.12)},
		"frames": [
			["................", "................", "................", "................", "................", "...........F.F..",
			 "..........FFFF..", "..........FWeFF.", ".F.......FFFFFFn", "FFFFFFFFFFFFFf..", ".FWWWWWWWFFFf...", ".FFFFFFFFFFFf...",
			 ".fFFfffffFFf....", ".fF.f...fF.f....", ".f..f...f..f....", "................"],
			{"from": 0, "rows": {13: "..fFf....fFf....", 14: "...ff.....ff...."}},
		],
	},
	"assassin": {
		"w": 16, "outline": Color(0.04, 0.03, 0.06),
		"pal": {"C": Color(0.24, 0.22, 0.36), "c": Color(0.14, 0.12, 0.22), "R": Color(0.88, 0.18, 0.24), "e": Color(1.0, 0.92, 0.40), "W": Color(0.86, 0.90, 0.96)},
		"frames": [
			["................", "................", "......CCC.......", ".....CCCCC......", ".....CcceC......", "....RRRRRR......",
			 "...RRCCCCCC.....", "..R..CCCCCCC.W..", ".....CCCCCC.WW..", ".....cCCCCcCC...", "......CCCCC.....", "......Cc.cC.....",
			 ".....cC...Cc....", "....cc.....cc...", "................", "................"],
			{"from": 0, "rows": {7: "...R.CCCCCCC.W..", 11: "......CccC......", 12: "......cCCc......", 13: ".....cc..cc....."}},
		],
	},
	"bat": {
		"w": 16, "outline": Color(0.10, 0.04, 0.14),
		"pal": {"P": Color(0.56, 0.26, 0.76), "p": Color(0.36, 0.14, 0.50), "M": Color(0.72, 0.42, 0.92), "e": Color(1.0, 0.30, 0.30)},
		"frames": [
			["................", "................", "................", ".M............M.", ".MM..........MM.", ".MMM........MMM.",
			 ".MMMM.PPPP.MMMM.", "..MMMPPPPPPMMM..", "...MMPePPePMM...", ".....PPPPPP.....", "......pPPp......", ".......pp.......",
			 "................", "................", "................", "................"],
			["................", "................", "................", "................", "................", "................",
			 "......PPPP......", ".....PPPPPP.....", "..MMMPePPePMMM..", ".MMMMPPPPPPMMMM.", "MMMM..pPPp..MMMM", "MM.....pp.....MM",
			 "M..............M", "................", "................", "................"],
		],
	},
	"gargoyle": {
		"w": 16, "outline": Color(0.08, 0.08, 0.10),
		"pal": {"R": Color(0.58, 0.58, 0.63), "r": Color(0.38, 0.38, 0.44), "M": Color(0.46, 0.43, 0.52), "e": Color(1.0, 0.56, 0.20), "h": Color(0.86, 0.82, 0.72)},
		"frames": [
			["................", "................", "......h..h......", ".M....RRRR....M.", ".MM...ReeR...MM.", ".MMM..RRRR..MMM.",
			 ".MMMMRRRRRRMMMM.", "..MMMRRRRRRMMM..", "...MMrRRRRrMM...", ".....rRRRRr.....", ".....rr..rr.....", "....rr....rr....",
			 "................", "................", "................", "................"],
			["................", "................", "......h..h......", "......RRRR......", "......ReeR......", "......RRRR......",
			 "..MMMRRRRRRMMM..", ".MMMMRRRRRRMMMM.", "MMMM.rRRRRr.MMMM", "MM...rRRRRr...MM", ".....rr..rr.....", "....rr....rr....",
			 "................", "................", "................", "................"],
		],
	},
	"boss_warlord": {
		"w": 24, "outline": Color(0.07, 0.06, 0.05),
		"pal": {"S": Color(0.48, 0.72, 0.30), "s": Color(0.32, 0.52, 0.22), "A": Color(0.64, 0.66, 0.74), "a": Color(0.42, 0.44, 0.52),
			"H": Color(0.50, 0.52, 0.60), "h": Color(0.92, 0.88, 0.74), "e": Color(1.0, 0.30, 0.20), "t": Color(1.0, 1.0, 0.90),
			"R": Color(0.72, 0.16, 0.16), "Y": Color(0.96, 0.78, 0.30), "X": Color(0.82, 0.84, 0.90), "m": Color(0.52, 0.34, 0.16), "L": Color(0.30, 0.24, 0.18)},
		"frames": [
			["........................", ".....h..........h.......", ".....hh........hh.......", "......hhHHHHHHhh........",
			 ".......HHHHHHHH.........", ".......HHHHHHHHh........", ".......SSeSSeSSh....XXX.", ".......SSSSSSSSs...XXXXX",
			 "........sSttSSs....XXXX.", "......RRssssssRR....m...", ".....RAAAAAAAAAAR..Sm...", "....RAAAAYYAAAAAaSSSm...",
			 "....RAAAAAAAAAAAa...m...", "...SSAaAAAAAAAAaa...m...", "...SSRaAAAAAAAAaR...m...", "....RRaaAAAAAAaRR...m...",
			 "....RR.aAAAAAAa.R...m...", ".......aaAAAAaa.....m...", "........LLL.LLL.........", "........LLL.LLL.........",
			 ".......LLLL..LLLL.......", "........................", "........................", "........................"],
			{"from": 0, "rows": {18: ".........LLLLLL.........", 19: "........LLL..LLL........", 20: ".......LLL....LLL......."}},
		],
	},
	"boss_frost_colossus": {
		"w": 24, "outline": Color(0.06, 0.12, 0.22),
		"pal": {"I": Color(0.64, 0.87, 1.0), "i": Color(0.36, 0.60, 0.86), "W": Color(0.95, 1.0, 1.0), "e": Color(0.40, 1.0, 1.0), "R": Color(0.40, 0.45, 0.62)},
		"frames": [
			["........................", "........................", ".........WWWW...........", "........WIIIIW..........",
			 ".......WIIeIeII.........", ".......IIIIIIIi.........", "..WW....iIIIIi....WW....", ".WIIWWIIIIIIIIIIWWIIW...",
			 ".WIIIIIIIRRRRIIIIIIIW...", ".IIIIIIIRRRRRRIIIIIIi...", ".IIiiIIIRReRRRIIIiiIi...", ".iIi.IIIRRRRRRIII.iIi...",
			 ".iIi.iIIIRRRRIIIi.iIi...", "..WW..iIIIIIIIIi..WW....", "......iIIIIIIIIi........", "......iIIi..iIIi........",
			 ".....iIIIi..iIIIi.......", ".....WWWW....WWWW.......", "........................", "........................",
			 "........................", "........................", "........................", "........................"],
		],
	},
	"boss_obsidian": {
		"w": 24, "outline": Color(0.04, 0.02, 0.06),
		"pal": {"O": Color(0.24, 0.20, 0.32), "o": Color(0.13, 0.11, 0.20), "P": Color(0.78, 0.38, 1.0), "Y": Color(0.96, 0.76, 0.30),
			"e": Color(1.0, 0.30, 0.30), "h": Color(0.86, 0.82, 0.78), "C": Color(0.44, 0.08, 0.20)},
		"frames": [
			["....h..............h....", "....hh............hh....", ".....hh..OOOOOO..hh.....", "......hOOOOOOOOOOh......",
			 ".......OOeOOOOeOO.......", ".......OOOOPPOOOO.......", ".....CCOOOOOOOOOOCC.....", "....CCYOOOOOOOOOOYCC....",
			 "...CCOOOOOPPPPOOOOOCC...", "..CCOOOOOPPPPPPOOOOOCC..", "..CC.OOOOOPPPPOOOOO.CC..", "..CC.oOOOOOOOOOOOOo.CC..",
			 "..CC..oOOOOYYOOOOo..CC..", "..C....oOOOOOOOOo....C..", ".......oOOO..OOOo.......", ".......oOO....OOo.......",
			 "......ooo......ooo......", "........................", "........................", "........................",
			 "........................", "........................", "........................", "........................"],
		],
	},
	"boss_obsidian_awakened": {
		"template": "boss_obsidian", "outline": Color(0.08, 0.01, 0.03),
		"pal": {"O": Color(0.30, 0.10, 0.18), "o": Color(0.16, 0.05, 0.10), "P": Color(1.0, 0.45, 0.20), "Y": Color(1.0, 0.85, 0.35),
			"e": Color(1.0, 0.95, 0.40), "h": Color(1.0, 0.86, 0.40), "C": Color(0.70, 0.10, 0.16)},
	},
	"hero_p1": {
		"w": 16, "outline": Color(0.04, 0.05, 0.10),
		"pal": {"S": Color(0.96, 0.80, 0.64), "e": Color(0.10, 0.10, 0.20), "B": Color(0.62, 0.42, 0.20), "W": Color(0.92, 0.92, 0.95),
			"L": Color(0.30, 0.24, 0.20), "Y": Color(1.0, 0.85, 0.35)},
		"frames": [
			["................", "......CCC.......", ".....CCCCc......", "....CCSSec......", "....cCSSSc..B...", "....dcSSc...BW..",
			 "...dcccccc.SBW..", "..ddcCcccccS.BW.", "..ddcCYcccc..BW.", "..ddcCcccc...B..", "..d.cccccc..B...", "....cccccc......",
			 "....LL..LL......", "...LL....LL.....", "................", "................"],
			{"from": 0, "rows": {12: ".....LLLL.......", 13: "....LL..LL......"}},
		],
	},
	"hero_p2": {
		"w": 16, "outline": Color(0.06, 0.04, 0.05),
		"pal": {"H": Color(0.76, 0.78, 0.86), "h": Color(0.50, 0.52, 0.60), "Y": Color(1.0, 0.82, 0.32), "e": Color(0.10, 0.08, 0.10),
			"W": Color(0.92, 0.94, 1.0), "S": Color(0.96, 0.80, 0.64), "L": Color(0.30, 0.24, 0.20)},
		"frames": [
			["......YY........", "......cc........", ".....HHHH.......", "....HHHHHh......", "....hYeeYh......", "....HHHHHh...W..",
			 "...YdddHHh..WW..", "..YdcCcdHHHSW...", "..YdCYCdHHHH....", "..YdcCcdHHHh....", "...YdddHHHHh....", "....YY.hHHh.....",
			 "....LL..LL......", "...LL....LL.....", "................", "................"],
			{"from": 0, "rows": {12: ".....LLLL.......", 13: "....LL..LL......"}},
		],
	},
	"elder": {
		"w": 16, "outline": Color(0.05, 0.05, 0.08),
		"pal": {"H": Color(0.66, 0.68, 0.76), "h": Color(0.44, 0.46, 0.54), "S": Color(0.94, 0.78, 0.62), "e": Color(0.10, 0.08, 0.10),
			"W": Color(0.92, 0.92, 0.94), "B": Color(0.36, 0.42, 0.60), "b": Color(0.22, 0.26, 0.40), "Y": Color(1.0, 0.82, 0.32), "m": Color(0.52, 0.34, 0.16)},
		"frames": [
			["................", ".....HHHH.......", "....HHHHHh......", "....hSeSeh......", "....SSSSSS......", "....WSWWSW......",
			 "....WWWWWW......", ".....WWWW...m...", "...BBBYBBBB.m...", "..BBBBYBBBBSm...", "..BbBBYBBbB.m...", "..BbBBBBBbB.m...",
			 "...BBBBBBB..m...", "....bb.bb...m...", "....bb.bb.......", "................"],
		],
	},
	"soldier": {
		"w": 16, "outline": Color(0.05, 0.05, 0.08),
		"pal": {"H": Color(0.72, 0.74, 0.82), "h": Color(0.46, 0.48, 0.56), "S": Color(0.96, 0.80, 0.64), "e": Color(0.10, 0.08, 0.10),
			"W": Color(0.92, 0.94, 1.0), "L": Color(0.32, 0.24, 0.18), "Y": Color(1.0, 0.82, 0.32)},
		"frames": [
			["................", "................", ".....cc.........", ".....HHHH.......", "....HHHHHh......", "....hSSeSh......",
			 ".....SSSS.......", "...dccccccd..W..", "..ddcccYccd.WW..", "..ddccccccdSW...", "..ddccccccd.....", "...dcccccd......",
			 "....LL.LL.......", "...LL...LL......", "................", "................"],
			{"from": 0, "rows": {12: ".....LLL........", 13: "....LL.LL......."}},
		],
	},
}

const OWNER_PALETTES: Dictionary = {
	1: {"c": Color(0.26, 0.62, 0.96), "C": Color(0.56, 0.84, 1.0), "d": Color(0.14, 0.34, 0.64)},
	2: {"c": Color(0.90, 0.26, 0.32), "C": Color(1.0, 0.56, 0.58), "d": Color(0.56, 0.12, 0.18)},
	3: {"c": Color(0.98, 0.90, 0.62), "C": Color(1.0, 1.0, 0.86), "d": Color(0.80, 0.62, 0.24)}, # holy reinforcements
}


static func frame_count(sprite_id: String) -> int:
	var spec: Dictionary = SPRITES.get(sprite_id, SPRITES["slime"])
	if spec.has("template"):
		spec = SPRITES[str(spec["template"])]
	return (spec["frames"] as Array).size()


static func get_width(sprite_id: String) -> int:
	var spec: Dictionary = SPRITES.get(sprite_id, SPRITES["slime"])
	if spec.has("template"):
		spec = SPRITES[str(spec["template"])]
	return int(spec["w"])


## Returns the texture for `sprite_id` (enemy id or unit id), animation frame, optional owner recolor and mirror.
static func get_frame(sprite_id: String, frame: int = 0, owner: int = 0, flip: bool = false) -> Texture2D:
	if not SPRITES.has(sprite_id):
		sprite_id = "slime"
	var n := frame_count(sprite_id)
	frame = posmod(frame, n)
	var key := "%s|%d|%d|%d" % [sprite_id, frame, owner, int(flip)]
	if _cache.has(key):
		return _cache[key]
	var spec: Dictionary = SPRITES[sprite_id]
	var pal: Dictionary = (spec.get("pal", {}) as Dictionary).duplicate()
	var outline: Color = spec.get("outline", Color(0.05, 0.05, 0.08))
	if spec.has("template"):
		spec = SPRITES[str(spec["template"])]
	if owner > 0:
		for k in OWNER_PALETTES[owner].keys():
			pal[k] = OWNER_PALETTES[owner][k]
	var rows := _resolve_rows(spec, frame)
	var img := _rasterize(rows, int(spec["w"]), pal, outline)
	if flip:
		img.flip_x()
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


static func _resolve_rows(spec: Dictionary, frame: int) -> Array:
	var frames: Array = spec["frames"]
	var f: Variant = frames[frame]
	if f is Array:
		return f
	var d: Dictionary = f
	var base: Array = (_resolve_rows(spec, int(d.get("from", 0))) as Array).duplicate()
	var w := int(spec["w"])
	var dy := int(d.get("dy", 0))
	if dy != 0:
		var blank := ".".repeat(w)
		var shifted: Array = []
		for i in range(base.size()):
			var src := i - dy
			shifted.append(base[src] if src >= 0 and src < base.size() else blank)
		base = shifted
	var over: Dictionary = d.get("rows", {})
	for ri in over.keys():
		base[int(ri)] = over[ri]
	return base


static func _rasterize(rows: Array, w: int, pal: Dictionary, outline: Color) -> Image:
	var h := rows.size()
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var filled := PackedByteArray()
	filled.resize(w * h)
	for y in range(h):
		var row: String = rows[y]
		for x in range(mini(w, row.length())):
			var ch := row[x]
			if ch != "." and pal.has(ch):
				img.set_pixel(x, y, pal[ch])
				filled[y * w + x] = 1
	# Auto outline: transparent pixels touching a filled pixel (4-neighborhood) become outline color.
	for y in range(h):
		for x in range(w):
			if filled[y * w + x] == 1:
				continue
			var touch := false
			for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + o.x
				var ny: int = y + o.y
				if nx >= 0 and nx < w and ny >= 0 and ny < h and filled[ny * w + nx] == 1:
					touch = true
					break
			if touch:
				img.set_pixel(x, y, outline)
	return img
