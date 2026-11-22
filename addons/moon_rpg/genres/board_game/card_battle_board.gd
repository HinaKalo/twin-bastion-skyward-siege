class_name CardBattleBoard
extends RefCounted
## Hearthstone × Balatro Hybrid Card Battle Board (Pure-Data, Headless-Testable).
## Combines `DeckManager`, `CardRuleMachine`, and `CardScoringPipeline` into a
## complete turn-based card game core supporting:
## - Mana curve (1..10), dual-side Heroes (HP / Armor / Mana), up to 4 Minion slots per side
## - Hearthstone Keywords: TAUNT, CHARGE, DIVINE_SHIELD, BATTLECRY, DEATHRATTLE, LIFESTEAL
## - Balatro Relics / Jokers (up to 5 slots) with ordered Chips × Mult evaluation
## - Smart Enemy AI (curve play, taunt compliance, lethal detection)
## - Multi-stage boss progression with Post-Stage Relic Draft phase.

signal board_changed()
signal scoring_evaluated(result: Dictionary, context_label: String)
signal combat_event(text: String, kind: String)
signal stage_cleared(stage_index: int)
signal match_ended(won: bool)

const MAX_BOARD_SIZE := 4
const MAX_RELIC_SLOTS := 5
const MANA_CAP := 10

var rules := CardRuleMachine.new()
var deck := DeckManager.new()

var stage_index: int = 1
var total_stages: int = 2
var cards_played_this_turn: int = 0

var player: Dictionary = {}
var enemy: Dictionary = {}
var player_minions: Array[Dictionary] = []
var enemy_minions: Array[Dictionary] = []
var relics: Array[Dictionary] = []

var _enemy_deck: Array[Dictionary] = []
var _minion_seq: int = 0


func _init() -> void:
	_register_core_handlers()


func _register_core_handlers() -> void:
	rules.register_effect_handler("damage", _handle_damage_effect)
	rules.register_effect_handler("aoe_enemy", _handle_aoe_enemy_effect)
	rules.register_effect_handler("heal_hero", _handle_heal_hero_effect)
	rules.register_effect_handler("gain_armor", _handle_gain_armor_effect)
	rules.register_effect_handler("draw", _handle_draw_effect)
	rules.register_effect_handler("buff_allies", _handle_buff_allies_effect)
	rules.register_effect_handler("summon_token", _handle_summon_token_effect)


func setup_match(player_cards: Array[Dictionary], boss_def: Dictionary, starter_relics: Array[Dictionary] = [], seed_val: int = 0) -> void:
	rules.reset()
	deck = DeckManager.new(seed_val)
	deck.max_hand_size = 7
	stage_index = int(boss_def.get("stage_index", 1))
	cards_played_this_turn = 0
	player_minions.clear()
	enemy_minions.clear()
	relics.clear()
	_minion_seq = 0

	player = {
		"id": "player_hero",
		"name": "酒馆旅者",
		"hp": 30,
		"max_hp": 30,
		"armor": 0,
		"mana": 0,
		"max_mana": 0,
	}
	for cdef in player_cards:
		deck.add_card(cdef, "draw")
	deck.shuffle_draw_pile()

	for r in starter_relics:
		add_relic(r)

	_load_boss(boss_def)
	deck.draw(3)
	start_player_turn()


func start_next_stage(boss_def: Dictionary) -> void:
	stage_index = int(boss_def.get("stage_index", stage_index + 1))
	player["hp"] = mini(int(player["max_hp"]), int(player["hp"]) + 10)
	player["armor"] = 0
	player["mana"] = 0
	player["max_mana"] = 0
	player_minions.clear()
	enemy_minions.clear()
	deck.discard_hand()
	deck.reshuffle_discard_into_draw()
	_load_boss(boss_def)
	deck.draw(3)
	rules.set_phase(CardRuleMachine.Phase.IDLE)
	start_player_turn()


func _load_boss(boss_def: Dictionary) -> void:
	enemy = {
		"id": "enemy_hero",
		"name": str(boss_def.get("name", "哥布林牌王")),
		"portrait": str(boss_def.get("portrait", "enemy_goblin.png")),
		"hp": int(boss_def.get("hp", 22)),
		"max_hp": int(boss_def.get("hp", 22)),
		"armor": int(boss_def.get("armor", 0)),
		"mana": 0,
		"max_mana": 0,
	}
	_enemy_deck.clear()
	for ec in boss_def.get("deck", []):
		if ec is Dictionary:
			_enemy_deck.append((ec as Dictionary).duplicate(true))


