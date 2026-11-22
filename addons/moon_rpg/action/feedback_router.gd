class_name FeedbackRouter
extends RefCounted
## Routes structured combat events to per-viewer feedback recipes.
##
## Event: { event_id, phase (startup|contact|telegraph), result (hit|blocked|deflect|parry|
##   perfect_guard|perfect_evade|pogo|hurt|break|...), material (flesh|metal|stone|thorns|water...),
##   attacker_seat, target_seat (0 = not a player), seat (who caused it), predicted: bool }
## For each local viewer seat the router decides the *role* — attacker, victim, ally (another
## local/remote player watching), or remote — and looks up the recipe by
## (phase, result, material, role) with wildcard fallback. Intensities are scaled by role and by
## AccessibilitySettings. A predicted event and its later confirmation share an event_id, so the
## confirmation never re-plays sound / flash / rumble.
##
## Recipe: { sfx, vfx, shake, flash, rumble: [weak, strong, dur], hitstop, text }.

const ROLE_SCALE := {"attacker": 1.0, "victim": 1.0, "ally": 0.35, "remote": 0.0}

var recipes: Array[Dictionary] = []
var accessibility: AccessibilitySettings = null
var _played: Dictionary = {} # event_id -> true
var _played_order: Array[String] = []
var dedupe_capacity: int = 1024


func _init() -> void:
	load_defaults()


func load_defaults() -> void:
	recipes.clear()
	for r in [
		{"phase": "contact", "result": "hit", "material": "flesh", "role": "attacker", "sfx": "sfx.hit_flesh", "vfx": "hit_spark", "shake": 2.2, "flash": 0.0, "rumble": [0.22, 0.08, 0.07]},
		{"phase": "contact", "result": "hit", "material": "*", "role": "victim", "sfx": "sfx.hurt", "vfx": "hit_spark", "shake": 3.0, "flash": 0.4, "rumble": [0.30, 0.65, 0.18]},
		{"phase": "contact", "result": "hit", "material": "*", "role": "attacker", "sfx": "sfx.hit", "vfx": "hit_spark", "shake": 2.0, "flash": 0.0, "rumble": [0.2, 0.1, 0.07]},
		{"phase": "contact", "result": "deflect", "material": "*", "role": "attacker", "sfx": "sfx.block", "vfx": "metal_spark", "shake": 1.2, "flash": 0.0, "rumble": [0.15, 0.25, 0.06]},
		{"phase": "contact", "result": "perfect_guard", "material": "*", "role": "victim", "sfx": "sfx.parry", "vfx": "parry_ring", "shake": 4.0, "flash": 0.6, "rumble": [0.35, 0.75, 0.16], "text": "PARRY!"},
		{"phase": "contact", "result": "perfect_evade", "material": "*", "role": "victim", "sfx": "sfx.evade", "vfx": "afterimage", "shake": 0.0, "flash": 0.2, "rumble": [0.1, 0.2, 0.06]},
		{"phase": "contact", "result": "pogo", "material": "*", "role": "attacker", "sfx": "sfx.pogo", "vfx": "hit_spark", "shake": 1.0, "flash": 0.0, "rumble": [0.12, 0.18, 0.05]},
		{"phase": "contact", "result": "hurt", "material": "thorns", "role": "victim", "sfx": "sfx.hurt", "vfx": "blood", "shake": 3.0, "flash": 0.4, "rumble": [0.3, 0.6, 0.16]},
		{"phase": "telegraph", "result": "*", "material": "*", "role": "*", "sfx": "sfx.danger", "vfx": "telegraph", "shake": 0.0, "flash": 0.0, "rumble": [0.0, 0.0, 0.0], "readable": true},
		{"phase": "*", "result": "*", "material": "*", "role": "ally", "sfx": "", "vfx": "", "shake": 0.0, "flash": 0.0, "rumble": [0.0, 0.0, 0.0]},
	]:
		recipes.append(r)


func load_json(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY or not (parsed as Dictionary).has("recipes"):
		return false
	recipes.clear()
	for r in parsed["recipes"]:
		recipes.append(r)
	return true


static func role_for(event: Dictionary, viewer_seat: int, viewer_is_local: bool = true) -> String:
	if not viewer_is_local:
		return "remote"
	if int(event.get("target_seat", 0)) == viewer_seat:
		return "victim"
	if int(event.get("attacker_seat", event.get("seat", 0))) == viewer_seat:
		return "attacker"
	return "ally"


func find_recipe(phase: String, result: String, material: String, role: String) -> Dictionary:
	for r in recipes:
		if _m(r, "phase", phase) and _m(r, "result", result) and _m(r, "material", material) and _m(r, "role", role):
			return r
	return {}


static func _m(r: Dictionary, key: String, v: String) -> bool:
	var want := str(r.get(key, "*"))
	return want == "*" or want == v


## Returns the per-viewer feedback plan, or {} if this event_id was already played
## (prediction → confirmation dedupe) or nothing applies.
func route(event: Dictionary, viewer_seat: int, viewer_is_local: bool = true) -> Dictionary:
	var eid := str(event.get("event_id", ""))
	var dedupe_key := "%s@%d" % [eid, viewer_seat]
	if not eid.is_empty() and _played.has(dedupe_key):
		return {}
	var role := role_for(event, viewer_seat, viewer_is_local)
	var r := find_recipe(str(event.get("phase", "contact")), str(event.get("result", "hit")), str(event.get("material", "*")), role)
	if r.is_empty():
		return {}
	if not eid.is_empty():
		_played[dedupe_key] = true
		_played_order.append(dedupe_key)
		if _played_order.size() > dedupe_capacity:
			_played.erase(_played_order.pop_front())
	var scale := float(ROLE_SCALE.get(role, 1.0))
	var readable := bool(r.get("readable", false))
	var rum: Array = r.get("rumble", [0.0, 0.0, 0.0])
	var plan := {
		"role": role, "sfx": str(r.get("sfx", "")), "vfx": str(r.get("vfx", "")), "text": str(r.get("text", "")),
		"shake": _acc("shake", float(r.get("shake", 0.0)) * scale, readable),
		"flash": _acc("flash", float(r.get("flash", 0.0)) * scale, readable),
		"rumble": [_acc("rumble", float(rum[0]) * scale, false), _acc("rumble", float(rum[1]) * scale, false), float(rum[2])],
		"event_id": eid,
	}
	return plan


func _acc(channel: String, v: float, readable: bool) -> float:
	if accessibility == null:
		return v
	return accessibility.apply_readable(channel, v) if readable else accessibility.apply(channel, v)


func was_played(event_id: String, viewer_seat: int) -> bool:
	return _played.has("%s@%d" % [event_id, viewer_seat])
