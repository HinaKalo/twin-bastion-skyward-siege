class_name CheckpointService
extends RefCounted
## Silent background checkpoints + per-checkpoint failure assist.
##
## - Authors place commit points (safe zone, door, combat_clear, valve, boss_phase, page_hide,
##   disconnect, custom). Committing never emits UI / toast / rumble — it is fully silent.
## - Respawn position prefers a standable, operable spot that is not inside an active threat;
##   the game supplies `is_safe_cb(pos) -> bool` (e.g. floor probe + threat radius check).
## - World state is classified into persistent / resettable / transient / pending sections;
##   `restore_after_wipe()` keeps persistent + confirmed pending, resets resettable encounters.
## - Failure counting per checkpoint feeds `assist_damage_scale()` (default 5 → 92%, 10 → 85%),
##   cleared when the segment is passed. Assist never touches boss HP / moves / phase rules.

signal committed(checkpoint_id: String, kind: String)

const KINDS := ["safe_zone", "door", "combat_clear", "valve", "boss_phase", "page_hide", "disconnect", "custom"]

var points: Dictionary = {}   # id -> { id, kind, room_id, candidates: Array[Vector2], segment }
var active_id: String = ""
var active_snapshot: Dictionary = {}
var commit_count: int = 0
var last_commit_unix: int = 0

var assist_enabled: bool = true
var assist_curve: Array = [{"failures": 5, "damage_scale": 0.92}, {"failures": 10, "damage_scale": 0.85}]
var failures: Dictionary = {} # segment_id -> int

var is_safe_cb: Callable = Callable()


func register_point(id: String, kind: String, room_id: String, candidates: Array, segment: String = "") -> void:
	var cands: Array = []
	for c in candidates:
		cands.append(c if c is Vector2 else Vector2(float(c[0]), float(c[1])))
	points[id] = {
		"id": id,
		"kind": kind if KINDS.has(kind) else "custom",
		"room_id": room_id,
		"candidates": cands,
		"segment": segment if not segment.is_empty() else id,
	}


func point_count() -> int:
	return points.size()


## Chooses the first candidate the game reports as safe; falls back to the first candidate.
func choose_respawn(id: String) -> Vector2:
	var p: Dictionary = points.get(id, {})
	var cands: Array = p.get("candidates", [])
	if cands.is_empty():
		return Vector2.ZERO
	if is_safe_cb.is_valid():
		for c in cands:
			if bool(is_safe_cb.call(c)):
				return c
	return cands[0]


## Silent commit. `state` holds sections { persistent, resettable, transient, pending }.
## Returns { id, segment_changed, respawn }.
func commit(id: String, state: Dictionary = {}, now_unix: int = 0) -> Dictionary:
	if not points.has(id):
		return {}
	var prev_segment := segment_of(active_id)
	active_id = id
	var new_segment := segment_of(id)
	var segment_changed := prev_segment != new_segment
	if segment_changed and not prev_segment.is_empty():
		failures.erase(prev_segment) # passing a segment restores baseline difficulty
	active_snapshot = {
		"id": id,
		"respawn": choose_respawn(id),
		"persistent": (state.get("persistent", {}) as Dictionary).duplicate(true),
		"resettable": (state.get("resettable", {}) as Dictionary).duplicate(true),
		"pending": (state.get("pending", {}) as Dictionary).duplicate(true),
	}
	commit_count += 1
	last_commit_unix = now_unix if now_unix > 0 else int(Time.get_unix_time_from_system())
	committed.emit(id, str(points[id]["kind"]))
	return {"id": id, "segment_changed": segment_changed, "respawn": active_snapshot["respawn"]}


func segment_of(id: String) -> String:
	if id.is_empty() or not points.has(id):
		return ""
	return str(points[id]["segment"])


## Team wipe: count a failure on the active segment and produce the state to restore.
## `current_persistent` is the live persistent section (confirmed mechanisms / story / build
## that changed since commit are kept); resettable encounters revert to the commit snapshot.
func restore_after_wipe(current_persistent: Dictionary = {}) -> Dictionary:
	var seg := segment_of(active_id)
	if not seg.is_empty():
		failures[seg] = int(failures.get(seg, 0)) + 1
	var persistent: Dictionary = (active_snapshot.get("persistent", {}) as Dictionary).duplicate(true)
	persistent.merge(current_persistent, true)
	return {
		"checkpoint_id": active_id,
		"respawn": active_snapshot.get("respawn", Vector2.ZERO),
		"persistent": persistent,
		"resettable": (active_snapshot.get("resettable", {}) as Dictionary).duplicate(true),
		"pending": (active_snapshot.get("pending", {}) as Dictionary).duplicate(true),
		"failures": int(failures.get(seg, 0)),
		"damage_scale": assist_damage_scale(),
	}


func failure_count(segment: String = "") -> int:
	var seg := segment if not segment.is_empty() else segment_of(active_id)
	return int(failures.get(seg, 0))


## Incoming-damage multiplier for the active segment. 1.0 when disabled or below threshold.
func assist_damage_scale(segment: String = "") -> float:
	if not assist_enabled:
		return 1.0
	var n := failure_count(segment)
	var scale := 1.0
	for step in assist_curve:
		if n >= int((step as Dictionary).get("failures", 999999)):
			scale = minf(scale, float(step.get("damage_scale", 1.0)))
	return scale


## Loads `{ "curve": [ {failures, damage_scale} ... ] }` (e.g. content/data/assist_curves.json).
func load_assist_curve(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY or not (parsed as Dictionary).has("curve"):
		return false
	assist_curve = (parsed["curve"] as Array).duplicate(true)
	assist_curve.sort_custom(func(a, b): return int(a.get("failures", 0)) < int(b.get("failures", 0)))
	return true


func serialize() -> Dictionary:
	var snap := active_snapshot.duplicate(true)
	if snap.has("respawn"):
		var r: Vector2 = snap["respawn"]
		snap["respawn"] = [r.x, r.y]
	return {
		"active_id": active_id,
		"snapshot": snap,
		"failures": failures.duplicate(),
		"assist_enabled": assist_enabled,
		"commit_count": commit_count,
		"last_commit_unix": last_commit_unix,
	}


func deserialize(data: Dictionary) -> void:
	active_id = str(data.get("active_id", ""))
	active_snapshot = (data.get("snapshot", {}) as Dictionary).duplicate(true)
	if active_snapshot.get("respawn", null) is Array:
		var a: Array = active_snapshot["respawn"]
		active_snapshot["respawn"] = Vector2(float(a[0]), float(a[1]))
	failures = (data.get("failures", {}) as Dictionary).duplicate()
	assist_enabled = bool(data.get("assist_enabled", true))
	commit_count = int(data.get("commit_count", 0))
	last_commit_unix = int(data.get("last_commit_unix", 0))
