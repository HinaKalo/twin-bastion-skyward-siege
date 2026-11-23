extends SceneTree
## Scripted visual tour: drives the real scenes into representative states and saves PNGs to res://tools/out/.
## Run windowed (not headless): godot --path . --script res://tools/screenshot_tour.gd [-- only=<substring>]
## Uses a scratch save path so the player's real progress is never modified.

const OUT_DIR := "res://tools/out/"
const SHOT_SIZE := Vector2i(960, 540)

var _only: String = ""
var _count: int = 0


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("only="):
			_only = a.substr(5)
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var gs: Node = root.get_node("GameSession")
	gs.meta = MetaProgress.new()
	gs.meta.save_path = "user://_tour_meta.json"
	gs.meta.stage_stars = {"stage_1_twin_bridge": 3, "stage_2_rift_cross": 2, "stage_3_royal_siege": 1}
	gs.meta.unlocked_talents = {"start_gold": true}
	gs.play_mode = 0

	await _open("res://game/scenes/title_lobby.tscn", 1.2)
	await _shot("01_title")
	await _open("res://game/scenes/campaign_map.tscn", 0.8)
	await _shot("02_map")

	var stages := CampaignData.get_stages()
	for si in range(stages.size()):
		var sid := str(stages[si]["id"])
		gs.selected_stage_id = sid
		gs.difficulty = "normal"
		gs.endless_mode = false
		if _only != "" and not _only.begins_with("s%d" % (si + 1)) and not _only.begins_with("battle"):
			continue
		await _battle_states(si + 1, sid)

	print("[tour] saved %d screenshots to %s" % [_count, ProjectSettings.globalize_path(OUT_DIR)])
	quit(0)


func _battle_states(n: int, sid: String) -> void:
	await _open("res://game/scenes/coop_battle.tscn", 0.4)
	var scene: Node = current_scene
	await _shot("s%d_00_intro" % n)
	await create_timer(2.6).timeout
	await _shot("s%d_01_empty" % n)

	var d: CoopTDDirector = scene.director
	d.gold[1] = 99999
	d.gold[2] = 99999
	var types := ["arrow", "mage", "frost", "barracks"]
	for i in range(d.pads.size()):
		var pad: Dictionary = d.pads[i]
		var pid := 2 if int(pad.get("owner_hint", 0)) == 2 else (1 if i % 2 == 0 else 2)
		d.execute_command({"player_id": pid, "action": "build_or_upgrade", "pad_id": str(pad["id"]), "tower_id": types[i % types.size()]})
		var lv := i % 3
		if lv >= 1:
			d.execute_command({"player_id": pid, "action": "upgrade", "pad_id": str(pad["id"])})
		if lv >= 2:
			d.execute_command({"player_id": pid, "action": "upgrade", "pad_id": str(pad["id"]), "branch": i % 2})
	if scene.has_method("_refresh_hud"):
		scene._refresh_hud()
	await create_timer(0.3).timeout
	await _shot("s%d_02_towers" % n)

	d.call_next_wave()
	d.call_next_wave()
	d.call_next_wave()
	await create_timer(5.5).timeout
	await _shot("s%d_03_combat" % n)

	var boss_id := ""
	for w in d.wave_dir.waves:
		for g in w["groups"]:
			if CreepCatalog.is_boss(str(g["enemy_id"])):
				boss_id = str(g["enemy_id"])
	if boss_id != "":
		d.wave_dir.enemy_spawn_requested.emit(boss_id, str(d.engine.lanes.keys()[0]), 4)
		await create_timer(0.5).timeout
		await _shot("s%d_04_boss_cutin" % n)
		await create_timer(3.0).timeout
		await _shot("s%d_05_boss_field" % n)

	d.synchro_charge = 100.0
	d.execute_command({"player_id": 1, "action": "synchro_ult"})
	d.execute_command({"player_id": 2, "action": "synchro_ult"})
	await create_timer(0.5).timeout
	await _shot("s%d_06_ult" % n)

	if scene.has_method("_finish_stage"):
		await create_timer(1.6).timeout
		scene._finish_stage(true)
		await create_timer(0.6).timeout
		await _shot("s%d_07_result" % n)


func _open(path: String, wait: float) -> void:
	change_scene_to_file(path)
	await process_frame
	await process_frame
	await create_timer(wait).timeout


func _shot(name: String) -> void:
	if _only != "" and not name.begins_with(_only) and not _only.begins_with("battle"):
		return
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.resize(SHOT_SIZE.x, SHOT_SIZE.y, Image.INTERPOLATE_NEAREST)
	img.save_png(ProjectSettings.globalize_path(OUT_DIR + name + ".png"))
	_count += 1
