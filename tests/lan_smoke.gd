extends SceneTree
## Run one host and one client with -- role=host/client port=<local port>.

var _failed := false


func _initialize() -> void:
	_run.call_deferred()


func _expect(ok: bool, message: String) -> void:
	if not ok:
		_failed = true
		printerr("[LAN FAIL] ", message)


func _wait_for(check: Callable, seconds: float) -> bool:
	var until := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < until:
		if check.call():
			return true
		await process_frame
	return false


func _battle(version: int) -> bool:
	return current_scene != null and current_scene.get("director") != null and current_scene.get("_lan_version") == version and not SceneFader.is_busy()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var host := args.has("role=host")
	var port := 24635
	for arg in args:
		if arg.begins_with("port="):
			port = int(arg.substr(5))
	var gs := root.get_node("GameSession")
	gs.meta = MetaProgress.new()
	gs.meta.save_path = "user://_twin_lan_%s.json" % ("host" if host else "client")
	if host:
		gs.play_mode = 2
		_expect(gs.net.host_game(port, 1), "Host starts the ENet server")
		_expect(await _wait_for(func(): return gs.net.peers.size() == 2, 12.0), "Host sees the second peer")
		gs.difficulty = "normal"
		_expect(gs.request_lan_match("stage_2_rift_cross"), "Host can select the battlefield")
	else:
		gs.play_mode = 3
		gs.local_player_id = 2
		_expect(gs.net.join_game("127.0.0.1", port), "Client starts the ENet connection")
	if not await _wait_for(_battle.bind(1), 12.0):
		_expect(false, "Both peers load match 1")
		quit(1)
		return
	var game := current_scene
	var d: CoopTDDirector = game.director
	_expect(str(d.stage_def["id"]) == "stage_2_rift_cross", "Peers load the host's chosen map")
	if host:
		game._dispatch_cmd({"action": "call_wave", "player_id": 1})
		_expect(d.wave_dir.current_wave_index == -1, "Host readiness alone holds the first wave")
	else:
		_expect(await _wait_for(func(): return d.ready_seats.has(1), 5.0), "Client receives the host's readiness")
		game._dispatch_cmd({"action": "call_wave", "player_id": 1})
		var pad := str(d.pads[7]["id"])
		game._dispatch_cmd({"action": "build_or_upgrade", "player_id": 1, "pad_id": pad, "tower_id": "arrow"})
		_expect(await _wait_for(func(): return d.get_pad_owner(pad) == 2, 5.0), "Client's command is assigned to P2")
	_expect(await _wait_for(func(): return d.wave_dir.current_wave_index == 0 and not d.engine.creeps.is_empty(), 6.0), "Both peers see the same opened wave and units")
	if host:
		for i in range(100):
			var route: Dictionary = d.routes[i % d.routes.size()]
			d._spawn_at_progress("slime", route["id"], 0.10 + float(i % 8) * 0.04)
		game._open_pause()
		var elapsed := d.elapsed
		await create_timer(0.70).timeout
		_expect(is_equal_approx(d.elapsed, elapsed), "Pause freezes the host's simulation")
		game.pause_menu._on_button("resume")
		game._cycle_speed()
		await create_timer(0.70).timeout
		game._finish_stage(true)
		await create_timer(0.70).timeout
		game._restart_battle()
	else:
		_expect(await _wait_for(func(): return d.engine.creeps.size() >= 100, 4.0), "A crowded frame survives snapshot chunking")
		_expect(await _wait_for(func(): return game._lan_paused, 4.0), "Client receives shared pause")
		_expect(await _wait_for(func(): return not game._lan_paused and game._speed_mult == 2.0, 4.0), "Client receives resume and speed")
		_expect(await _wait_for(func(): return game.result_screen.visible, 4.0), "Client receives the authoritative result")
	_expect(await _wait_for(_battle.bind(2), 7.0), "Both peers can restart the same map")
	if host:
		await create_timer(0.5).timeout
		gs.leave_lan()
	else:
		_expect(await _wait_for(func(): return not gs.is_lan(), 5.0), "Client returns to the lobby on disconnect")
	print("[LAN] ", "HOST" if host else "CLIENT", " FAIL" if _failed else " OK")
	quit(1 if _failed else 0)