func add_relic(relic_def: Dictionary) -> bool:
	if relics.size() >= MAX_RELIC_SLOTS:
		return false
	relics.append(relic_def.duplicate(true))
	board_changed.emit()
	return true


func start_player_turn() -> void:
	if rules.current_phase == CardRuleMachine.Phase.VICTORY or rules.current_phase == CardRuleMachine.Phase.DEFEAT:
		return
	rules.set_phase(CardRuleMachine.Phase.ROUND_START)
	cards_played_this_turn = 0
	player["max_mana"] = mini(MANA_CAP, int(player["max_mana"]) + 1)
	player["mana"] = int(player["max_mana"])
	for m in player_minions:
		m["can_attack"] = true
	rules.emit_trigger("ON_TURN_START", {"side": "player", "turn": rules.turn_number})

	rules.set_phase(CardRuleMachine.Phase.DRAW)
	deck.draw(1)

	rules.set_phase(CardRuleMachine.Phase.MAIN_ACTION)
	rules.flush_queue()
	board_changed.emit()


func can_play_card(uid: String) -> Dictionary:
	if rules.current_phase != CardRuleMachine.Phase.MAIN_ACTION:
		return {"ok": false, "reason": "非玩家行动阶段"}
	var card := _find_hand_card(uid)
	if card.is_empty():
		return {"ok": false, "reason": "手牌不存在"}
	var cost := int(card.get("cost", 0))
	if int(player["mana"]) < cost:
		return {"ok": false, "reason": "法力不足"}
	if str(card.get("type", "minion")) == "minion" and player_minions.size() >= MAX_BOARD_SIZE:
		return {"ok": false, "reason": "战场已满(最多4随从)"}
	return {"ok": true, "card": card}


func play_card(uid: String, target_id: String = "enemy_hero") -> Dictionary:
	var chk := can_play_card(uid)
	if not bool(chk["ok"]):
		return chk
	var card: Dictionary = chk["card"]
	var cost := int(card.get("cost", 0))
	player["mana"] = int(player["mana"]) - cost
	deck.play_card(uid, bool(card.get("exhaust", false)))
	cards_played_this_turn += 1

	var ctype := str(card.get("type", "minion"))
	if ctype == "minion":
		var minion := _spawn_minion("player", card)
		combat_event.emit("召唤【%s】(%d/%d)" % [minion["name"], minion["atk"], minion["hp"]], "summon")
		rules.emit_trigger("ON_MINION_SUMMON", {"side": "player", "minion": minion})
		# Battlecry effect!
		var bc: Dictionary = card.get("battlecry", {})
		if not bc.is_empty():
			var eff := bc.duplicate(true)
			eff["side"] = "player"
			eff["source_name"] = str(card.get("name", ""))
			eff["target_id"] = target_id
			eff["card_tag"] = str(card.get("tag", ""))
			rules.enqueue_effect(eff)
	else:
		# Spell card evaluated through Balatro Scoring Pipeline!
		var eff: Dictionary = (card.get("effect", {}) as Dictionary).duplicate(true)
		eff["side"] = "player"
		eff["source_name"] = str(card.get("name", ""))
		eff["target_id"] = target_id
		eff["card_tag"] = str(card.get("tag", ""))
		eff["is_spell"] = true
		rules.enqueue_effect(eff)

	rules.emit_trigger("ON_CARD_PLAYED", {"side": "player", "card": card})
	rules.flush_queue()
	_check_deaths_and_victory()
	board_changed.emit()
	return {"ok": true, "card": card}


func get_valid_attack_targets(attacker_side: String) -> Array[String]:
	var opp_minions := enemy_minions if attacker_side == "player" else player_minions
	var opp_hero_id := "enemy_hero" if attacker_side == "player" else "player_hero"
	var taunts: Array[String] = []
	for m in opp_minions:
		if has_keyword(m, "TAUNT") and int(m["hp"]) > 0:
			taunts.append(str(m["uid"]))
	if not taunts.is_empty():
		return taunts
	var all_targets: Array[String] = [opp_hero_id]
	for m in opp_minions:
		if int(m["hp"]) > 0:
			all_targets.append(str(m["uid"]))
	return all_targets


