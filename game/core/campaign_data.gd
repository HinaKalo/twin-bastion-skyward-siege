class_name CampaignData
extends RefCounted
## 5-stage co-op campaign on large road-network maps (1080x608 world, camera-scrolled).
## Each stage defines a directed road graph (nodes, edges with optional via points, named spawns, one gate),
## areas pads must avoid (river, chasm), wave rosters and flavor text. Routes, flight paths, build pads,
## rally points and hero spawns are derived by MapGraph, so every layout stays valid by construction.
## Wave groups name a spawn in "lane_id"; "random" picks a spawn at spawn time, and the enemy id
## "adaptive" lets the director counter-pick against the players' current defenses.

const WORLD := Vector2(1080, 608)

static var _stages: Array[Dictionary] = []


static func _g(enemy: String, spawn: String, count: int, interval: float, delay: float = 0.0) -> Dictionary:
	return {"enemy_id": enemy, "lane_id": spawn, "count": count, "interval": interval, "delay": delay}


static func _w(wname: String, bonus: int, groups: Array) -> Dictionary:
	return {"name": wname, "early_bonus": bonus, "groups": groups}


static func _river_points() -> Array:
	var pts: Array = []
	for k in range(0, 34):
		var y := -12.0 + float(k) * 20.0
		pts.append(Vector2(485.0 + sin(y * 0.012) * 14.0, y))
	return pts


