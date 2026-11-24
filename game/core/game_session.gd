extends Node
## Global Session Autoload for Twin Bastion TD.
## Coordinates Play Mode (SOLO_AI / LOCAL_2P / LAN_HOST / LAN_CLIENT),
## Selected Campaign Stage, Persistent MetaProgress, NetSessionManager, and ReplaySession.

enum PlayMode { SOLO_AI, LOCAL_2P, LAN_HOST, LAN_CLIENT }

signal lan_state_received(state: Dictionary)
signal lan_fx_received(events: Array)
signal lan_lost()

const BATTLE_SCENE := "res://game/scenes/coop_battle.tscn"
const MAP_SCENE := "res://game/scenes/campaign_map.tscn"
const STATE_CHUNK := 1024
const MAX_STATE_SIZE := 2_000_000

var play_mode: int = PlayMode.SOLO_AI
var selected_stage_id: String = "stage_1_twin_bridge"
var difficulty: String = "normal" # casual | normal | hard
var endless_mode: bool = false
var local_player_id: int = 1 # 1 for Host/Solo/Local, 2 for LAN Client
var meta := MetaProgress.new()
var net: NetSessionManager
var replay := ReplaySession.new()
var lan_match := 0
var lan_talents: Dictionary = {}
var lan_notice := ""
var _room_config: Dictionary = {}
var _leaving_lan := false
var _out_frame := 0
var _in_frame := 0
var _in_chunks := {}


func _ready() -> void:
	meta.load_from_disk()
	GameSettings.load_settings()
	GameSettings.apply(AudioManager)
	net = NetSessionManager.new()
	net.name = "Room"
	add_child(net)
	net.command_received.connect(_on_room_command)
	net.peer_left.connect(_on_lan_peer_left)
	multiplayer.server_disconnected.connect(_on_lan_server_lost)
	multiplayer.connection_failed.connect(_on_lan_server_lost)
	if OS.get_cmdline_user_args().has("--battle-review"):
		_run_battle_review.call_deferred()


func _run_battle_review() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var review := Node.new()
	review.set_script(load("res://tools/battle_review.gd"))
	add_child(review)
	review.run()


func push_lan_fx(match_id: int, events: Array) -> void:
	if play_mode == PlayMode.LAN_HOST and net.peers.size() == 2:
		_receive_lan_fx.rpc(match_id, events)


@rpc("authority", "call_remote", "reliable", 2)
func _receive_lan_fx(match_id: int, events: Array) -> void:
	if play_mode == PlayMode.LAN_CLIENT and match_id == lan_match:
		lan_fx_received.emit(events)


func is_lan() -> bool:
	return play_mode == PlayMode.LAN_HOST or play_mode == PlayMode.LAN_CLIENT


func request_lan_match(stage_id: String) -> bool:
	if play_mode != PlayMode.LAN_HOST or net.peers.size() < 2:
		return false
	net.send_command("td_room", {"match": lan_match + 1, "stage": stage_id, "difficulty": difficulty,
		"endless": endless_mode, "talents": meta.unlocked_talents})
	return true


func request_lan_map() -> void:
	if play_mode == PlayMode.LAN_HOST:
		net.send_command("td_room", {"match": lan_match + 1, "map": true})


func _on_room_command(sender: int, kind: String, payload: Dictionary) -> void:
	if kind != "td_room" or not is_lan() or sender != 1:
		return
	var match_id := int(payload.get("match", 0))
	if match_id <= lan_match:
		return
	lan_match = match_id
	_room_config = payload.duplicate(true)
	_follow_room.call_deferred(match_id)


func _follow_room(match_id: int) -> void:
	while SceneFader.is_busy() and is_lan() and match_id == lan_match:
		await get_tree().create_timer(0.04).timeout
	if not is_lan() or match_id != lan_match:
		return
	if bool(_room_config.get("map", false)):
		SceneFader.go(get_tree(), MAP_SCENE)
		return
	selected_stage_id = str(_room_config["stage"])
	difficulty = str(_room_config["difficulty"])
	endless_mode = bool(_room_config["endless"])
	lan_talents = _room_config["talents"]
	SceneFader.go(get_tree(), BATTLE_SCENE)


func push_lan_state(state: Dictionary) -> void:
	if play_mode == PlayMode.LAN_HOST and net.peers.size() == 2:
		var data := var_to_bytes(state)
		var packet := data.compress(FileAccess.COMPRESSION_FASTLZ)
		var count := ceili(float(packet.size()) / STATE_CHUNK)
		if data.size() > MAX_STATE_SIZE or count > 128:
			return
		_out_frame += 1
		for i in range(count):
			var start := i * STATE_CHUNK
			_receive_lan_chunk.rpc(lan_match, _out_frame, i, count, data.size(), packet.slice(start, start + STATE_CHUNK))


@rpc("authority", "call_remote", "unreliable", 1)
func _receive_lan_chunk(match_id: int, frame_id: int, index: int, count: int, raw_size: int, chunk: PackedByteArray) -> void:
	if play_mode != PlayMode.LAN_CLIENT or match_id != lan_match or frame_id < _in_frame:
		return
	if count < 1 or count > 128 or index < 0 or index >= count or raw_size < 1 or raw_size > MAX_STATE_SIZE:
		return
	if frame_id > _in_frame:
		_in_frame = frame_id
		_in_chunks.clear()
	_in_chunks[index] = chunk
	if _in_chunks.size() != count:
		return
	var packed := PackedByteArray()
	for i in range(count):
		packed.append_array(_in_chunks[i])
	_in_frame += 1
	_in_chunks.clear()
	var data := packed.decompress(raw_size, FileAccess.COMPRESSION_FASTLZ)
	if not data.is_empty():
		var state: Variant = bytes_to_var(data)
		if state is Dictionary:
			lan_state_received.emit(state)


func _on_lan_peer_left(_peer: int) -> void:
	if is_lan():
		_on_lan_server_lost()


func _on_lan_server_lost() -> void:
	if not is_lan() or _leaving_lan:
		return
	_leaving_lan = true
	lan_notice = "搭档已断开连接，本局结束"
	lan_lost.emit()
	_leave_room.call_deferred()


func leave_lan() -> void:
	play_mode = PlayMode.SOLO_AI
	local_player_id = 1
	lan_match = 0
	_room_config.clear()
	_in_frame = 0
	_in_chunks.clear()
	net.close_session()
	_leaving_lan = false


func _leave_room() -> void:
	while SceneFader.is_busy():
		await get_tree().create_timer(0.04).timeout
	leave_lan()
	SceneFader.go(get_tree(), "res://game/scenes/title_lobby.tscn")


func is_ai_partner_enabled() -> bool:
	return play_mode == PlayMode.SOLO_AI


func get_mode_label() -> String:
	match play_mode:
		PlayMode.SOLO_AI: return "单人 + AI搭档"
		PlayMode.LOCAL_2P: return "同屏双人 (2P)"
		PlayMode.LAN_HOST: return "局域网房主 (P1)"
		PlayMode.LAN_CLIENT: return "局域网加入 (P2)"
		_: return "合作模式"