func attack_with_minion(attacker_uid: String, target_id: String) -> Dictionary:
	if rules.current_phase != CardRuleMachine.Phase.MAIN_ACTION:
		return {"ok": false, "reason": "非玩家行动阶段"}
	var attacker := _find_minion("player", attacker_uid)
	if attacker.is_empty():
		return {"ok": false, "reason": "随从不存在"}
	if not bool(attacker.get("can_attack", false)):
		return {"ok": false, "reason": "该随从本回合已行动或召唤失调"}
	var valid := get_valid_attack_targets("player")
	if not valid.has(target_id):
		return {"ok": false, "reason": "必须先攻击带有【嘲讽】的随从！"}

	attacker["can_attack"] = false
	var eval_res := _evaluate_player_value(float(attacker["atk"]), "attack", str(attacker.get("tag", "")))
	var dmg := int(eval_res["final_total"])
	scoring_evaluated.emit(eval_res, "%s 攻击" % str(attacker["name"]))

	_apply_damage_to_target(target_id, dmg, "player", has_keyword(attacker, "LIFESTEAL"))
	# Counter-damage if target is a minion
	var def_minion := _find_minion("enemy", target_id)
	if not def_minion.is_empty() and int(def_minion["atk"]) > 0:
		_apply_damage_to_minion(attacker, int(def_minion["atk"]))

	rules.flush_queue()
	_check_deaths_and_victory()
	board_changed.emit()
	return {"ok": true, "damage": dmg, "scoring": eval_res}


func end_player_turn() -> void:
	if rules.current_phase != CardRuleMachine.Phase.MAIN_ACTION:
		return
	rules.emit_trigger("ON_TURN_END", {"side": "player"})
	rules.flush_queue()
	if _is_terminal_or_draft():
		board_changed.emit()
		return

	rules.set_phase(CardRuleMachine.Phase.ENEMY_TURN)
	_run_enemy_ai()
	if _is_terminal_or_draft():
		board_changed.emit()
		return

	rules.set_phase(CardRuleMachine.Phase.ROUND_END)
	start_player_turn()


func _run_enemy_ai() -> void:
	enemy["max_mana"] = mini(MANA_CAP, int(enemy["max_mana"]) + 1)
	enemy["mana"] = int(enemy["max_mana"])
	for m in enemy_minions:
		m["can_attack"] = true

	# 1. Play cards from enemy deck curve (up to 2 plays per turn)
	var plays := 0
	for cdef in _enemy_deck:
		if plays >= 2:
			break
		var cost := int(cdef.get("cost", 1))
		if int(enemy["mana"]) < cost:
			continue
		if str(cdef.get("type", "minion")) == "minion":
			if enemy_minions.size() >= MAX_BOARD_SIZE:
				continue
			enemy["mana"] = int(enemy["mana"]) - cost
			var em := _spawn_minion("enemy", cdef)
			combat_event.emit("敌方召唤【%s】(%d/%d)" % [em["name"], em["atk"], em["hp"]], "enemy")
			plays += 1
		else:
			enemy["mana"] = int(enemy["mana"]) - cost
			var eff: Dictionary = (cdef.get("effect", {}) as Dictionary).duplicate(true)
			eff["side"] = "enemy"
			eff["source_name"] = str(cdef.get("name", "敌方法术"))
			eff["target_id"] = "player_hero"
			rules.enqueue_effect(eff)
			plays += 1
	rules.flush_queue()
	_check_deaths_and_victory()
	if _is_terminal_or_draft():
		return

	# 2. Attack with ready enemy minions (respect TAUNT, go lethal if possible)
	var attackers := enemy_minions.duplicate()
	for em in attackers:
		if int(em["hp"]) <= 0 or not bool(em.get("can_attack", false)):
			continue
		var valid := get_valid_attack_targets("enemy")
		if valid.is_empty():
			break
		var chosen := valid[0]
		if valid.has("player_hero"):
			# Go face if lethal or no dangerous player minion
			if int(em["atk"]) >= int(player["hp"]) + int(player["armor"]) or player_minions.is_empty():
				chosen = "player_hero"
			else:
				# Trade into highest-attack player minion
				var best_uid := "player_hero"
				var best_atk := -1
				for pm in player_minions:
					if valid.has(str(pm["uid"])) and int(pm["atk"]) > best_atk:
						best_atk = int(pm["atk"])
						best_uid = str(pm["uid"])
				chosen = best_uid
		em["can_attack"] = false
		_apply_damage_to_target(chosen, int(em["atk"]), "enemy", has_keyword(em, "LIFESTEAL"))
		var pdef := _find_minion("player", chosen)
		if not pdef.is_empty() and int(pdef["atk"]) > 0:
			_apply_damage_to_minion(em, int(pdef["atk"]))
		rules.flush_queue()
		_check_deaths_and_victory()
		if _is_terminal_or_draft():
			return


