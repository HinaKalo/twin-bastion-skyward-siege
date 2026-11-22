class_name MoveDef
extends RefCounted
## Frame-based move timeline (all timings in fixed ticks, 60 Hz by default).
##
## age 0 is the first frame of the move. Fields:
## - `windup`, `active` ([[start, end_exclusive], ...] multi-hit segments), `recovery`
## - `cancel`: { hit_delay, hit_window, whiff, blocked, startup } — when the move may be
##   left, split by contact outcome (hit-confirm vs whiff vs blocked)
## - `buffer_open`: first age at which inputs for the next move are kept in the buffer
## - `facing_lock`: [from, to] ages during which turning is ignored
## - `root_motion`: [[from, to_exclusive, vx, vy], ...] velocity overrides (vx facing-relative)
## - `armor` / `invuln`: [[from, to], ...] age ranges
## - `events`: [{ age, name, data }] (sfx / vfx / camera / spawn cues)
## - `hit`: damage_mult, reach, y_top, y_bottom, knockback, hitstop, guard_force, both_sides, step,
##   attack_tag (blade / blunt / pierce / projectile / dive) for the interaction matrix
## - `tags`: light / heavy / air / launcher / dive / pogo / command / signature ...

var id: String = ""
var anim: String = ""
var skill_id: String = ""
var windup: int = 5
var active: Array = [] # [[start, end_exclusive], ...]
var recovery: int = 10
var cancel: Dictionary = {}
var buffer_open: int = 0
var facing_lock: Array = []
var root_motion: Array = []
var armor: Array = []
var invuln: Array = []
var events: Array = []
var hit: Dictionary = {}
var tags: Array = []
var extra: Dictionary = {}


static func from_dict(move_id: String, d: Dictionary) -> MoveDef:
	var m := MoveDef.new()
	m.id = move_id
	m.anim = str(d.get("anim", ""))
	m.skill_id = str(d.get("skill", ""))
	m.windup = int(d.get("windup", 5))
	if d.has("active") and d["active"] is Array and not (d["active"] as Array).is_empty() and d["active"][0] is Array:
		for seg in d["active"]:
			m.active.append([int(seg[0]), int(seg[1])])
	else:
		var dur := int(d.get("active", 5))
		m.active = [[m.windup, m.windup + maxi(1, dur)]]
	m.recovery = int(d.get("recovery", 10))
	m.cancel = (d.get("cancel", {}) as Dictionary).duplicate(true)
	m.buffer_open = int(d.get("buffer_open", 0))
	m.facing_lock = (d.get("facing_lock", []) as Array).duplicate(true)
	m.root_motion = (d.get("root_motion", []) as Array).duplicate(true)
	m.armor = (d.get("armor", []) as Array).duplicate(true)
	m.invuln = (d.get("invuln", []) as Array).duplicate(true)
	m.events = (d.get("events", []) as Array).duplicate(true)
	m.hit = (d.get("hit", {}) as Dictionary).duplicate(true)
	m.tags = (d.get("tags", []) as Array).duplicate()
	m.extra = (d.get("extra", {}) as Dictionary).duplicate(true)
	if d.has("row"):
		m.apply_frame_row(d["row"])
	return m


## Tideforge-compatible 10-field frame row:
## [windup, active, recovery, damage_mult, reach, knockback, hitstop, guard_force, both_sides, step]
static func from_frame_row(move_id: String, row: Array, tags_in: Array = []) -> MoveDef:
	var m := MoveDef.new()
	m.id = move_id
	m.tags = tags_in.duplicate()
	m.apply_frame_row(row)
	return m


func apply_frame_row(row: Array) -> void:
	windup = int(row[0])
	active = [[windup, windup + maxi(1, int(row[1]))]]
	recovery = int(row[2])
	hit["damage"] = float(row[3])
	hit["reach"] = float(row[4])
	hit["knockback"] = float(row[5])
	hit["hitstop"] = int(row[6])
	hit["guard_force"] = float(row[7])
	hit["both_sides"] = int(row[8]) != 0
	hit["step"] = float(row[9])


