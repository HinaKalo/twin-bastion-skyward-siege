extends Node
## Launch the game with user argument --battle-review, adding --profile for frame measurements.

const THREATS := [
	["slime", "wolf", "goblin_archer"],
	["shield_bearer", "shaman", "troll_breaker"],
	["assassin", "gargoyle", "boss_obsidian"],
	["wolf", "bomb_bat", "boss_frost_colossus"],
	["shield_bearer", "troll_breaker", "boss_obsidian_awakened"],
]


var _profile_file: FileAccess


func run() -> void:
	var tree := get_tree()
	var profile := "--profile" in OS.get_cmdline_user_args()
	var session := tree.root.get_node("GameSession")
	session.meta = MetaProgress.new()
	session.meta.save_path = "user://_twin_battle_review.json"
	session.meta.tutorial_done = true
	session.play_mode = 0
	if profile:
		_profile_file = FileAccess.open("user://_twin_battle_profile.log", FileAccess.WRITE)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
	var stages := CampaignData.get_stage_ids()
	for i in range(stages.size()):
		session.meta.story_seen[stages[i]] = true
		session.selected_stage_id = stages[i]
		tree.change_scene_to_file("res://game/scenes/coop_battle.tscn")
		await get_tree().process_frame
		await get_tree().process_frame
		var game := tree.current_scene
		game.ai_partner = null
		var d: CoopTDDirector = game.director
		var center: Vector2 = d.stage_def["opening_view"]
		game._user_zoom = 0.74 if profile else 0.90
		game._zoom = game._user_zoom
		var routes: Array = d.routes.filter(func(route: Dictionary): return route["spawn"] != "portal")
		var choices := ["arrow", "mage", "frost", "barracks"]
		d.gold = {1: 5000, 2: 5000}
		for pi in range(d.pads.size()):
			var pad: Dictionary = d.pads[pi]
			if not profile and (pad["pos"] as Vector2).distance_to(center) > 176.0:
				continue
			var seat := int(pad["owner_hint"])
			if seat == 0:
				seat = 1 + (pi % 2)
			d.build_or_upgrade_pad(seat, pad["id"], choices[pi % choices.size()])
			if profile or pi % 3 == 0:
				d.upgrade_pad(seat, pad["id"])
		d.gold = {1: 138, 2: 162}
		game.focus_camera(center)
		await tree.create_timer(0.45).timeout
		d.wave_dir.current_wave_index = 2 if i == 4 else 0
		d.call_next_wave()
		game.vfx.play_wave_banner(str(d.stage_def["name"]))
		if i == 4:
			d._on_spawn_requested("shield_bearer", "portal", 3)
		for n in range(120 if profile else 18):
			var route: Dictionary = routes[n % routes.size()]
			var lane: TDPathLane = d.engine.lanes[route["id"]]
			var pos := _near_progress(lane, center)
			var type: String = THREATS[i][n % 2]
			d._spawn_at_progress(type, lane.lane_id, maxf(0.0, pos - 0.08 + float(n % 7) * 0.016))
		var main: TDPathLane = d.engine.lanes[routes[0]["id"]]
		var special := d._spawn_at_progress(THREATS[i][2], main.lane_id, _near_progress(main, center))
		special["ab_timer"] = 0.65
		if i == 2 or i == 4:
			special["hp"] = float(special["max_hp"]) * 0.48
		if profile:
			for speed in [1.0, 2.0, 3.0]:
				game._speed_mult = speed
				await _profile(stages[i], speed)
		else:
			await tree.create_timer(1.4).timeout
			d.cast_hero_skill(1, center)
			await tree.create_timer(3.4).timeout
	if _profile_file != null:
		_profile_file.close()
	tree.quit(0)


func _near_progress(lane: TDPathLane, center: Vector2) -> float:
	var best := 0.0
	var dist := INF
	for sample in range(45):
		var p := float(sample) / 50.0
		var gap := lane.get_point_at_progress(p).distance_squared_to(center)
		if gap < dist:
			dist = gap
			best = p
	return best


func _profile(stage: String, speed: float) -> void:
	var samples: Array[float] = []
	var previous := Time.get_ticks_usec()
	for i in range(180):
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		if i > 10:
			samples.append(float(now - previous) / 1000.0)
		previous = now
	samples.sort()
	var result := "[FRAME] %s %.0fx p95=%.2fms peak=%.2fms" % [stage, speed, samples[int(samples.size() * 0.95)], samples.back()]
	print(result)
	if _profile_file != null:
		_profile_file.store_line(result)
		_profile_file.flush()
