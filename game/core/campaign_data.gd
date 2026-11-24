class_name CampaignData
extends RefCounted
## 5-stage co-op campaign on large road-network maps (1080x608 world, camera-scrolled).
## Each stage defines a directed road graph (nodes, edges with optional via points, named spawns, one gate),
## Pads, opening views, landmarks and attack groups are authored per battlefield.
## MapGraph derives routes, flight paths and pad rally points from the same topology.

const WORLD := Vector2(1080, 608)

static var _stages: Array[Dictionary] = []


static func _g(enemy: String, spawn: String, count: int, interval: float, delay: float = 0.0) -> Dictionary:
	return {"enemy_id": enemy, "lane_id": spawn, "count": count, "interval": interval, "delay": delay}


static func _w(wname: String, bonus: int, groups: Array, rest: float) -> Dictionary:
	return {"name": wname, "early_bonus": bonus, "groups": groups, "rest": rest}


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
			"start_gold": 260, "lives": 20, "hp_scale": 1.12,
			"avoid": [{"points": _river_points(), "r": 36.0}],
			"features": {"river": _river_points()},
			"opening_view": V.call(484, 247), "opening_pads": ["p2", "p12"],
			"hero_spawns": [V.call(356, 162), V.call(351, 430)],
			"authored_pads": [
				[1, V.call(388, 118)], [1, V.call(559, 125)], [1, V.call(654, 176)], [1, V.call(753, 178)], [1, V.call(848, 194)],
				[2, V.call(382, 473)], [2, V.call(566, 479)], [2, V.call(666, 416)], [2, V.call(755, 418)], [2, V.call(847, 418)],
				[0, V.call(367, 219)], [0, V.call(367, 369)], [0, V.call(586, 251)], [0, V.call(575, 335)], [0, V.call(668, 291)], [0, V.call(709, 401)], [0, V.call(812, 307)], [0, V.call(917, 307)],
			],
			"landmarks": [
				["bridge_tree", V.call(435, 85)],
				["bridge_lantern", V.call(453, 140)],
				["bridge_lantern", V.call(545, 188)],
				["bridge_tree", V.call(550, 539)],
				["obelisk", V.call(718, 304)],
				["bridge_lantern", V.call(548, 457)],
			],
			"graph": {
				"nodes": {
					"north": V.call(246, 162), "south": V.call(242, 430), "creek": V.call(226, 295),
					"meadow": V.call(350, 292), "north_bank": V.call(444, 164), "north_bridge": V.call(534, 164),
					"south_bank": V.call(444, 430), "south_bridge": V.call(534, 430), "orchard": V.call(630, 224),
					"bend": V.call(624, 368), "north_keep": V.call(836, 239), "south_keep": V.call(836, 373),
					"commons": V.call(754, 306), "gate": V.call(1010, 306),
				},
				"edges": [
					["north", "north_bank"], ["north", "meadow"], ["south", "south_bank"],
					["south", "meadow"], ["creek", "meadow"], ["meadow", "north_bank"],
					["meadow", "south_bank"], ["north_bank", "north_bridge"], ["south_bank", "south_bridge"],
					["north_bridge", "orchard"], ["south_bridge", "bend", [V.call(579, 433), V.call(581, 382)]], ["orchard", "north_keep", [V.call(724, 218)]],
					["bend", "south_keep"], ["orchard", "commons"], ["bend", "commons"],
					["commons", "north_keep"], ["commons", "south_keep"], ["north_keep", "gate"],
					["south_keep", "gate", [V.call(926, 351)]],
				],
				"spawns": {"west_n": "north", "west": "creek", "west_s": "south"},
				"spawn_labels": {"west_n": "北桥", "west": "溪畔", "west_s": "南桥"},
				"gate": "gate",
			},
			"waves": [
				_w("第1波：三路斥候", 20, [
					_g("slime", "west_n", 5, 1.00, 0.0),
					_g("slime", "west_s", 6, 0.90, 6.0),
					_g("slime", "west", 6, 0.90, 15.0),
					_g("slime", "west_n", 4, 1.00, 25.0),
				], 15.0),
				_w("第2波：重甲步兵", 22, [
					_g("goblin", "west_n", 6, 1.00, 0.0),
					_g("goblin", "west_s", 6, 1.00, 5.0),
					_g("slime", "west", 5, 0.70, 10.0),
					_g("slime", "west", 3, 0.70, 28.0),
				], 16.0),
				_w("第3波：暗影空袭", 24, [
					_g("bat", "west_n", 5, 0.70, 0.0),
					_g("wolf", "west", 8, 0.70, 5.0),
					_g("bat", "west_s", 6, 0.80, 10.0),
					_g("bat", "west_n", 3, 0.70, 29.0),
				], 15.0),
				_w("第4波：弓手压境", 26, [
					_g("goblin_archer", "west", 3, 1.00, 0.0),
					_g("splitter", "west_n", 6, 1.00, 5.0),
					_g("splitter", "west_s", 6, 1.00, 10.0),
					_g("goblin", "random", 6, 0.80, 15.0),
					_g("goblin_archer", "west", 3, 1.00, 27.0),
				], 17.0),
				_w("第5波：狼群合围", 28, [
					_g("wolf", "west_n", 7, 0.50, 0.0),
					_g("wolf", "west_s", 10, 0.50, 5.0),
					_g("goblin_archer", "random", 6, 0.90, 10.0),
					_g("adaptive", "random", 8, 0.70, 15.0),
					_g("wolf", "west_n", 3, 0.50, 28.0),
				], 14.0),
				_w("第6波：哥布林督军", 0, [
					_g("goblin", "west_n", 7, 0.70, 0.0),
					_g("boss_warlord", "west", 1, 1.00, 7.0),
					_g("goblin", "west_s", 10, 0.70, 10.0),
					_g("goblin_archer", "west", 8, 0.80, 15.0),
					_g("bat", "random", 8, 0.60, 19.0),
					_g("adaptive", "random", 8, 0.70, 22.0),
					_g("goblin", "west_n", 3, 0.70, 29.0),
				], 21.0),
			],
		},
		{
			"id": "stage_2_rift_cross", "index": 2,
			"name": "第2关：裂谷交叉",
			"subtitle": "四面来敌 · 两处十字路口",
			"intro_enemies": ["shield_bearer", "shaman", "troll_breaker"],
			"start_gold": 280, "lives": 20,
			"avoid": [{"points": chasm, "r": 24.0}],
			"features": {"chasm": chasm},
			"opening_view": V.call(510, 253), "opening_pads": ["p2", "p14"],
			"hero_spawns": [V.call(370, 170), V.call(365, 437)],
			"authored_pads": [
				[1, V.call(337, 111)], [1, V.call(437, 136)], [1, V.call(581, 144)], [1, V.call(647, 161)], [1, V.call(759, 170)], [1, V.call(861, 171)],
				[2, V.call(332, 480)], [2, V.call(436, 471)], [2, V.call(585, 462)], [2, V.call(629, 450)], [2, V.call(756, 446)], [2, V.call(865, 445)],
				[0, V.call(359, 293)], [0, V.call(437, 236)], [0, V.call(437, 361)], [0, V.call(601, 234)], [0, V.call(608, 373)], [0, V.call(718, 299)], [0, V.call(819, 267)], [0, V.call(820, 350)], [0, V.call(904, 275)],
			],
			"landmarks": [
				["rift_column", V.call(310, 233)],
				["obelisk", V.call(382, 366)],
				["abyss_crystal", V.call(571, 344)],
				["rift_brazier", V.call(735, 281)],
				["rift_brazier", V.call(729, 330)],
				["rift_column", V.call(843, 504)],
			],
			"graph": {
				"nodes": {
					"west_n": V.call(215, 122), "west_s": V.call(222, 488), "north": V.call(682, 74),
					"south": V.call(647, 536), "shelf": V.call(370, 170), "quarry": V.call(365, 437),
					"crossing": V.call(411, 302), "top_bridge": V.call(546, 188), "low_bridge": V.call(554, 416),
					"north_pass": V.call(697, 191), "south_pass": V.call(685, 422), "redoubt": V.call(774, 304),
					"upper_wall": V.call(865, 219), "lower_wall": V.call(875, 398), "gate": V.call(1015, 305),
				},
				"edges": [
					["west_n", "shelf"], ["west_s", "quarry"], ["shelf", "crossing"],
					["quarry", "crossing"], ["shelf", "top_bridge", [V.call(450, 186)]], ["quarry", "low_bridge", [V.call(454, 421)]],
					["crossing", "top_bridge"], ["crossing", "low_bridge"], ["top_bridge", "north_pass"],
					["low_bridge", "south_pass"], ["north", "north_pass"], ["south", "south_pass"],
					["north_pass", "redoubt"], ["south_pass", "redoubt"], ["north_pass", "upper_wall"],
					["south_pass", "lower_wall"], ["redoubt", "gate", [V.call(909, 305)]], ["upper_wall", "gate"],
					["lower_wall", "gate"],
				],
				"spawns": {"west_n": "west_n", "west_s": "west_s", "north": "north", "south": "south"},
				"spawn_labels": {"west_n": "北侧崖道", "west_s": "南侧矿道", "north": "北谷", "south": "南谷"},
				"gate": "gate",
			},
			"waves": [
				_w("第1波：裂谷先锋", 20, [
					_g("goblin", "west_n", 7, 0.90, 0.0),
					_g("slime", "west_s", 7, 0.60, 5.0),
					_g("slime", "west_s", 3, 0.60, 21.0),
				], 14.0),
				_w("第2波：疾风狼群", 22, [
					_g("wolf", "west_n", 6, 0.55, 0.0),
					_g("wolf", "west_s", 9, 0.55, 5.0),
					_g("wolf", "north", 5, 0.60, 10.0),
					_g("wolf", "west_n", 3, 0.55, 22.0),
				], 15.0),
				_w("第3波：铁壁盾卫", 24, [
					_g("shield_bearer", "west_n", 3, 1.10, 0.0),
					_g("goblin_archer", "west_s", 6, 1.00, 5.0),
					_g("shield_bearer", "south", 4, 1.10, 10.0),
					_g("shield_bearer", "west_n", 3, 1.10, 23.0),
				], 17.0),
				_w("第4波：夜翼集群", 26, [
					_g("bat", "north", 7, 0.55, 0.0),
					_g("bat", "south", 10, 0.55, 5.0),
					_g("wolf", "random", 8, 0.60, 10.0),
					_g("bat", "north", 3, 0.55, 21.0),
				], 14.0),
				_w("第5波：萨满与破城槌", 28, [
					_g("shaman", "west_n", 3, 1.80, 0.0),
					_g("goblin", "west_n", 7, 0.70, 5.0),
					_g("troll_breaker", "west_s", 2, 3.00, 10.0),
					_g("shield_bearer", "west_s", 6, 1.00, 15.0),
					_g("goblin", "west_n", 3, 0.70, 22.0),
				], 16.0),
				_w("第6波：裂变潮", 30, [
					_g("splitter", "west_n", 5, 0.80, 0.0),
					_g("splitter", "west_s", 8, 0.80, 5.0),
					_g("shaman", "random", 3, 2.00, 10.0),
					_g("bomb_bat", "north", 6, 0.80, 15.0),
					_g("adaptive", "random", 8, 0.70, 19.0),
					_g("splitter", "west_n", 3, 0.80, 23.0),
				], 12.0),
				_w("第7波：双线督军", 0, [
					_g("boss_warlord", "west_n", 1, 1.00, 7.0),
					_g("boss_warlord", "west_s", 1, 1.00, 10.0),
					_g("shield_bearer", "north", 5, 0.80, 10.0),
					_g("troll_breaker", "south", 3, 2.50, 15.0),
					_g("shaman", "random", 3, 1.80, 19.0),
					_g("adaptive", "random", 10, 0.60, 22.0),
					_g("shield_bearer", "north", 3, 0.80, 21.0),
				], 23.0),
			],
		},
		{
			"id": "stage_3_royal_siege", "index": 3,
			"name": "第3关：王城终局",
			"subtitle": "五路围城 · 中央广场决战",
			"intro_enemies": ["assassin", "gargoyle", "bomb_bat", "boss_obsidian"],
			"start_gold": 300, "lives": 20,
			"opening_view": V.call(525, 271), "opening_pads": ["p15", "p17"],
			"hero_spawns": [V.call(393, 147), V.call(411, 462)],
			"authored_pads": [
				[1, V.call(319, 109)], [1, V.call(431, 100)], [1, V.call(533, 129)], [1, V.call(622, 154)], [1, V.call(710, 165)], [1, V.call(796, 144)],
				[2, V.call(313, 507)], [2, V.call(449, 506)], [2, V.call(554, 483)], [2, V.call(652, 460)], [2, V.call(726, 461)], [2, V.call(817, 469)],
				[0, V.call(340, 263)], [0, V.call(342, 353)], [0, V.call(478, 231)], [0, V.call(502, 378)], [0, V.call(584, 269)], [0, V.call(616, 341)], [0, V.call(729, 259)], [0, V.call(746, 352)], [0, V.call(840, 256)], [0, V.call(840, 359)], [0, V.call(915, 350)],
			],
			"landmarks": [
				["castle_banner", V.call(382, 181)],
				["castle_banner", V.call(393, 430)],
				["castle_fountain", V.call(668, 254)],
				["castle_statue", V.call(713, 354)],
				["castle_wall", V.call(805, 259)],
				["castle_wall", V.call(804, 359)],
				["bridge_lantern", V.call(905, 273)],
			],
			"graph": {
				"nodes": {
					"north_gate": V.call(243, 147), "avenue": V.call(220, 307), "south_gate": V.call(242, 462),
					"north_alley": V.call(562, 57), "south_alley": V.call(590, 545), "north_market": V.call(393, 147),
					"west_square": V.call(455, 307), "south_market": V.call(411, 462), "north_arcade": V.call(562, 202),
					"south_arcade": V.call(591, 411), "plaza": V.call(691, 306), "north_bastion": V.call(811, 190),
					"south_bastion": V.call(817, 422), "inner_gate": V.call(872, 306), "gate": V.call(1013, 306),
				},
				"edges": [
					["north_gate", "north_market"], ["south_gate", "south_market"], ["avenue", "west_square"],
					["north_market", "west_square"], ["south_market", "west_square"], ["north_market", "north_arcade", [V.call(509, 147), V.call(509, 202)]],
					["south_market", "south_arcade", [V.call(516, 462), V.call(516, 410)]], ["north_alley", "north_arcade"], ["south_alley", "south_arcade"],
					["west_square", "plaza"], ["north_arcade", "plaza"], ["south_arcade", "plaza"],
					["north_arcade", "north_bastion"], ["south_arcade", "south_bastion"], ["plaza", "inner_gate"],
					["north_bastion", "inner_gate", [V.call(870, 202)]], ["south_bastion", "inner_gate", [V.call(870, 410)]], ["inner_gate", "gate"],
				],
				"spawns": {"west_n": "north_gate", "west": "avenue", "west_s": "south_gate", "north": "north_alley", "south": "south_alley"},
				"spawn_labels": {"west_n": "北城门", "west": "西大道", "west_s": "南城门", "north": "北巷", "south": "南巷"},
				"gate": "gate",
			},
			"waves": [
				_w("第1波：三路试探", 20, [
					_g("goblin", "west_n", 6, 0.90, 0.0),
					_g("slime", "west", 7, 0.60, 5.0),
					_g("goblin", "west_s", 6, 0.90, 10.0),
					_g("slime", "west", 3, 0.60, 26.0),
				], 15.0),
				_w("第2波：狼潮突袭", 22, [
					_g("wolf", "west_n", 5, 0.55, 0.0),
					_g("wolf", "west", 8, 0.55, 5.0),
					_g("wolf", "west_s", 8, 0.55, 10.0),
					_g("wolf", "random", 6, 0.50, 15.0),
					_g("wolf", "west_n", 3, 0.55, 27.0),
				], 14.0),
				_w("第3波：迅影刺客", 24, [
					_g("assassin", "north", 5, 0.60, 0.0),
					_g("shield_bearer", "west_n", 5, 1.10, 5.0),
					_g("shield_bearer", "west_s", 5, 1.10, 10.0),
					_g("assassin", "south", 6, 0.50, 15.0),
					_g("assassin", "north", 3, 0.60, 28.0),
				], 17.0),
				_w("第4波：石像鬼", 26, [
					_g("gargoyle", "west_n", 5, 1.20, 0.0),
					_g("gargoyle", "west_s", 5, 1.20, 5.0),
					_g("bomb_bat", "random", 8, 0.60, 10.0),
					_g("bat", "west", 7, 0.50, 15.0),
					_g("bat", "west", 3, 0.50, 26.0),
				], 17.0),
				_w("第5波：萨满大军", 28, [
					_g("shaman", "west", 4, 1.50, 0.0),
					_g("goblin", "west", 8, 0.55, 5.0),
					_g("splitter", "north", 6, 0.90, 10.0),
					_g("splitter", "south", 6, 0.90, 15.0),
					_g("goblin_archer", "random", 8, 0.80, 19.0),
					_g("goblin", "west", 4, 0.55, 27.0),
				], 15.0),
				_w("第6波：督军亲卫", 30, [
					_g("shield_bearer", "west", 5, 0.80, 0.0),
					_g("boss_warlord", "west_n", 1, 1.00, 7.0),
					_g("boss_warlord", "west_s", 1, 1.00, 13.0),
					_g("troll_breaker", "random", 3, 2.50, 15.0),
					_g("assassin", "north", 8, 0.50, 19.0),
					_g("shield_bearer", "west", 3, 0.80, 28.0),
				], 20.0),
				_w("第7波：遮天蔽日", 32, [
					_g("gargoyle", "west", 8, 1.00, 0.0),
					_g("bat", "north", 8, 0.45, 5.0),
					_g("bat", "south", 12, 0.45, 10.0),
					_g("bomb_bat", "random", 10, 0.50, 15.0),
					_g("adaptive", "random", 10, 0.60, 19.0),
					_g("bat", "north", 4, 0.45, 26.0),
				], 14.0),
				_w("最终波：黑曜大魔王", 0, [
					_g("shield_bearer", "west_n", 8, 0.80, 0.0),
					_g("boss_obsidian", "west", 1, 1.00, 7.0),
					_g("assassin", "west_s", 7, 0.50, 10.0),
					_g("troll_breaker", "north", 3, 2.50, 15.0),
					_g("gargoyle", "south", 6, 1.00, 19.0),
					_g("shaman", "random", 3, 1.80, 22.0),
					_g("adaptive", "random", 12, 0.50, 24.0),
					_g("assassin", "west_s", 3, 0.50, 27.0),
				], 23.0),
			],
		},
		{
			"id": "stage_4_frost_trail", "index": 4,
			"name": "第4关：霜原雪径",
			"subtitle": "蜿蜒雪径 · 冰川与山口",
			"intro_enemies": ["troll_breaker", "bomb_bat", "boss_frost_colossus"],
			"start_gold": 360, "lives": 20, "hp_scale": 0.82,
			"opening_view": V.call(527, 332), "opening_pads": ["p16", "p17"],
			"hero_spawns": [V.call(360, 140), V.call(414, 462)],
			"authored_pads": [
				[1, V.call(309, 100)], [1, V.call(405, 128)], [1, V.call(476, 224)], [1, V.call(583, 200)], [1, V.call(661, 133)], [1, V.call(766, 177)], [1, V.call(884, 178)],
				[2, V.call(322, 504)], [2, V.call(448, 504)], [2, V.call(536, 439)], [2, V.call(681, 474)], [2, V.call(776, 477)], [2, V.call(887, 468)],
				[0, V.call(313, 299)], [0, V.call(402, 311)], [0, V.call(470, 318)], [0, V.call(528, 339)], [0, V.call(629, 365)], [0, V.call(713, 253)], [0, V.call(725, 379)], [0, V.call(810, 304)], [0, V.call(935, 309)],
			],
			"landmarks": [
				["snow_fir", V.call(375, 75)],
				["snow_fir", V.call(455, 188)],
				["snow_crystal", V.call(472, 416)],
				["snow_crystal", V.call(581, 507)],
				["snow_fir", V.call(757, 124)],
				["obelisk", V.call(793, 352)],
				["snow_crystal", V.call(680, 497)],
			],
			"graph": {
				"nodes": {
					"western_trail": V.call(226, 140), "glacier": V.call(217, 466), "mountain": V.call(640, 60),
					"turn_one": V.call(360, 140), "turn_two": V.call(360, 287), "ridge": V.call(514, 265),
					"shoulder": V.call(633, 231), "icefield": V.call(414, 462), "blue_pass": V.call(622, 427),
					"gap": V.call(741, 309), "north_grate": V.call(840, 206), "south_grate": V.call(853, 434),
					"gate": V.call(1016, 303),
				},
				"edges": [
					["western_trail", "turn_one"], ["turn_one", "turn_two"], ["turn_two", "ridge"],
					["turn_two", "icefield", [V.call(357, 394)]], ["ridge", "shoulder", [V.call(562, 229)]], ["mountain", "shoulder", [V.call(692, 125), V.call(687, 201)]],
					["shoulder", "gap"], ["shoulder", "north_grate"], ["glacier", "icefield"],
					["icefield", "blue_pass", [V.call(530, 475)]], ["ridge", "blue_pass"], ["blue_pass", "gap"],
					["blue_pass", "south_grate"], ["gap", "north_grate"], ["gap", "south_grate"],
					["north_grate", "gate"], ["south_grate", "gate", [V.call(942, 407)]],
				],
				"spawns": {"west_n": "western_trail", "west_s": "glacier", "north": "mountain"},
				"spawn_labels": {"west_n": "回转雪径", "west_s": "蓝冰川", "north": "山口"},
				"gate": "gate",
			},
			"waves": [
				_w("第1波：雪原狼迹", 20, [
					_g("wolf", "west_n", 7, 0.60, 0.0),
					_g("slime", "west_s", 10, 0.60, 5.0),
					_g("wolf", "west_n", 3, 0.60, 17.0),
				], 13.0),
				_w("第2波：冰封盾阵", 22, [
					_g("shield_bearer", "west_n", 7, 1.00, 0.0),
					_g("goblin", "west_s", 7, 0.70, 5.0),
					_g("goblin_archer", "north", 5, 1.00, 10.0),
					_g("goblin", "west_s", 3, 0.70, 18.0),
				], 14.0),
				_w("第3波：霜翼", 24, [
					_g("gargoyle", "north", 5, 1.20, 0.0),
					_g("bat", "west_s", 8, 0.50, 5.0),
					_g("bomb_bat", "random", 6, 0.70, 10.0),
					_g("bat", "west_s", 4, 0.50, 19.0),
				], 15.0),
				_w("第4波：雪崩裂变", 26, [
					_g("splitter", "west_n", 5, 0.80, 0.0),
					_g("splitter", "west_s", 8, 0.80, 5.0),
					_g("shaman", "north", 3, 1.80, 10.0),
					_g("troll_breaker", "random", 2, 3.00, 15.0),
					_g("splitter", "west_n", 3, 0.80, 17.0),
				], 13.0),
				_w("第5波：白影突袭", 28, [
					_g("assassin", "west_s", 8, 0.45, 0.0),
					_g("wolf", "west_n", 12, 0.45, 5.0),
					_g("shield_bearer", "north", 6, 0.90, 10.0),
					_g("adaptive", "random", 8, 0.60, 15.0),
					_g("assassin", "west_s", 4, 0.45, 18.0),
				], 14.0),
				_w("第6波：萨满与盾", 30, [
					_g("shaman", "west_n", 4, 1.50, 0.0),
					_g("shield_bearer", "west_n", 7, 0.70, 5.0),
					_g("gargoyle", "west_s", 6, 1.00, 10.0),
					_g("troll_breaker", "north", 3, 2.50, 15.0),
					_g("shield_bearer", "west_n", 3, 0.70, 19.0),
				], 12.0),
				_w("第7波：督军冲阵", 32, [
					_g("goblin", "west_s", 8, 0.55, 0.0),
					_g("boss_warlord", "west_s", 1, 1.00, 7.0),
					_g("assassin", "west_n", 10, 0.45, 10.0),
					_g("bomb_bat", "north", 8, 0.60, 15.0),
					_g("adaptive", "random", 10, 0.60, 19.0),
					_g("goblin", "west_s", 4, 0.55, 17.0),
				], 21.0),
				_w("最终波：冰霜巨像", 0, [
					_g("shield_bearer", "west_n", 5, 0.80, 0.0),
					_g("boss_frost_colossus", "west_n", 1, 1.00, 7.0),
					_g("gargoyle", "west_s", 8, 1.00, 10.0),
					_g("troll_breaker", "north", 3, 2.50, 15.0),
					_g("splitter", "west_s", 8, 0.80, 19.0),
					_g("shaman", "random", 3, 1.80, 19.0),
					_g("adaptive", "random", 12, 0.50, 21.0),
					_g("shield_bearer", "west_n", 3, 0.80, 18.0),
				], 24.0),
			],
		},
		{
			"id": "stage_5_abyss_corridor", "index": 5,
			"name": "第5关：深渊回廊",
			"subtitle": "三条回廊 · 中央裂隙会开门",
			"intro_enemies": ["boss_obsidian_awakened"],
			"start_gold": 340, "lives": 20, "hp_scale": 0.92,
			"opening_view": V.call(504, 269), "opening_pads": ["p3", "p20"],
			"hero_spawns": [V.call(378, 127), V.call(376, 487)],
			"authored_pads": [
				[1, V.call(319, 83)], [1, V.call(451, 130)], [1, V.call(492, 149)], [1, V.call(591, 164)], [1, V.call(707, 163)], [1, V.call(811, 132)], [1, V.call(908, 154)],
				[2, V.call(319, 526)], [2, V.call(451, 484)], [2, V.call(494, 462)], [2, V.call(591, 450)], [2, V.call(710, 448)], [2, V.call(813, 471)], [2, V.call(905, 443)],
				[0, V.call(313, 257)], [0, V.call(314, 349)], [0, V.call(423, 243)], [0, V.call(419, 364)], [0, V.call(535, 273)], [0, V.call(541, 341)], [0, V.call(653, 247)], [0, V.call(652, 363)], [0, V.call(744, 250)], [0, V.call(746, 359)], [0, V.call(844, 306)],
			],
			"landmarks": [
				["rift_column", V.call(381, 219)],
				["rift_column", V.call(379, 406)],
				["rift_brazier", V.call(489, 259)],
				["rift_brazier", V.call(489, 356)],
				["abyss_crystal", V.call(618, 260)],
				["abyss_crystal", V.call(617, 352)],
				["obelisk", V.call(860, 294)],
			],
			"graph": {
				"nodes": {
					"north_mouth": V.call(219, 126), "middle_mouth": V.call(220, 304), "south_mouth": V.call(227, 485),
					"rift": V.call(626, 305), "north_outer": V.call(378, 127), "middle_outer": V.call(365, 304),
					"south_outer": V.call(376, 487), "north_inner": V.call(552, 213), "south_inner": V.call(554, 400),
					"crown": V.call(773, 178), "crossfire": V.call(769, 305), "root": V.call(773, 434),
					"upper_gate": V.call(907, 215), "lower_gate": V.call(909, 393), "gate": V.call(1019, 305),
				},
				"edges": [
					["north_mouth", "north_outer"], ["middle_mouth", "middle_outer"], ["south_mouth", "south_outer"],
					["north_outer", "north_inner"], ["south_outer", "south_inner"], ["middle_outer", "north_inner"],
					["middle_outer", "south_inner"], ["north_outer", "crown", [V.call(488, 84), V.call(660, 89)]], ["south_outer", "root", [V.call(487, 531), V.call(657, 530)]],
					["north_inner", "crossfire", [V.call(658, 207), V.call(696, 252)]], ["south_inner", "crossfire", [V.call(650, 409), V.call(699, 356)]], ["rift", "crossfire"],
					["crossfire", "upper_gate"], ["crossfire", "lower_gate"], ["crown", "upper_gate", [V.call(861, 163)]],
					["root", "lower_gate"], ["upper_gate", "gate"], ["lower_gate", "gate"],
				],
				"spawns": {"west_n": "north_mouth", "west": "middle_mouth", "west_s": "south_mouth", "portal": "rift"},
				"spawn_labels": {"west_n": "北外廊", "west": "中央长廊", "west_s": "南外廊", "portal": "中央裂隙"},
				"gate": "gate",
			},
			"waves": [
				_w("第1波：深渊低语", 20, [
					_g("slime", "west_n", 7, 0.55, 0.0),
					_g("goblin", "west", 8, 0.80, 5.0),
					_g("slime", "west_s", 10, 0.55, 10.0),
					_g("slime", "west_n", 3, 0.55, 25.0),
				], 14.0),
				_w("第2波：疾影", 22, [
					_g("assassin", "west_n", 8, 0.55, 0.0),
					_g("wolf", "west", 7, 0.50, 5.0),
					_g("assassin", "west_s", 8, 0.55, 10.0),
					_g("wolf", "west", 3, 0.50, 26.0),
				], 14.0),
				_w("第3波：盾墙", 24, [
					_g("shield_bearer", "west_n", 6, 1.00, 0.0),
					_g("shield_bearer", "west", 6, 1.00, 5.0),
					_g("shaman", "west_s", 3, 1.80, 10.0),
					_g("goblin_archer", "west_s", 5, 0.80, 15.0),
					_g("goblin_archer", "west_s", 3, 0.80, 27.0),
				], 15.0),
				_w("第4波：裂隙开门", 26, [
					_g("gargoyle", "west_n", 6, 1.00, 0.0),
					_g("bat", "west", 8, 0.45, 5.0),
					_g("goblin", "portal", 10, 0.60, 12.0),
					_g("bomb_bat", "random", 8, 0.60, 15.0),
					_g("bat", "west", 4, 0.45, 24.0),
				], 17.0),
				_w("第5波：督军双雄", 28, [
					_g("boss_warlord", "west_n", 1, 1.00, 7.0),
					_g("boss_warlord", "west_s", 1, 1.00, 10.0),
					_g("goblin", "west", 10, 0.50, 10.0),
					_g("troll_breaker", "portal", 2, 3.00, 19.0),
					_g("goblin", "west", 4, 0.50, 26.0),
				], 21.0),
				_w("第6波：裂变深渊", 30, [
					_g("splitter", "west_n", 5, 0.70, 0.0),
					_g("splitter", "west", 8, 0.70, 5.0),
					_g("splitter", "west_s", 8, 0.70, 10.0),
					_g("shaman", "portal", 3, 1.80, 19.0),
					_g("adaptive", "random", 10, 0.60, 19.0),
					_g("splitter", "west_n", 3, 0.70, 27.0),
				], 14.0),
				_w("第7波：寒霜使者", 32, [
					_g("shield_bearer", "west_n", 8, 0.80, 0.0),
					_g("boss_frost_colossus", "west", 1, 1.00, 7.0),
					_g("assassin", "west_s", 8, 0.40, 10.0),
					_g("troll_breaker", "random", 3, 2.50, 15.0),
					_g("assassin", "west_s", 4, 0.40, 25.0),
				], 23.0),
				_w("第8波：混沌之潮", 34, [
					_g("gargoyle", "west_n", 8, 0.90, 0.0),
					_g("shield_bearer", "west", 10, 0.70, 5.0),
					_g("wolf", "west_s", 10, 0.40, 15.0),
					_g("shaman", "portal", 4, 1.50, 17.0),
					_g("bomb_bat", "random", 10, 0.50, 19.0),
					_g("adaptive", "random", 10, 0.60, 22.0),
					_g("wolf", "west_s", 4, 0.40, 26.0),
				], 14.0),
				_w("第9波：魔王先锋", 36, [
					_g("assassin", "west", 10, 0.40, 0.0),
					_g("boss_obsidian", "portal", 1, 1.00, 7.0),
					_g("gargoyle", "west_s", 8, 0.90, 10.0),
					_g("troll_breaker", "west_n", 3, 2.50, 15.0),
					_g("splitter", "random", 8, 0.80, 19.0),
					_g("assassin", "west", 4, 0.40, 27.0),
				], 22.0),
				_w("最终波：觉醒·黑曜魔王", 0, [
					_g("shield_bearer", "west_n", 10, 0.70, 0.0),
					_g("boss_obsidian_awakened", "west", 1, 1.00, 7.0),
					_g("shield_bearer", "west_s", 10, 0.70, 10.0),
					_g("shaman", "portal", 4, 1.80, 19.0),
					_g("gargoyle", "west_n", 8, 1.00, 19.0),
					_g("assassin", "west_s", 8, 0.40, 22.0),
					_g("troll_breaker", "portal", 4, 2.50, 19.0),
					_g("adaptive", "random", 14, 0.50, 21.0),
					_g("assassin", "west_s", 4, 0.40, 25.0),
				], 24.0),
			],
		},
	]


static func get_stages() -> Array[Dictionary]:
	if _stages.is_empty():
		for s in _defs():
			s["world"] = WORLD
			var roads := MapGraph.all_edge_polylines(s["graph"])
			var pads: Array[Dictionary] = []
			for pair in s["authored_pads"]:
				var pos: Vector2 = pair[1]
				pads.append({
					"id": "p%d" % (pads.size() + 1), "owner_hint": pair[0], "pos": pos,
					"rally": MapGraph.nearest_on_polylines(pos, roads).round(),
				})
			s["pads"] = pads
			s.erase("authored_pads")
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
