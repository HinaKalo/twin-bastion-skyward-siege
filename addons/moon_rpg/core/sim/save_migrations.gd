class_name SaveMigrationRegistry
extends RefCounted
## Versioned save migration registry with dry-run preview and provenance.
##
## Register `migrate(from_version, fn)` where `fn(save: Dictionary, trail: Array) -> Dictionary`
## upgrades a save from `from_version` to `from_version + 1`. `run()` chains them, and every
## step appends provenance lines ({ step, field, from, to, note }) so a save can explain
## which version each field came from. `preview()` runs on a deep copy (batch dry runs).

var _steps: Dictionary = {} # from_version -> { fn, label }
var current_version: int = 1


func _init(target_version: int = 1) -> void:
	current_version = target_version


func migrate(from_version: int, fn: Callable, label: String = "") -> void:
	_steps[from_version] = {"fn": fn, "label": label if not label.is_empty() else "v%d->v%d" % [from_version, from_version + 1]}
	current_version = maxi(current_version, from_version + 1)


func has_path(from_version: int) -> bool:
	var v := from_version
	while v < current_version:
		if not _steps.has(v):
			return false
		v += 1
	return true


## Applies all steps. Returns { ok, save, from, to, trail, error }.
func run(save: Dictionary, version_key: String = "schema_version") -> Dictionary:
	var data := save
	var from := int(data.get(version_key, 1))
	var trail: Array = []
	var v := from
	while v < current_version:
		if not _steps.has(v):
			return {"ok": false, "save": data, "from": from, "to": v, "log": trail, "error": "missing_migration_v%d" % v}
		var step: Dictionary = _steps[v]
		var before_log := trail.size()
		data = (step["fn"] as Callable).call(data, trail)
		for i in range(before_log, trail.size()):
			(trail[i] as Dictionary)["step"] = str(step["label"])
		v += 1
		data[version_key] = v
	return {"ok": true, "save": data, "from": from, "to": v, "log": trail, "error": ""}


## Dry-run on a deep copy; the input save is never mutated.
func preview(save: Dictionary, version_key: String = "schema_version") -> Dictionary:
	return run(save.duplicate(true), version_key)


## Batch dry-run over a sample library. Returns per-sample summaries.
func preview_batch(saves: Array, version_key: String = "schema_version") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s in saves:
		var r := preview(s, version_key)
		out.append({"ok": r["ok"], "from": r["from"], "to": r["to"], "changes": (r["log"] as Array).size(), "error": r["error"]})
	return out


## Helper for the common "numeric room index -> stable area id" migration.
## Logs unmapped rooms as conflicts instead of silently dropping them.
static func map_room_ids(save: Dictionary, trail: Array, field_path: Array, mapping: Dictionary) -> Dictionary:
	var node: Variant = save
	for i in range(field_path.size() - 1):
		if typeof(node) != TYPE_DICTIONARY or not (node as Dictionary).has(field_path[i]):
			return save
		node = node[field_path[i]]
	var leaf: String = field_path.back()
	if typeof(node) != TYPE_DICTIONARY or not (node as Dictionary).has(leaf):
		return save
	var old: Variant = node[leaf]
	var key := str(old)
	if mapping.has(key):
		node[leaf] = mapping[key]
		trail.append({"field": ".".join(field_path), "from": old, "to": mapping[key], "note": "room_id_remap"})
	else:
		trail.append({"field": ".".join(field_path), "from": old, "to": old, "note": "conflict:unmapped_room"})
	return save
