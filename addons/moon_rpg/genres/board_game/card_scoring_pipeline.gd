class_name CardScoringPipeline
extends RefCounted
## Balatro-Style `Base (Chips) × Mult` Relic/Joker Scoring Pipeline + Combo Detector.
## Evaluates any card play, spell cast, or minion attack through an ordered left-to-right
## list of Relics/Jokers (`add_flat`, `add_mult`, `x_mult`) and emits a step-by-step
## trace (`steps`) so the UI can animate each relic popping in sequence!

static func detect_synergies(ctx: Dictionary) -> Array[Dictionary]:
	var tags: Array[Dictionary] = []
	var combo := int(ctx.get("combo_count", 0))
	var board_cnt := int(ctx.get("board_count", 0))
	var hp_pct := float(ctx.get("player_hp_pct", 1.0))
	var action_type := str(ctx.get("action_type", ""))

	if combo >= 2 and action_type == "spell":
		tags.append({"id": "SPELL_CHAIN", "label": "法术连击", "add_mult": 0.5})
	if board_cnt >= 3 and action_type == "attack":
		tags.append({"id": "FULL_BOARD", "label": "战阵协同", "add_flat": 1.0})
	if hp_pct <= 0.40:
		tags.append({"id": "CLUTCH", "label": "绝境爆发", "add_mult": 0.5})
	return tags


static func evaluate(base_value: float, ctx: Dictionary, relics: Array[Dictionary]) -> Dictionary:
	var chips: float = maxf(0.0, base_value)
	var mult: float = 1.0
	var steps: Array[Dictionary] = []

	# 1. Built-in Synergy / Combo Bonuses
	var synergies := detect_synergies(ctx)
	for syn in synergies:
		var df := float(syn.get("add_flat", 0.0))
		var dm := float(syn.get("add_mult", 0.0))
		chips += df
		mult += dm
		var delta_txt := ("+%d基值" % int(df)) if df > 0.0 else ("+%.1f倍率" % dm)
		steps.append({
			"source_id": str(syn["id"]),
			"label": str(syn["label"]),
			"delta_text": delta_txt,
			"chips": chips,
			"mult": mult,
			"total": int(round(chips * mult)),
		})

	# 2. Ordered Left-to-Right Relic / Joker Chain (Balatro order matters!)
	var action_type := str(ctx.get("action_type", ""))
	var card_tag := str(ctx.get("card_tag", ""))
	var combo := int(ctx.get("combo_count", 0))

	for relic in relics:
		var cond := str(relic.get("when", "always"))
		var matched := false
		match cond:
			"always":
				matched = true
			"spell":
				matched = (action_type == "spell")
			"attack":
				matched = (action_type == "attack")
			"combo":
				matched = (combo >= 2)
			"fire":
				matched = (card_tag == "fire")
			"low_hp":
				matched = (float(ctx.get("player_hp_pct", 1.0)) <= 0.50)
			_:
				matched = (cond == action_type or cond == card_tag)
		if not matched:
			continue

		var af := float(relic.get("add_flat", 0.0))
		var am := float(relic.get("add_mult", 0.0))
		var xm := float(relic.get("x_mult", 1.0))
		if bool(relic.get("scale_with_combo", false)) and combo > 0:
			af *= float(combo)
			am *= float(combo)

		chips += af
		mult += am
		if xm > 0.0 and not is_equal_approx(xm, 1.0):
			mult *= xm

		var parts: Array[String] = []
		if af > 0.0:
			parts.append("+%d" % int(round(af)))
		if am > 0.0:
			parts.append("+%.1f倍" % am)
		if not is_equal_approx(xm, 1.0):
			parts.append("×%.1f!" % xm)
		steps.append({
			"source_id": str(relic.get("id", "relic")),
			"label": str(relic.get("name", "圣物")),
			"delta_text": " ".join(parts),
			"chips": chips,
			"mult": mult,
			"total": int(round(chips * mult)),
		})

	var final_total := maxi(0, int(round(chips * mult)))
	return {
		"base_value": base_value,
		"final_chips": chips,
		"final_mult": mult,
		"final_total": final_total,
		"steps": steps,
		"synergies": synergies,
	}
