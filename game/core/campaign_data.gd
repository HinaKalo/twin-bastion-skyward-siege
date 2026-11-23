class_name CampaignData
extends RefCounted
## 5-stage co-op campaign. Each stage defines lanes, build pads (owner_hint: 1=P1, 2=P2, 0=shared),
## hero spawn points, wave rosters (with early-call bonus) and flavor text.
## Each stage introduces new enemies (see CreepCatalog) and the biome is derived from the stage id.

static func _g(enemy: String, lane: String, count: int, interval: float, delay: float = 0.0) -> Dictionary:
	return {"enemy_id": enemy, "lane_id": lane, "count": count, "interval": interval, "delay": delay}


static func _w(wname: String, bonus: int, groups: Array) -> Dictionary:
	return {"name": wname, "early_bonus": bonus, "groups": groups}


static func get_stages() -> Array[Dictionary]:
	return [
		{
			"id": "stage_1_twin_bridge",
			"index": 1,
			"name": "第1关：翡翠双桥",
			"subtitle": "经典双路汇合 · P1守北桥 / P2守南桥",
			"intro_enemies": ["slime", "goblin", "wolf", "bat", "splitter", "boss_warlord"],
			"start_gold": 170,
			"lives": 20,
			"hero_spawns": [Vector2(372, 116), Vector2(372, 156)],
			"lanes": [
				{"id": "north", "label": "北桥", "points": [Vector2(10, 86), Vector2(150, 86), Vector2(210, 68), Vector2(315, 68), Vector2(355, 136), Vector2(435, 136)]},
				{"id": "south", "label": "南桥", "points": [Vector2(10, 184), Vector2(250, 184), Vector2(355, 136), Vector2(435, 136)]},
			],
			"pads": [
				{"id": "p1", "owner_hint": 1, "pos": Vector2(96, 60),   "rally": Vector2(96, 86)},
				{"id": "p2", "owner_hint": 1, "pos": Vector2(254, 96),  "rally": Vector2(254, 68)},
				{"id": "p3", "owner_hint": 0, "pos": Vector2(312, 104), "rally": Vector2(332, 96)},
				{"id": "p4", "owner_hint": 0, "pos": Vector2(388, 108), "rally": Vector2(388, 136)},
				{"id": "p5", "owner_hint": 2, "pos": Vector2(110, 212), "rally": Vector2(110, 184)},
				{"id": "p6", "owner_hint": 2, "pos": Vector2(226, 212), "rally": Vector2(226, 184)},
				{"id": "p7", "owner_hint": 2, "pos": Vector2(318, 186), "rally": Vector2(300, 162)},
				{"id": "p8", "owner_hint": 1, "pos": Vector2(96, 120),  "rally": Vector2(96, 86)},
			],
			"waves": [
				_w("第1波：双桥斥候", 15, [_g("slime", "north", 6, 0.9), _g("slime", "south", 6, 0.9)]),
				_w("第2波：重甲步兵", 18, [_g("goblin", "north", 6, 1.0), _g("goblin", "south", 5, 1.0), _g("slime", "south", 5, 0.8, 4.0)]),
				_w("第3波：暗影空袭", 20, [_g("bat", "north", 7, 0.75), _g("wolf", "south", 7, 0.8), _g("bat", "south", 4, 0.8, 4.0)]),
				_w("第4波：裂变来袭", 22, [_g("splitter", "north", 5, 1.1), _g("splitter", "south", 5, 1.1), _g("wolf", "north", 6, 0.6, 4.0)]),
				_w("第5波：狼群合围", 25, [_g("wolf", "north", 10, 0.55), _g("goblin", "south", 8, 0.8), _g("bat", "south", 6, 0.7, 4.0), _g("splitter", "north", 3, 1.0, 6.0)]),
				_w("第6波：哥布林督军", 0, [_g("boss_warlord", "north", 1, 1.0, 2.0), _g("goblin", "north", 6, 0.8), _g("goblin", "south", 8, 0.7), _g("bat", "south", 6, 0.7, 3.0), _g("splitter", "south", 4, 1.0, 6.0)]),
			],
		},
		{
			"id": "stage_2_rift_cross",
			"index": 2,
			"name": "第2关：裂谷交叉",
			"subtitle": "X型交叉双路 · 中路黄金连携高地",
			"intro_enemies": ["shield_bearer", "shaman"],
			"start_gold": 190,
			"lives": 20,
			"hero_spawns": [Vector2(390, 122), Vector2(390, 150)],
			"lanes": [
				{"id": "north", "label": "北谷", "points": [Vector2(10, 74), Vector2(140, 74), Vector2(235, 136), Vector2(335, 186), Vector2(435, 136)]},
				{"id": "south", "label": "南谷", "points": [Vector2(10, 194), Vector2(140, 194), Vector2(235, 136), Vector2(335, 86), Vector2(435, 136)]},
			],
			"pads": [
				{"id": "p1", "owner_hint": 1, "pos": Vector2(92, 104),  "rally": Vector2(92, 74)},
				{"id": "p2", "owner_hint": 0, "pos": Vector2(176, 136), "rally": Vector2(228, 136)},
				{"id": "p3", "owner_hint": 0, "pos": Vector2(235, 96),  "rally": Vector2(235, 128)},
				{"id": "p4", "owner_hint": 0, "pos": Vector2(235, 176), "rally": Vector2(235, 144)},
				{"id": "p5", "owner_hint": 2, "pos": Vector2(92, 164),  "rally": Vector2(92, 194)},
				{"id": "p6", "owner_hint": 0, "pos": Vector2(335, 136), "rally": Vector2(300, 104)},
				{"id": "p7", "owner_hint": 2, "pos": Vector2(385, 192), "rally": Vector2(385, 161)},
				{"id": "p8", "owner_hint": 1, "pos": Vector2(300, 52),  "rally": Vector2(300, 100)},
				{"id": "p9", "owner_hint": 2, "pos": Vector2(300, 220), "rally": Vector2(300, 170)},
			],
			"waves": [
				_w("第1波：裂谷先锋", 15, [_g("goblin", "north", 6, 0.9), _g("slime", "south", 8, 0.7)]),
				_w("第2波：疾风狼群", 18, [_g("wolf", "north", 8, 0.6), _g("wolf", "south", 8, 0.6)]),
				_w("第3波：铁壁盾卫", 20, [_g("shield_bearer", "north", 5, 1.2), _g("goblin", "south", 7, 0.8), _g("shield_bearer", "south", 3, 1.2, 5.0)]),
				_w("第4波：夜翼集群", 22, [_g("bat", "north", 9, 0.6), _g("bat", "south", 9, 0.6), _g("wolf", "north", 5, 0.6, 5.0)]),
				_w("第5波：萨满祝福", 24, [_g("shaman", "north", 2, 2.0, 1.0), _g("goblin", "north", 8, 0.7), _g("shaman", "south", 2, 2.0, 1.0), _g("shield_bearer", "south", 5, 1.0)]),
				_w("第6波：裂变潮", 26, [_g("splitter", "north", 6, 0.9), _g("splitter", "south", 6, 0.9), _g("shaman", "south", 2, 2.5, 3.0), _g("bat", "north", 6, 0.6, 5.0)]),
				_w("第7波：双线督军", 0, [_g("boss_warlord", "north", 1, 1.0, 1.0), _g("boss_warlord", "south", 1, 1.0, 4.0), _g("shield_bearer", "north", 6, 0.9), _g("shaman", "south", 3, 1.8), _g("wolf", "south", 8, 0.55, 5.0)]),
			],
		},
		{
			"id": "stage_3_royal_siege",
			"index": 3,
			"name": "第3关：王城终局",
			"subtitle": "三路围城决战 · 讨伐【黑曜大魔王】",
			"intro_enemies": ["assassin", "gargoyle", "boss_obsidian"],
			"start_gold": 230,
			"lives": 20,
			"hero_spawns": [Vector2(400, 118), Vector2(400, 154)],
			"lanes": [
				{"id": "north", "label": "北城", "points": [Vector2(10, 68), Vector2(220, 68), Vector2(345, 136), Vector2(435, 136)]},
				{"id": "mid",   "label": "中道", "points": [Vector2(10, 136), Vector2(435, 136)]},
				{"id": "south", "label": "南城", "points": [Vector2(10, 204), Vector2(220, 204), Vector2(345, 136), Vector2(435, 136)]},
			],
			"pads": [
				{"id": "p1", "owner_hint": 1, "pos": Vector2(115, 102), "rally": Vector2(115, 68)},
				{"id": "p2", "owner_hint": 1, "pos": Vector2(225, 104), "rally": Vector2(225, 136)},
				{"id": "p3", "owner_hint": 0, "pos": Vector2(318, 88),  "rally": Vector2(300, 112)},
				{"id": "p4", "owner_hint": 0, "pos": Vector2(385, 108), "rally": Vector2(385, 136)},
				{"id": "p5", "owner_hint": 2, "pos": Vector2(115, 170), "rally": Vector2(115, 204)},
				{"id": "p6", "owner_hint": 2, "pos": Vector2(225, 168), "rally": Vector2(225, 136)},
				{"id": "p7", "owner_hint": 0, "pos": Vector2(318, 184), "rally": Vector2(300, 160)},
				{"id": "p8", "owner_hint": 0, "pos": Vector2(385, 164), "rally": Vector2(385, 136)},
				{"id": "p9", "owner_hint": 1, "pos": Vector2(270, 44),  "rally": Vector2(270, 92)},
				{"id": "p10", "owner_hint": 2, "pos": Vector2(270, 228), "rally": Vector2(270, 180)},
			],
			"waves": [
				_w("第1波：三路试探", 15, [_g("goblin", "north", 5, 0.9), _g("slime", "mid", 8, 0.7), _g("goblin", "south", 5, 0.9)]),
				_w("第2波：狼潮突袭", 18, [_g("wolf", "north", 7, 0.6), _g("wolf", "mid", 7, 0.6), _g("wolf", "south", 7, 0.6)]),
				_w("第3波：迅影刺客", 20, [_g("assassin", "mid", 6, 0.7), _g("shield_bearer", "north", 4, 1.1), _g("shield_bearer", "south", 4, 1.1), _g("assassin", "mid", 4, 0.5, 6.0)]),
				_w("第4波：石像鬼", 22, [_g("gargoyle", "north", 4, 1.3), _g("gargoyle", "south", 4, 1.3), _g("bat", "mid", 8, 0.55)]),
				_w("第5波：萨满大军", 24, [_g("shaman", "mid", 3, 1.6), _g("goblin", "mid", 10, 0.6), _g("splitter", "north", 5, 1.0), _g("splitter", "south", 5, 1.0)]),
				_w("第6波：督军亲卫", 26, [_g("boss_warlord", "north", 1, 1.0, 1.0), _g("shield_bearer", "mid", 7, 0.8), _g("boss_warlord", "south", 1, 1.0, 3.0), _g("assassin", "mid", 6, 0.5, 6.0)]),
				_w("第7波：遮天蔽日", 28, [_g("gargoyle", "mid", 6, 1.0), _g("bat", "north", 10, 0.5), _g("bat", "south", 10, 0.5), _g("shaman", "mid", 2, 2.0, 4.0)]),
				_w("最终波：黑曜大魔王", 0, [_g("boss_obsidian", "mid", 1, 1.0, 2.0), _g("shield_bearer", "north", 6, 0.9), _g("assassin", "south", 8, 0.55), _g("gargoyle", "mid", 4, 1.2, 6.0), _g("shaman", "north", 2, 2.0, 5.0)]),
			],
		},
		{
			"id": "stage_4_frost_trail",
			"index": 4,
			"name": "第4关：霜原雪径",
			"subtitle": "蜿蜒雪径 · 寒冰与分支塔的舞台",
			"intro_enemies": ["boss_frost_colossus"],
			"start_gold": 250,
			"lives": 20,
			"hp_scale": 1.12,
			"hero_spawns": [Vector2(392, 118), Vector2(392, 154)],
			"lanes": [
				{"id": "serpent", "label": "蛇径", "points": [Vector2(10, 62), Vector2(112, 62), Vector2(112, 194), Vector2(234, 194), Vector2(234, 70), Vector2(352, 70), Vector2(352, 136), Vector2(435, 136)]},
				{"id": "glacier", "label": "冰川", "points": [Vector2(10, 226), Vector2(300, 226), Vector2(392, 180), Vector2(435, 136)]},
			],
			"pads": [
				{"id": "p1", "owner_hint": 1, "pos": Vector2(60, 96),   "rally": Vector2(60, 62)},
				{"id": "p2", "owner_hint": 0, "pos": Vector2(160, 110), "rally": Vector2(112, 110)},
				{"id": "p3", "owner_hint": 0, "pos": Vector2(172, 160), "rally": Vector2(172, 194)},
				{"id": "p4", "owner_hint": 1, "pos": Vector2(282, 110), "rally": Vector2(234, 110)},
				{"id": "p5", "owner_hint": 0, "pos": Vector2(286, 166), "rally": Vector2(234, 166)},
				{"id": "p6", "owner_hint": 2, "pos": Vector2(60, 194),  "rally": Vector2(60, 226)},
				{"id": "p7", "owner_hint": 0, "pos": Vector2(78, 140),  "rally": Vector2(112, 140)},
				{"id": "p8", "owner_hint": 1, "pos": Vector2(300, 40),  "rally": Vector2(300, 70)},
				{"id": "p9", "owner_hint": 2, "pos": Vector2(392, 100), "rally": Vector2(374, 136)},
				{"id": "p10", "owner_hint": 2, "pos": Vector2(370, 166), "rally": Vector2(370, 136)},
			],
			"waves": [
				_w("第1波：雪原狼迹", 15, [_g("wolf", "serpent", 8, 0.7), _g("slime", "glacier", 8, 0.7)]),
				_w("第2波：冰封盾阵", 18, [_g("shield_bearer", "serpent", 6, 1.0), _g("goblin", "glacier", 8, 0.8)]),
				_w("第3波：霜翼", 20, [_g("gargoyle", "serpent", 4, 1.3), _g("bat", "glacier", 10, 0.55)]),
				_w("第4波：雪崩裂变", 22, [_g("splitter", "serpent", 7, 0.9), _g("splitter", "glacier", 6, 0.9), _g("shaman", "serpent", 2, 2.0, 3.0)]),
				_w("第5波：白影突袭", 24, [_g("assassin", "glacier", 10, 0.5), _g("wolf", "serpent", 10, 0.5), _g("shield_bearer", "glacier", 4, 1.0, 5.0)]),
				_w("第6波：萨满与盾", 26, [_g("shaman", "serpent", 3, 1.6), _g("shield_bearer", "serpent", 8, 0.8), _g("gargoyle", "glacier", 5, 1.1)]),
				_w("第7波：督军冲阵", 28, [_g("boss_warlord", "glacier", 1, 1.0, 1.0), _g("goblin", "glacier", 10, 0.6), _g("assassin", "serpent", 8, 0.5, 3.0), _g("bat", "serpent", 8, 0.55, 6.0)]),
				_w("最终波：冰霜巨像", 0, [_g("boss_frost_colossus", "serpent", 1, 1.0, 2.0), _g("shield_bearer", "serpent", 6, 0.9, 5.0), _g("gargoyle", "glacier", 6, 1.0), _g("splitter", "glacier", 6, 0.9, 4.0), _g("shaman", "serpent", 2, 2.0, 8.0)]),
			],
		},
		{
			"id": "stage_5_abyss_corridor",
			"index": 5,
			"name": "第5关：深渊回廊",
			"subtitle": "三路深渊终局 · 觉醒魔王降临",
			"intro_enemies": ["boss_obsidian_awakened"],
			"start_gold": 270,
			"lives": 20,
			"hp_scale": 0.94,
			"hero_spawns": [Vector2(398, 120), Vector2(398, 152)],
			"lanes": [
				{"id": "north", "label": "北廊", "points": [Vector2(10, 56), Vector2(196, 56), Vector2(300, 108), Vector2(435, 136)]},
				{"id": "mid",   "label": "中廊", "points": [Vector2(10, 136), Vector2(170, 136), Vector2(236, 172), Vector2(330, 152), Vector2(435, 136)]},
				{"id": "south", "label": "南廊", "points": [Vector2(10, 216), Vector2(216, 216), Vector2(320, 176), Vector2(435, 136)]},
			],
			"pads": [
				{"id": "p1", "owner_hint": 1, "pos": Vector2(96, 96),   "rally": Vector2(96, 56)},
				{"id": "p2", "owner_hint": 1, "pos": Vector2(196, 92),  "rally": Vector2(196, 60)},
				{"id": "p3", "owner_hint": 0, "pos": Vector2(268, 140), "rally": Vector2(262, 166)},
				{"id": "p4", "owner_hint": 0, "pos": Vector2(370, 102), "rally": Vector2(370, 124)},
				{"id": "p5", "owner_hint": 2, "pos": Vector2(96, 176),  "rally": Vector2(96, 216)},
				{"id": "p6", "owner_hint": 2, "pos": Vector2(196, 186), "rally": Vector2(196, 216)},
				{"id": "p7", "owner_hint": 0, "pos": Vector2(298, 206), "rally": Vector2(304, 182)},
				{"id": "p8", "owner_hint": 0, "pos": Vector2(380, 196), "rally": Vector2(380, 155)},
				{"id": "p9", "owner_hint": 1, "pos": Vector2(300, 64),  "rally": Vector2(300, 108)},
				{"id": "p10", "owner_hint": 2, "pos": Vector2(150, 236), "rally": Vector2(150, 216)},
			],
			"waves": [
				_w("第1波：深渊低语", 15, [_g("slime", "north", 8, 0.6), _g("goblin", "mid", 6, 0.8), _g("slime", "south", 8, 0.6)]),
				_w("第2波：疾影", 18, [_g("assassin", "north", 6, 0.6), _g("wolf", "mid", 8, 0.55), _g("assassin", "south", 6, 0.6)]),
				_w("第3波：盾墙", 20, [_g("shield_bearer", "north", 5, 1.0), _g("shield_bearer", "mid", 5, 1.0), _g("shaman", "south", 2, 2.0), _g("goblin", "south", 8, 0.7)]),
				_w("第4波：石翼", 22, [_g("gargoyle", "north", 5, 1.1), _g("bat", "mid", 12, 0.45), _g("gargoyle", "south", 5, 1.1)]),
				_w("第5波：督军双雄", 24, [_g("boss_warlord", "north", 1, 1.0, 1.0), _g("boss_warlord", "south", 1, 1.0, 3.0), _g("goblin", "mid", 12, 0.55)]),
				_w("第6波：裂变深渊", 26, [_g("splitter", "north", 7, 0.8), _g("splitter", "mid", 7, 0.8), _g("splitter", "south", 7, 0.8), _g("shaman", "mid", 2, 2.0, 3.0)]),
				_w("第7波：寒霜使者", 28, [_g("boss_frost_colossus", "mid", 1, 1.0, 1.0), _g("shield_bearer", "north", 6, 0.9), _g("assassin", "south", 10, 0.45, 2.0)]),
				_w("第8波：混沌之潮", 30, [_g("gargoyle", "north", 6, 1.0), _g("shield_bearer", "mid", 8, 0.8), _g("shaman", "mid", 3, 1.6, 2.0), _g("wolf", "south", 12, 0.45)]),
				_w("第9波：魔王先锋", 32, [_g("boss_obsidian", "north", 1, 1.0, 1.0), _g("assassin", "mid", 12, 0.45), _g("gargoyle", "south", 6, 1.0), _g("splitter", "south", 6, 0.9, 5.0)]),
				_w("最终波：觉醒·黑曜魔王", 0, [_g("boss_obsidian_awakened", "mid", 1, 1.0, 3.0), _g("shield_bearer", "north", 8, 0.8), _g("shield_bearer", "south", 8, 0.8), _g("shaman", "mid", 3, 2.0, 1.0), _g("gargoyle", "north", 6, 1.1, 6.0), _g("assassin", "south", 10, 0.45, 8.0)]),
			],
		},
	]


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
