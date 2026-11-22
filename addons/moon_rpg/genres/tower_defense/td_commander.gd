class_name TDCommander
extends RefCounted
## Playable Rallyable TD Hero + Global Commander Active Skills (Kingdom Rush style).
## - Hero walks to any rallied point on the map, blocks up to 2 ground creeps,
##   fights in melee, regenerates out of combat, and auto-respawns if defeated.
## - Global Commander Skills with independent cooldowns:
##   1. `meteor_rain`: Targeted large AoE magic burst + 3s burn DoT
##   2. `reinforcements`: Drops 2 temporary blocker soldiers anywhere on the lane
##   3. `frost_freeze`: Stuns/freezes ALL enemies on the map for 2.8s

signal skill_cast(skill_id: String, pos: Vector2)

var hero: Dictionary = {}
var skill_cooldowns: Dictionary = {
	"meteor_rain": 0.0,
	"reinforcements": 0.0,
	"frost_freeze": 0.0,
}
var skill_max_cds: Dictionary = {
	"meteor_rain": 16.0,
	"reinforcements": 12.0,
	"frost_freeze": 20.0,
}


func setup_hero(engine: TDTowerEngine, start_pos: Vector2, hero_name: String = "勇者·沈照") -> Dictionary:
	hero = {
		"uid": "td_hero",
		"owner_tower": "__hero__",
		"name": hero_name,
		"pos": start_pos,
		"rally_pos": start_pos,
		"move_speed": 95.0,
		"hp": 160.0,
		"max_hp": 160.0,
		"atk": 24.0,
		"block_count": 2,
		"attack_cd": 0.0,
		"respawn_timer": 0.0,
		"lifetime": -1.0,
		"is_hero": true,
	}
	engine.soldiers.append(hero)
	return hero


func rally_hero(target_pos: Vector2) -> void:
	if not hero.is_empty():
		hero["rally_pos"] = target_pos


func tick(delta: float) -> void:
	for k in skill_cooldowns.keys():
		skill_cooldowns[k] = maxf(0.0, float(skill_cooldowns[k]) - delta)

	if not hero.is_empty() and float(hero["hp"]) > 0.0:
		var cur: Vector2 = hero["pos"]
		var dst: Vector2 = hero["rally_pos"]
		var diff := dst - cur
		if diff.length() > 2.0:
			var step := minf(diff.length(), float(hero["move_speed"]) * delta)
			hero["pos"] = cur + diff.normalized() * step
		else:
			# Passive out-of-combat regen
			hero["hp"] = minf(float(hero["max_hp"]), float(hero["hp"]) + 6.0 * delta)


func is_skill_ready(skill_id: String) -> bool:
	return float(skill_cooldowns.get(skill_id, 99.0)) <= 0.0


func cast_meteor_rain(pos: Vector2, engine: TDTowerEngine, radius: float = 68.0, damage: float = 65.0) -> int:
	if not is_skill_ready("meteor_rain"):
		return 0
	skill_cooldowns["meteor_rain"] = float(skill_max_cds["meteor_rain"])
	var hits := 0
	for c in engine.creeps:
		if float(c["hp"]) > 0.0 and pos.distance_to(c["pos"]) <= radius:
			engine.apply_damage_to_creep(c, damage, "magic")
			engine.apply_status_to_creep(c, "burn", 12.0, 3.0)
			hits += 1
	engine._cleanup_dead_creeps()
	skill_cast.emit("meteor_rain", pos)
	return hits


func cast_reinforcements(pos: Vector2, engine: TDTowerEngine) -> bool:
	if not is_skill_ready("reinforcements"):
		return false
	skill_cooldowns["reinforcements"] = float(skill_max_cds["reinforcements"])
	engine.spawn_temporary_blocker(pos + Vector2(-8, 0), 70.0, 12.0, 12.0, 1)
	engine.spawn_temporary_blocker(pos + Vector2(8, 0), 70.0, 12.0, 12.0, 1)
	skill_cast.emit("reinforcements", pos)
	return true


func cast_frost_freeze(engine: TDTowerEngine, duration: float = 2.8) -> int:
	if not is_skill_ready("frost_freeze"):
		return 0
	skill_cooldowns["frost_freeze"] = float(skill_max_cds["frost_freeze"])
	var frozen := 0
	for c in engine.creeps:
		if float(c["hp"]) > 0.0:
			engine.apply_status_to_creep(c, "stun", 1.0, duration)
			frozen += 1
	skill_cast.emit("frost_freeze", Vector2(240, 135))
	return frozen