func _evaluate_player_value(base_val: float, action_type: String, card_tag: String) -> Dictionary:
	var ctx := {
		"action_type": action_type,
		"card_tag": card_tag,
		"combo_count": cards_played_this_turn,
		"board_count": player_minions.size(),
		"player_hp_pct": float(player["hp"]) / maxf(1.0, float(player["max_hp"])),
	}
	return CardScoringPipeline.evaluate(base_val, ctx, relics)


func _spawn_minion(side: String, card_def: Dictionary) -> Dictionary:
	_minion_seq += 1
	var kws: Array[String] = []
	for k in card_def.get("keywords", []):
		kws.append(str(k))
	var m := {
		"uid": "%s_m_%d" % [side, _minion_seq],
		"card_id": str(card_def.get("id", "minion")),
		"name": str(card_def.get("name", "随从")),
		"sprite": str(card_def.get("sprite", "npc_guard.png")),
		"tag": str(card_def.get("tag", "")),
		"atk": int(card_def.get("atk", 2)),
		"hp": int(card_def.get("hp", 2)),
		"max_hp": int(card_def.get("hp", 2)),
		"keywords": kws,
		"divine_shield": kws.has("DIVINE_SHIELD"),
		"can_attack": kws.has("CHARGE"),
		"deathrattle": (card_def.get("deathrattle", {}) as Dictionary).duplicate(true),
		"side": side,
	}
	if side == "player":
		player_minions.append(m)
	else:
		enemy_minions.append(m)
	return m


func has_keyword(minion: Dictionary, kw: String) -> bool:
	if kw == "DIVINE_SHIELD":
		return bool(minion.get("divine_shield", false))
	var kws: Array = minion.get("keywords", [])
	return kws.has(kw)


func _apply_damage_to_target(target_id: String, amount: int, source_side: String, lifesteal: bool = false) -> int:
	if amount <= 0:
		return 0
	var dealt := 0
	if target_id == "enemy_hero":
		dealt = _damage_hero(enemy, amount)
		combat_event.emit("对【%s】造成 %d 点伤害！" % [enemy["name"], dealt], "damage")
	elif target_id == "player_hero":
		dealt = _damage_hero(player, amount)
		combat_event.emit("【%s】受到 %d 点伤害！" % [player["name"], dealt], "enemy")
	else:
		var m := _find_minion("enemy", target_id)
		if m.is_empty():
			m = _find_minion("player", target_id)
		if not m.is_empty():
			dealt = _apply_damage_to_minion(m, amount)
			combat_event.emit("【%s】受到 %d 点伤害" % [m["name"], dealt], "damage")

	if lifesteal and dealt > 0:
		var h := player if source_side == "player" else enemy
		h["hp"] = mini(int(h["max_hp"]), int(h["hp"]) + dealt)
		combat_event.emit("吸血回复 +%d HP" % dealt, "heal")
	rules.emit_trigger("ON_DAMAGE", {"target_id": target_id, "amount": dealt, "source_side": source_side})
	return dealt


func _damage_hero(hero: Dictionary, amount: int) -> int:
	var rem := amount
	var arm := int(hero["armor"])
	if arm > 0:
		var absorbed := mini(arm, rem)
		hero["armor"] = arm - absorbed
		rem -= absorbed
	if rem > 0:
		hero["hp"] = maxi(0, int(hero["hp"]) - rem)
	return amount


func _apply_damage_to_minion(m: Dictionary, amount: int) -> int:
	if amount <= 0:
		return 0
	if bool(m.get("divine_shield", false)):
		m["divine_shield"] = false
		combat_event.emit("【%s】的圣盾抵挡了伤害！" % m["name"], "shield")
		return 0
	m["hp"] = int(m["hp"]) - amount
	return amount


func _check_deaths_and_victory() -> void:
	for side_pair in [["player", player_minions], ["enemy", enemy_minions]]:
		var side: String = side_pair[0]
		var arr: Array[Dictionary] = side_pair[1]
		for i in range(arr.size() - 1, -1, -1):
			if int(arr[i]["hp"]) <= 0:
				var dead: Dictionary = arr[i]
				arr.remove_at(i)
				combat_event.emit("【%s】阵亡！" % dead["name"], "death")
				rules.emit_trigger("ON_MINION_DEATH", {"side": side, "minion": dead})
				var dr: Dictionary = dead.get("deathrattle", {})
				if not dr.is_empty():
					var eff := dr.duplicate(true)
					eff["side"] = side
					eff["source_name"] = str(dead["name"]) + "(亡语)"
					rules.enqueue_effect(eff)
	if not rules.effect_queue.is_empty():
		rules.flush_queue()

	if int(player["hp"]) <= 0:
		rules.set_phase(CardRuleMachine.Phase.DEFEAT)
		match_ended.emit(false)
	elif int(enemy["hp"]) <= 0:
		if stage_index < total_stages:
			rules.set_phase(CardRuleMachine.Phase.RELIC_DRAFT)
			stage_cleared.emit(stage_index)
		else:
			rules.set_phase(CardRuleMachine.Phase.VICTORY)
			match_ended.emit(true)