## Converts a legacy seconds-based skills.json entry (duration / cancel_from / hitstop).
static func from_skill(skill: Dictionary, tick_rate: int = 60) -> MoveDef:
	var m := MoveDef.new()
	m.id = str(skill.get("id", ""))
	m.skill_id = m.id
	m.anim = str(skill.get("anim", ""))
	var total := maxi(2, int(round(float(skill.get("duration", 0.34)) * tick_rate)))
	var cancel_from := int(round(float(skill.get("cancel_from", float(skill.get("duration", 0.34)) * 0.62)) * tick_rate))
	m.windup = maxi(1, int(round(total * 0.3)))
	m.active = [[m.windup, maxi(m.windup + 1, cancel_from)]]
	m.recovery = maxi(1, total - int(m.active[0][1]))
	m.cancel = {"whiff": cancel_from, "blocked": cancel_from, "hit_delay": 0, "hit_window": total, "startup": 4}
	m.hit = {
		"damage_mult": float(skill.get("damage_mult", 1.0)),
		"reach": float(skill.get("range_x", 44.0)),
		"knockback": float(skill.get("knockback_x", 110.0)),
		"hitstop": int(round(float(skill.get("hitstop", 0.04)) * tick_rate)),
		"guard_force": float(skill.get("poise_dmg", 14.0)),
		"both_sides": false,
		"step": float(skill.get("lunge_x", 0.0)) / 3.8,
	}
	return m


func first_active() -> int:
	return int(active[0][0]) if not active.is_empty() else windup


## Exclusive end of the last active segment ("contact end").
func active_end() -> int:
	var e := windup
	for seg in active:
		e = maxi(e, int(seg[1]))
	return e


func total_frames() -> int:
	return active_end() + recovery


func is_active_at(age: int) -> bool:
	for seg in active:
		if age >= int(seg[0]) and age < int(seg[1]):
			return true
	return false


## Index of the active segment at `age` (multi-hit moves re-hit per segment), -1 if none.
func segment_at(age: int) -> int:
	for i in range(active.size()):
		if age >= int(active[i][0]) and age < int(active[i][1]):
			return i
	return -1


func is_recovery(age: int) -> bool:
	return age >= active_end()


func phase_at(age: int) -> String:
	if age < first_active():
		return "windup"
	if is_active_at(age):
		return "active"
	if age < active_end():
		return "between"
	return "recovery"


static func _in_ranges(ranges: Array, age: int) -> bool:
	for r in ranges:
		if age >= int(r[0]) and age < int(r[1]):
			return true
	return false


func has_armor_at(age: int) -> bool:
	return _in_ranges(armor, age)


func is_invuln_at(age: int) -> bool:
	return _in_ranges(invuln, age)


func is_facing_locked_at(age: int) -> bool:
	return facing_lock.size() == 2 and age >= int(facing_lock[0]) and age < int(facing_lock[1])


## Root-motion velocity override active at `age` (facing-relative x), or null.
func root_motion_at(age: int) -> Variant:
	for k in root_motion:
		if age >= int(k[0]) and age < int(k[1]):
			return Vector2(float(k[2]), float(k[3]))
	return null


func events_at(age: int) -> Array:
	var out: Array = []
	for e in events:
		if int((e as Dictionary).get("age", -1)) == age:
			out.append(e)
	return out


func has_tag(tag: String) -> bool:
	return tags.has(tag)


## Field-level overlay (weapon overrides only what it specifies for this move).
func overlay(d: Dictionary) -> void:
	if d.has("row"):
		apply_frame_row(d["row"])
	for key in ["windup", "recovery", "buffer_open"]:
		if d.has(key):
			set(key, int(d[key]))
	if d.has("windup_delta"):
		var delta := int(d["windup_delta"])
		windup += delta
		for seg in active:
			seg[0] = int(seg[0]) + delta
			seg[1] = int(seg[1]) + delta
	for key in ["active", "facing_lock", "root_motion", "armor", "invuln", "events", "tags"]:
		if d.has(key):
			set(key, (d[key] as Array).duplicate(true))
	if d.has("anim"):
		anim = str(d["anim"])
	for key in ["cancel", "hit", "extra"]:
		if d.has(key):
			(get(key) as Dictionary).merge(d[key], true)


func duplicate_def() -> MoveDef:
	return MoveDef.from_dict(id, to_dict())


func to_dict() -> Dictionary:
	return {
		"anim": anim, "skill": skill_id, "windup": windup, "active": active.duplicate(true), "recovery": recovery,
		"cancel": cancel.duplicate(true), "buffer_open": buffer_open, "facing_lock": facing_lock.duplicate(true),
		"root_motion": root_motion.duplicate(true), "armor": armor.duplicate(true), "invuln": invuln.duplicate(true),
		"events": events.duplicate(true), "hit": hit.duplicate(true), "tags": tags.duplicate(), "extra": extra.duplicate(true),
	}
