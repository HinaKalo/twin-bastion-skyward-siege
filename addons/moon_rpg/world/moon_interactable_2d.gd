class_name MoonInteractable2D
extends Area2D
## Base class for all world interactables (NPCs, Portals, Shrines, Chests).

@export var interact_size: Vector2 = Vector2(40, 48)


func _ready() -> void:
	collision_layer = 64 # layer 7: interactable
	collision_mask = 0
	if get_node_or_null("CollisionShape2D") == null:
		var col := CollisionShape2D.new()
		col.name = "CollisionShape2D"
		var rect := RectangleShape2D.new()
		rect.size = interact_size
		col.shape = rect
		col.position = Vector2(0, -interact_size.y * 0.5)
		add_child(col)


func get_interact_label() -> String:
	return "[E] 交互"


func interact(_player: Node) -> void:
	pass
