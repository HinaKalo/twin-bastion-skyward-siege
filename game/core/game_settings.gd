class_name GameSettings
extends RefCounted
## Persistent player settings (audio volumes, screen shake, damage numbers) stored in user://twin_bastion_settings.json.
## `apply()` creates dedicated "BGM" / "SFX" audio buses and routes AudioManager's players to them.

const SETTINGS_PATH := "user://twin_bastion_settings.json"

static var bgm_volume: float = 0.75
static var sfx_volume: float = 0.85
static var screen_shake: bool = true
static var damage_numbers: bool = true
static var save_path: String = SETTINGS_PATH


static func load_settings() -> void:
	if not FileAccess.file_exists(save_path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var d: Dictionary = parsed
	bgm_volume = clampf(float(d.get("bgm_volume", bgm_volume)), 0.0, 1.0)
	sfx_volume = clampf(float(d.get("sfx_volume", sfx_volume)), 0.0, 1.0)
	screen_shake = bool(d.get("screen_shake", screen_shake))
	damage_numbers = bool(d.get("damage_numbers", damage_numbers))


static func save_settings() -> bool:
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify({
		"bgm_volume": bgm_volume, "sfx_volume": sfx_volume,
		"screen_shake": screen_shake, "damage_numbers": damage_numbers,
	}, "\t"))
	f.close()
	return true


static func _ensure_bus(bus_name: String) -> int:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master")
	return idx


static func apply(audio_manager: Node = null) -> void:
	var bgm_idx := _ensure_bus("BGM")
	var sfx_idx := _ensure_bus("SFX")
	AudioServer.set_bus_volume_db(bgm_idx, linear_to_db(maxf(0.0001, bgm_volume)))
	AudioServer.set_bus_mute(bgm_idx, bgm_volume <= 0.001)
	AudioServer.set_bus_volume_db(sfx_idx, linear_to_db(maxf(0.0001, sfx_volume)))
	AudioServer.set_bus_mute(sfx_idx, sfx_volume <= 0.001)
	if audio_manager == null:
		return
	for key in ["_bgm_a", "_bgm_b"]:
		var p: Variant = audio_manager.get(key)
		if p is AudioStreamPlayer:
			(p as AudioStreamPlayer).bus = "BGM"
	var pool: Variant = audio_manager.get("_sfx_pool")
	if pool is Array:
		for p in pool:
			if p is AudioStreamPlayer:
				(p as AudioStreamPlayer).bus = "SFX"
