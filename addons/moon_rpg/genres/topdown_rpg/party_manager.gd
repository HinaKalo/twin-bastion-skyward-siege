class_name PartyManager
extends RefCounted
## Multi-Member JRPG Party Container (Active Squad up to 4 + Tavern Reserve Roster).
## Supports per-member StatBlock, elemental affinities, CP gauge, and SaveManager provider serialization.

var members: Array[Dictionary] = [] # Active squad (max 4)
var reserve: Array[Dictionary] = [] # Tavern reserve bench
var max_party_size: int = 4


func add_member(member_id: String, display_name: String, base_stats: Dictionary = {}, skills: Array = [], actor_key: String = "", affinities: Dictionary = {}) -> Dictionary:
	var existing := get_member(member_id)
	if not existing.is_empty():
		return existing
	var typed_skills: Array[String] = []
	for s in skills:
		typed_skills.append(str(s))
	var entry := {
		"id": member_id,
		"name": display_name,
		"actor_key": actor_key,
		"stat_block": StatBlock.new(base_stats),
		"skills": typed_skills,
		"affinities": affinities.duplicate(true),
		"cp": 50.0,
	}
	if members.size() < max_party_size:
		members.append(entry)
	else:
		reserve.append(entry)
	return entry


func remove_member(member_id: String) -> bool:
	for arr in [members, reserve]:
		for i in range(arr.size()):
			if str(arr[i]["id"]) == member_id:
				arr.remove_at(i)
				return true
	return false


func get_member(member_id: String) -> Dictionary:
	for m in members + reserve:
		if str(m["id"]) == member_id:
			return m
	return {}


func swap_member(active_id: String, reserve_id: String) -> bool:
	var a_idx := -1
	var r_idx := -1
	for i in range(members.size()):
		if str(members[i]["id"]) == active_id:
			a_idx = i
	for i in range(reserve.size()):
		if str(reserve[i]["id"]) == reserve_id:
			r_idx = i
	if a_idx < 0 or r_idx < 0:
		return false
	var tmp := members[a_idx]
	members[a_idx] = reserve[r_idx]
	reserve[r_idx] = tmp
	return true


func get_leader() -> Dictionary:
	return members[0] if not members.is_empty() else {}


func get_alive_members() -> Array[Dictionary]:
	var alive: Array[Dictionary] = []
	for m in members:
		if (m["stat_block"] as StatBlock).hp > 0.0:
			alive.append(m)
	return alive


func is_wiped_out() -> bool:
	return get_alive_members().is_empty()


func heal_all() -> void:
	for m in members + reserve:
		(m["stat_block"] as StatBlock).full_restore()


func serialize() -> Dictionary:
	return {
		"members": _serialize_list(members),
		"reserve": _serialize_list(reserve),
	}


func deserialize(data: Dictionary) -> void:
	members = _deserialize_list(data.get("members", []))
	reserve = _deserialize_list(data.get("reserve", []))


func _serialize_list(list: Array[Dictionary]) -> Array:
	var arr: Array = []
	for m in list:
		arr.append({
			"id": m["id"],
			"name": m["name"],
			"actor_key": m["actor_key"],
			"skills": m["skills"],
			"affinities": m.get("affinities", {}),
			"cp": float(m.get("cp", 0.0)),
			"stats": (m["stat_block"] as StatBlock).serialize(),
		})
	return arr


func _deserialize_list(raw: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in raw:
		var sb := StatBlock.new()
		sb.deserialize(entry.get("stats", {}))
		var skills: Array[String] = []
		for s in entry.get("skills", []):
			skills.append(str(s))
		out.append({
			"id": str(entry.get("id", "")),
			"name": str(entry.get("name", "")),
			"actor_key": str(entry.get("actor_key", "")),
			"stat_block": sb,
			"skills": skills,
			"affinities": entry.get("affinities", {}).duplicate(true),
			"cp": float(entry.get("cp", 0.0)),
		})
	return out
