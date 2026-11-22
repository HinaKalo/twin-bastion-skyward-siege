class_name InputBuffer
extends RefCounted
## Fighting-game / Dead Cells style Input Buffer.
## Buffers action presses for `window_sec` (default 0.14s) so pressing Attack/Dodge/Parry/Jump
## a few frames before recovery ends executes on the exact first legal cancel frame.

var window_sec: float = 0.14
var _entries: Dictionary = {} # action_name -> remaining_sec


func _init(buffer_window: float = 0.14) -> void:
	window_sec = buffer_window


func push(action_name: String) -> void:
	_entries[action_name] = window_sec


func tick(delta: float) -> void:
	if _entries.is_empty():
		return
	var expired: Array[String] = []
	for k in _entries.keys():
		var rem := float(_entries[k]) - delta
		if rem <= 0.0:
			expired.append(str(k))
		else:
			_entries[k] = rem
	for k in expired:
		_entries.erase(k)


func has(action_name: String) -> bool:
	return _entries.has(action_name)


func consume(action_name: String) -> bool:
	if not _entries.has(action_name):
		return false
	_entries.erase(action_name)
	return true


func clear() -> void:
	_entries.clear()
