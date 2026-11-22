class_name MapEvent2D
extends Area2D
## RPG Maker MZ Style Multi-Page Conditional Map Event.
##
## Evaluates `pages` from last to first using StoryBlackboard conditions
## (just like RPG Maker's Page 1..N priority!). Supports:
## - ACTION_BUTTON: triggered when player interacts
## - PLAYER_TOUCH:  triggered when player enters area
## - AUTORUN:       triggered automatically once when active page matches
## - PARALLEL:      runs repeatedly while active page matches

enum TriggerMode { ACTION_BUTTON, PLAYER_TOUCH, AUTORUN, PARALLEL }

signal event_triggered(event_id: String, page_index: int)

@export var event_id: String = "ev_default"
var pages: Array[Dictionary] = [] # [{ condition, trigger, commands: Array[Dictionary] }]

var _active_page_index: int = -1
var _autorun_done: Dictionary = {}


func _ready() -> void:
	collision_layer = 64
	collision_mask = 4
	if get_node_or_null("CollisionShape2D") == null:
		var col := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(28, 28)
		col.shape = rect
		add_child(col)
	body_entered.connect(_on_body_entered)
	refresh_active_page()


func set_pages(page_list: Array) -> void:
	pages.clear()
	for p in page_list:
		if typeof(p) == TYPE_DICTIONARY:
			pages.append(p)
	refresh_active_page()


## Returns the highest-priority page index whose condition evaluates to true (-1 if none).
func resolve_active_page_index() -> int:
	for i in range(pages.size() - 1, -1, -1):
		var cond := str(pages[i].get("condition", ""))
		if cond.is_empty():
			return i
		if StoryBlackboard != null and StoryBlackboard.check(cond):
			return i
	return -1


func refresh_active_page() -> int:
	_active_page_index = resolve_active_page_index()
	visible = _active_page_index >= 0
	if _active_page_index >= 0:
		var page := pages[_active_page_index]
		if int(page.get("trigger", TriggerMode.ACTION_BUTTON)) == TriggerMode.AUTORUN and not _autorun_done.has(_active_page_index):
			_autorun_done[_active_page_index] = true
			trigger()
	return _active_page_index


func trigger() -> bool:
	var idx := resolve_active_page_index()
	if idx < 0:
		return false
	_active_page_index = idx
	var page := pages[idx]
	_execute_commands(page.get("commands", []))
	event_triggered.emit(event_id, idx)
	return true


func interact(_player: Node) -> void:
	var idx := resolve_active_page_index()
	if idx >= 0 and int(pages[idx].get("trigger", TriggerMode.ACTION_BUTTON)) == TriggerMode.ACTION_BUTTON:
		trigger()


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	var idx := resolve_active_page_index()
	if idx >= 0 and int(pages[idx].get("trigger", TriggerMode.ACTION_BUTTON)) == TriggerMode.PLAYER_TOUCH:
		trigger()


func _execute_commands(commands: Array) -> void:
	for cmd in commands:
		if typeof(cmd) != TYPE_DICTIONARY:
			continue
		match str(cmd.get("type", "")):
			"dialogue":
				if DialogueRunner:
					DialogueRunner.start_dialogue(str(cmd.get("dialogue_id", "")))
			"say_line":
				if DialogueRunner:
					DialogueRunner.say_line(str(cmd.get("speaker", "")), str(cmd.get("text", "")), str(cmd.get("portrait", "")))
			"give_item":
				if InventoryManager:
					InventoryManager.add_item(str(cmd.get("item_id", "")), int(cmd.get("count", 1)))
			"set_flag":
				if SaveManager:
					SaveManager.set_flag(str(cmd.get("flag", "")), cmd.get("value", true))
			"bb_tag":
				if StoryBlackboard:
					StoryBlackboard.add_tag(str(cmd.get("tag", "")))
			"bb_inc":
				if StoryBlackboard:
					StoryBlackboard.inc(str(cmd.get("key", "")), float(cmd.get("delta", 1.0)))
			"hook":
				if ScriptBridge:
					ScriptBridge.invoke_hook(str(cmd.get("name", "")), cmd.get("payload", {}))
