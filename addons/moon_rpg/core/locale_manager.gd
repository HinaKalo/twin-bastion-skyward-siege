extends Node
## Hot-swappable externalized dialogue & UI string table manager.
## All character lines live in `content/locales/<locale>.json` keyed by stable IDs,
## so dialogue text can be edited, translated, or replaced without touching scenes or code.

const DEFAULT_LOCALE_DIR := "res://content/locales"

var current_locale: String = "zh_CN"
var _strings: Dictionary = {}
var _overrides: Dictionary = {}


func _ready() -> void:
	load_locale(current_locale)


func load_locale(locale_code: String, custom_path: String = "") -> bool:
	var base_path := custom_path if not custom_path.is_empty() else "%s/%s.json" % [DEFAULT_LOCALE_DIR, locale_code]
	if not FileAccess.file_exists(base_path):
		push_warning("[LocaleManager] Locale file not found: %s" % base_path)
		return false
	var merged: Dictionary = {}
	if not _merge_locale_file(base_path, merged):
		return false

	# Auto-merge extension files such as `zh_CN.narrative.json` from NarrativeNode sync
	if custom_path.is_empty() and DirAccess.dir_exists_absolute(DEFAULT_LOCALE_DIR):
		var dir := DirAccess.open(DEFAULT_LOCALE_DIR)
		if dir != null:
			var extras: Array[String] = []
			dir.list_dir_begin()
			var fname := dir.get_next()
			var prefix := locale_code + "."
			while not fname.is_empty():
				if not dir.current_is_dir() and fname.begins_with(prefix) and fname.ends_with(".json"):
					extras.append(fname)
				fname = dir.get_next()
			dir.list_dir_end()
			extras.sort()
			for extra_name in extras:
				_merge_locale_file("%s/%s" % [DEFAULT_LOCALE_DIR, extra_name], merged)

	current_locale = locale_code
	_strings = merged
	if EventBus:
		EventBus.locale_reloaded.emit(locale_code)
	return true


func _merge_locale_file(path: String, target: Dictionary) -> bool:
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("[LocaleManager] Invalid JSON in locale file: %s" % path)
		return false
	for k in parsed.keys():
		target[str(k)] = str(parsed[k])
	return true


func reload_current() -> bool:
	return load_locale(current_locale)


func set_override(key: String, text: String) -> void:
	_overrides[key] = text


func clear_overrides() -> void:
	_overrides.clear()


func has_key(key: String) -> bool:
	return _overrides.has(key) or _strings.has(key)


## Resolves a localization key with optional `{placeholder}` interpolation.
## If the key is not found, returns `fallback` (or the key itself if fallback is empty).
func tr_key(key: String, vars: Dictionary = {}, fallback: String = "") -> String:
	var raw := ""
	if _overrides.has(key):
		raw = str(_overrides[key])
	elif _strings.has(key):
		raw = str(_strings[key])
	else:
		raw = fallback if not fallback.is_empty() else key
	if vars.is_empty():
		return raw
	return raw.format(vars)


func export_dictionary() -> Dictionary:
	var merged := _strings.duplicate(true)
	for k in _overrides.keys():
		merged[k] = _overrides[k]
	return merged
