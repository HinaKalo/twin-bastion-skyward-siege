class_name TacticsUnit
extends RefCounted
## Pure-Data Tactical SRPG Unit wrapping MoonRPG's shared `StatBlock`.
## Supports Fire Emblem / FFT / Triangle Strategy attributes:
## - Faction, Class, Weapon Type (for Weapon Triangle), Movement Type & Jump Height
## - Attack Min/Max Range (e.g. Bow 2..3, Magic 1..2, Melee 1..1)
## - Facing direction (for backstab / flank detection)
## - Active Skills (AoE Diamond/Cross/Line, Heal, Knockback/Shove)
## - AI Personality Profile & full `serialize()` / `deserialize()`.

var unit_id: String = ""
var display_name: String = ""
var faction: String = "player" # "player" | "enemy" | "ally"
var class_title: String = "剑士"
var is_boss: bool = false
var is_leader: bool = false

var stat_block: StatBlock
var move_range: int = 4
var jump_height: int = 1
var move_type: String = "infantry" # "infantry" | "cavalry" | "flying"
var weapon_type: String = "sword" # "sword" | "lance" | "axe" | "bow" | "magic" | "staff"
var attack_min_range: int = 1
var attack_max_range: int = 1
var facing: Vector2i = Vector2i(1, 0)
var ai_profile: String = "aggressive" # "aggressive" | "defensive" | "healer" | "boss_guard"
var sprite_path: String = ""
var accent_color: Color = Color(0.35, 0.85, 1.0)

## Skill spec dict:
## { "id", "name", "mp_cost", "power_mult", "min_range", "max_range", "aoe_shape", "aoe_radius",
##   "target_allies": bool, "heal_amount": float, "knockback": int, "weapon_type": String }
var skills: Array[Dictionary] = []


func _init(spec: Dictionary = {}) -> void:
	stat_block = StatBlock.new()
	if not spec.is_empty():
		setup(spec)


func setup(spec: Dictionary) -> void:
	unit_id = str(spec.get("id", unit_id))
	display_name = str(spec.get("name", unit_id))
	faction = str(spec.get("faction", "player"))
	class_title = str(spec.get("class_title", "战士"))
	is_boss = bool(spec.get("is_boss", false))
	is_leader = bool(spec.get("is_leader", false))
	move_range = int(spec.get("move_range", 4))
	jump_height = int(spec.get("jump_height", 1))
	move_type = str(spec.get("move_type", "infantry"))
	weapon_type = str(spec.get("weapon_type", "sword"))
	attack_min_range = int(spec.get("attack_min_range", 1))
	attack_max_range = int(spec.get("attack_max_range", 1))
	ai_profile = str(spec.get("ai_profile", "aggressive"))
	sprite_path = str(spec.get("sprite_path", ""))
	if spec.has("accent_color"):
		accent_color = spec["accent_color"]
	if spec.has("facing"):
		facing = spec["facing"]
	else:
		facing = Vector2i(1, 0) if faction == "player" else Vector2i(-1, 0)

	var st: Dictionary = spec.get("stats", {})
	stat_block = StatBlock.new({
		"max_hp": float(st.get("max_hp", 100.0)),
		"max_mp": float(st.get("max_mp", 30.0)),
		"atk": float(st.get("atk", 20.0)),
		"def": float(st.get("def", 8.0)),
		"move_spd": float(st.get("move_spd", 14.0)),
		"crit_rate": float(st.get("crit_rate", 0.10)),
		"crit_dmg": float(st.get("crit_dmg", st.get("crit_mult", 1.5))),
	})
	skills.clear()
	for sk in spec.get("skills", []):
		skills.append((sk as Dictionary).duplicate(true))


func is_alive() -> bool:
	return stat_block.hp > 0.0


func get_speed() -> float:
	return stat_block.get_stat("move_spd")


func can_afford_skill(skill: Dictionary) -> bool:
	return stat_block.mp >= float(skill.get("mp_cost", 0.0))


func face_toward(from_cell: Vector2i, to_cell: Vector2i) -> void:
	var d := to_cell - from_cell
	if d == Vector2i.ZERO:
		return
	if absi(d.x) >= absi(d.y):
		facing = Vector2i(signi(d.x), 0)
	else:
		facing = Vector2i(0, signi(d.y))


func serialize() -> Dictionary:
	return {
		"unit_id": unit_id,
		"display_name": display_name,
		"faction": faction,
		"class_title": class_title,
		"is_boss": is_boss,
		"is_leader": is_leader,
		"move_range": move_range,
		"jump_height": jump_height,
		"move_type": move_type,
		"weapon_type": weapon_type,
		"attack_min_range": attack_min_range,
		"attack_max_range": attack_max_range,
		"facing": [facing.x, facing.y],
		"ai_profile": ai_profile,
		"hp": stat_block.hp,
		"mp": stat_block.mp,
	}


func deserialize(data: Dictionary) -> void:
	stat_block.hp = float(data.get("hp", stat_block.hp))
	stat_block.mp = float(data.get("mp", stat_block.mp))
	var fa: Array = data.get("facing", [facing.x, facing.y])
	if fa.size() >= 2:
		facing = Vector2i(int(fa[0]), int(fa[1]))
