class_name MoonPortal2D
extends MoonInteractable2D
## Room Transition Portal with automatic BFS quest-routing beacon highlight
## and smooth fade transition via MoonRPG.goto_room().

@export var target_room_id: String = ""
@export var target_spawn: String = "default"

var _marker: WorldMarker2D


func _ready() -> void:
	interact_size = Vector2(36, 64)
	super._ready()

	_marker = WorldMarker2D.new()
	add_child(_marker)

	if WorldManager and not target_room_id.is_empty():
		WorldManager.register_room_entity("portal:" + target_room_id, self)
	if EventBus:
		EventBus.quest_updated.connect(_on_quest_event)
		EventBus.tracked_quest_changed.connect(_on_quest_event)
	_refresh_beacon()


func _exit_tree() -> void:
	if WorldManager and not target_room_id.is_empty():
		WorldManager.unregister_room_entity("portal:" + target_room_id, self)
	if EventBus:
		if EventBus.quest_updated.is_connected(_on_quest_event):
			EventBus.quest_updated.disconnect(_on_quest_event)
		if EventBus.tracked_quest_changed.is_connected(_on_quest_event):
			EventBus.tracked_quest_changed.disconnect(_on_quest_event)


func _on_quest_event(_q: String) -> void:
	_refresh_beacon()


func _refresh_beacon() -> void:
	if _marker == null or WorldManager == null:
		return
	var resolved := WorldManager.resolve_tracked_objective_node()
	if not resolved.is_empty() and resolved.get("node") == self:
		_marker.set_marker("◆", Color(1.0, 0.84, 0.2))
	else:
		_marker.set_marker("")


func _draw() -> void:
	draw_rect(Rect2(-12, -52, 24, 52), Color(0.28, 0.72, 0.95, 0.28), true)
	draw_rect(Rect2(-12, -52, 24, 52), Color(0.55, 0.90, 1.0, 0.85), false, 1.5)


func get_interact_label() -> String:
	var rname := LocaleManager.tr_key("room.%s.name" % target_room_id, {}, target_room_id)
	return "%s 前往 %s" % [MoonRPG.prompt("interact"), rname]


func interact(_player: Node) -> void:
	MoonRPG.play_sfx("sfx.door")
	MoonRPG.goto_room(target_room_id, target_spawn, true)
