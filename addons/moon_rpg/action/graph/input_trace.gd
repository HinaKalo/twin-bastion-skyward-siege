class_name InputTrace
extends RefCounted
## Frame-based input buffer that records the fate of every press.
##
## Each press becomes an entry: { uid, input, tick, dir (Vector2i at press), facing, ttl,
## status: buffered | triggered | expired | blocked, reason, move }.
## - buffered: waiting in the buffer
## - triggered: consumed by a move (`move` names it)
## - blocked: resolution refused it this tick — `reason` names the gating condition
##   (cancel_window, chain_cap, air, grounded, dir, command, min_delay, ...). A blocked entry stays
##   in the buffer and may still trigger later; if it then expires its final status is `expired`
##   with `reason` = the last block reason ("expired after being blocked by cancel_window").
## - expired: ttl ran out
##
## TTLs are paused while the owner is frozen by hitstop, so decisions the player makes during
## a hit-freeze are preserved.

const DEFAULT_TTL := {"light": 12, "heavy": 12, "ultimate": 12, "dodge": 8, "jump": 8, "guard": 8, "surge": 9}

var ttl: Dictionary = DEFAULT_TTL.duplicate()
var history_limit: int = 256
var _active: Array[Dictionary] = []
var history: Array[Dictionary] = []
var _uid: int = 0


func set_ttl(input: String, frames: int) -> void:
	ttl[input] = maxi(1, frames)


## Records a press. A newer press of the same input replaces the older buffered one
## (the older one is marked expired with reason "superseded").
func push(input: String, tick: int, dir: Vector2i = Vector2i.ZERO, facing: int = 1) -> Dictionary:
	for e in _active:
		if str(e["input"]) == input:
			_finish(e, "expired", "superseded")
	_active = _active.filter(func(e): return str(e["status"]) == "buffered" or str(e["status"]) == "blocked")
	_uid += 1
	var entry := {
		"uid": _uid, "input": input, "tick": tick, "dir": dir, "facing": facing,
		"ttl": int(ttl.get(input, 10)), "status": "buffered", "reason": "", "move": "", "age": 0,
	}
	_active.append(entry)
	_append_history(entry)
	return entry


## Advances one tick (skipped while frozen). Expired entries leave the buffer.
func tick(frozen: bool = false) -> void:
	if frozen:
		return
	var keep: Array[Dictionary] = []
	for e in _active:
		e["ttl"] = int(e["ttl"]) - 1
		e["age"] = int(e["age"]) + 1
		if int(e["ttl"]) <= 0:
			_finish(e, "expired", str(e["reason"]))
		else:
			keep.append(e)
	_active = keep


func has(input: String) -> bool:
	return peek(input) != {}


func peek(input: String) -> Dictionary:
	for e in _active:
		if str(e["input"]) == input:
			return e
	return {}


## Buffered inputs, oldest first.
func pending() -> Array[Dictionary]:
	return _active.duplicate()


func mark_blocked(input: String, reason: String) -> void:
	var e := peek(input)
	if e.is_empty():
		return
	e["status"] = "blocked"
	e["reason"] = reason


func consume(input: String, move_id: String = "") -> Dictionary:
	var e := peek(input)
	if e.is_empty():
		return {}
	_finish(e, "triggered", "")
	e["move"] = move_id
	_active.erase(e)
	return e


func clear(reason: String = "cleared") -> void:
	for e in _active:
		_finish(e, "expired", reason)
	_active.clear()


func _finish(e: Dictionary, status: String, reason: String) -> void:
	e["status"] = status
	e["reason"] = reason


func _append_history(e: Dictionary) -> void:
	history.append(e)
	if history.size() > history_limit:
		history.pop_front()


## Last N history entries as plain dictionaries (for overlays, logs and fixtures).
func export_recent(count: int = 16) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var start := maxi(0, history.size() - count)
	for i in range(start, history.size()):
		var e: Dictionary = history[i]
		out.append({
			"input": e["input"], "tick": e["tick"], "status": e["status"],
			"reason": e["reason"], "move": e["move"], "dir": [e["dir"].x, e["dir"].y],
		})
	return out


func last_of(input: String) -> Dictionary:
	for i in range(history.size() - 1, -1, -1):
		if str(history[i]["input"]) == input:
			return history[i]
	return {}
