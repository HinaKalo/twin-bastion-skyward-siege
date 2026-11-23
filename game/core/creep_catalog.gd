class_name CreepCatalog
extends RefCounted
## Enemy roster for Twin Bastion TD: base stats (TDTowerEngine creep_def format) plus codex text.
## Special mechanics are flagged with `"ability"` and executed by CoopTDDirector each tick:
## - shield      : `shield` HP absorbs magic/true damage first; physical damage is reduced 70% while it holds
## - heal_aura   : periodically heals nearby allies
## - split       : spawns `split_into` x `split_count` at the same lane position on death
## - war_cry     : boss periodically hastes nearby allies
## - summon_shield: boss summons minions and raises a shield at 50% HP
## - frost_roar  : boss periodically freezes nearby towers (adds cooldown)

const ROSTER: Dictionary = {
	"slime": {"name": "翠绿史莱姆", "hp": 52.0, "speed": 30.0, "armor": 0.0, "magic_resist": 0.0, "bounty": 16, "atk": 8.0,
		"desc": "最基础的软泥怪，数量众多。"},
	"slimelet": {"name": "小史莱姆", "hp": 34.0, "speed": 38.0, "armor": 0.0, "magic_resist": 0.0, "bounty": 5, "atk": 5.0,
		"desc": "裂变史莱姆分裂出的碎块。"},
	"goblin": {"name": "哥布林重步兵", "hp": 88.0, "speed": 26.0, "armor": 10.0, "magic_resist": 0.0, "bounty": 22, "atk": 12.0,
		"desc": "披甲步兵，物理伤害被大幅削减——用法师塔对付。"},
	"wolf": {"name": "疾风狼", "hp": 68.0, "speed": 46.0, "armor": 2.0, "magic_resist": 0.0, "bounty": 20, "atk": 10.0,
		"desc": "速度很快，容易漏过防线，寒冰塔能拖住它们。"},
	"bat": {"name": "夜翼蝠", "hp": 58.0, "speed": 42.0, "armor": 0.0, "magic_resist": 0.15, "bounty": 20, "atk": 0.0, "is_flying": true,
		"desc": "飞行单位，兵营无法拦截。"},
	"shield_bearer": {"name": "铁壁盾卫", "hp": 120.0, "speed": 22.0, "armor": 6.0, "magic_resist": 0.0, "bounty": 30, "atk": 14.0,
		"shield": 90.0, "ability": "shield",
		"desc": "举盾时物理伤害 -70%，魔法可以先击碎护盾。"},
	"shaman": {"name": "哥布林萨满", "hp": 90.0, "speed": 26.0, "armor": 0.0, "magic_resist": 0.30, "bounty": 28, "atk": 8.0,
		"ability": "heal_aura", "heal_amount": 16.0, "heal_radius": 50.0, "heal_interval": 2.6,
		"desc": "每隔几秒治疗附近的敌人，优先击杀！"},
	"splitter": {"name": "裂变史莱姆", "hp": 116.0, "speed": 24.0, "armor": 0.0, "magic_resist": 0.0, "bounty": 16, "atk": 10.0,
		"ability": "split", "split_into": "slimelet", "split_count": 2,
		"desc": "死亡时分裂成两只小史莱姆。"},
	"assassin": {"name": "迅影刺客", "hp": 50.0, "speed": 72.0, "armor": 0.0, "magic_resist": 0.0, "bounty": 18, "atk": 14.0,
		"desc": "极速突进，生命很低。"},
	"gargoyle": {"name": "石像鬼", "hp": 132.0, "speed": 30.0, "armor": 14.0, "magic_resist": 0.10, "bounty": 30, "atk": 0.0, "is_flying": true,
		"desc": "重甲飞行单位，需要魔法塔或狙击箭塔。"},
	"boss_warlord": {"name": "哥布林督军·格罗什", "hp": 520.0, "speed": 20.0, "armor": 12.0, "magic_resist": 0.15, "bounty": 90, "atk": 30.0, "life_cost": 4,
		"is_boss": true, "ability": "war_cry", "cry_interval": 6.5, "cry_radius": 64.0, "cry_haste": 1.4, "cry_duration": 3.0,
		"cutin_sub": "战吼令周围敌人加速 · 用冰火超载击破！",
		"desc": "周期性战吼，让附近敌人加速。"},
	"boss_frost_colossus": {"name": "冰霜巨像", "hp": 1150.0, "speed": 15.0, "armor": 20.0, "magic_resist": 0.40, "bounty": 160, "atk": 42.0, "life_cost": 6,
		"is_boss": true, "ability": "frost_roar", "roar_interval": 8.0, "roar_radius": 96.0, "roar_freeze": 2.2,
		"cutin_sub": "寒霜咆哮会冻结附近防御塔 · 分散布防！",
		"desc": "咆哮冻结范围内的防御塔，物理与魔法抗性都很高。"},
	"boss_obsidian": {"name": "黑曜深渊大魔王", "hp": 960.0, "speed": 18.0, "armor": 16.0, "magic_resist": 0.25, "bounty": 160, "atk": 45.0, "life_cost": 6,
		"is_boss": true, "ability": "summon_shield", "summon_id": "slime", "summon_count": 4, "summon_shield": 240.0,
		"cutin_sub": "半血召唤护盾与仆从 · 双人合体大招决胜负！",
		"desc": "生命降到一半时召唤仆从并展开黑曜护盾。"},
	"boss_obsidian_awakened": {"name": "觉醒·黑曜魔王", "hp": 1700.0, "speed": 19.0, "armor": 20.0, "magic_resist": 0.30, "bounty": 260, "atk": 55.0, "life_cost": 10,
		"is_boss": true, "ability": "summon_shield", "summon_id": "assassin", "summon_count": 5, "summon_shield": 420.0,
		"cutin_sub": "深渊最终形态 · 召唤刺客与巨型护盾！",
		"desc": "深渊回廊的最终形态，召唤迅影刺客。"},
}


static func get_def(enemy_id: String) -> Dictionary:
	return (ROSTER.get(enemy_id, ROSTER["slime"]) as Dictionary)


static func get_display_name(enemy_id: String) -> String:
	return str(get_def(enemy_id).get("name", enemy_id))


static func is_boss(enemy_id: String) -> bool:
	return bool(get_def(enemy_id).get("is_boss", false))
