class_name EnemyAudit
extends RefCounted
## Content audit for enemy rosters.
##
## - Every enemy declares a tier (fodder / soldier / rival / elite); missing tiers are reported.
## - "Reskin with only HP changed": two enemies whose behaviour-relevant fields are identical
##   (moves, ranges, windup, cooldown, speed, poise, tier) but differ only in max_hp / rewards are
##   flagged, so a roster cannot silently pad variety with HP sponges.
## - Rivals must declare at least one readable counter/opening; elites at least two moves.

const IGNORED_FIELDS := ["id", "name_key", "actor_key", "max_hp", "xp_reward", "gold_reward", "mastery_xp", "drops", "skin", "palette"]


static func behaviour_signature(def: Dictionary) -> String:
	var keys := def.keys()
	keys.sort()
	var parts: PackedStringArray = []
	for k in keys:
		if IGNORED_FIELDS.has(str(k)):
			continue
		parts.append("%s=%s" % [k, JSON.stringify(def[k], "", true)])
	return "|".join(parts)


static func audit(enemies: Array) -> Dictionary:
	var issues: Array[Dictionary] = []
	var by_sig: Dictionary = {}
	for e in enemies:
		var d: Dictionary = e
		var eid := str(d.get("id", "?"))
		var tier := str(d.get("tier", ""))
		if not AttackTokenPool.TIERS.has(tier):
			issues.append({"enemy": eid, "issue": "missing_tier"})
		var moves: Array = d.get("moves", [])
		if tier == "rival" and not d.has("openings"):
			issues.append({"enemy": eid, "issue": "rival_without_openings"})
		if tier == "elite" and moves.size() < 2:
			issues.append({"enemy": eid, "issue": "elite_needs_two_moves"})
		var sig := behaviour_signature(d)
		if not by_sig.has(sig):
			by_sig[sig] = []
		by_sig[sig].append(eid)
	var reskins: Array = []
	for sig in by_sig.keys():
		if (by_sig[sig] as Array).size() > 1:
			reskins.append(by_sig[sig])
			issues.append({"enemy": ",".join(PackedStringArray(by_sig[sig])), "issue": "hp_only_variants"})
	return {"issues": issues, "hp_only_groups": reskins}
