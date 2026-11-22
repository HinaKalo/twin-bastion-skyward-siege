extends Node
## Unified Multi-Slot JSON Save, Rolling Auto-Save & Checkpoint Manager.
##
## Features:
## - Rich slot metadata headers (`list_saves()`, `get_save_meta()`, `delete_save()`)
## - Rolling Auto-Save slots (`autosave_1..N`) triggered on room transitions,
##   quest completions, checkpoints, or configurable periodic timer
## - Active Checkpoint registration (`set_checkpoint()`) & respawn (`respawn_at_checkpoint()`)
## - Full serialization of Player, Inventory, Quests, StoryBlackboard, Difficulty, World & Flags

const SAVE_DIR := "user://moon_rpg_saves"
const SCHEMA_VERSION := 2

var world_flags: Dictionary = {}
var active_checkpoint: Dictionary = {} # { id, room_id, position: [x, y] }

# Auto-Save configuration
var autosave_enabled: bool = true
var autosave_on_room_change: bool = true
var autosave_on_quest_complete: bool = true
var autosave_interval_sec: float = 0.0 # > 0 enables periodic timer autosave
var autosave_slot_count: int = 3
var latest_autosave_slot: String = ""

var _autosave_cursor: int = 0
var _autosave_timer: float = 0.0
var _player_ref: Node = null
var _providers: Dictionary = {} # section_key -> { save: Callable, load: Callable }

## Silent checkpoints + failure assist (core/sim/checkpoint_service.gd).
var checkpoints: CheckpointService = CheckpointService.new()
## Idempotent settlement ledger persisted with every save.
var ledger: TransactionLedger = TransactionLedger.new()
## Versioned migrations applied on load (v1 -> v2 is identity for pre-ledger saves).
var migrations: SaveMigrationRegistry = SaveMigrationRegistry.new(SCHEMA_VERSION)
## Result of the most recent load: { slot, source: "primary"|"backup", migrated_from, log }.
var last_load_report: Dictionary = {}
var last_save_unix: int = 0


func register_provider(section_key: String, serialize_cb: Callable, deserialize_cb: Callable) -> void:
	if section_key.is_empty():
		return
	_providers[section_key] = {"save": serialize_cb, "load": deserialize_cb}


func unregister_provider(section_key: String) -> void:
	_providers.erase(section_key)


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	migrations.migrate(1, func(save: Dictionary, _trail: Array) -> Dictionary: return save, "v1->v2 identity")
	checkpoints.load_assist_curve("res://content/data/assist_curves.json")
	register_provider("checkpoints", checkpoints.serialize, checkpoints.deserialize)
	register_provider("ledger", ledger.serialize, ledger.deserialize)
	if EventBus:
		EventBus.player_registered.connect(func(p: Node): _player_ref = p)
		EventBus.room_changed.connect(_on_room_changed)
		EventBus.quest_completed.connect(_on_quest_completed)


func _process(delta: float) -> void:
	if not autosave_enabled or autosave_interval_sec <= 0.0:
		return
	if DialogueRunner != null and DialogueRunner.is_active:
		return
	_autosave_timer += delta
	if _autosave_timer >= autosave_interval_sec:
		_autosave_timer = 0.0
		trigger_autosave("timer")


func _on_room_changed(_room_id: String, _spawn: String) -> void:
	if autosave_enabled and autosave_on_room_change and is_instance_valid(_player_ref):
		trigger_autosave("room_change")


func _on_quest_completed(_quest_id: String) -> void:
	if autosave_enabled and autosave_on_quest_complete and is_instance_valid(_player_ref):
		trigger_autosave("quest_complete")


# =============================================================================
# World Flags
# =============================================================================

func set_flag(flag_name: String, value: Variant = true) -> void:
	world_flags[flag_name] = value
	if EventBus:
		EventBus.world_flag_changed.emit(flag_name, value)
	if StoryBlackboard:
		StoryBlackboard.evaluate_arcs()


func get_flag(flag_name: String, default_value: Variant = false) -> Variant:
	return world_flags.get(flag_name, default_value)


func has_flag(flag_name: String) -> bool:
	return true if world_flags.get(flag_name, false) else false


# =============================================================================
# Checkpoints & Respawn
# =============================================================================

func set_checkpoint(checkpoint_id: String, room_id: String = "", pos: Vector2 = Vector2.ZERO) -> void:
	var resolved_room := room_id if not room_id.is_empty() else (WorldManager.current_room_id if WorldManager else "")
	var resolved_pos := pos
	if resolved_pos == Vector2.ZERO and is_instance_valid(_player_ref) and _player_ref is Node2D:
		resolved_pos = (_player_ref as Node2D).global_position
	active_checkpoint = {
		"id": checkpoint_id,
		"room_id": resolved_room,
		"position": [resolved_pos.x, resolved_pos.y],
	}
	if EventBus:
		EventBus.checkpoint_updated.emit(checkpoint_id, resolved_room)


