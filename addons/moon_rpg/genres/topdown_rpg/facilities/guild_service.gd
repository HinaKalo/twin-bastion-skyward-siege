class_name GuildService
extends RefCounted
## Adventurer / Bracer Guild Service (Trails in the Sky style).
## Manages Guild Rank (F -> E -> D -> C -> B -> A -> S), Guild Points (BP),
## Rank-Gated Commission Board, and shop discount tiers.

signal rank_promoted(old_rank: String, new_rank: String)

const RANK_THRESHOLDS := [
	["F", 0],
	["E", 20],
	["D", 50],
	["C", 100],
	["B", 180],
	["A", 300],
	["S", 500],
]

var guild_points: int = 0
var rank: String = "F"
var _commissions: Dictionary = {} # commission_id -> { id, title, min_rank, bp_reward, gold_reward, item_rewards, status }


func get_rank_index(rank_letter: String) -> int:
	for i in range(RANK_THRESHOLDS.size()):
		if str(RANK_THRESHOLDS[i][0]) == rank_letter:
			return i
	return 0


func add_guild_points(amount: int) -> bool:
	if amount <= 0:
		return false
	guild_points += amount
	var prev := rank
	for entry in RANK_THRESHOLDS:
		if guild_points >= int(entry[1]):
			rank = str(entry[0])
	if StoryBlackboard:
		StoryBlackboard.set_var("guild_rank", rank, false)
		StoryBlackboard.set_var("guild_bp", guild_points, true)
	if rank != prev:
		rank_promoted.emit(prev, rank)
		return true
	return false


## Returns a shop discount multiplier (e.g., Rank F = 0%, Rank S = 18% off).
func get_shop_discount() -> float:
	return float(get_rank_index(rank)) * 0.03


func register_commission(comm_id: String, title: String, min_rank: String = "F", bp_reward: int = 15, gold_reward: int = 80, quest_id: String = "") -> void:
	_commissions[comm_id] = {
		"id": comm_id,
		"title": title,
		"min_rank": min_rank,
		"bp_reward": bp_reward,
		"gold_reward": gold_reward,
		"quest_id": quest_id,
		"status": "open", # "open" | "accepted" | "completed"
	}


func get_available_commissions() -> Array[Dictionary]:
	var my_idx := get_rank_index(rank)
	var out: Array[Dictionary] = []
	for cid in _commissions.keys():
		var c: Dictionary = _commissions[cid]
		if str(c["status"]) == "open" and get_rank_index(str(c["min_rank"])) <= my_idx:
			out.append(c)
	return out


func accept_commission(comm_id: String) -> bool:
	if not _commissions.has(comm_id):
		return false
	var c: Dictionary = _commissions[comm_id]
	if str(c["status"]) != "open" or get_rank_index(str(c["min_rank"])) > get_rank_index(rank):
		return false
	c["status"] = "accepted"
	if not str(c["quest_id"]).is_empty() and QuestManager:
		QuestManager.start_quest(str(c["quest_id"]))
	return true


func complete_commission(comm_id: String) -> bool:
	if not _commissions.has(comm_id):
		return false
	var c: Dictionary = _commissions[comm_id]
	if str(c["status"]) != "accepted":
		return false
	c["status"] = "completed"
	if InventoryManager and int(c["gold_reward"]) > 0:
		InventoryManager.add_gold(int(c["gold_reward"]))
	add_guild_points(int(c["bp_reward"]))
	return true


func serialize() -> Dictionary:
	return {
		"guild_points": guild_points,
		"rank": rank,
		"commissions": _commissions.duplicate(true),
	}


func deserialize(data: Dictionary) -> void:
	if data.is_empty():
		return
	guild_points = int(data.get("guild_points", 0))
	rank = str(data.get("rank", "F"))
	_commissions = data.get("commissions", {}).duplicate(true)
