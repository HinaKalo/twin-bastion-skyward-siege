class_name MoonShrine2D
extends MoonInteractable2D
## Save & Rest Shrine (Campfire / Statue). Restores HP/MP/ST and saves to SaveManager.

@export var prop_key: String = "campfire"
@export var save_slot: String = "slot_1"


func _ready() -> void:
	interact_size = Vector2(36, 36)
	super._ready()
	var spr := Sprite2D.new()
	spr.texture = AssetRegistry.get_prop_texture(prop_key) if AssetRegistry else null
	spr.position = Vector2(0, -16)
	add_child(spr)


func get_interact_label() -> String:
	return "%s 篝火休整并存档" % MoonRPG.prompt("interact")


func interact(player: Node) -> void:
	if player != null and player.has_method("full_restore"):
		player.full_restore()
	var cp_id := "%s_shrine_%d" % [MoonRPG.current_room(), int(global_position.x)]
	MoonRPG.set_checkpoint(cp_id, MoonRPG.current_room(), global_position)
	MoonRPG.save(save_slot)
	MoonRPG.play_sfx("sfx.checkpoint")
	MoonRPG.toast("已在检查点恢复状态并完成存档！", "gold")
