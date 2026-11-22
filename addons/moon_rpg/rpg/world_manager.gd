extends Node
## Multi-Room World Topology, Fog-of-War Minimap State, and BFS Cross-Room Objective Routing.

var current_room_id: String = ""
var discovered_rooms: Dictionary = {} # room_id -> true
var _room_container: Node = null
var _current_room_node: Node = null
var _room_entities: Dictionary = {} # target_id -> Array[Node2D]


func bind_room_container(container: Node) -> void:
	_room_container = container


func load_room(room_id: String, spawn_point: String = "default") -> bool:
	var meta := DataRegistry.get_room_meta(room_id)
	if meta.is_empty():
		push_error("[WorldManager] Unknown room_id: %s" % room_id)
		return false

	var scene_path := str(meta.get("scene", ""))
	if not ResourceLoader.exists(scene_path):
		push_error("[WorldManager] Room scene not found: %s" % scene_path)
		return false

	_room_entities.clear()
	if is_instance_valid(_current_room_node):
		_current_room_node.queue_free()
		_current_room_node = null

	var packed: PackedScene = ResourceLoader.load(scene_path)
	var instance := packed.instantiate()
	if _room_container != null:
		_room_container.add_child(instance)
	else:
		get_tree().current_scene.add_child(instance)
	_current_room_node = instance
	current_room_id = room_id

	if not discovered_rooms.has(room_id):
		discovered_rooms[room_id] = true
		if EventBus:
			EventBus.room_discovered.emit(room_id)

	# Position all players (solo or 2P co-op) at requested spawn point
	var players := get_tree().get_nodes_in_group("player")
	var spawn_pos := _find_spawn_position(instance, spawn_point)
	for i in range(players.size()):
		if players[i] is Node2D:
			var p2d := players[i] as Node2D
			p2d.global_position = spawn_pos + Vector2(float(i) * 26.0, 0.0)
			p2d.reset_physics_interpolation()

	# Play room BGM if configured
	var bgm_key := str(meta.get("bgm", ""))
	if not bgm_key.is_empty() and AudioManager:
		AudioManager.play_bgm(bgm_key)

	if EventBus:
		EventBus.room_changed.emit(room_id, spawn_point)
	return true


func _find_spawn_position(room_node: Node, spawn_name: String) -> Vector2:
	var spawns := room_node.get_node_or_null("Spawns")
	if spawns != null:
		var marker := spawns.get_node_or_null(spawn_name)
		if marker == null and spawns.get_child_count() > 0:
			marker = spawns.get_child(0)
		if marker is Node2D:
			return (marker as Node2D).global_position
	return Vector2(80, 180)


func register_room_entity(entity_id: String, node: Node2D) -> void:
	if entity_id.is_empty():
		return
	if not _room_entities.has(entity_id):
		_room_entities[entity_id] = []
	var arr: Array = _room_entities[entity_id]
	if not arr.has(node):
		arr.append(node)


func unregister_room_entity(entity_id: String, node: Node2D) -> void:
	if _room_entities.has(entity_id):
		(_room_entities[entity_id] as Array).erase(node)


func find_live_entity(entity_id: String) -> Node2D:
	if not _room_entities.has(entity_id):
		return null
	var arr: Array = _room_entities[entity_id]
	for n in arr:
		if is_instance_valid(n) and n is Node2D:
			return n as Node2D
	return null


## Computes shortest path of room_ids from `from_room` to `to_room` via BFS on world_graph.
func find_room_path(from_room: String, to_room: String) -> Array[String]:
	if from_room == to_room:
		return [from_room]
	var rooms: Dictionary = DataRegistry.world_graph.get("rooms", {})
	if not rooms.has(from_room) or not rooms.has(to_room):
		return []

	var queue: Array = [[from_room]]
	var visited: Dictionary = {from_room: true}
	while not queue.is_empty():
		var path: Array = queue.pop_front()
		var last := str(path[path.size() - 1])
		var neighbors: Array = rooms[last].get("connections", [])
		for conn in neighbors:
			var nxt := str(conn.get("to_room", "")) if typeof(conn) == TYPE_DICTIONARY else str(conn)
			if nxt.is_empty() or visited.has(nxt):
				continue
			var next_path := path.duplicate()
			next_path.append(nxt)
			if nxt == to_room:
				var typed: Array[String] = []
				for r in next_path:
					typed.append(str(r))
				return typed
			visited[nxt] = true
			queue.append(next_path)
	return []


## Resolves the world-space Node2D that the player should move toward for the tracked quest.
## If the objective is in another room, returns the Portal2D leading to the next BFS hop!
func resolve_tracked_objective_node() -> Dictionary:
	if QuestManager == null:
		return {}
	var info := QuestManager.get_tracked_objective_info()
	if info.is_empty():
		return {}
	var target_room := str(info.get("room_id", ""))
	var target_id := str(info.get("target_id", ""))
	if target_room.is_empty() or target_room == current_room_id:
		var node := find_live_entity(target_id)
		if node != null:
			return {"node": node, "label": str(info.get("description", "")), "is_portal": false}
		return {}

	var path := find_room_path(current_room_id, target_room)
	if path.size() >= 2:
		var next_hop := path[1]
		var portal_node := find_live_entity("portal:" + next_hop)
		if portal_node != null:
			var next_meta := DataRegistry.get_room_meta(next_hop)
			var room_name := LocaleManager.tr_key(str(next_meta.get("name_key", next_hop)), {}, next_hop)
			return {"node": portal_node, "label": "前往 " + room_name, "is_portal": true}
	return {}


func is_room_discovered(room_id: String) -> bool:
	return bool(discovered_rooms.get(room_id, false))


func get_current_room_bounds() -> Rect2:
	var meta := DataRegistry.get_room_meta(current_room_id)
	var b: Array = meta.get("bounds", [0, 0, 960, 270])
	return Rect2(float(b[0]), float(b[1]), float(b[2]), float(b[3]))


func serialize_state() -> Dictionary:
	return {
		"current_room_id": current_room_id,
		"discovered_rooms": discovered_rooms.keys(),
	}


func deserialize_state(data: Dictionary) -> void:
	if data.is_empty():
		return
	discovered_rooms.clear()
	for r in data.get("discovered_rooms", []):
		discovered_rooms[str(r)] = true
	var saved_room := str(data.get("current_room_id", ""))
	if not saved_room.is_empty() and _room_container != null:
		load_room(saved_room, "default")
