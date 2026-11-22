extends Node
## Centralized JSON Data Table Registry.
## Loads items, skills, enemies, quests, world_graph, and dialogues from `content/`.

const DATA_DIR := "res://content/data"
const DIALOGUE_DIR := "res://content/dialogues"

var items: Dictionary = {}
var skills: Dictionary = {}
var enemies: Dictionary = {}
var quests: Dictionary = {}
var story_arcs: Dictionary = {}
var world_graph: Dictionary = {}
var dialogues: Dictionary = {}


func _ready() -> void:
	reload_all()


func reload_all() -> void:
	items = _load_indexed_table("%s/items.json" % DATA_DIR, "items")
	skills = _load_indexed_table("%s/skills.json" % DATA_DIR, "skills")
	enemies = _load_indexed_table("%s/enemies.json" % DATA_DIR, "enemies")
	quests = _load_indexed_table("%s/quests.json" % DATA_DIR, "quests")
	story_arcs = _load_dict("%s/story_arcs.json" % DATA_DIR).get("arcs", {})
	world_graph = _load_dict("%s/world_graph.json" % DATA_DIR)
	dialogues = _load_dialogues_dir(DIALOGUE_DIR)


func get_item(item_id: String) -> Dictionary:
	return items.get(item_id, {})


func get_skill(skill_id: String) -> Dictionary:
	return skills.get(skill_id, {})


func get_enemy(enemy_id: String) -> Dictionary:
	return enemies.get(enemy_id, {})


func get_quest(quest_id: String) -> Dictionary:
	return quests.get(quest_id, {})


func get_dialogue(dialogue_id: String) -> Dictionary:
	return dialogues.get(dialogue_id, {})


func get_room_meta(room_id: String) -> Dictionary:
	return world_graph.get("rooms", {}).get(room_id, {})


## Cross-validates all data tables against AssetRegistry and LocaleManager.
## Returns an empty array when all references are valid.
func validate_all() -> Array[String]:
	var errors: Array[String] = []
	for iid in items.keys():
		var idef: Dictionary = items[iid]
		var icon_key := str(idef.get("icon_key", ""))
		if not icon_key.is_empty() and AssetRegistry and AssetRegistry.get_icon(icon_key) == null:
			errors.append("item '%s' references missing icon_key '%s'" % [iid, icon_key])
		var nkey := str(idef.get("name_key", ""))
		if not nkey.is_empty() and LocaleManager and not LocaleManager.has_key(nkey):
			errors.append("item '%s' references missing locale key '%s'" % [iid, nkey])

	for eid in enemies.keys():
		var edef: Dictionary = enemies[eid]
		var akey := str(edef.get("actor_key", ""))
		if not akey.is_empty() and AssetRegistry and AssetRegistry.get_actor_meta(akey).is_empty():
			errors.append("enemy '%s' references missing actor_key '%s'" % [eid, akey])
		for drop in edef.get("drops", []):
			var drop_id := str(drop.get("item_id", ""))
			if not drop_id.is_empty() and not items.has(drop_id):
				errors.append("enemy '%s' drops unknown item '%s'" % [eid, drop_id])

	for qid in quests.keys():
		var qdef: Dictionary = quests[qid]
		var rooms: Dictionary = world_graph.get("rooms", {})
		var turn_room := str(qdef.get("turn_in_room", ""))
		if not turn_room.is_empty() and not rooms.has(turn_room):
			errors.append("quest '%s' turn_in_room '%s' not in world_graph" % [qid, turn_room])
		for obj in qdef.get("objectives", []):
			var oroom := str(obj.get("room_id", ""))
			if not oroom.is_empty() and not rooms.has(oroom):
				errors.append("quest '%s' objective '%s' room_id '%s' not in world_graph" % [qid, obj.get("id", ""), oroom])
		for ritem in qdef.get("rewards", {}).get("items", []):
			var rid := str(ritem.get("id", ""))
			if not rid.is_empty() and not items.has(rid):
				errors.append("quest '%s' reward item '%s' not in items.json" % [qid, rid])

	for rid in world_graph.get("rooms", {}).keys():
		var rmeta: Dictionary = world_graph["rooms"][rid]
		var scene_path := str(rmeta.get("scene", ""))
		if not scene_path.is_empty() and not FileAccess.file_exists(scene_path):
			errors.append("room '%s' scene not found: %s" % [rid, scene_path])
		var bgm := str(rmeta.get("bgm", ""))
		if not bgm.is_empty() and AssetRegistry and AssetRegistry.get_audio_meta(bgm).is_empty():
			errors.append("room '%s' bgm '%s' missing from pack.json" % [rid, bgm])

	return errors


func _load_dict(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _load_indexed_table(path: String, array_key: String) -> Dictionary:
	var raw := _load_dict(path)
	if raw.is_empty():
		return {}
	if raw.has(array_key) and typeof(raw[array_key]) == TYPE_ARRAY:
		var out: Dictionary = {}
		for entry in raw[array_key]:
			if typeof(entry) == TYPE_DICTIONARY and entry.has("id"):
				out[str(entry["id"])] = entry
		return out
	return raw


func _load_dialogues_dir(dir_path: String) -> Dictionary:
	var out: Dictionary = {}
	if not DirAccess.dir_exists_absolute(dir_path):
		return out
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var fname := dir.get_next()
	while not fname.is_empty():
		if not dir.current_is_dir() and fname.ends_with(".json"):
			var parsed := _load_dict("%s/%s" % [dir_path, fname])
			if parsed.has("dialogues") and typeof(parsed["dialogues"]) == TYPE_DICTIONARY:
				for k in parsed["dialogues"].keys():
					out[str(k)] = parsed["dialogues"][k]
			elif parsed.has("id"):
				out[str(parsed["id"])] = parsed
		fname = dir.get_next()
	dir.list_dir_end()
	return out
