class_name AttackTokenPool
extends RefCounted
## Shared attack tokens for enemy groups.
##
## Enemies request a token before committing to a telegraphed attack. Separate budgets cap how
## many may stand in melee range, how many may shoot, and how many distinct dangers may be live on
## screen at once. Tier weights let elites take precedence. Tokens expire automatically so a
## killed or stunned holder never deadlocks the group.

const TIERS := {"fodder": 1, "soldier": 2, "rival": 3, "elite": 4}

var limits: Dictionary = {"melee": 2, "ranged": 2, "danger": 3}
var holders: Dictionary = {} # holder_id -> { kind, tier, expires_tick }
var denials: Array[Dictionary] = []


func configure(melee: int, ranged: int, danger: int) -> void:
	limits = {"melee": melee, "ranged": ranged, "danger": danger}


func count(kind: String) -> int:
	var n := 0
	for h in holders.values():
		if str(h["kind"]) == kind:
			n += 1
	return n


## Requests a token. `kind`: melee | ranged. Each token also consumes one "danger" slot.
## An elite may preempt the lowest-tier holder of the same kind.
func request(holder_id: String, kind: String, tier: int = 1, now_tick: int = 0, ttl_ticks: int = 90) -> bool:
	expire(now_tick)
	if holders.has(holder_id):
		holders[holder_id]["expires_tick"] = now_tick + ttl_ticks
		return true
	var full_kind := count(kind) >= int(limits.get(kind, 1))
	var full_danger := holders.size() >= int(limits.get("danger", 3))
	if full_kind or full_danger:
		var victim := _lowest_tier_holder(kind if full_kind else "")
		if tier >= 4 and not victim.is_empty() and int(holders[victim]["tier"]) < tier:
			holders.erase(victim)
		else:
			denials.append({"holder": holder_id, "kind": kind, "tick": now_tick, "reason": "%s_full" % (kind if full_kind else "danger")})
			return false
	holders[holder_id] = {"kind": kind, "tier": tier, "expires_tick": now_tick + ttl_ticks}
	return true


func release(holder_id: String) -> void:
	holders.erase(holder_id)


func expire(now_tick: int) -> void:
	for hid in holders.keys():
		if int(holders[hid]["expires_tick"]) <= now_tick:
			holders.erase(hid)


func _lowest_tier_holder(kind: String) -> String:
	var best := ""
	var best_tier := 99
	for hid in holders.keys():
		var h: Dictionary = holders[hid]
		if (kind.is_empty() or str(h["kind"]) == kind) and int(h["tier"]) < best_tier:
			best_tier = int(h["tier"])
			best = hid
	return best


static func tier_of(name: String) -> int:
	return int(TIERS.get(name, 1))
