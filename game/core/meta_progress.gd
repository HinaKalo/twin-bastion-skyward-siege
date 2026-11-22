class_name MetaProgress
extends RefCounted
## Persistent Campaign Star Ratings (1..3★ per Stage) & 6-Node Co-op Talent Tree.
## Saved atomically to `user://twin_bastion_meta.json`.

const META_PATH := "user://twin_bastion_meta.json"

const TALENT_DEFS: Array[Dictionary] = [
	{"id": "start_gold",  "name": "双子军饷", "cost": 1, "desc": "P1与P2开局各额外获得 +40G"},
	{"id": "combo_power", "name": "连携增幅", "cost": 1, "desc": "跨玩家塔防连携伤害额外 +25%"},
	{"id": "gold_gift",   "name": "同舟共济", "cost": 1, "desc": "给搭档转账50G时系统额外赠 +15G"},
	{"id": "ult_charge",  "name": "双星聚能", "cost": 2, "desc": "双星合体超必杀充能速度 +40%"},
	{"id": "guard_hp",    "name": "铁壁卫队", "cost": 2, "desc": "双方兵营卫兵与英雄生命 +30%"},
	{"id": "discount",    "name": "联合作坊", "cost": 2, "desc": "全防御塔建造费用 -10%"},
]

var stage_stars: Dictionary = {} # stage_id -> int (0..3)
var unlocked_talents: Dictionary = {} # talent_id -> bool


func get_total_stars() -> int:
	var s := 0
	for v in stage_stars.values():
		s += int(v)
	return s


func get_spent_stars() -> int:
	var s := 0
	for t in TALENT_DEFS:
		if has_talent(str(t["id"])):
			s += int(t["cost"])
	return s


func get_available_stars() -> int:
	return maxi(0, get_total_stars() - get_spent_stars())


func has_talent(talent_id: String) -> bool:
	return bool(unlocked_talents.get(talent_id, false))


func record_stage_clear(stage_id: String, lives_left: int, max_lives: int = 20) -> int:
	var ratio := float(lives_left) / maxf(1.0, float(max_lives))
	var stars := 3 if ratio >= 0.90 else (2 if ratio >= 0.55 else 1)
	var prev := int(stage_stars.get(stage_id, 0))
	if stars > prev:
		stage_stars[stage_id] = stars
	save_to_disk()
	return stars


func unlock_talent(talent_id: String) -> bool:
	if has_talent(talent_id):
		return false
	for t in TALENT_DEFS:
		if str(t["id"]) == talent_id:
			var cost := int(t["cost"])
			if get_available_stars() < cost:
				return false
			unlocked_talents[talent_id] = true
			save_to_disk()
			return true
	return false


func reset_talents() -> void:
	unlocked_talents.clear()
	save_to_disk()


func save_to_disk(path: String = META_PATH) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify({
		"stage_stars": stage_stars,
		"unlocked_talents": unlocked_talents,
	}, "\t"))
	f.close()
	return true


func load_from_disk(path: String = META_PATH) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var d: Dictionary = parsed
	stage_stars = (d.get("stage_stars", {}) as Dictionary).duplicate(true)
	unlocked_talents = (d.get("unlocked_talents", {}) as Dictionary).duplicate(true)
	return true
