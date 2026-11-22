class_name CampaignData
extends RefCounted
## 3-Stage Commercial Co-op Tower Defense Campaign Definitions.
## Each stage defines lanes, P1/P2/Shared build pads (owner_hint: 1=P1, 2=P2, 0=Shared),
## wave rosters, and flavor metadata.

static func get_stages() -> Array[Dictionary]:
	return [
		{
			"id": "stage_1_twin_bridge",
			"index": 1,
			"name": "第1关：翡翠双桥",
			"subtitle": "经典双路汇合 · P1守北桥 / P2守南桥",
			"start_gold": 160,
			"lives": 20,
			"lanes": [
				{"id": "north", "label": "北桥", "points": [Vector2(10, 86), Vector2(150, 86), Vector2(210, 68), Vector2(315, 68), Vector2(355, 136), Vector2(435, 136)]},
				{"id": "south", "label": "南桥", "points": [Vector2(10, 184), Vector2(250, 184), Vector2(355, 136), Vector2(435, 136)]},
			],
			"pads": [
				{"id": "p1", "owner_hint": 1, "pos": Vector2(96, 62),   "rally": Vector2(96, 86)},
				{"id": "p2", "owner_hint": 1, "pos": Vector2(248, 96),  "rally": Vector2(248, 68)},
				{"id": "p3", "owner_hint": 0, "pos": Vector2(320, 102), "rally": Vector2(335, 118)},
				{"id": "p4", "owner_hint": 0, "pos": Vector2(376, 108), "rally": Vector2(376, 136)},
				{"id": "p5", "owner_hint": 2, "pos": Vector2(110, 210), "rally": Vector2(110, 184)},
				{"id": "p6", "owner_hint": 2, "pos": Vector2(226, 210), "rally": Vector2(226, 184)},
				{"id": "p7", "owner_hint": 2, "pos": Vector2(318, 178), "rally": Vector2(318, 152)},
			],
			"waves": [
				{"name": "第1波：双桥斥候", "groups": [{"enemy_id": "slime", "lane_id": "north", "count": 5, "interval": 0.9}, {"enemy_id": "slime", "lane_id": "south", "count": 5, "interval": 0.9}]},
				{"name": "第2波：重甲步兵", "groups": [{"enemy_id": "goblin", "lane_id": "north", "count": 5, "interval": 1.0}, {"enemy_id": "goblin", "lane_id": "south", "count": 5, "interval": 1.0}]},
				{"name": "第3波：暗影空袭", "groups": [{"enemy_id": "bat", "lane_id": "north", "count": 6, "interval": 0.75}, {"enemy_id": "wolf", "lane_id": "south", "count": 5, "interval": 0.85}]},
				{"name": "第4波：狼群合围", "groups": [{"enemy_id": "wolf", "lane_id": "north", "count": 7, "interval": 0.65}, {"enemy_id": "goblin", "lane_id": "south", "count": 6, "interval": 0.85}]},
				{"name": "第5波：哥布林督军", "groups": [{"enemy_id": "boss_warlord", "lane_id": "north", "count": 1, "interval": 1.0}, {"enemy_id": "bat", "lane_id": "south", "count": 6, "interval": 0.7}]},
			],
		},
		{
			"id": "stage_2_rift_cross",
			"index": 2,
			"name": "第2关：裂谷交叉",
			"subtitle": "X型交叉双路 · 中路黄金连携高地",
			"start_gold": 190,
			"lives": 20,
			"lanes": [
				{"id": "north", "label": "北谷", "points": [Vector2(10, 74), Vector2(140, 74), Vector2(235, 136), Vector2(335, 186), Vector2(435, 136)]},
				{"id": "south", "label": "南谷", "points": [Vector2(10, 194), Vector2(140, 194), Vector2(235, 136), Vector2(335, 86), Vector2(435, 136)]},
			],
			"pads": [
				{"id": "p1", "owner_hint": 1, "pos": Vector2(92, 102),  "rally": Vector2(92, 74)},
				{"id": "p2", "owner_hint": 0, "pos": Vector2(188, 136), "rally": Vector2(235, 136)},
				{"id": "p3", "owner_hint": 0, "pos": Vector2(235, 98),  "rally": Vector2(235, 136)},
				{"id": "p4", "owner_hint": 0, "pos": Vector2(235, 174), "rally": Vector2(235, 136)},
				{"id": "p5", "owner_hint": 2, "pos": Vector2(92, 166),  "rally": Vector2(92, 194)},
				{"id": "p6", "owner_hint": 1, "pos": Vector2(335, 118), "rally": Vector2(335, 86)},
				{"id": "p7", "owner_hint": 2, "pos": Vector2(335, 154), "rally": Vector2(335, 186)},
			],
			"waves": [
				{"name": "第1波：裂谷先锋", "groups": [{"enemy_id": "goblin", "lane_id": "north", "count": 5, "interval": 0.9}, {"enemy_id": "slime", "lane_id": "south", "count": 6, "interval": 0.8}]},
				{"name": "第2波：疾风狼群", "groups": [{"enemy_id": "wolf", "lane_id": "north", "count": 6, "interval": 0.7}, {"enemy_id": "wolf", "lane_id": "south", "count": 6, "interval": 0.7}]},
				{"name": "第3波：夜翼集群", "groups": [{"enemy_id": "bat", "lane_id": "north", "count": 7, "interval": 0.65}, {"enemy_id": "bat", "lane_id": "south", "count": 7, "interval": 0.65}]},
				{"name": "第4波：铁甲冲锋", "groups": [{"enemy_id": "goblin", "lane_id": "north", "count": 8, "interval": 0.75}, {"enemy_id": "goblin", "lane_id": "south", "count": 8, "interval": 0.75}]},
				{"name": "第5波：双线督军", "groups": [{"enemy_id": "boss_warlord", "lane_id": "north", "count": 1, "interval": 1.0}, {"enemy_id": "boss_warlord", "lane_id": "south", "count": 1, "interval": 1.0}]},
			],
		},
		{
			"id": "stage_3_royal_siege",
			"index": 3,
			"name": "第3关：王城终局",
			"subtitle": "三路围城决战 · 讨伐【黑曜大魔王】",
			"start_gold": 220,
			"lives": 20,
			"lanes": [
				{"id": "north", "label": "北城", "points": [Vector2(10, 68), Vector2(220, 68), Vector2(345, 136), Vector2(435, 136)]},
				{"id": "mid",   "label": "中道", "points": [Vector2(10, 136), Vector2(435, 136)]},
				{"id": "south", "label": "南城", "points": [Vector2(10, 202), Vector2(220, 202), Vector2(345, 136), Vector2(435, 136)]},
			],
			"pads": [
				{"id": "p1", "owner_hint": 1, "pos": Vector2(115, 98),  "rally": Vector2(115, 68)},
				{"id": "p2", "owner_hint": 1, "pos": Vector2(225, 102), "rally": Vector2(225, 136)},
				{"id": "p3", "owner_hint": 0, "pos": Vector2(305, 102), "rally": Vector2(345, 136)},
				{"id": "p4", "owner_hint": 0, "pos": Vector2(378, 104), "rally": Vector2(378, 136)},
				{"id": "p5", "owner_hint": 2, "pos": Vector2(115, 170), "rally": Vector2(115, 202)},
				{"id": "p6", "owner_hint": 2, "pos": Vector2(225, 170), "rally": Vector2(225, 136)},
				{"id": "p7", "owner_hint": 0, "pos": Vector2(305, 170), "rally": Vector2(345, 136)},
				{"id": "p8", "owner_hint": 0, "pos": Vector2(378, 168), "rally": Vector2(378, 136)},
			],
			"waves": [
				{"name": "第1波：三路试探", "groups": [{"enemy_id": "goblin", "lane_id": "north", "count": 4, "interval": 0.9}, {"enemy_id": "slime", "lane_id": "mid", "count": 6, "interval": 0.7}, {"enemy_id": "goblin", "lane_id": "south", "count": 4, "interval": 0.9}]},
				{"name": "第2波：狼潮突袭", "groups": [{"enemy_id": "wolf", "lane_id": "north", "count": 6, "interval": 0.65}, {"enemy_id": "wolf", "lane_id": "mid", "count": 6, "interval": 0.65}, {"enemy_id": "wolf", "lane_id": "south", "count": 6, "interval": 0.65}]},
				{"name": "第3波：遮天蝠群", "groups": [{"enemy_id": "bat", "lane_id": "north", "count": 7, "interval": 0.6}, {"enemy_id": "bat", "lane_id": "mid", "count": 7, "interval": 0.6}, {"enemy_id": "bat", "lane_id": "south", "count": 7, "interval": 0.6}]},
				{"name": "第4波：督军亲卫", "groups": [{"enemy_id": "boss_warlord", "lane_id": "north", "count": 1, "interval": 1.0}, {"enemy_id": "goblin", "lane_id": "mid", "count": 8, "interval": 0.6}, {"enemy_id": "boss_warlord", "lane_id": "south", "count": 1, "interval": 1.0}]},
				{"name": "最终波：黑曜大魔王", "groups": [{"enemy_id": "boss_obsidian", "lane_id": "mid", "count": 1, "interval": 1.0}, {"enemy_id": "bat", "lane_id": "north", "count": 6, "interval": 0.7}, {"enemy_id": "wolf", "lane_id": "south", "count": 6, "interval": 0.7}]},
			],
		},
	]


static func get_stage_by_id(stage_id: String) -> Dictionary:
	for s in get_stages():
		if str(s["id"]) == stage_id:
			return s.duplicate(true)
	return get_stages()[0].duplicate(true)
