class_name DiplomacyEngine
extends RefCounted
## Multi-Faction Diplomacy & Treaty Matrix (Civilization / Stellaris / Three Kingdoms style).
## Tracks bilateral opinion (-100..+100), treaty state (WAR / NEUTRAL / TRUCE / ALLIANCE),
## truce turn countdowns, and diplomatic event signals.

enum Treaty { NEUTRAL, WAR, TRUCE, ALLIANCE }

signal war_declared(attacker: String, defender: String)
signal peace_signed(faction_a: String, faction_b: String, truce_turns: int)
signal alliance_formed(faction_a: String, faction_b: String)
signal opinion_changed(faction_a: String, faction_b: String, new_opinion: int)

var _relations: Dictionary = {} # "a|b" (sorted) -> { treaty, opinion, truce_turns }


func _pair_key(a: String, b: String) -> String:
	return (a + "|" + b) if a < b else (b + "|" + a)


func _ensure(a: String, b: String) -> Dictionary:
	var k := _pair_key(a, b)
	if not _relations.has(k):
		_relations[k] = {"treaty": Treaty.NEUTRAL, "opinion": 0, "truce_turns": 0}
	return _relations[k]


func get_treaty(a: String, b: String) -> int:
	if a == b:
		return Treaty.ALLIANCE
	return int(_ensure(a, b)["treaty"])


func get_treaty_name(a: String, b: String) -> String:
	match get_treaty(a, b):
		Treaty.WAR: return "交战"
		Treaty.TRUCE: return "停战(%d回合)" % int(_ensure(a, b)["truce_turns"])
		Treaty.ALLIANCE: return "同盟"
	return "中立"


func are_at_war(a: String, b: String) -> bool:
	return a != b and get_treaty(a, b) == Treaty.WAR


func get_opinion(a: String, b: String) -> int:
	return int(_ensure(a, b)["opinion"])


func modify_opinion(a: String, b: String, delta: int) -> int:
	if a == b:
		return 100
	var rel := _ensure(a, b)
	rel["opinion"] = clampi(int(rel["opinion"]) + delta, -100, 100)
	opinion_changed.emit(a, b, int(rel["opinion"]))
	return int(rel["opinion"])


func declare_war(attacker: String, defender: String) -> bool:
	if attacker == defender:
		return false
	var rel := _ensure(attacker, defender)
	if int(rel["treaty"]) == Treaty.WAR:
		return false
	if int(rel["treaty"]) == Treaty.TRUCE and int(rel["truce_turns"]) > 0:
		return false
	rel["treaty"] = Treaty.WAR
	rel["truce_turns"] = 0
	modify_opinion(attacker, defender, -50)
	war_declared.emit(attacker, defender)
	return true


func make_peace(a: String, b: String, truce_turns: int = 5) -> bool:
	if a == b:
		return false
	var rel := _ensure(a, b)
	if int(rel["treaty"]) != Treaty.WAR:
		return false
	rel["treaty"] = Treaty.TRUCE
	rel["truce_turns"] = maxi(1, truce_turns)
	modify_opinion(a, b, 15)
	peace_signed.emit(a, b, int(rel["truce_turns"]))
	return true


func form_alliance(a: String, b: String) -> bool:
	if a == b:
		return false
	var rel := _ensure(a, b)
	if int(rel["treaty"]) == Treaty.WAR:
		return false
	rel["treaty"] = Treaty.ALLIANCE
	rel["truce_turns"] = 0
	modify_opinion(a, b, 30)
	alliance_formed.emit(a, b)
	return true


func tick_turn() -> void:
	for k in _relations.keys():
		var rel: Dictionary = _relations[k]
		if int(rel["treaty"]) == Treaty.TRUCE and int(rel["truce_turns"]) > 0:
			rel["truce_turns"] = int(rel["truce_turns"]) - 1
			if int(rel["truce_turns"]) <= 0:
				rel["treaty"] = Treaty.NEUTRAL


func serialize() -> Dictionary:
	return {"relations": _relations.duplicate(true)}


func deserialize(data: Dictionary) -> void:
	_relations = (data.get("relations", {}) as Dictionary).duplicate(true)
