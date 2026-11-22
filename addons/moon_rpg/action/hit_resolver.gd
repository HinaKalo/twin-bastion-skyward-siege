class_name HitResolver
extends RefCounted
## Deterministic contact resolution with an interaction matrix.
##
## All contacts found during one tick are collected first, then resolved in a fixed order:
## contact kind priority (pogo → parry → strike → projectile → hazard), then distance, then ids.
## The interaction matrix maps (attack tag × surface tag) → result:
##   hit | deflect | parry | clash | pogo | pass | ignore | hurt
## e.g. blade vs shield_front → deflect, dive vs thorns → pogo, body vs thorns → hurt,
## dash vs low_barrier → pass, projectile vs parry_surface → parry.
## A pogo for an actor supersedes that actor's hazard contacts in the same tick
## ("the blade touched the thorns first: bounce, then (no) damage").
## Every resolution is logged: who touched whom first, nth hit on that target, and why a hit
## was negated.

const KIND_PRIORITY := {"pogo": 0, "parry": 1, "strike": 2, "projectile": 3, "hazard": 4}

var rules: Array[Dictionary] = []
var history: Array[Dictionary] = []
var log_limit: int = 512
var _hit_counts: Dictionary = {} # "attacker|target" -> count since reset_counts


func _init() -> void:
	load_defaults()


func load_defaults() -> void:
	rules.clear()
	for r in [
		{"attack": "dive", "surface": "thorns", "result": "pogo"},
		{"attack": "dive", "surface": "head", "result": "pogo"},
		{"attack": "body", "surface": "thorns", "result": "hurt"},
		{"attack": "*", "surface": "thorns", "result": "ignore"},
		{"attack": "blade", "surface": "shield_front", "result": "deflect"},
		{"attack": "pierce", "surface": "shield_front", "result": "deflect"},
		{"attack": "blunt", "surface": "shield_front", "result": "clash"},
		{"attack": "projectile", "surface": "parry_surface", "result": "parry"},
		{"attack": "dash", "surface": "low_barrier", "result": "pass"},
		{"attack": "*", "surface": "low_barrier", "result": "ignore"},
		{"attack": "*", "surface": "body", "result": "hit"},
		{"attack": "*", "surface": "head", "result": "hit"},
	]:
		rules.append(r)


func load_json(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY or not (parsed as Dictionary).has("rules"):
		return false
	rules.clear()
	for r in parsed["rules"]:
		rules.append(r)
	return true


func interaction(attack_tag: String, surface_tag: String) -> String:
	for r in rules:
		var a := str(r.get("attack", "*"))
		var s := str(r.get("surface", "*"))
		if (a == "*" or a == attack_tag) and (s == "*" or s == surface_tag):
			return str(r.get("result", "hit"))
	return "hit"


func reset_counts() -> void:
	_hit_counts.clear()


func hit_count(attacker: String, target: String) -> int:
	return int(_hit_counts.get(attacker + "|" + target, 0))


## Resolves a tick's contacts. Each contact:
## { attacker, target, kind (strike/pogo/hazard/projectile/parry), attack_tag, surface_tag,
##   distance, tick }. Returns the ordered contacts with "result", "order", "nth", "reason".
func resolve(contacts: Array) -> Array[Dictionary]:
	var ordered: Array[Dictionary] = []
	for c in contacts:
		var cc: Dictionary = (c as Dictionary).duplicate()
		cc["result"] = interaction(str(cc.get("attack_tag", "blade")), str(cc.get("surface_tag", "body")))
		if cc["result"] == "pogo":
			cc["kind"] = "pogo"
		ordered.append(cc)
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var pa := int(KIND_PRIORITY.get(str(a.get("kind", "strike")), 9))
		var pb := int(KIND_PRIORITY.get(str(b.get("kind", "strike")), 9))
		if pa != pb:
			return pa < pb
		var da := float(a.get("distance", 0.0))
		var db := float(b.get("distance", 0.0))
		if not is_equal_approx(da, db):
			return da < db
		return str(a.get("attacker", "")) + str(a.get("target", "")) < str(b.get("attacker", "")) + str(b.get("target", "")))
	var pogo_actors: Dictionary = {}
	var order := 0
	for c in ordered:
		order += 1
		c["order"] = order
		c["reason"] = ""
		var attacker := str(c.get("attacker", ""))
		if str(c["result"]) == "pogo":
			pogo_actors[attacker] = true
		if str(c.get("kind", "")) == "hazard" and pogo_actors.has(str(c.get("target", attacker))):
			c["result"] = "ignore"
			c["reason"] = "superseded_by_pogo"
		var key := attacker + "|" + str(c.get("target", ""))
		if str(c["result"]) == "hit" or str(c["result"]) == "hurt":
			_hit_counts[key] = int(_hit_counts.get(key, 0)) + 1
		c["nth"] = int(_hit_counts.get(key, 0))
		if c["reason"] == "" and str(c["result"]) in ["deflect", "parry", "clash", "ignore", "pass"]:
			c["reason"] = "%s:%s->%s" % [c.get("attack_tag", ""), c.get("surface_tag", ""), c["result"]]
		history.append(c)
	if history.size() > log_limit:
		history = history.slice(history.size() - log_limit)
	return ordered


func recent_log(count: int = 16) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in range(maxi(0, history.size() - count), history.size()):
		out.append(history[i])
	return out
