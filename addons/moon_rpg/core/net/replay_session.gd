class_name ReplaySession
extends RefCounted
## Deterministic Match Replay Recorder & Playback Engine (.moonreplay JSON).
## Records tick-stamped player/AI events with seed & genre metadata, writes atomic
## checksum-verified replay files to `user://moon_rpg_replays/`, and plays them back
## frame-accurately for demos, bug repro, or turn-based/real-time spectator replays.

const REPLAY_DIR := "user://moon_rpg_replays"
const FORMAT_VERSION := 1

signal recording_started(genre_id: String, seed_val: int)
signal event_recorded(entry: Dictionary)
signal playback_event_fired(entry: Dictionary)

var is_recording: bool = false
var is_playing: bool = false
var genre_id: String = ""
var seed_val: int = 0
var metadata: Dictionary = {}
var events: Array[Dictionary] = []
var checksum: String = ""

var _play_cursor: int = 0


func start_recording(genre: String, seed_value: int, meta: Dictionary = {}) -> void:
	genre_id = genre
	seed_val = seed_value
	metadata = meta.duplicate(true)
	events.clear()
	checksum = ""
	is_recording = true
	is_playing = false
	_play_cursor = 0
	recording_started.emit(genre_id, seed_val)


func record_event(tick_idx: int, actor_id: String, action: String, data: Dictionary = {}) -> Dictionary:
	if not is_recording:
		return {}
	var entry := {
		"tick": tick_idx,
		"actor": actor_id,
		"action": action,
		"data": data.duplicate(true),
	}
	events.append(entry)
	event_recorded.emit(entry)
	return entry


func stop_recording() -> String:
	is_recording = false
	checksum = compute_checksum()
	return checksum


func compute_checksum() -> String:
	var body := {
		"version": FORMAT_VERSION,
		"genre_id": genre_id,
		"seed_val": seed_val,
		"events": events,
	}
	var norm: Variant = JSON.parse_string(JSON.stringify(body))
	return JSON.stringify(norm, "", true).sha256_text()


func save_replay(file_name: String) -> bool:
	if is_recording:
		stop_recording()
	else:
		checksum = compute_checksum()
	DirAccess.make_dir_recursive_absolute(REPLAY_DIR)
	var path := file_name if (file_name.begins_with("user://") or file_name.begins_with("res://") or file_name.contains(":")) else "%s/%s.moonreplay" % [REPLAY_DIR, file_name]
	var payload := {
		"version": FORMAT_VERSION,
		"genre_id": genre_id,
		"seed_val": seed_val,
		"metadata": metadata,
		"events": events,
		"checksum": checksum,
		"saved_at": Time.get_datetime_string_from_system(),
	}
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(payload, "\t"))
	f.close()
	return true


func load_replay(file_name: String) -> bool:
	var path := file_name if (file_name.begins_with("user://") or file_name.begins_with("res://") or file_name.contains(":")) else "%s/%s.moonreplay" % [REPLAY_DIR, file_name]
	if not FileAccess.file_exists(path):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var d: Dictionary = parsed
	genre_id = str(d.get("genre_id", ""))
	seed_val = int(d.get("seed_val", 0))
	metadata = (d.get("metadata", {}) as Dictionary).duplicate(true)
	events.clear()
	for ev in d.get("events", []):
		if ev is Dictionary:
			events.append((ev as Dictionary).duplicate(true))
	checksum = str(d.get("checksum", ""))
	is_recording = false
	is_playing = false
	_play_cursor = 0
	return verify_checksum()


func verify_checksum() -> bool:
	if checksum.is_empty():
		return false
	return checksum == compute_checksum()


func start_playback() -> void:
	is_recording = false
	is_playing = true
	_play_cursor = 0


func pop_events_for_tick(current_tick: int) -> Array[Dictionary]:
	var fired: Array[Dictionary] = []
	if not is_playing:
		return fired
	while _play_cursor < events.size():
		var ev: Dictionary = events[_play_cursor]
		if int(ev.get("tick", 0)) <= current_tick:
			fired.append(ev)
			playback_event_fired.emit(ev)
			_play_cursor += 1
		else:
			break
	if _play_cursor >= events.size():
		is_playing = false
	return fired
