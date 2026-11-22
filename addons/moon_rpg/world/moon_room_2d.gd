class_name MoonRoom2D
extends Node2D
## Declarative Side-Scrolling ARPG Room Builder.
## Auto-builds 4-layer parallax backgrounds, tiled ground, boundary walls,
## and exposes a clean fluent API to place spawns, platforms, NPCs, enemies,
## portals, shrines, and chests in just a few lines of code.

@export var room_id: String = ""
@export var biome_key: String = "village"
@export var room_width: float = 720.0
@export var ground_y: float = 224.0

var _spawns_node: Node2D = null


func _ready() -> void:
	_spawns_node = get_node_or_null("Spawns")
	if _spawns_node == null:
		_spawns_node = Node2D.new()
		_spawns_node.name = "Spawns"
		add_child(_spawns_node)
	_build_parallax()
	_build_ground(room_width, ground_y)
	_build_room_walls(room_width, 270.0)


# =============================================================================
# Fluent Room Builder API
# =============================================================================

func add_spawn(spawn_name: String, x_pos: float, y_pos: float = -1.0) -> Marker2D:
	var m := Marker2D.new()
	m.name = spawn_name
	m.position = Vector2(x_pos, ground_y if y_pos < 0.0 else y_pos)
	_spawns_node.add_child(m)
	return m


func add_platform(x_pos: float, y_pos: float, tile_count: int) -> StaticBody2D:
	var width := float(tile_count) * 32.0
	var body := StaticBody2D.new()
	body.collision_layer = 2 # one_way
	body.collision_mask = 0
	body.position = Vector2(x_pos, y_pos)
	add_child(body)

	var col := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(width, 8.0)
	col.shape = rect
	col.position = Vector2(width * 0.5, 4.0)
	col.one_way_collision = true
	body.add_child(col)

	var biome := AssetRegistry.get_biome_meta(biome_key) if AssetRegistry else {}
	var tiles: Dictionary = biome.get("tiles", {})
	var plat_tex := AssetRegistry.load_texture(str(tiles.get("platform", ""))) if AssetRegistry else null
	for i in range(tile_count):
		if plat_tex != null:
			var s := Sprite2D.new()
			s.texture = plat_tex
			s.centered = false
			s.position = Vector2(i * 32.0, 0.0)
			body.add_child(s)
	return body


func add_npc(npc_id: String, dialogue_id: String, x_pos: float, y_pos: float = -1.0) -> MoonNpc2D:
	var npc := MoonNpc2D.new()
	npc.npc_id = npc_id
	npc.dialogue_id = dialogue_id
	npc.position = Vector2(x_pos, ground_y if y_pos < 0.0 else y_pos)
	add_child(npc)
	return npc


func add_enemy(enemy_id: String, x_pos: float, y_pos: float = -1.0) -> EnemyController:
	var enemy := EnemyController.new()
	enemy.enemy_id = enemy_id
	enemy.position = Vector2(x_pos, ground_y if y_pos < 0.0 else y_pos)
	add_child(enemy)
	return enemy


func add_portal(target_room: String, target_spawn: String, x_pos: float, y_pos: float = -1.0) -> MoonPortal2D:
	var portal := MoonPortal2D.new()
	portal.target_room_id = target_room
	portal.target_spawn = target_spawn
	portal.position = Vector2(x_pos, ground_y if y_pos < 0.0 else y_pos)
	add_child(portal)
	return portal


func add_shrine(x_pos: float, y_pos: float = -1.0, prop_key: String = "campfire") -> MoonShrine2D:
	var shrine := MoonShrine2D.new()
	shrine.prop_key = prop_key
	shrine.position = Vector2(x_pos, ground_y if y_pos < 0.0 else y_pos)
	add_child(shrine)
	return shrine


func add_chest(chest_id: String, item_id: String, count: int, gold: int, x_pos: float, y_pos: float = -1.0) -> MoonChest2D:
	var chest := MoonChest2D.new()
	chest.chest_id = chest_id
	chest.reward_item_id = item_id
	chest.reward_count = count
	chest.reward_gold = gold
	chest.position = Vector2(x_pos, ground_y if y_pos < 0.0 else y_pos)
	add_child(chest)
	return chest


# =============================================================================
# Internal Geometry & Parallax Builders
# =============================================================================

func _build_parallax() -> void:
	if AssetRegistry == null:
		return
	var biome := AssetRegistry.get_biome_meta(biome_key)
	var layers: Array = biome.get("parallax", [])
	if layers.is_empty():
		return
	var pb := ParallaxBackground.new()
	pb.name = "BiomeParallax"
	add_child(pb)

	for lmeta in layers:
		var tex := AssetRegistry.load_texture(str(lmeta.get("file", "")))
		if tex == null:
			continue
		var pl := ParallaxLayer.new()
		pl.motion_scale = Vector2(float(lmeta.get("parallax_x", 0.5)), 0.0)
		var tw := float(lmeta.get("width", tex.get_width()))
		if bool(lmeta.get("repeat_x", true)):
			pl.motion_mirroring = Vector2(tw, 0.0)
		var spr := Sprite2D.new()
		spr.texture = tex
		spr.centered = false
		spr.scale = Vector2(1.0, 270.0 / maxf(1.0, float(tex.get_height())))
		pl.add_child(spr)
		pb.add_child(pl)


func _build_ground(width: float, y_top: float) -> void:
	var body := StaticBody2D.new()
	body.name = "GroundBody"
	body.collision_layer = 1 # world
	body.collision_mask = 0
	add_child(body)

	var col := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(width, 64.0)
	col.shape = rect
	col.position = Vector2(width * 0.5, y_top + 32.0)
	body.add_child(col)

	var biome := AssetRegistry.get_biome_meta(biome_key) if AssetRegistry else {}
	var tiles: Dictionary = biome.get("tiles", {})
	var surface_tex := AssetRegistry.load_texture(str(tiles.get("surface", ""))) if AssetRegistry else null
	var fill_tex := AssetRegistry.load_texture(str(tiles.get("fill", ""))) if AssetRegistry else null

	var tile_w := 32.0
	var cols := int(ceil(width / tile_w))
	for c in range(cols):
		if surface_tex != null:
			var s := Sprite2D.new()
			s.texture = surface_tex
			s.centered = false
			s.position = Vector2(c * tile_w, y_top)
			body.add_child(s)
		if fill_tex != null:
			var f := Sprite2D.new()
			f.texture = fill_tex
			f.centered = false
			f.position = Vector2(c * tile_w, y_top + 32.0)
			body.add_child(f)


func _build_room_walls(width: float, height: float) -> void:
	var walls := StaticBody2D.new()
	walls.name = "RoomWalls"
	walls.collision_layer = 1
	walls.collision_mask = 0
	add_child(walls)
	for x in [-8.0, width + 8.0]:
		var col := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(16.0, height * 2.0)
		col.shape = rect
		col.position = Vector2(x, height * 0.5)
		walls.add_child(col)