func get_checkpoint() -> Dictionary:
	return active_checkpoint.duplicate(true)


func respawn_at_checkpoint() -> bool:
	var target_room := str(active_checkpoint.get("room_id", ""))
	if target_room.is_empty():
		target_room = str(DataRegistry.world_graph.get("start_room", "village_camp")) if DataRegistry else "village_camp"
	if WorldManager:
		WorldManager.load_room(target_room, "default")
	if is_instance_valid(_player_ref):
		if _player_ref.has_method("full_restore"):
			_player_ref.full_restore()
		var cp_pos: Array = active_checkpoint.get("position", [])
		if cp_pos.size() == 2 and _player_ref is Node2D:
			(_player_ref as Node2D).global_position = Vector2(float(cp_pos[0]), float(cp_pos[1]))
	return true


# =============================================================================
# Slot Paths, Metadata Listing & Deletion
# =============================================================================

func get_slot_path(slot_id: String) -> String:
	return "%s/%s.json" % [SAVE_DIR, slot_id]


func has_save(slot_id: String) -> bool:
	return FileAccess.file_exists(get_slot_path(slot_id))


func delete_save(slot_id: String) -> bool:
	var path := get_slot_path(slot_id)
	if not FileAccess.file_exists(path):
		return false
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK


func get_save_meta(slot_id: String, custom_path: String = "") -> Dictionary:
	var path := custom_path if not custom_path.is_empty() else get_slot_path(slot_id)
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return (parsed as Dictionary).get("meta", {})


func list_saves() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var fname := dir.get_next()
	while not fname.is_empty():
		if not dir.current_is_dir() and fname.ends_with(".json"):
			var slot := fname.trim_suffix(".json")
			var meta := get_save_meta(slot)
			if meta.is_empty():
				meta = {"slot_id": slot}
			out.append(meta)
		fname = dir.get_next()
	dir.list_dir_end()
	out.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.get("saved_at_unix", 0)) > int(b.get("saved_at_unix", 0)))
	return out


# =============================================================================
# Snapshot Build / Apply / Save / Auto-Save / Load
# =============================================================================

func build_snapshot(slot_id: String = "slot_1", is_autosave: bool = false, reason: String = "") -> Dictionary:
	var player_data: Dictionary = {}
	var p_level := 1
	if is_instance_valid(_player_ref) and _player_ref.has_method("serialize_state"):
		player_data = _player_ref.serialize_state()
		p_level = int(player_data.get("stats", {}).get("level", 1))

	var room_id := WorldManager.current_room_id if WorldManager else ""
	var room_meta := DataRegistry.get_room_meta(room_id) if DataRegistry else {}
	var room_name := LocaleManager.tr_key(str(room_meta.get("name_key", room_id)), {}, room_id) if LocaleManager else room_id
	var now_unix := int(Time.get_unix_time_from_system())

	var provider_data: Dictionary = {}
	for key in _providers.keys():
		var cb: Callable = _providers[key]["save"]
		if cb.is_valid():
			provider_data[key] = cb.call()

	return {
		"schema_version": SCHEMA_VERSION,
		"saved_at_unix": now_unix,
		"meta": {
			"slot_id": slot_id,
			"saved_at_unix": now_unix,
			"is_autosave": is_autosave,
			"reason": reason,
			"room_id": room_id,
			"room_name": room_name,
			"player_level": p_level,
			"gold": InventoryManager.gold if InventoryManager else 0,
			"checkpoint_id": str(active_checkpoint.get("id", "")),
			"difficulty": DifficultyManager.preset if DifficultyManager else "normal",
		},
		"world_flags": world_flags.duplicate(true),
		"checkpoint": active_checkpoint.duplicate(true),
		"player": player_data,
		"inventory": InventoryManager.serialize_state() if InventoryManager else {},
		"quests": QuestManager.serialize_state() if QuestManager else {},
		"story": StoryBlackboard.serialize_state() if StoryBlackboard else {},
		"difficulty": DifficultyManager.serialize_state() if DifficultyManager else {},
		"world": WorldManager.serialize_state() if WorldManager else {},
		"providers": provider_data,
	}