func _is_terminal_or_draft() -> bool:
	var p := rules.current_phase
	return p == CardRuleMachine.Phase.VICTORY or p == CardRuleMachine.Phase.DEFEAT or p == CardRuleMachine.Phase.RELIC_DRAFT


func _handle_damage_effect(eff: Dictionary) -> void:
	var side := str(eff.get("side", "player"))
	var base_amt := float(eff.get("amount", 2))
	var final_amt := int(base_amt)
	if side == "player":
		var eval_res := _evaluate_player_value(base_amt, "spell", str(eff.get("card_tag", "")))
		final_amt = int(eval_res["final_total"])
		scoring_evaluated.emit(eval_res, str(eff.get("source_name", "法术")))
	var tid := str(eff.get("target_id", "enemy_hero" if side == "player" else "player_hero"))
	_apply_damage_to_target(tid, final_amt, side, bool(eff.get("lifesteal", false)))


func _handle_aoe_enemy_effect(eff: Dictionary) -> void:
	var side := str(eff.get("side", "player"))
	var base_amt := float(eff.get("amount", 2))
	var final_amt := int(base_amt)
	if side == "player":
		var eval_res := _evaluate_player_value(base_amt, "spell", str(eff.get("card_tag", "")))
		final_amt = int(eval_res["final_total"])
		scoring_evaluated.emit(eval_res, str(eff.get("source_name", "群攻")))
	var targets := enemy_minions.duplicate() if side == "player" else player_minions.duplicate()
	for m in targets:
		_apply_damage_to_minion(m, final_amt)
	if bool(eff.get("hit_hero", true)):
		_damage_hero(enemy if side == "player" else player, final_amt)
	combat_event.emit("【%s】全场造成 %d 点范围伤害！" % [str(eff.get("source_name", "法术")), final_amt], "damage")


func _handle_heal_hero_effect(eff: Dictionary) -> void:
	var side := str(eff.get("side", "player"))
	var amt := int(eff.get("amount", 4))
	var h := player if side == "player" else enemy
	h["hp"] = mini(int(h["max_hp"]), int(h["hp"]) + amt)
	combat_event.emit("【%s】回复 +%d 生命" % [h["name"], amt], "heal")


func _handle_gain_armor_effect(eff: Dictionary) -> void:
	var side := str(eff.get("side", "player"))
	var amt := int(eff.get("amount", 4))
	var h := player if side == "player" else enemy
	h["armor"] = int(h["armor"]) + amt
	combat_event.emit("【%s】获得 +%d 护甲" % [h["name"], amt], "shield")


func _handle_draw_effect(eff: Dictionary) -> void:
	if str(eff.get("side", "player")) == "player":
		var cnt := int(eff.get("amount", 1))
		deck.draw(cnt)
		combat_event.emit("抽取 %d 张卡牌" % cnt, "draw")


func _handle_buff_allies_effect(eff: Dictionary) -> void:
	var side := str(eff.get("side", "player"))
	var arr := player_minions if side == "player" else enemy_minions
	var da := int(eff.get("atk", 1))
	var dh := int(eff.get("hp", 1))
	for m in arr:
		m["atk"] = int(m["atk"]) + da
		m["hp"] = int(m["hp"]) + dh
		m["max_hp"] = int(m["max_hp"]) + dh
	combat_event.emit("全体友军 +%d/+%d！" % [da, dh], "buff")


func _handle_summon_token_effect(eff: Dictionary) -> void:
	var side := str(eff.get("side", "player"))
	var arr := player_minions if side == "player" else enemy_minions
	if arr.size() >= MAX_BOARD_SIZE:
		return
	var token: Dictionary = eff.get("token", {"id": "token_slime", "name": "小史莱姆", "atk": 1, "hp": 1, "sprite": "enemy_slime.png"})
	_spawn_minion(side, token)


func _find_hand_card(uid: String) -> Dictionary:
	for c in deck.hand:
		if str(c.get("uid", "")) == uid:
			return c
	return {}


func _find_minion(side: String, uid: String) -> Dictionary:
	var arr := player_minions if side == "player" else enemy_minions
	for m in arr:
		if str(m.get("uid", "")) == uid:
			return m
	return {}
