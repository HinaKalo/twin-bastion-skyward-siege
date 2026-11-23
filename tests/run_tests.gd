extends SceneTree
## Automated Headless Verification Suite for 《双子堡垒：共守苍穹》(Twin Bastion TD)
## Never touches the player's real save: every MetaProgress here uses a scratch `save_path`.

const TEST_META := "user://_test_twin_bastion_meta.json"

var _passed: int = 0
var _failed: int = 0


func _init() -> void:
	call_deferred("_run_all")


func _assert_true(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		printerr("[FAIL] %s" % msg)


func _assert_eq(a: Variant, b: Variant, msg: String) -> void:
	if a == b:
		_passed += 1
	else:
		_failed += 1
		printerr("[FAIL] %s (got %s, expected %s)" % [msg, str(a), str(b)])


func _new_meta() -> MetaProgress:
	var m := MetaProgress.new()
	m.save_path = TEST_META
	return m


func _new_dir(stage_id: String = "stage_2_rift_cross", meta: MetaProgress = null, diff: String = "normal") -> CoopTDDirector:
	var d := CoopTDDirector.new()
	d.setup_stage(CampaignData.get_stage_by_id(stage_id), meta if meta != null else _new_meta(), diff)
	d.gold[1] = 5000
	d.gold[2] = 5000
	return d


func _tick(d: CoopTDDirector, seconds: float, dt: float = 0.05) -> void:
	var t := 0.0
	while t < seconds:
		d.tick(dt)
		t += dt


func _run_all() -> void:
	print("=== Twin Bastion TD Automated Test Suite ===")
	var real_before := FileAccess.get_file_as_string(MetaProgress.META_PATH) if FileAccess.file_exists(MetaProgress.META_PATH) else "<none>"

	_test_campaign()
	_test_meta()
	_test_wallets_and_combos()
	_test_upgrades_and_branches()
	_test_frost_and_overload()
	_test_fire_rate_survives_recompute()
	_test_kill_attribution()
	_test_enemy_abilities()
	_test_hero_skills()
	_test_wave_flow()
	_test_difficulty_and_endless()
	_test_ai()
	_test_presentation()
	await _test_scenes()

	var real_after := FileAccess.get_file_as_string(MetaProgress.META_PATH) if FileAccess.file_exists(MetaProgress.META_PATH) else "<none>"
	_assert_eq(real_after, real_before, "Test suite leaves the real player save untouched")

	print("=== Results: %d passed, %d failed ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _test_campaign() -> void:
	var stages := CampaignData.get_stages()
	_assert_true(stages.size() >= 3, "CampaignData provides the handcrafted co-op stages")
	_assert_eq(str(CampaignData.get_stage_by_id("stage_3_royal_siege")["index"]), "3", "Stage 3 Royal Siege lookup works")
	for s in stages:
		for w in s["waves"]:
			for g in w["groups"]:
				_assert_true(CreepCatalog.ROSTER.has(str(g["enemy_id"])), "%s uses a known enemy (%s)" % [s["id"], g["enemy_id"]])


func _test_meta() -> void:
	var meta := _new_meta()
	_assert_eq(MetaProgress.compute_stars(20, 20, "normal", 0), 3, "No leaks on Normal = 3 stars")
	_assert_eq(MetaProgress.compute_stars(20, 20, "casual", 0), 2, "Casual caps at 2 stars")
	_assert_eq(MetaProgress.compute_stars(12, 20, "normal", 3), 2, "Half lives with leaks = 2 stars")
	_assert_eq(MetaProgress.compute_stars(4, 20, "normal", 9), 1, "Low lives = 1 star")
	var stars3 := meta.record_stage_clear("stage_1_twin_bridge", 20, 20, "hard", 0)
	_assert_eq(stars3, 3, "Flawless Hard clear awards 3 stars")
	_assert_eq(meta.get_available_stars(), 4, "Hard clear adds a crown star (3 + 1)")
	_assert_true(meta.unlock_talent("gold_gift"), "Unlock gold_gift talent (1 star)")
	_assert_true(meta.unlock_talent("discount"), "Unlock discount talent (2 stars)")
	_assert_eq(meta.get_available_stars(), 1, "Stars deducted cleanly after unlocks")
	_assert_true(meta.record_endless("stage_1_twin_bridge", 12), "Endless record saved")
	_assert_true(not meta.record_endless("stage_1_twin_bridge", 7), "Lower endless wave does not overwrite record")
	var meta2 := _new_meta()
	_assert_true(meta2.load_from_disk() and meta2.has_talent("gold_gift") and int(meta2.endless_best["stage_1_twin_bridge"]) == 12, "MetaProgress reloads talents and records from its own save path")
	meta2.reset_talents()
	_assert_eq(meta2.get_available_stars(), 4, "Talent respec refunds all spent stars")


func _test_wallets_and_combos() -> void:
	var meta := _new_meta()
	meta.unlocked_talents = {"gold_gift": true}
	var d := CoopTDDirector.new()
	d.setup_stage(CampaignData.get_stage_by_id("stage_2_rift_cross"), meta)
	var g1 := int(d.gold[1])
	var g2 := int(d.gold[2])
	_assert_true(d.transfer_gold(1, 2, 50), "P1 transfers 50G to P2")
	_assert_eq(int(d.gold[1]), g1 - 50, "P1 wallet reduced by 50G")
	_assert_eq(int(d.gold[2]), g2 + 65, "P2 receives 50G + 15G gold_gift bonus")
	d.gold[1] = 1000
	d.gold[2] = 1000
	var b1 := d.execute_command({"player_id": 1, "action": "build_or_upgrade", "pad_id": "p3", "tower_id": "frost"})
	var b2 := d.execute_command({"player_id": 2, "action": "build_or_upgrade", "pad_id": "p2", "tower_id": "mage"})
	_assert_true(bool(b1["ok"]) and bool(b2["ok"]), "P1 and P2 build adjacent towers")
	_assert_true(d.combo_links.size() >= 1, "Adjacent P1xP2 towers form a combo link")
	_assert_eq(str(d.combo_links[0]["kind"]), "ice_fire_overload", "Frost + Mage = Ice-Fire Overload")
	_assert_true(not bool(d.build_or_upgrade_pad(1, "p2", "arrow")["ok"]), "P1 cannot upgrade P2's tower")
	_assert_true(not bool(d.sell_pad(1, "p2")["ok"]), "P1 cannot sell P2's tower")
	d.execute_command({"player_id": 1, "action": "build_or_upgrade", "pad_id": "p4", "tower_id": "frost"})
	var same_owner_links := 0
	for l in d.combo_links:
		if int(d.tower_owners[l["t1_uid"]]) == int(d.tower_owners[l["t2_uid"]]):
			same_owner_links += 1
	_assert_eq(same_owner_links, 0, "Combos never link two towers of the same player")
	_assert_eq(d._combo_kind_for("arrow", "frost"), "shatter_arrow", "Arrow + Frost = Shatter Arrow")
	_assert_eq(d._combo_kind_for("barracks", "frost"), "frost_bulwark", "Barracks + Frost = Frost Bulwark")
	_assert_eq(d._combo_kind_for("mage", "arrow"), "arcane_shred", "Arrow + Mage = Arcane Shred")
	_assert_eq(d._combo_kind_for("mage", "barracks"), "twin_star_haste", "Other pairs = Twin Star Haste")

	d.synchro_charge = 100.0
	d.engine.spawn_creep("goblin", "north")
	_assert_eq(str(d.trigger_synchro_ult(1)["state"]), "pending", "P1 starts Synchro and waits for P2")
	_assert_true(not bool(d.trigger_synchro_ult(1)["ok"]), "Initiator cannot confirm their own Synchro")
	_assert_eq(str(d.trigger_synchro_ult(2)["state"]), "unleashed", "P2 confirmation unleashes Twin Star Meteor")
	_assert_eq(int(d.synchro_charge), 0, "Synchro charge resets after unleash")
	d.synchro_charge = 100.0
	d.trigger_synchro_ult(2)
	_tick(d, CoopTDDirector.SYNCHRO_WINDOW_SEC + 0.2)
	_assert_eq(d.synchro_pending_by, 0, "Unanswered Synchro request expires")


func _test_upgrades_and_branches() -> void:
	var d := _new_dir()
	d.execute_command({"player_id": 1, "action": "build_or_upgrade", "pad_id": "p1", "tower_id": "arrow"})
	var t := d.get_tower_at_pad("p1")
	var opts1 := d.get_upgrade_options("p1")
	_assert_eq(opts1.size(), 1, "Lv1 tower offers one straight upgrade")
	var gold_before := int(d.gold[1])
	var u1 := d.execute_command({"player_id": 1, "action": "upgrade", "pad_id": "p1"})
	_assert_true(bool(u1["ok"]) and int(t["level"]) == 2, "Lv1 -> Lv2 upgrade works")
	_assert_eq(int(d.gold[1]), gold_before - int(opts1[0]["cost"]), "Upgrade charges the catalog cost")
	var opts2 := d.get_upgrade_options("p1")
	_assert_eq(opts2.size(), 2, "Lv2 tower offers two Lv3 branches")
	var u2 := d.execute_command({"player_id": 1, "action": "upgrade", "pad_id": "p1", "branch": 0})
	_assert_true(bool(u2["ok"]) and int(t["level"]) == 3 and str(t["branch"]) == "sniper", "Branch 0 turns the arrow tower into a Sniper")
	_assert_true(float(t["crit_chance"]) > 0.2 and float(t["range"]) > 150.0, "Sniper branch grants crit and long range")
	_assert_true(not bool(d.execute_command({"player_id": 1, "action": "upgrade", "pad_id": "p1"})["ok"]), "Lv3 is the max level")
	_assert_true(d.get_sell_refund("p1") > 0, "Sell refund reflects invested gold")

	d.execute_command({"player_id": 2, "action": "build_or_upgrade", "pad_id": "p5", "tower_id": "barracks"})
	d.execute_command({"player_id": 2, "action": "upgrade", "pad_id": "p5"})
	d.execute_command({"player_id": 2, "action": "upgrade", "pad_id": "p5", "branch": 0})
	var bt := d.get_tower_at_pad("p5")
	var count := 0
	for s in d.engine.soldiers:
		if str(s.get("owner_tower", "")) == str(bt["uid"]):
			count += 1
	_assert_eq(count, 3, "Paladin barracks fields 3 soldiers")
	_assert_true(bool(d.execute_command({"player_id": 2, "action": "set_priority", "pad_id": "p5", "priority": 2})["ok"]), "Owner can change target priority")
	_assert_true(not bool(d.execute_command({"player_id": 1, "action": "set_priority", "pad_id": "p5", "priority": 1})["ok"]), "Partner cannot change target priority")


func _test_frost_and_overload() -> void:
	var d := _new_dir()
	d.execute_command({"player_id": 1, "action": "build_or_upgrade", "pad_id": "p3", "tower_id": "frost"})
	d.execute_command({"player_id": 2, "action": "build_or_upgrade", "pad_id": "p2", "tower_id": "mage"})
	for i in range(4):
		var c := d.engine.spawn_creep("shield_bearer", "north")
		c["progress"] = 0.42
		c["pos"] = (d.engine.lanes["north"] as TDPathLane).get_point_at_progress(0.42)
		c["hp"] = 5000.0
		c["max_hp"] = 5000.0
		c["speed"] = 0.0
		c["base_speed"] = 0.0
	_tick(d, 3.0)
	var slowed := 0
	for c in d.engine.creeps:
		if float(c["slow_timer"]) > 0.0 and float(c["slow_factor"]) < 1.0:
			slowed += 1
	_assert_true(slowed > 0, "Frost tower actually slows enemies")
	_assert_true(int(d.stats[1]["combo_procs"]) > 0, "Ice-Fire Overload procs on slowed targets")


func _test_fire_rate_survives_recompute() -> void:
	var d := _new_dir()
	d.execute_command({"player_id": 1, "action": "build_or_upgrade", "pad_id": "p3", "tower_id": "arrow"})
	d.execute_command({"player_id": 1, "action": "upgrade", "pad_id": "p3"})
	var t := d.get_tower_at_pad("p3")
	var upgraded_rate := float(t["fire_rate"])
	_assert_true(upgraded_rate > 1.4, "Lv2 arrow fire rate includes upgrade bonus")
	d.execute_command({"player_id": 2, "action": "build_or_upgrade", "pad_id": "p2", "tower_id": "arrow"})
	_assert_true(absf(float(t["fire_rate"]) - upgraded_rate * 1.15) < 0.01, "Twin Star haste multiplies the upgraded rate")
	d.execute_command({"player_id": 2, "action": "sell", "pad_id": "p2"})
	_assert_true(absf(float(t["fire_rate"]) - upgraded_rate) < 0.01, "Fire rate returns to upgraded base after combo ends")


func _test_kill_attribution() -> void:
	var d := _new_dir()
	d.execute_command({"player_id": 2, "action": "build_or_upgrade", "pad_id": "p6", "tower_id": "arrow"})
	var c := d.engine.spawn_creep("slime", "south")
	c["hp"] = 1.0
	c["progress"] = 0.85
	c["pos"] = (d.engine.lanes["south"] as TDPathLane).get_point_at_progress(0.85)
	c["speed"] = 0.0
	# Keep heroes away so the tower lands the hit
	d.heroes[1]["pos"] = Vector2(-500, -500)
	d.heroes[2]["pos"] = Vector2(-500, -500)
	_tick(d, 1.5)
	_assert_eq(int(d.stats[2]["kills"]), 1, "Kill is credited to the owner of the tower that landed it")
	_assert_eq(int(d.stats[1]["kills"]), 0, "Partner gets no credit for that kill")


func _test_enemy_abilities() -> void:
	var d := _new_dir()
	var sp := d.engine.spawn_creep("splitter", "north")
	d._init_creep(sp, 0)
	sp["progress"] = 0.3
	sp["hp"] = 0.0
	d.engine._cleanup_dead_creeps()
	var slimelets := 0
	for c in d.engine.creeps:
		if str(c["enemy_id"]) == "slimelet":
			slimelets += 1
	_assert_eq(slimelets, 2, "Splitter splits into 2 slimelets on death")

	var sh := d.engine.spawn_creep("shield_bearer", "north")
	var before := float(sh["hp"])
	d.engine.apply_damage_to_creep(sh, 40.0, "physical")
	_assert_true(before - float(sh["hp"]) <= 7.0, "Shield cuts physical damage hard")
	d.engine.apply_damage_to_creep(sh, 200.0, "magic")
	_assert_true(float(sh["shield"]) <= 0.0, "Magic breaks the shield")

	var shaman := d.engine.spawn_creep("shaman", "south")
	d._init_creep(shaman, 0)
	var hurt := d.engine.spawn_creep("goblin", "south")
	hurt["hp"] = 10.0
	shaman["ab_timer"] = 0.0
	d._tick_creep_abilities(0.05)
	_assert_true(float(hurt["hp"]) > 10.0, "Shaman heals nearby allies")

	var boss := d.engine.spawn_creep("boss_obsidian", "north")
	d._init_creep(boss, 4)
	boss["hp"] = float(boss["max_hp"]) * 0.45
	var n_before := d.engine.creeps.size()
	d._tick_creep_abilities(0.05)
	_assert_true(float(boss["shield"]) > 0.0 and d.engine.creeps.size() > n_before, "Obsidian boss summons minions and raises a shield at half HP")

	d.execute_command({"player_id": 1, "action": "build_or_upgrade", "pad_id": "p6", "tower_id": "arrow"})
	var colossus := d.engine.spawn_creep("boss_frost_colossus", "north")
	d._init_creep(colossus, 4)
	colossus["pos"] = d.get_tower_at_pad("p6")["pos"]
	colossus["ab_timer"] = 0.0
	d._tick_creep_abilities(0.05)
	_assert_true(float(d.get_tower_at_pad("p6")["frozen_timer"]) > 0.0, "Frost Colossus roar freezes nearby towers")


func _test_hero_skills() -> void:
	var d := _new_dir()
	var targets := []
	for i in range(3):
		var c := d.engine.spawn_creep("slime", "north")
		c["pos"] = Vector2(120, 80)
		targets.append(c)
	var r1 := d.execute_command({"player_id": 1, "action": "hero_skill", "x": 120.0, "y": 80.0})
	_assert_true(bool(r1["ok"]) and int(r1["hits"]) == 3, "P1 meteor volley hits clustered enemies")
	_assert_true(not bool(d.execute_command({"player_id": 1, "action": "hero_skill", "x": 120.0, "y": 80.0})["ok"]), "Hero skill respects cooldown")
	_assert_true(not bool(d.execute_command({"player_id": 2, "action": "hero_skill", "x": 240.0, "y": 30.0})["ok"]), "Reinforcements must be placed near a road")
	var n_before := d.engine.soldiers.size()
	_assert_true(bool(d.execute_command({"player_id": 2, "action": "hero_skill", "x": 92.0, "y": 194.0})["ok"]) and d.engine.soldiers.size() == n_before + 2, "P2 reinforcements drop two blockers on the road")


func _test_wave_flow() -> void:
	var d := _new_dir("stage_1_twin_bridge")
	d.engine.lives = 999
	_assert_eq(d.wave_countdown, -1.0, "First wave waits for the players")
	d.call_next_wave()
	_tick(d, 12.0)
	_assert_true(d.wave_countdown > 0.0, "Countdown starts after a wave finishes spawning")
	_assert_true(d.get_early_call_bonus() > 0, "Calling early during countdown pays a bonus")
	var g := int(d.gold[1])
	var bonus := d.get_early_call_bonus()
	d.call_next_wave()
	_assert_eq(d.wave_dir.current_wave_index, 1, "Early call starts wave 2")
	_assert_eq(int(d.gold[1]), g + bonus, "Early-call bonus is paid to both players")
	_tick(d, 12.0)
	_tick(d, d.countdown_total + 0.5)
	_assert_true(d.wave_dir.current_wave_index >= 2, "Countdown auto-starts the next wave")


func _test_difficulty_and_endless() -> void:
	var dn := _new_dir("stage_1_twin_bridge", null, "normal")
	var dh := _new_dir("stage_1_twin_bridge", null, "hard")
	var dc := _new_dir("stage_1_twin_bridge", null, "casual")
	_assert_true(dh.max_lives < dn.max_lives and dc.max_lives > dn.max_lives, "Difficulty changes lives")
	_assert_true(float(dh.engine.creep_defs["goblin"]["hp"]) > float(dn.engine.creep_defs["goblin"]["hp"]), "Hard enemies have more HP")
	var de := CoopTDDirector.new()
	de.setup_stage(CampaignData.get_stage_by_id("stage_1_twin_bridge"), _new_meta(), "normal", true)
	var total := de.wave_dir.get_total_waves()
	for i in range(total + 3):
		de.call_next_wave()
	_assert_true(de.wave_dir.has_next_wave(), "Endless mode always queues another wave")
	_assert_true(de.endless_best_wave >= total + 3, "Endless tracks the best wave reached")
	_assert_true(not de.is_victory(), "Endless mode never reports victory")
	_assert_true(de.get_endless_hp_scale(10) > de.get_endless_hp_scale(2), "Endless HP scales up with waves")


func _test_ai() -> void:
	var d := _new_dir()
	var ai := CoopAIPartner.new(2)
	ai.decision_interval = 0.05
	d.gold[1] = 20
	d.gold[2] = 200
	ai.tick(0.9, d)
	_assert_true(int(d.gold[1]) >= 70, "AI transfers gold when its partner is broke")
	d.synchro_charge = 100.0
	d.trigger_synchro_ult(1)
	ai.tick(0.1, d)
	_assert_eq(d.synchro_pending_by, 0, "AI immediately confirms the partner's Synchro")
	var d2 := _new_dir()
	var ai1 := CoopAIPartner.new(1)
	ai1.decision_interval = 0.05
	for i in range(40):
		ai1.tick(0.06, d2)
	var p1_towers := 0
	for o in d2.tower_owners.values():
		if int(o) == 1:
			p1_towers += 1
	_assert_true(p1_towers >= 2, "AI can drive the P1 seat too")
	for uid in d2.tower_owners.keys():
		var pad := ""
		for k in d2.pad_to_tower_uid.keys():
			if d2.pad_to_tower_uid[k] == uid:
				pad = k
		_assert_true(int(d2._find_pad(pad).get("owner_hint", 0)) != 2, "P1 AI leaves P2's pads alone")


func _test_presentation() -> void:
	var bvfx := BattleVFX.new()
	bvfx.init_ambient_motes("rift", 16)
	_assert_eq(bvfx.ambient_motes.size(), 16, "BattleVFX spawns biome ambient motes")
	bvfx.spawn_projectile(Vector2(50, 50), Vector2(150, 50), "arrow")
	bvfx.play_boss_cutin("黑曜大魔王", "终极测试", null)
	bvfx.play_synchro_ultimate_cinematic()
	bvfx.tick(0.5)
	_assert_true(bvfx.ult_cinematic_timer > 0.0 and bvfx.boss_cutin_timer > 0.0, "BattleVFX runs cinematic timers")
	_assert_eq(TowerArtRenderer.get_biome_for_stage("stage_1_twin_bridge"), "bridge", "Stage 1 maps to bridge biome")
	_assert_eq(TowerArtRenderer.get_biome_for_stage("stage_2_rift_cross"), "rift", "Stage 2 maps to rift biome")
	_assert_eq(TowerArtRenderer.get_biome_for_stage("stage_3_royal_siege"), "siege", "Stage 3 maps to siege biome")


func _test_scenes() -> void:
	for spath in [
		"res://game/scenes/title_lobby.tscn",
		"res://game/scenes/campaign_map.tscn",
		"res://game/scenes/coop_battle.tscn",
	]:
		var ps: PackedScene = ResourceLoader.load(spath)
		_assert_true(ps != null, "Load scene: %s" % spath)
		if ps != null:
			var inst := ps.instantiate()
			root.add_child(inst)
			for i in range(3):
				await process_frame
			inst.queue_free()
			await process_frame