func apply_snapshot(data: Dictionary) -> bool:
	if data.is_empty():
		return false
	world_flags = data.get("world_flags", {}).duplicate(true)
	active_checkpoint = data.get("checkpoint", {}).duplicate(true)
	if InventoryManager:
		InventoryManager.deserialize_state(data.get("inventory", {}))
	if QuestManager:
		QuestManager.deserialize_state(data.get("quests", {}))
	if StoryBlackboard:
		StoryBlackboard.deserialize_state(data.get("story", {}))
	if DifficultyManager:
		DifficultyManager.deserialize_state(data.get("difficulty", {}))
	if WorldManager:
		WorldManager.deserialize_state(data.get("world", {}))
	if is_instance_valid(_player_ref) and _player_ref.has_method("deserialize_state"):
		_player_ref.deserialize_state(data.get("player", {}))
	var provider_data: Dictionary = data.get("providers", {})
	for key in _providers.keys():
		if provider_data.has(key):
			var cb: Callable = _providers[key]["load"]
			if cb.is_valid():
				cb.call(provider_data[key])
	return true


func save_game(slot_id: String = "slot_1", custom_path: String = "", is_autosave: bool = false, reason: String = "") -> bool:
	var path := custom_path if not custom_path.is_empty() else get_slot_path(slot_id)
	if not write_snapshot_atomic(path, build_snapshot(slot_id, is_autosave, reason)):
		return false
	last_save_unix = int(Time.get_unix_time_from_system())
	if EventBus:
		EventBus.game_saved.emit(slot_id)
	return true


## Atomic two-generation write: body + checksum -> `<path>.tmp`, previous file -> `<path>.bak`,
## then tmp -> path. A crash at any point leaves either the old or the new file intact.
func write_snapshot_atomic(path: String, snapshot: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	# Normalise through JSON first so the checksum matches what a later parse will see.
	var norm: Variant = JSON.parse_string(JSON.stringify(snapshot))
	if typeof(norm) != TYPE_DICTIONARY:
		return false
	var body: Dictionary = norm
	body.erase("checksum")
	body["checksum"] = _checksum_of(body)
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		push_error("[SaveManager] Failed to open save file for writing: %s" % tmp)
		return false
	file.store_string(JSON.stringify(body, "	"))
	file.close()
	var abs_path := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path):
		var bak := abs_path + ".bak"
		if FileAccess.file_exists(path + ".bak"):
			DirAccess.remove_absolute(bak)
		DirAccess.rename_absolute(abs_path, bak)
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), abs_path) == OK


## Reads a snapshot, verifying its checksum; falls back to `<path>.bak` when the primary is
## missing, unparsable or corrupt. Returns { ok, data, source }.
func read_snapshot_verified(path: String) -> Dictionary:
	for candidate in [path, path + ".bak"]:
		if not FileAccess.file_exists(candidate):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(candidate))
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		var data: Dictionary = parsed
		if data.has("checksum"):
			var expect := str(data["checksum"])
			var body := data.duplicate(true)
			body.erase("checksum")
			if _checksum_of(body) != expect:
				continue
		return {"ok": true, "data": data, "source": "primary" if candidate == path else "backup"}
	return {"ok": false, "data": {}, "source": ""}


func _checksum_of(body: Dictionary) -> String:
	return JSON.stringify(body, "", true).sha256_text()


func trigger_autosave(reason: String = "auto") -> String:
	_autosave_cursor = (_autosave_cursor % maxi(1, autosave_slot_count)) + 1
	var slot_id := "autosave_%d" % _autosave_cursor
	if save_game(slot_id, "", true, reason):
		latest_autosave_slot = slot_id
		return slot_id
	return ""


func load_latest_autosave() -> bool:
	if not latest_autosave_slot.is_empty() and has_save(latest_autosave_slot):
		return load_game(latest_autosave_slot)
	for meta in list_saves():
		if bool(meta.get("is_autosave", false)):
			return load_game(str(meta.get("slot_id", "")))
	return false


func load_game(slot_id: String = "slot_1", custom_path: String = "") -> bool:
	var path := custom_path if not custom_path.is_empty() else get_slot_path(slot_id)
	var read := read_snapshot_verified(path)
	if not bool(read["ok"]):
		last_load_report = {"slot": slot_id, "source": "", "error": "missing_or_corrupt"}
		return false
	var mig := migrations.run(read["data"])
	if not bool(mig["ok"]):
		last_load_report = {"slot": slot_id, "source": read["source"], "error": mig["error"]}
		push_error("[SaveManager] Migration failed for %s: %s" % [slot_id, mig["error"]])
		return false
	last_load_report = {"slot": slot_id, "source": read["source"], "migrated_from": mig["from"], "log": mig["log"], "error": ""}
	var ok := apply_snapshot(mig["save"])
	if ok and EventBus:
		EventBus.game_loaded.emit(slot_id)
	return ok
