class_name StrategyVictory
extends RefCounted
## Multi-Path 4X Victory Evaluator (Domination / Science / Economic / Turn-Limit Score).

var science_victory_tech: String = "star_navigation"
var economic_gold_goal: float = 500.0
var turn_limit: int = 40


## Returns { "winner": String, "type": String, "label": String } (empty winner if ongoing).
func evaluate(
	factions: Array[String],
	city_mgr: CityManager,
	techs: Dictionary, # faction_id -> TechTree
	ledgers: Dictionary, # faction_id -> ResourceLedger
	turn_number: int
) -> Dictionary:
	# 1. Domination Victory: only 1 faction still owns cities
	var alive_factions: Array[String] = []
	for f in factions:
		if not city_mgr.get_faction_cities(f).is_empty():
			alive_factions.append(f)
	if alive_factions.size() == 1:
		return {"winner": alive_factions[0], "type": "DOMINATION", "label": "征服胜利（统一大陆所有城邦）"}

	# 2. Science Victory: unlocked capstone tech
	for f in factions:
		if techs.has(f) and (techs[f] as TechTree).is_unlocked(science_victory_tech):
			return {"winner": f, "type": "SCIENCE", "label": "科技胜利（完成终极科技【%s】）" % science_victory_tech}

	# 3. Economic Victory: treasury reached gold goal
	for f in factions:
		if ledgers.has(f) and (ledgers[f] as ResourceLedger).get_amount("gold") >= economic_gold_goal:
			return {"winner": f, "type": "ECONOMIC", "label": "经济胜利（国库储备突破 %dG）" % int(economic_gold_goal)}

	# 4. Score Victory at turn limit
	if turn_limit > 0 and turn_number >= turn_limit:
		var best_f := factions[0]
		var best_score := -1.0
		for f in factions:
			var sc := compute_score(f, city_mgr, techs.get(f), ledgers.get(f))
			if sc > best_score:
				best_score = sc
				best_f = f
		return {"winner": best_f, "type": "SCORE", "label": "分数胜利（总国力 %.0f 分）" % best_score}

	return {"winner": "", "type": "", "label": ""}


func compute_score(faction_id: String, city_mgr: CityManager, tech: TechTree, ledger: ResourceLedger) -> float:
	var score := 0.0
	for c in city_mgr.get_faction_cities(faction_id):
		score += 50.0 + float(int(c["population"])) * 15.0 + float((c["buildings"] as Array).size()) * 12.0
	if tech != null:
		score += float(tech.unlocked.size()) * 35.0
	if ledger != null:
		score += ledger.get_amount("gold") * 0.25
	return score
