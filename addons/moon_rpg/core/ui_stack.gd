extends Node
## Cross-Genre Modal UI & Focus Stack.
## Manages layered panels/menus across ARPG, Top-Down RPG, Tactics, and 4X Strategy games,
## automatically restoring previous focus and managing optional world pause.

signal stack_changed(depth: int)

var _stack: Array[Dictionary] = [] # { control, pause_world, prev_focus, on_close }


func push(control: Control, pause_world: bool = false, initial_focus: Control = null, on_close: Callable = Callable()) -> void:
	if control == null:
		return
	var prev_focus: Control = get_viewport().gui_get_focus_owner() if get_viewport() != null else null
	control.visible = true
	_stack.append({
		"control": control,
		"pause_world": pause_world,
		"prev_focus": prev_focus,
		"on_close": on_close,
	})
	_sync_pause_state()
	if initial_focus != null and is_instance_valid(initial_focus):
		initial_focus.grab_focus()
	stack_changed.emit(_stack.size())


func pop() -> Control:
	if _stack.is_empty():
		return null
	var entry: Dictionary = _stack.pop_back()
	var ctrl: Control = entry["control"]
	if is_instance_valid(ctrl):
		ctrl.visible = false
	var cb: Callable = entry["on_close"]
	if cb.is_valid():
		cb.call()
	_sync_pause_state()
	var prev: Control = entry["prev_focus"]
	if is_instance_valid(prev) and prev.is_visible_in_tree():
		prev.grab_focus()
	stack_changed.emit(_stack.size())
	return ctrl


func top() -> Control:
	if _stack.is_empty():
		return null
	return _stack[_stack.size() - 1]["control"]


func depth() -> int:
	return _stack.size()


func is_empty() -> bool:
	return _stack.is_empty()


func clear() -> void:
	while not _stack.is_empty():
		pop()


func _sync_pause_state() -> void:
	var should_pause := false
	for entry in _stack:
		if bool(entry["pause_world"]):
			should_pause = true
			break
	if get_tree() != null:
		get_tree().paused = should_pause
