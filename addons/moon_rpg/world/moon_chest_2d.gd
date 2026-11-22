class_name MoonChest2D
extends MoonInteractable2D
## Persistent One-Time Treasure Chest backed by SaveManager world flags.

@export var chest_id: String = "chest_default"
@export var reward_item_id: String = "iron_helmet"
@export var reward_count: int = 1
@export var reward_gold: int = 40

var _sprite: Sprite2D


func _ready() -> void:
	interact_size = Vector2(36, 36)
	super._ready()
	_sprite = Sprite2D.new()
	_sprite.texture = AssetRegistry.get_prop_texture("chest") if AssetRegistry else null
	_sprite.scale = Vector2(0.5, 0.5)
	_sprite.position = Vector2(0, -16)
	add_child(_sprite)
	_refresh_visual()


func _is_opened() -> bool:
	return bool(MoonRPG.flag("chest:" + chest_id, false))


func _refresh_visual() -> void:
	if _sprite != null:
		_sprite.modulate = Color(0.55, 0.55, 0.55, 0.8) if _is_opened() else Color.WHITE


func get_interact_label() -> String:
	return "宝箱已开启" if _is_opened() else "%s 开启宝箱" % MoonRPG.prompt("interact")


func interact(_player: Node) -> void:
	if _is_opened():
		return
	MoonRPG.set_flag("chest:" + chest_id, true)
	if not reward_item_id.is_empty():
		MoonRPG.give(reward_item_id, reward_count)
	if reward_gold > 0:
		MoonRPG.add_gold(reward_gold)
	MoonRPG.play_sfx("sfx.collect")
	_refresh_visual()
	var idef := DataRegistry.get_item(reward_item_id)
	var iname := MoonRPG.tr_key(str(idef.get("name_key", reward_item_id)), {}, reward_item_id)
	MoonRPG.toast("开启宝箱获得：%s x%d + %d金币！" % [iname, reward_count, reward_gold], "gold")