static func _defs() -> Array[Dictionary]:
	var V := func(x: float, y: float) -> Vector2: return Vector2(x, y)
	var chasm: Array = [V.call(470, -10), V.call(520, 160), V.call(560, 304), V.call(510, 450), V.call(570, 620)]
	return [
		{
			"id": "stage_1_twin_bridge", "index": 1,
			"name": "第1关：翡翠双桥",
			"subtitle": "三路来敌汇向南北两座桥",
			"intro_enemies": ["slime", "goblin", "wolf", "bat", "splitter", "goblin_archer", "boss_warlord"],
			"start_gold": 260, "lives": 20, "pad_count": 24, "hp_scale": 1.12,
			"avoid": [{"points": _river_points(), "r": 36.0}],
			"features": {"river": _river_points()},
			"graph": {
				"nodes": {"nw": V.call(16, 110), "w": V.call(16, 304), "sw": V.call(16, 500), "a": V.call(200, 118), "b": V.call(210, 304),
					"c": V.call(200, 492), "nbw": V.call(430, 196), "nbe": V.call(545, 196), "sbw": V.call(430, 418), "sbe": V.call(545, 418),
					"e": V.call(700, 150), "f": V.call(720, 304), "g": V.call(700, 462), "h": V.call(880, 226), "i": V.call(880, 388), "gate": V.call(1040, 304)},
				"edges": [
					["nw", "a"], ["a", "nbw", [V.call(330, 150)]], ["a", "b", [V.call(150, 210)]], ["w", "b"],
					["b", "nbw", [V.call(330, 252)]], ["b", "sbw", [V.call(330, 362)]], ["sw", "c"], ["c", "sbw", [V.call(330, 460)]],
					["c", "b", [V.call(150, 400)]], ["nbw", "nbe"], ["sbw", "sbe"],
					["nbe", "e"], ["nbe", "f", [V.call(620, 252)]], ["sbe", "f", [V.call(620, 360)]], ["sbe", "g"],
					["e", "h", [V.call(800, 160)]], ["f", "h"], ["f", "i"], ["g", "i", [V.call(800, 452)]],
					["h", "gate", [V.call(960, 240)]], ["i", "gate", [V.call(960, 370)]],
				],
				"spawns": {"west_n": "nw", "west": "w", "west_s": "sw"},
				"spawn_labels": {"west_n": "西北", "west": "正西", "west_s": "西南"},
				"gate": "gate",
			},
			"waves": [
				_w("第1波：三路斥候", 20, [_g("slime", "west_n", 6, 0.9), _g("slime", "west", 6, 0.9), _g("slime", "west_s", 6, 0.9)]),
				_w("第2波：重甲步兵", 22, [_g("goblin", "west_n", 6, 1.0), _g("goblin", "west_s", 6, 1.0), _g("slime", "west", 8, 0.7, 3.0)]),
				_w("第3波：暗影空袭", 24, [_g("bat", "west_n", 8, 0.7), _g("wolf", "west", 8, 0.7), _g("bat", "west_s", 6, 0.8, 4.0)]),
				_w("第4波：弓手压境", 26, [_g("goblin_archer", "west", 6, 1.0), _g("splitter", "west_n", 6, 1.0), _g("splitter", "west_s", 6, 1.0), _g("goblin", "random", 6, 0.8, 5.0)]),
				_w("第5波：狼群合围", 28, [_g("wolf", "west_n", 10, 0.5), _g("wolf", "west_s", 10, 0.5), _g("goblin_archer", "random", 6, 0.9, 3.0), _g("adaptive", "random", 8, 0.7, 6.0)]),
				_w("第6波：哥布林督军", 0, [_g("boss_warlord", "west", 1, 1.0, 2.0), _g("goblin", "west_n", 10, 0.7), _g("goblin", "west_s", 10, 0.7), _g("goblin_archer", "west", 8, 0.8, 4.0), _g("bat", "random", 8, 0.6, 6.0), _g("adaptive", "random", 8, 0.7, 9.0)]),
			],
		},
		{
			"id": "stage_2_rift_cross", "index": 2,
			"name": "第2关：裂谷交叉",
			"subtitle": "四面来敌 · 两处十字路口",
			"intro_enemies": ["shield_bearer", "shaman", "troll_breaker"],
			"start_gold": 280, "lives": 20, "pad_count": 26,
			"avoid": [{"points": chasm, "r": 24.0}],
			"features": {"chasm": chasm},
			"graph": {
				"nodes": {"nw": V.call(16, 96), "sw": V.call(16, 512), "n": V.call(400, 16), "s": V.call(660, 592), "a": V.call(170, 150), "b": V.call(170, 458),
					"x1": V.call(320, 304), "c": V.call(520, 190), "d": V.call(520, 418), "x2": V.call(740, 304), "e": V.call(890, 200), "f": V.call(890, 408), "gate": V.call(1040, 304)},
				"edges": [
					["nw", "a"], ["a", "x1", [V.call(250, 230)]], ["a", "c", [V.call(340, 110)]], ["sw", "b"], ["b", "x1", [V.call(250, 380)]],
					["b", "d", [V.call(340, 500)]], ["n", "c", [V.call(430, 110)]], ["s", "d", [V.call(620, 500)]],
					["x1", "c"], ["x1", "d"], ["x1", "x2"], ["c", "x2"], ["c", "e", [V.call(700, 170)]], ["d", "x2"], ["d", "f", [V.call(700, 440)]],
					["x2", "e"], ["x2", "f"], ["e", "gate", [V.call(980, 240)]], ["f", "gate", [V.call(980, 370)]],
				],
				"spawns": {"west_n": "nw", "west_s": "sw", "north": "n", "south": "s"},
				"spawn_labels": {"west_n": "西北", "west_s": "西南", "north": "北谷", "south": "南谷"},
				"gate": "gate",
			},
			"waves": [
				_w("第1波：裂谷先锋", 20, [_g("goblin", "west_n", 7, 0.9), _g("slime", "west_s", 10, 0.6)]),
				_w("第2波：疾风狼群", 22, [_g("wolf", "west_n", 9, 0.55), _g("wolf", "west_s", 9, 0.55), _g("wolf", "north", 5, 0.6, 4.0)]),
				_w("第3波：铁壁盾卫", 24, [_g("shield_bearer", "west_n", 6, 1.1), _g("goblin_archer", "west_s", 6, 1.0), _g("shield_bearer", "south", 4, 1.1, 5.0)]),
				_w("第4波：夜翼集群", 26, [_g("bat", "north", 10, 0.55), _g("bat", "south", 10, 0.55), _g("wolf", "random", 8, 0.6, 5.0)]),
				_w("第5波：萨满与破城槌", 28, [_g("shaman", "west_n", 3, 1.8, 1.0), _g("goblin", "west_n", 10, 0.7), _g("troll_breaker", "west_s", 2, 3.0), _g("shield_bearer", "west_s", 6, 1.0, 2.0)]),
				_w("第6波：裂变潮", 30, [_g("splitter", "west_n", 8, 0.8), _g("splitter", "west_s", 8, 0.8), _g("shaman", "random", 3, 2.0, 3.0), _g("bomb_bat", "north", 6, 0.8, 5.0), _g("adaptive", "random", 8, 0.7, 7.0)]),
				_w("第7波：双线督军", 0, [_g("boss_warlord", "west_n", 1, 1.0, 1.0), _g("boss_warlord", "west_s", 1, 1.0, 4.0), _g("shield_bearer", "north", 8, 0.8), _g("troll_breaker", "south", 3, 2.5), _g("shaman", "random", 3, 1.8), _g("adaptive", "random", 10, 0.6, 6.0)]),
			],
		},
		{
			"id": "stage_3_royal_siege", "index": 3,
			"name": "第3关：王城终局",
			"subtitle": "五路围城 · 中央广场决战",
			"intro_enemies": ["assassin", "gargoyle", "bomb_bat", "boss_obsidian"],
			"start_gold": 300, "lives": 20, "pad_count": 28,
			"graph": {
				"nodes": {"w1": V.call(16, 140), "w2": V.call(16, 304), "w3": V.call(16, 468), "n": V.call(560, 16), "s": V.call(560, 592),
					"a": V.call(250, 140), "b": V.call(250, 304), "c": V.call(250, 468), "d": V.call(560, 128), "m1": V.call(470, 236), "m2": V.call(470, 372),
					"h": V.call(560, 480), "p": V.call(700, 304), "e": V.call(780, 172), "f": V.call(780, 436), "g": V.call(900, 304), "gate": V.call(1040, 304)},
				"edges": [
					["w1", "a"], ["w2", "b"], ["w3", "c"], ["a", "d", [V.call(400, 110)]], ["a", "m1"], ["b", "m1"], ["b", "m2"], ["c", "m2"],
					["c", "h", [V.call(400, 498)]], ["n", "d"], ["s", "h"], ["d", "e"], ["m1", "p"], ["m2", "p"], ["m1", "e", [V.call(620, 200)]],
					["m2", "f", [V.call(620, 408)]], ["h", "f"], ["e", "g"], ["p", "g"], ["f", "g"], ["e", "gate", [V.call(950, 190)]],
					["f", "gate", [V.call(950, 418)]], ["g", "gate"],
				],
				"spawns": {"west_n": "w1", "west": "w2", "west_s": "w3", "north": "n", "south": "s"},
				"spawn_labels": {"west_n": "北城门", "west": "西大道", "west_s": "南城门", "north": "北巷", "south": "南巷"},
				"gate": "gate",
			},
			"waves": [
				_w("第1波：三路试探", 20, [_g("goblin", "west_n", 6, 0.9), _g("slime", "west", 10, 0.6), _g("goblin", "west_s", 6, 0.9)]),
				_w("第2波：狼潮突袭", 22, [_g("wolf", "west_n", 8, 0.55), _g("wolf", "west", 8, 0.55), _g("wolf", "west_s", 8, 0.55), _g("wolf", "random", 6, 0.5, 4.0)]),
				_w("第3波：迅影刺客", 24, [_g("assassin", "north", 8, 0.6), _g("shield_bearer", "west_n", 5, 1.1), _g("shield_bearer", "west_s", 5, 1.1), _g("assassin", "south", 6, 0.5, 5.0)]),
				_w("第4波：石像鬼", 26, [_g("gargoyle", "west_n", 5, 1.2), _g("gargoyle", "west_s", 5, 1.2), _g("bomb_bat", "random", 8, 0.6, 3.0), _g("bat", "west", 10, 0.5)]),
				_w("第5波：萨满大军", 28, [_g("shaman", "west", 4, 1.5), _g("goblin", "west", 12, 0.55), _g("splitter", "north", 6, 0.9), _g("splitter", "south", 6, 0.9), _g("goblin_archer", "random", 8, 0.8, 4.0)]),
				_w("第6波：督军亲卫", 30, [_g("boss_warlord", "west_n", 1, 1.0, 1.0), _g("shield_bearer", "west", 8, 0.8), _g("boss_warlord", "west_s", 1, 1.0, 3.0), _g("troll_breaker", "random", 3, 2.5, 2.0), _g("assassin", "north", 8, 0.5, 6.0)]),
				_w("第7波：遮天蔽日", 32, [_g("gargoyle", "west", 8, 1.0), _g("bat", "north", 12, 0.45), _g("bat", "south", 12, 0.45), _g("bomb_bat", "random", 10, 0.5, 4.0), _g("adaptive", "random", 10, 0.6, 6.0)]),
				_w("最终波：黑曜大魔王", 0, [_g("boss_obsidian", "west", 1, 1.0, 2.0), _g("shield_bearer", "west_n", 8, 0.8), _g("assassin", "west_s", 10, 0.5), _g("troll_breaker", "north", 3, 2.5), _g("gargoyle", "south", 6, 1.0, 6.0), _g("shaman", "random", 3, 1.8, 5.0), _g("adaptive", "random", 12, 0.5, 8.0)]),
			],
		},
		{
			"id": "stage_4_frost_trail", "index": 4,
			"name": "第4关：霜原雪径",
			"subtitle": "蜿蜒雪径 · 冰川与山口",
			"intro_enemies": ["troll_breaker", "bomb_bat", "boss_frost_colossus"],
			"start_gold": 340, "lives": 20, "pad_count": 28, "hp_scale": 0.86,
			"graph": {
				"nodes": {"nw": V.call(16, 80), "sw": V.call(16, 530), "n": V.call(330, 16), "a": V.call(200, 80), "b": V.call(200, 290), "c": V.call(410, 290),
					"d": V.call(410, 96), "e": V.call(640, 96), "f": V.call(640, 300), "g": V.call(330, 530), "h": V.call(660, 530), "i": V.call(820, 450),
					"k": V.call(840, 304), "l": V.call(860, 140), "gate": V.call(1040, 304)},
				"edges": [
					["nw", "a"], ["a", "b"], ["b", "c"], ["c", "d"], ["d", "e"], ["e", "f"], ["n", "d"], ["b", "g", [V.call(200, 420)]],
					["sw", "g"], ["g", "h"], ["c", "h", [V.call(520, 420)]], ["h", "i"], ["f", "k"], ["i", "k"], ["e", "l"],
					["l", "gate", [V.call(960, 200)]], ["k", "gate"], ["i", "gate", [V.call(960, 420)]],
				],
				"spawns": {"west_n": "nw", "west_s": "sw", "north": "n"},
				"spawn_labels": {"west_n": "雪径", "west_s": "冰川", "north": "山口"},
				"gate": "gate",
			},
			"waves": [
				_w("第1波：雪原狼迹", 20, [_g("wolf", "west_n", 10, 0.6), _g("slime", "west_s", 10, 0.6)]),
				_w("第2波：冰封盾阵", 22, [_g("shield_bearer", "west_n", 7, 1.0), _g("goblin", "west_s", 10, 0.7), _g("goblin_archer", "north", 5, 1.0, 3.0)]),
				_w("第3波：霜翼", 24, [_g("gargoyle", "north", 5, 1.2), _g("bat", "west_s", 12, 0.5), _g("bomb_bat", "random", 6, 0.7, 4.0)]),
				_w("第4波：雪崩裂变", 26, [_g("splitter", "west_n", 8, 0.8), _g("splitter", "west_s", 8, 0.8), _g("shaman", "north", 3, 1.8, 3.0), _g("troll_breaker", "random", 2, 3.0, 5.0)]),
				_w("第5波：白影突袭", 28, [_g("assassin", "west_s", 12, 0.45), _g("wolf", "west_n", 12, 0.45), _g("shield_bearer", "north", 6, 0.9, 5.0), _g("adaptive", "random", 8, 0.6, 7.0)]),
				_w("第6波：萨满与盾", 30, [_g("shaman", "west_n", 4, 1.5), _g("shield_bearer", "west_n", 10, 0.7), _g("gargoyle", "west_s", 6, 1.0), _g("troll_breaker", "north", 3, 2.5, 3.0)]),
				_w("第7波：督军冲阵", 32, [_g("boss_warlord", "west_s", 1, 1.0, 1.0), _g("goblin", "west_s", 12, 0.55), _g("assassin", "west_n", 10, 0.45, 3.0), _g("bomb_bat", "north", 8, 0.6, 6.0), _g("adaptive", "random", 10, 0.6, 8.0)]),
				_w("最终波：冰霜巨像", 0, [_g("boss_frost_colossus", "west_n", 1, 1.0, 2.0), _g("shield_bearer", "west_n", 8, 0.8, 5.0), _g("gargoyle", "west_s", 8, 1.0), _g("troll_breaker", "north", 3, 2.5, 3.0), _g("splitter", "west_s", 8, 0.8, 4.0), _g("shaman", "random", 3, 1.8, 8.0), _g("adaptive", "random", 12, 0.5, 9.0)]),
			],
		},
		{
			"id": "stage_5_abyss_corridor", "index": 5,
			"name": "第5关：深渊回廊",
			"subtitle": "三条回廊 · 中央裂隙会开门",
			"intro_enemies": ["boss_obsidian_awakened"],
			"start_gold": 340, "lives": 20, "pad_count": 30, "hp_scale": 0.92,
			"graph": {
				"nodes": {"nw": V.call(16, 100), "w": V.call(16, 304), "sw": V.call(16, 508), "portal": V.call(560, 304), "a": V.call(230, 100), "b": V.call(230, 304),
					"c": V.call(230, 508), "d": V.call(450, 170), "e": V.call(450, 438), "f": V.call(680, 100), "g": V.call(680, 304), "h": V.call(680, 508),
					"i": V.call(880, 200), "j": V.call(880, 408), "gate": V.call(1040, 304)},
				"edges": [
					["nw", "a"], ["w", "b"], ["sw", "c"], ["a", "d"], ["b", "d"], ["b", "e"], ["c", "e"], ["a", "f", [V.call(450, 60)]], ["c", "h", [V.call(450, 548)]],
					["d", "f"], ["d", "g"], ["e", "g"], ["e", "h"], ["portal", "g"], ["f", "i"], ["g", "i"], ["g", "j"], ["h", "j"],
					["i", "gate", [V.call(980, 240)]], ["j", "gate", [V.call(980, 370)]],
				],
				"spawns": {"west_n": "nw", "west": "w", "west_s": "sw", "portal": "portal"},
				"spawn_labels": {"west_n": "北廊", "west": "中廊", "west_s": "南廊", "portal": "中央裂隙"},
				"gate": "gate",
			},
			"waves": [
				_w("第1波：深渊低语", 20, [_g("slime", "west_n", 10, 0.55), _g("goblin", "west", 8, 0.8), _g("slime", "west_s", 10, 0.55)]),
				_w("第2波：疾影", 22, [_g("assassin", "west_n", 8, 0.55), _g("wolf", "west", 10, 0.5), _g("assassin", "west_s", 8, 0.55)]),
				_w("第3波：盾墙", 24, [_g("shield_bearer", "west_n", 6, 1.0), _g("shield_bearer", "west", 6, 1.0), _g("shaman", "west_s", 3, 1.8), _g("goblin_archer", "west_s", 8, 0.8)]),
				_w("第4波：裂隙开门", 26, [_g("gargoyle", "west_n", 6, 1.0), _g("bat", "west", 12, 0.45), _g("goblin", "portal", 10, 0.6, 3.0), _g("bomb_bat", "random", 8, 0.6, 5.0)]),
				_w("第5波：督军双雄", 28, [_g("boss_warlord", "west_n", 1, 1.0, 1.0), _g("boss_warlord", "west_s", 1, 1.0, 3.0), _g("goblin", "west", 14, 0.5), _g("troll_breaker", "portal", 2, 3.0, 4.0)]),
				_w("第6波：裂变深渊", 30, [_g("splitter", "west_n", 8, 0.7), _g("splitter", "west", 8, 0.7), _g("splitter", "west_s", 8, 0.7), _g("shaman", "portal", 3, 1.8, 3.0), _g("adaptive", "random", 10, 0.6, 6.0)]),
				_w("第7波：寒霜使者", 32, [_g("boss_frost_colossus", "west", 1, 1.0, 1.0), _g("shield_bearer", "west_n", 8, 0.8), _g("assassin", "west_s", 12, 0.4, 2.0), _g("troll_breaker", "random", 3, 2.5, 4.0)]),
				_w("第8波：混沌之潮", 34, [_g("gargoyle", "west_n", 8, 0.9), _g("shield_bearer", "west", 10, 0.7), _g("shaman", "portal", 4, 1.5, 2.0), _g("wolf", "west_s", 14, 0.4), _g("bomb_bat", "random", 10, 0.5, 5.0), _g("adaptive", "random", 10, 0.6, 7.0)]),
				_w("第9波：魔王先锋", 36, [_g("boss_obsidian", "portal", 1, 1.0, 1.0), _g("assassin", "west", 14, 0.4), _g("gargoyle", "west_s", 8, 0.9), _g("troll_breaker", "west_n", 3, 2.5, 3.0), _g("splitter", "random", 8, 0.8, 5.0)]),
				_w("最终波：觉醒·黑曜魔王", 0, [_g("boss_obsidian_awakened", "west", 1, 1.0, 3.0), _g("shield_bearer", "west_n", 10, 0.7), _g("shield_bearer", "west_s", 10, 0.7), _g("shaman", "portal", 4, 1.8, 1.0), _g("gargoyle", "west_n", 8, 1.0, 6.0), _g("assassin", "west_s", 12, 0.4, 8.0), _g("troll_breaker", "portal", 4, 2.5, 6.0), _g("adaptive", "random", 14, 0.5, 10.0)]),
			],
		},
	]


static func get_stages() -> Array[Dictionary]:
	if _stages.is_empty():
		for s in _defs():
			s["world"] = WORLD
			s["pads"] = MapGraph.auto_pads(s)
			s["hero_spawns"] = MapGraph.hero_spawns(s)
			_stages.append(s)
	return _stages


static func get_stage_by_id(stage_id: String) -> Dictionary:
	for s in get_stages():
		if str(s["id"]) == stage_id:
			return s.duplicate(true)
	return get_stages()[0].duplicate(true)


static func get_stage_ids() -> Array[String]:
	var out: Array[String] = []
	for s in get_stages():
		out.append(str(s["id"]))
	return out


## A stage is unlocked when it is the first one or the previous stage has at least 1 star.
static func is_unlocked(stage_id: String, meta: MetaProgress) -> bool:
	var ids := get_stage_ids()
	var idx := ids.find(stage_id)
	if idx <= 0:
		return true
	return meta != null and meta.is_stage_cleared(ids[idx - 1])


## Endless mode opens once stage 3 has been cleared.
static func is_endless_unlocked(meta: MetaProgress) -> bool:
	return meta != null and meta.is_stage_cleared("stage_3_royal_siege")
