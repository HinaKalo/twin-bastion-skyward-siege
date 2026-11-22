class_name MoonNpc2D
extends MoonInteractable2D
## Out-of-the-box Interactable NPC with AssetRegistry sprite, overhead Quest Marker (! / ?),
## and automatic DialogueRunner integration.

@export var npc_id: String = "npc.camp_smith"
@export var dialogue_id: String = "camp_smith_talk"

var _sprite: AnimatedSprite2D
var _marker: WorldMarker2D


func _ready() -> void:
	interact_size = Vector2(44, 56)
	super._ready()

	_sprite = AnimatedSprite2D.new()
	_sprite.centered = false
	add_child(_sprite)
	if AssetRegistry:
		var sf := AssetRegistry.build_actor_sprite_frames(npc_id)
		if sf != null:
			_sprite.sprite_frames = sf
			_sprite.offset = -AssetRegistry.get_actor_pivot(npc_id)
			_sprite.play("idle")

	_marker = WorldMarker2D.new()
	add_child(_marker)

	if WorldManager:
		WorldManager.register_room_entity(npc_id, self)
	if EventBus:
		EventBus.quest_started.connect(_on_quest_event)
		EventBus.quest_updated.connect(_on_quest_event)
		EventBus.quest_completed.connect(_on_quest_event)
	_refresh_marker()


func _exit_tree() -> void:
	if WorldManager:
		WorldManager.unregister_room_entity(npc_id, self)
	if EventBus:
		if EventBus.quest_started.is_connected(_on_quest_event):
			EventBus.quest_started.disconnect(_on_quest_event)
		if EventBus.quest_updated.is_connected(_on_quest_event):
			EventBus.quest_updated.disconnect(_on_quest_event)
		if EventBus.quest_completed.is_connected(_on_quest_event):
			EventBus.quest_completed.disconnect(_on_quest_event)


func _on_quest_event(_q: String) -> void:
	_refresh_marker()


func _refresh_marker() -> void:
	if _marker == null or QuestManager == null:
		return
	var sym := QuestManager.get_npc_marker_type(npc_id)
	var col := Color(0.35, 0.95, 0.55) if sym == "?" else Color(1.0, 0.85, 0.2)
	_marker.set_marker(sym, col)


func get_interact_label() -> String:
	var dname := LocaleManager.tr_key(npc_id + ".name", {}, npc_id)
	return "%s 与 %s 对话" % [MoonRPG.prompt("interact"), dname]


func interact(_player: Node) -> void:
	MoonRPG.say(dialogue_id)
