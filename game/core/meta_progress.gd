class_name MetaProgress
extends RefCounted
## Persistent campaign progress: best stars per stage, hard-mode crowns, endless records and the co-op talent tree.
## Saved to `save_path` (defaults to `user://twin_bastion_meta.json`; tests point it at a scratch file).
##
## Star rules for a cleared stage:
##   1★ clear  ·  2★ at least half the lives left  ·  3★ zero leaks on Normal or Hard (Casual caps at 2★)
## Clearing on Hard additionally earns a crown worth +1 talent star.

const META_PATH := "user://twin_bastion_meta.json"

const TALENT_DEFS: Array[Dictionary] = [
	{"id": "start_gold",      "name": "双子军饷", "cost": 1, "desc": "P1与P2开局各额外获得 +40G"},
	{"id": "combo_power",     "name": "连携增幅", "cost": 1, "desc": "跨玩家连携效果额外 +25%"},
	{"id": "gold_gift",       "name": "同舟共济", "cost": 1, "desc": "给搭档转账50G时额外赠 +15G"},
	{"id": "ult_charge",      "name": "双星聚能", "cost": 2, "desc": "双星合体充能速度 +40%"},
	{"id": "guard_hp",        "name": "铁壁卫队", "cost": 2, "desc": "卫兵与英雄生命 +30%"},
	{"id": "discount",        "name": "联合作坊", "cost": 2, "desc": "建造与升级费用 -10%"},
	{"id": "hero_cd",         "name": "英雄觉醒", "cost": 2, "desc": "英雄技能冷却 -20%"},
	{"id": "branch_discount", "name": "精工改造", "cost": 2, "desc": "Lv3 分支升级额外 -10%"},
]

var save_path: String = META_PATH
var stage_stars: Dictionary = {} # stage_id -> int (0..3)
var hard_clears: Dictionary = {} # stage_id -> true
var endless_best: Dictionary = {} # stage_id -> best wave reached
var unlocked_talents: Dictionary = {} # talent_id -> bool
var tutorial_done: bool = false


func get_total_stars() -> int:
	var s := 0
	for v in stage_stars.values():
		s += int(v)
	return s + hard_clears.size()


func get_stage_stars(stage_id: String) -> int:
	return int(stage_stars.get(stage_id, 0))


func is_stage_cleared(stage_id: String) -> bool:
	return get_stage_stars(stage_id) > 0


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


static func compute_stars(lives_left: int, max_lives: int, difficulty: String = "normal", leaks: int = -1) -> int:
	var ratio := float(lives_left) / maxf(1.0, float(max_lives))
	var stars := 1
	if ratio >= 0.5:
		stars = 2
	var flawless := (leaks == 0) if leaks >= 0 else (ratio >= 0.9)
	if flawless and difficulty != "casual":
		stars = 3
	return stars


func record_stage_clear(stage_id: String, lives_left: int, max_lives: int = 20, difficulty: String = "normal", leaks: int = -1) -> int:
	var stars := compute_stars(lives_left, max_lives, difficulty, leaks)
	if stars > get_stage_stars(stage_id):
		stage_stars[stage_id] = stars
	if difficulty == "hard":
		hard_clears[stage_id] = true
	save_to_disk()
	return stars


func record_endless(stage_id: String, wave_reached: int) -> bool:
	if wave_reached > int(endless_best.get(stage_id, 0)):
		endless_best[stage_id] = wave_reached
		save_to_disk()
		return true
	return false


func unlock_talent(talent_id: String) -> bool:
	if has_talent(talent_id):
		return false
	for t in TALENT_DEFS:
		if str(t["id"]) == talent_id:
			if get_available_stars() < int(t["cost"]):
				return false
			unlocked_talents[talent_id] = true
			save_to_disk()
			return true
	return false


func reset_talents() -> void:
	unlocked_talents.clear()
	save_to_disk()


func mark_tutorial_done() -> void:
	if not tutorial_done:
		tutorial_done = true
		save_to_disk()


func save_to_disk(path: String = "") -> bool:
	var target := path if path != "" else save_path
	var f := FileAccess.open(target, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify({
		"version": 2,
		"stage_stars": stage_stars,
		"hard_clears": hard_clears,
		"endless_best": endless_best,
		"unlocked_talents": unlocked_talents,
		"tutorial_done": tutorial_done,
	}, "\t"))
	f.close()
	return true


func load_from_disk(path: String = "") -> bool:
	var target := path if path != "" else save_path
	if not FileAccess.file_exists(target):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(target))
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var d: Dictionary = parsed
	stage_stars.clear()
	for k in (d.get("stage_stars", {}) as Dictionary).keys():
		stage_stars[str(k)] = int(d["stage_stars"][k])
	hard_clears = (d.get("hard_clears", {}) as Dictionary).duplicate(true)
	endless_best.clear()
	for k in (d.get("endless_best", {}) as Dictionary).keys():
		endless_best[str(k)] = int(d["endless_best"][k])
	unlocked_talents = (d.get("unlocked_talents", {}) as Dictionary).duplicate(true)
	tutorial_done = bool(d.get("tutorial_done", false))
	return true
