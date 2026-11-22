class_name EncounterZone2D
extends Area2D
## Random Encounter Zone (暗雷区域 — Tall Grass / Dungeon Corridor).
## Tracks whether the player is inside and exposes `encounter_rate` + weighted `troop_table`.

@export var zone_size: Vector2 = Vector2(120, 80)
@export var encounter_rate: float = 1.0
var troop_table: Array = []
var player_inside: bool = false


func _ready() -> void:
	if get_node_or_null("CollisionShape2D") == null:
		var col := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = zone_size
		col.shape = rect
		add_child(col)
	body_entered.connect(func(b: Node):
		if b.is_in_group("player"):
			player_inside = true
	)
	body_exited.connect(func(b: Node):
		if b.is_in_group("player"):
			player_inside = false
	)


func _draw() -> void:
	var r := Rect2(-zone_size * 0.5, zone_size)
	draw_rect(r, Color(0.14, 0.42, 0.18, 0.45), true)
	draw_rect(r, Color(0.35, 0.72, 0.35, 0.75), false, 1.2)
