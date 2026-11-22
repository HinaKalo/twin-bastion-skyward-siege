class_name CommandQueue
extends RefCounted
## Command Pattern Queue with Undo / Redo & Deterministic History Log.
## Ideal for Tactics (undo move before attack), 4X Strategy, and deterministic replay.

var _undo_stack: Array[Dictionary] = [] # { label, do_cb: Callable, undo_cb: Callable }
var _redo_stack: Array[Dictionary] = []
var history_log: Array[String] = []


func execute(label: String, do_cb: Callable, undo_cb: Callable) -> bool:
	if not do_cb.is_valid():
		return false
	do_cb.call()
	_undo_stack.append({"label": label, "do_cb": do_cb, "undo_cb": undo_cb})
	_redo_stack.clear()
	history_log.append(label)
	return true


func can_undo() -> bool:
	return not _undo_stack.is_empty()


func can_redo() -> bool:
	return not _redo_stack.is_empty()


func undo() -> bool:
	if _undo_stack.is_empty():
		return false
	var cmd: Dictionary = _undo_stack.pop_back()
	var ucb: Callable = cmd["undo_cb"]
	if ucb.is_valid():
		ucb.call()
	_redo_stack.append(cmd)
	return true


func redo() -> bool:
	if _redo_stack.is_empty():
		return false
	var cmd: Dictionary = _redo_stack.pop_back()
	var dcb: Callable = cmd["do_cb"]
	if dcb.is_valid():
		dcb.call()
	_undo_stack.append(cmd)
	return true


func clear() -> void:
	_undo_stack.clear()
	_redo_stack.clear()
