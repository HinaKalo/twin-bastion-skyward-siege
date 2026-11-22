class_name StatBlock
extends RefCounted
## RPG Stat & Modifier Container.
## Tracks base stats, equipment/buff/mastery modifiers (ADD -> MUL -> OVERRIDE),
## dirty-flagged recalculation, resource pools (HP/MP/ST), and character level/XP.

enum ModOp { ADD, MUL, OVERRIDE }

const DEFAULT_BASE_STATS := {
	"max_hp": 120.0,
	"max_mp": 60.0,
	"max_st": 100.0,
	"atk": 18.0,
	"def": 6.0,
	"matk": 14.0,
	"mdef": 5.0,
	"crit_rate": 0.10,
	"crit_dmg": 1.50,
	"move_spd": 135.0,
	"luck": 5.0,
}

var level: int = 1
var xp: int = 0
var xp_to_next: int = 100

var hp: float = 120.0
var mp: float = 60.0
var st: float = 40.0

var _base: Dictionary = DEFAULT_BASE_STATS.duplicate(true)
var _modifiers: Array[Dictionary] = []
var _computed: Dictionary = {}
var _dirty: bool = true


func _init(initial_base: Dictionary = {}) -> void:
	for k in initial_base.keys():
		_base[str(k)] = float(initial_base[k])
	recalculate()
	hp = get_stat("max_hp")
	mp = get_stat("max_mp")
	st = minf(st, get_stat("max_st"))


func set_base(stat_name: String, value: float) -> void:
	_base[stat_name] = value
	_dirty = true


func get_base(stat_name: String) -> float:
	return float(_base.get(stat_name, 0.0))


func add_modifier(source_id: String, stat_name: String, value: float, op: int = ModOp.ADD) -> void:
	_modifiers.append({
		"source": source_id,
		"stat": stat_name,
		"value": value,
		"op": op,
	})
	_dirty = true


func remove_modifiers_by_source(source_id: String) -> void:
	var kept: Array[Dictionary] = []
	for m in _modifiers:
		if str(m["source"]) != source_id:
			kept.append(m)
	if kept.size() != _modifiers.size():
		_modifiers = kept
		_dirty = true


func clear_modifiers() -> void:
	_modifiers.clear()
	_dirty = true


func recalculate() -> void:
	_computed.clear()
	var adds: Dictionary = {}
	var muls: Dictionary = {}
	var overrides: Dictionary = {}

	for k in _base.keys():
		_computed[k] = float(_base[k])

	for m in _modifiers:
		var s: String = str(m["stat"])
		var v: float = float(m["value"])
		match int(m["op"]):
			ModOp.ADD:
				adds[s] = float(adds.get(s, 0.0)) + v
			ModOp.MUL:
				muls[s] = float(muls.get(s, 1.0)) * (1.0 + v)
			ModOp.OVERRIDE:
				overrides[s] = v

	var all_keys: Dictionary = {}
	for k in _base.keys():
		all_keys[k] = true
	for k in adds.keys():
		all_keys[k] = true
	for k in muls.keys():
		all_keys[k] = true
	for k in overrides.keys():
		all_keys[k] = true

	for k in all_keys.keys():
		if overrides.has(k):
			_computed[k] = float(overrides[k])
		else:
			var base_v := float(_base.get(k, 0.0))
			var add_v := float(adds.get(k, 0.0))
			var mul_v := float(muls.get(k, 1.0))
			_computed[k] = maxf(0.0, (base_v + add_v) * mul_v)

	_dirty = false
	hp = clampf(hp, 0.0, maxf(1.0, float(_computed.get("max_hp", 1.0))))
	mp = clampf(mp, 0.0, maxf(0.0, float(_computed.get("max_mp", 0.0))))
	st = clampf(st, 0.0, maxf(0.0, float(_computed.get("max_st", 100.0))))


func get_stat(stat_name: String) -> float:
	if _dirty:
		recalculate()
	return float(_computed.get(stat_name, 0.0))


func get_all_stats() -> Dictionary:
	if _dirty:
		recalculate()
	return _computed.duplicate(true)


func modify_hp(delta: float) -> float:
	var prev := hp
	hp = clampf(hp + delta, 0.0, get_stat("max_hp"))
	return hp - prev


func modify_mp(delta: float) -> float:
	var prev := mp
	mp = clampf(mp + delta, 0.0, get_stat("max_mp"))
	return mp - prev


func modify_st(delta: float) -> float:
	var prev := st
	st = clampf(st + delta, 0.0, get_stat("max_st"))
	return st - prev


func take_damage(amount: float) -> float:
	return -modify_hp(-maxf(0.0, amount))


func heal(amount: float) -> float:
	return modify_hp(maxf(0.0, amount))


func spend_mp(amount: float) -> bool:
	var cost := maxf(0.0, amount)
	if mp < cost:
		return false
	modify_mp(-cost)
	return true


func full_restore() -> void:
	recalculate()
	hp = get_stat("max_hp")
	mp = get_stat("max_mp")
	st = maxf(st, get_stat("max_st") * 0.5)


func add_xp(amount: int) -> bool:
	if amount <= 0:
		return false
	xp += amount
	var leveled := false
	while xp >= xp_to_next:
		xp -= xp_to_next
		level += 1
		xp_to_next = int(round(xp_to_next * 1.35))
		_base["max_hp"] = float(_base["max_hp"]) + 15.0
		_base["max_mp"] = float(_base["max_mp"]) + 5.0
		_base["atk"] = float(_base["atk"]) + 3.0
		_base["def"] = float(_base["def"]) + 1.5
		_dirty = true
		recalculate()
		hp = get_stat("max_hp")
		mp = get_stat("max_mp")
		leveled = true
	return leveled


func serialize() -> Dictionary:
	return {
		"level": level,
		"xp": xp,
		"xp_to_next": xp_to_next,
		"hp": hp,
		"mp": mp,
		"st": st,
		"base": _base.duplicate(true),
	}


func deserialize(data: Dictionary) -> void:
	if data.is_empty():
		return
	level = int(data.get("level", 1))
	xp = int(data.get("xp", 0))
	xp_to_next = int(data.get("xp_to_next", 100))
	if data.has("base") and typeof(data["base"]) == TYPE_DICTIONARY:
		_base = data["base"].duplicate(true)
	_dirty = true
	recalculate()
	hp = clampf(float(data.get("hp", get_stat("max_hp"))), 1.0, get_stat("max_hp"))
	mp = clampf(float(data.get("mp", get_stat("max_mp"))), 0.0, get_stat("max_mp"))
	st = clampf(float(data.get("st", 0.0)), 0.0, get_stat("max_st"))
