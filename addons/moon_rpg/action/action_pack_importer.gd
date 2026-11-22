class_name ActionPackImporter
extends RefCounted
## Import contract validator for action resources (frame tables + per-frame attachment points).
##
## An action pack entry (e.g. inside pack.json "actions" or a standalone *.action.json):
## {
##   "actor": "player.hook_blade", "anim": "light_1", "frames": 12, "fps": 60,
##   "frame_table": { "move": "light_1" } | { "row": [10-field row] },
##   "attach": [ { "frame": 0, "foot_l": [x,y], "foot_r": [x,y], "weight_foot": "r",
##                 "main_hand": [x,y], "off_hand": [x,y], "grip": [x,y], "tip": [x,y],
##                 "muzzle": [x,y], "weapon_layer": "front"|"back" }, ... ],
##   "hitboxes": [ { "frame": 5, "rect": [x,y,w,h] } ],
##   "baseline_y": 0, "source": "art/hook_blade.aseprite", "license": "CC-BY-4.0", "variant": "default"
## }
## `validate()` reports schema errors and, for each missing key, which moves / weapons are affected.

const REQUIRED_ATTACH := ["foot_l", "foot_r", "main_hand", "grip", "tip"]
const OPTIONAL_ATTACH := ["off_hand", "muzzle", "weight_foot", "weapon_layer"]
const REQUIRED_META := ["actor", "anim", "frames", "source", "license"]


## Validates one entry. `graph` (optional) is used to map the anim to the moves that use it.
static func validate(entry: Dictionary, graph: ActionGraph = null) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	for k in REQUIRED_META:
		if not entry.has(k) or str(entry[k]).is_empty():
			errors.append("missing:%s" % k)
	var frames := int(entry.get("frames", 0))
	var attach: Array = entry.get("attach", [])
	if attach.size() != frames:
		errors.append("attach_count:%d!=frames:%d" % [attach.size(), frames])
	var seen_frames := {}
	for a in attach:
		var d: Dictionary = a
		var f := int(d.get("frame", -1))
		if f < 0 or f >= frames:
			errors.append("attach_frame_out_of_range:%d" % f)
		seen_frames[f] = true
		for k in REQUIRED_ATTACH:
			if not d.has(k):
				errors.append("frame%d:missing_%s" % [f, k])
		var layer := str(d.get("weapon_layer", "front"))
		if layer != "front" and layer != "back":
			errors.append("frame%d:bad_weapon_layer:%s" % [f, layer])
		if d.has("muzzle") == false and str(entry.get("weapon_kind", "")) == "gun":
			warnings.append("frame%d:gun_without_muzzle" % f)
	for hb in entry.get("hitboxes", []):
		var hf := int((hb as Dictionary).get("frame", -1))
		if hf < 0 or hf >= frames:
			errors.append("hitbox_frame_out_of_range:%d" % hf)
	var ft: Dictionary = entry.get("frame_table", {})
	if ft.has("row") and (ft["row"] as Array).size() != 10:
		errors.append("frame_table_row_needs_10_fields")
	var affected: Array[String] = []
	if graph != null:
		var anim := str(entry.get("anim", ""))
		for mid in graph.moves.keys():
			var m: MoveDef = graph.moves[mid]
			if m.anim == anim or mid == anim or str(ft.get("move", "")) == mid:
				affected.append(mid)
		if ft.has("move") and not graph.moves.has(str(ft["move"])):
			errors.append("frame_table_unknown_move:%s" % ft["move"])
		if ft.has("move") and graph.moves.has(str(ft["move"])):
			var mv: MoveDef = graph.moves[str(ft["move"])]
			var need := mv.total_frames() * int(entry.get("fps", 60)) / 60
			if frames > 0 and absi(frames - need) > maxi(2, need / 4):
				warnings.append("frames_vs_timeline:%d_vs_%d" % [frames, need])
	return {"ok": errors.is_empty(), "errors": errors, "warnings": warnings, "affected_moves": affected}


## Validates a list of entries; aggregates which moves are affected by any error.
static func validate_all(entries: Array, graph: ActionGraph = null) -> Dictionary:
	var reports: Array[Dictionary] = []
	var broken_moves: Dictionary = {}
	for e in entries:
		var r := validate(e, graph)
		r["anim"] = (e as Dictionary).get("anim", "")
		reports.append(r)
		if not bool(r["ok"]):
			for m in r["affected_moves"]:
				broken_moves[m] = true
	return {"reports": reports, "broken_moves": broken_moves.keys()}


## Attachment point for `frame`, mirrored for facing (-1 flips x).
static func attach_point(entry: Dictionary, frame: int, key: String, facing: int = 1) -> Variant:
	for a in entry.get("attach", []):
		if int((a as Dictionary).get("frame", -1)) == frame and (a as Dictionary).has(key):
			var p: Array = a[key]
			return Vector2(float(p[0]) * float(facing), float(p[1]))
	return null
