extends SceneTree
## Automated Headless Verification Suite for 《双子堡垒：共守苍穹》(Twin Bastion TD)

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


func _run_all() -> void:
	print("=== Twin Bastion TD Automated Test Suite ===")

	# 1. Campaign Data (3 Stages)
	var stages := CampaignData.get_stages()
	_assert_eq(stages.size(), 3, "CampaignData provides 3 handcrafted co-op stages")
	_assert_eq(str(CampaignData.get_stage_by_id("stage_3_royal_siege")["index"]), "3", "Stage 3 Royal Siege lookup works")

	# 2. MetaProgress (Stars, Talents, Respec, Disk Persistence)
	var meta := MetaProgress.new()
	var test_meta_path := "user://_test_twin_bastion_meta.json"
	var stars3 := meta.record_stage_clear("stage_1_twin_bridge", 20, 20)
	_assert_eq(stars3, 3, "20/20 lives awards 3 stars")
	_assert_eq(meta.get_available_stars(), 3, "3 available stars after 3-star clear")
	_assert_true(meta.unlock_talent("gold_gift"), "Unlock gold_gift talent (1 star)")
	_assert_true(meta.unlock_talent("discount"), "Unlock discount talent (2 stars)")
	_assert_eq(meta.get_available_stars(), 0, "Stars deducted cleanly after unlocks")
	_assert_true(meta.save_to_disk(test_meta_path), "MetaProgress saves JSON to disk")
	var meta2 := MetaProgress.new()
	_assert_true(meta2.load_from_disk(test_meta_path) and meta2.has_talent("gold_gift"), "MetaProgress reloads talents from disk")
	meta2.reset_talents()
	_assert_eq(meta2.get_available_stars(), 3, "Talent respec refunds all spent stars")

	# 3. CoopTDDirector (Independent Wallets, Gold Transfer + Bonus, Cross-Player Combos, Synchro Ult)
	var dir := CoopTDDirector.new()
	dir.setup_stage(CampaignData.get_stage_by_id("stage_2_rift_cross"), meta)
	var g1_init := int(dir.gold[1])
	var g2_init := int(dir.gold[2])
	_assert_true(dir.transfer_gold(1, 2, 50), "P1 transfers 50G to P2")
	_assert_eq(int(dir.gold[1]), g1_init - 50, "P1 wallet reduced by 50G")
	_assert_eq(int(dir.gold[2]), g2_init + 65, "P2 receives 50G + 15G gold_gift talent bonus")

	# Build P1 Frost at p3 and P2 Mage at p2 (adjacent within COMBO_RADIUS) -> Ice-Fire Overload!
	var b1 := dir.execute_command({"player_id": 1, "action": "build_or_upgrade", "pad_id": "p3", "tower_id": "frost"})
	var b2 := dir.execute_command({"player_id": 2, "action": "build_or_upgrade", "pad_id": "p2", "tower_id": "mage"})
	_assert_true(bool(b1["ok"]) and bool(b2["ok"]), "P1 and P2 build adjacent towers cleanly")
	_assert_true(dir.combo_links.size() >= 1, "Adjacent P1×P2 towers form Co-op Combo Link")
	_assert_eq(str(dir.combo_links[0]["kind"]), "ice_fire_overload", "Frost + Mage triggers Ice-Fire Overload combo")

	# Cross-player ownership protection
	var steal := dir.build_or_upgrade_pad(1, "p2", "arrow")
	_assert_true(not bool(steal["ok"]), "P1 cannot overwrite or upgrade P2's tower")

	# Synchro Ultimate 2-Player Confirmation
	dir.synchro_charge = 100.0
	dir.engine.spawn_creep("goblin", "north")
	var u1 := dir.trigger_synchro_ult(1)
	_assert_eq(str(u1["state"]), "pending", "P1 initiates Synchro Ultimate and waits for P2")
	var u2 := dir.trigger_synchro_ult(2)
	_assert_eq(str(u2["state"]), "unleashed", "P2 confirmation unleashes Twin Star Meteor")
	_assert_eq(int(dir.synchro_charge), 0, "Synchro charge resets to 0 after unleash")

	# 4. CoopAIPartner (Auto-build synergy, Auto gold support, Auto ult confirm)
	var ai := CoopAIPartner.new()
	ai.decision_interval = 0.05
	dir.gold[1] = 20
	dir.gold[2] = 200
	ai.tick(0.9, dir)
	_assert_true(int(dir.gold[1]) >= 70, "CoopAIPartner proactively transfers gold when P1 is low")
	dir.synchro_charge = 100.0
	dir.trigger_synchro_ult(1)
	ai.tick(0.1, dir)
	_assert_eq(dir.synchro_pending_by, 0, "CoopAIPartner immediately confirms P1 Synchro Ultimate")

	# 4b. BattleVFX & TowerArtRenderer Presentation Engine Tests
	var bvfx := BattleVFX.new()
	bvfx.init_ambient_motes("rift", 16)
	_assert_eq(bvfx.ambient_motes.size(), 16, "BattleVFX spawns biome ambient motes")
	bvfx.spawn_projectile(Vector2(50, 50), Vector2(150, 50), "arrow")
	bvfx.play_boss_cutin("黑曜大魔王", "终极测试", null)
	bvfx.play_synchro_ultimate_cinematic()
	bvfx.tick(0.5)
	_assert_true(bvfx.ult_cinematic_timer > 0.0 and bvfx.boss_cutin_timer > 0.0, "BattleVFX runs cinematic timers & projectiles cleanly")
	_assert_eq(TowerArtRenderer.get_biome_for_stage("stage_1_twin_bridge"), "bridge", "Stage 1 maps to bridge biome")
	_assert_eq(TowerArtRenderer.get_biome_for_stage("stage_2_rift_cross"), "rift", "Stage 2 maps to rift biome")
	_assert_eq(TowerArtRenderer.get_biome_for_stage("stage_3_royal_siege"), "siege", "Stage 3 maps to siege biome")

	# 5. Live Scene Smoke Tests + Engine Click-Through Invariant
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
			await process_frame
			if spath.ends_with("coop_battle.tscn"):
				var bcn: ObjectiveBeacon2D = inst._guide_beacon
				_assert_true(bcn != null and bcn._ring.mouse_filter == Control.MOUSE_FILTER_IGNORE, "CoopBattle ObjectiveBeacon2D._ring is click-through")
			inst.queue_free()
			await process_frame

	print("=== Results: %d passed, %d failed ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
