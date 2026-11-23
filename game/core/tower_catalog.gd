class_name TowerCatalog
extends RefCounted
## Single source of truth for Twin Bastion tower stats.
## Every tower has 3 tiers: Lv1 (build) -> Lv2 (straight upgrade) -> Lv3 (choose 1 of 2 branches).
## Upgrade entries use the TDTowerEngine `upgrades` format (`from_level`, `cost`, `*_add`, override keys).
## Keys the engine does not copy itself (soldier_count, respawn_time, block_count, priority, branch)
## are listed under `"set"` and applied by CoopTDDirector after the engine upgrade succeeds.

const TOWER_IDS: Array[String] = ["arrow", "mage", "frost", "barracks"]

const PRIORITY_LABELS: Array[String] = ["先锋", "末尾", "最强", "最近"]


static func build_defs(build_mult: float = 1.0, branch_mult: float = 1.0, guard_hp_mult: float = 1.0) -> Dictionary:
	var c := func(v: float) -> int: return int(round(v * build_mult))
	var b := func(v: float) -> int: return int(round(v * build_mult * branch_mult))
	return {
		"arrow": {
			"name": "箭塔", "role": "ranged", "cost": c.call(60), "max_hp": 180.0, "range": 115.0, "damage": 16.0,
			"damage_type": "physical", "fire_rate": 1.35, "can_hit_air": true,
			"desc": "物理单体 · 可打空中",
			"upgrades": [
				{"hp_add": 90.0, "from_level": 1, "cost": c.call(60), "name": "精锐箭塔", "damage_add": 8.0, "range_add": 10.0, "fire_rate_add": 0.20},
				{"hp_add": 130.0, "from_level": 2, "cost": b.call(110), "name": "鹰眼狙击塔", "branch": "sniper", "desc": "超远射程 · 25%暴击 · 破甲",
					"damage_add": 30.0, "range_add": 42.0, "fire_rate_add": -0.70,
					"crit_chance": 0.25, "shred_amount": 6.0, "shred_duration": 3.0,
					"set": {"branch": "sniper", "priority": 2}},
				{"hp_add": 130.0, "from_level": 2, "cost": b.call(105), "name": "连弩哨塔", "branch": "repeater", "desc": "极速连射 · 压制成群",
					"damage_add": 3.0, "range_add": 4.0, "fire_rate_add": 1.55,
					"set": {"branch": "repeater"}},
			],
		},
		"mage": {
			"name": "法师塔", "role": "ranged", "cost": c.call(80), "max_hp": 150.0, "range": 108.0, "damage": 24.0,
			"damage_type": "magic", "fire_rate": 0.90, "can_hit_air": true, "chain_count": 2,
			"desc": "魔法连锁 · 克制重甲",
			"upgrades": [
				{"hp_add": 90.0, "from_level": 1, "cost": c.call(75), "name": "高阶法师塔", "damage_add": 12.0, "range_add": 8.0, "fire_rate_add": 0.10},
				{"hp_add": 130.0, "from_level": 2, "cost": b.call(125), "name": "奥术尖塔", "branch": "arcane", "desc": "连锁弹射 4 次 · 高额魔伤",
					"damage_add": 24.0, "range_add": 10.0, "fire_rate_add": 0.10, "chain_count": 4,
					"set": {"branch": "arcane"}},
				{"hp_add": 130.0, "from_level": 2, "cost": b.call(120), "name": "烈焰法坛", "branch": "inferno", "desc": "范围爆炸 · 灼烧持续伤害",
					"damage_add": 10.0, "range_add": 6.0, "fire_rate_add": 0.15, "chain_count": 0,
					"splash_radius": 30.0, "dot_dps": 11.0, "dot_duration": 3.0,
					"set": {"branch": "inferno"}},
			],
		},
		"frost": {
			"name": "寒冰塔", "role": "ranged", "cost": c.call(75), "max_hp": 170.0, "range": 102.0, "damage": 12.0,
			"damage_type": "magic", "fire_rate": 0.85, "can_hit_air": true,
			"slow_factor": 0.55, "slow_duration": 2.4,
			"desc": "减速控场 · 连携核心",
			"upgrades": [
				{"hp_add": 90.0, "from_level": 1, "cost": c.call(70), "name": "凛冬寒冰塔", "damage_add": 6.0, "range_add": 8.0, "fire_rate_add": 0.10,
					"slow_factor": 0.50, "slow_duration": 2.8},
				{"hp_add": 130.0, "from_level": 2, "cost": b.call(115), "name": "冰川之心", "branch": "glacier", "desc": "18%几率冰冻 1.2 秒",
					"damage_add": 14.0, "range_add": 10.0, "fire_rate_add": 0.10,
					"slow_factor": 0.45, "stun_chance": 0.18, "stun_duration": 1.2,
					"set": {"branch": "glacier"}},
				{"hp_add": 130.0, "from_level": 2, "cost": b.call(115), "name": "霜暴图腾", "branch": "blizzard", "desc": "范围减速 · 群体控制",
					"damage_add": 8.0, "range_add": 14.0, "fire_rate_add": 0.25,
					"slow_factor": 0.45, "slow_duration": 3.0, "splash_radius": 34.0,
					"set": {"branch": "blizzard"}},
			],
		},
		"barracks": {
			"name": "兵营塔", "role": "barracks", "cost": c.call(70), "max_hp": 260.0, "range": 85.0, "damage": 0.0,
			"can_hit_air": false, "soldier_count": 2, "soldier_hp": 72.0 * guard_hp_mult, "soldier_atk": 9.0,
			"respawn_time": 6.5, "block_count": 1,
			"desc": "卫兵拦截地面敌人",
			"upgrades": [
				{"hp_add": 90.0, "from_level": 1, "cost": c.call(65), "name": "坚盾兵营", "damage_add": 0.0, "range_add": 0.0, "fire_rate_add": 0.0,
					"soldier_hp_add": 40.0 * guard_hp_mult, "soldier_atk_add": 6.0},
				{"hp_add": 130.0, "from_level": 2, "cost": b.call(120), "name": "圣骑兵营", "branch": "paladin", "desc": "3 名重甲圣骑 · 极高生命",
					"damage_add": 0.0, "range_add": 0.0, "fire_rate_add": 0.0,
					"soldier_hp_add": 95.0 * guard_hp_mult, "soldier_atk_add": 6.0,
					"set": {"branch": "paladin", "soldier_count": 3, "respawn_time": 7.0}},
				{"hp_add": 130.0, "from_level": 2, "cost": b.call(115), "name": "游骑兵营", "branch": "ranger", "desc": "高攻速复活 · 每人拦截 2 敌",
					"damage_add": 0.0, "range_add": 0.0, "fire_rate_add": 0.0,
					"soldier_hp_add": 30.0 * guard_hp_mult, "soldier_atk_add": 16.0,
					"set": {"branch": "ranger", "respawn_time": 3.5, "block_count": 2}},
			],
		},
	}


static func get_branch_label(branch: String) -> String:
	match branch:
		"sniper": return "鹰眼狙击"
		"repeater": return "连弩哨塔"
		"arcane": return "奥术尖塔"
		"inferno": return "烈焰法坛"
		"glacier": return "冰川之心"
		"blizzard": return "霜暴图腾"
		"paladin": return "圣骑兵营"
		"ranger": return "游骑兵营"
	return ""


static func get_short_label(tower_id: String) -> String:
	match tower_id:
		"arrow": return "箭"
		"mage": return "法"
		"frost": return "冰"
		"barracks": return "兵"
	return "?"
