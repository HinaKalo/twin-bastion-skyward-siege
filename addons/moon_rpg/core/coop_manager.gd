extends Node
## Unified 2-Player Co-op Manager (Local Couch Co-op + Online ENet Host/Client).
##
## Local Co-op:
##   MoonRPG.start_local_coop()
##   MoonRPG.leave_coop()
##
## Online ENet Co-op:
##   MoonRPG.host_coop(7777)
##   MoonRPG.join_coop("127.0.0.1", 7777)
##   MoonRPG.leave_coop()

enum CoopMode { SOLO, LOCAL, ONLINE_HOST, ONLINE_CLIENT }
enum VoteRule { MAJORITY, HOST_TIEBREAK, ROLL_OFF }

const DEFAULT_PORT := 7777
const PlayerScript := preload("res://addons/moon_rpg/action/player_controller.gd")

signal dialogue_vote_resolved(winning_choice: int, details: Dictionary)

var mode: int = CoopMode.SOLO
var players: Dictionary = {} # player_index (1, 2) -> PlayerController
var _unit_owners: Dictionary = {} # unit_id -> player_index (1 or 2) for BG3/ForTheKing drop-in control
var _eavesdroppers: Dictionary = {} # player_index -> bool
var _dialogue_vote: Dictionary = {} # { active, choices_count, rule, votes: {p_idx: choice}, assists: [{player, label, bonus}] }
var _peer: ENetMultiplayerPeer = null
var _remote_peer_id: int = 0
var _sync_accum: float = 0.0
var _p2_joy_device: int = 0


func _ready() -> void:
	if EventBus:
		EventBus.player_registered.connect(_on_player_registered)
		EventBus.room_changed.connect(_on_room_changed)
	if multiplayer != null:
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
		multiplayer.connected_to_server.connect(_on_connected_to_server)
		multiplayer.server_disconnected.connect(_on_server_disconnected)


func _on_player_registered(player: Node) -> void:
	var idx := int(player.get("player_index")) if "player_index" in player else 1
	players[idx] = player


func is_coop() -> bool:
	return mode != CoopMode.SOLO


func is_online() -> bool:
	return mode == CoopMode.ONLINE_HOST or mode == CoopMode.ONLINE_CLIENT


func is_host() -> bool:
	return mode == CoopMode.SOLO or mode == CoopMode.LOCAL or mode == CoopMode.ONLINE_HOST


func get_mode_name() -> String:
	match mode:
		CoopMode.LOCAL: return "local"
		CoopMode.ONLINE_HOST: return "online_host"
		CoopMode.ONLINE_CLIENT: return "online_client"
		_: return "solo"


func get_players() -> Array[Node]:
	var list: Array[Node] = []
	for idx in [1, 2]:
		if players.has(idx) and is_instance_valid(players[idx]):
			list.append(players[idx])
	return list


func get_player(index: int) -> Node:
	if players.has(index) and is_instance_valid(players[index]):
		return players[index]
	return null


# =============================================================================
# Local 2-Player Couch Co-op
# =============================================================================

func start_local_coop(p2_actor_key: String = "player.shen_zhao", p2_joy_id: int = 0) -> Node:
	if mode == CoopMode.LOCAL and get_player(2) != null:
		return get_player(2)
	if is_online():
		leave_coop()

	_p2_joy_device = p2_joy_id
	_install_p2_input_bindings(p2_joy_id)
	mode = CoopMode.LOCAL
	var p2 := _spawn_p2(p2_actor_key, false)
	if EventBus:
		EventBus.coop_mode_changed.emit(get_mode_name())
		EventBus.toast_requested.emit("本地双人模式已开启！(P2: 手柄 / 方向键+小键盘)", "gold")
	return p2


# =============================================================================
# Online ENet 2-Player Co-op (LAN / Internet)
# =============================================================================

func host_coop(port: int = DEFAULT_PORT, max_clients: int = 1) -> Error:
	leave_coop()
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_server(port, maxi(1, max_clients))
	if err != OK:
		_peer = null
		push_warning("[CoopManager] Failed to host ENet server on port %d: %s" % [port, error_string(err)])
		return err
	multiplayer.multiplayer_peer = _peer
	mode = CoopMode.ONLINE_HOST
	if EventBus:
		EventBus.coop_mode_changed.emit(get_mode_name())
		EventBus.toast_requested.emit("联机房间已创建 (端口 %d)，等待 P2 加入..." % port, "info")
	return OK


func join_coop(address: String = "127.0.0.1", port: int = DEFAULT_PORT) -> Error:
	leave_coop()
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_client(address, port)
	if err != OK:
		_peer = null
		push_warning("[CoopManager] Failed to connect to %s:%d: %s" % [address, port, error_string(err)])
		return err
	multiplayer.multiplayer_peer = _peer
	mode = CoopMode.ONLINE_CLIENT
	if EventBus:
		EventBus.coop_mode_changed.emit(get_mode_name())
		EventBus.toast_requested.emit("正在连接联机主机 %s:%d..." % [address, port], "info")
	return OK


func leave_coop() -> void:
	_despawn_p2()
	# Seamless Drop-out: revert all P2-owned party/tactical units back to P1 (Host)
	for uid in _unit_owners.keys():
		if int(_unit_owners[uid]) == 2:
			_unit_owners[uid] = 1
	_eavesdroppers.clear()
	_dialogue_vote.clear()
	if _peer != null:
		_peer.close()
		_peer = null
	if multiplayer != null:
		multiplayer.multiplayer_peer = null
	_remote_peer_id = 0
	var prev := mode
	mode = CoopMode.SOLO
	if prev != CoopMode.SOLO and EventBus:
		EventBus.coop_mode_changed.emit("solo")


# =============================================================================
# BG3 / DOS2 / For The King RPG Co-op APIs
# (Drop-in Party Ownership, Dialogue Listen-In, Voting, Roll-Off & Skill Assist)
# =============================================================================

func assign_unit_owner(unit_id: String, player_index: int) -> void:
	_unit_owners[unit_id] = clampi(player_index, 1, 2)


func get_unit_owner(unit_id: String) -> int:
	return int(_unit_owners.get(unit_id, 1))


func get_owned_units(player_index: int) -> Array[String]:
	var out: Array[String] = []
	for uid in _unit_owners.keys():
		if int(_unit_owners[uid]) == player_index:
			out.append(str(uid))
	return out


func set_eavesdrop(player_index: int, enabled: bool) -> void:
	_eavesdroppers[player_index] = enabled


func is_eavesdropping(player_index: int) -> bool:
	return bool(_eavesdroppers.get(player_index, false))


func start_dialogue_vote(choices_count: int, rule: int = VoteRule.HOST_TIEBREAK, required_voters: int = 2) -> void:
	_dialogue_vote = {
		"active": true,
		"choices_count": maxi(1, choices_count),
		"rule": rule,
		"required_voters": maxi(1, required_voters),
		"votes": {},
		"assists": [],
	}


func offer_dialogue_assist(player_index: int, label: String, bonus: int) -> void:
	if not bool(_dialogue_vote.get("active", false)):
		return
	(_dialogue_vote["assists"] as Array).append({
		"player": player_index,
		"label": label,
		"bonus": bonus,
	})


func get_dialogue_assist_total() -> int:
	var total := 0
	for a in _dialogue_vote.get("assists", []):
		total += int(a.get("bonus", 0))
	return total


func cast_dialogue_vote(player_index: int, choice_index: int) -> Dictionary:
	if not bool(_dialogue_vote.get("active", false)):
		return {"resolved": false}
	var votes: Dictionary = _dialogue_vote["votes"]
	votes[player_index] = clampi(choice_index, 0, int(_dialogue_vote["choices_count"]) - 1)
	if votes.size() < int(_dialogue_vote["required_voters"]):
		return {"resolved": false, "votes_cast": votes.size()}

	# Tally votes
	var counts: Dictionary = {}
	for p in votes.keys():
		var c := int(votes[p])
		counts[c] = int(counts.get(c, 0)) + 1

	var best_choice := 0
	var best_count := -1
	var tied: Array[int] = []
	for c in counts.keys():
		var cnt := int(counts[c])
		if cnt > best_count:
			best_count = cnt
			best_choice = int(c)
			tied = [int(c)]
		elif cnt == best_count:
			tied.append(int(c))

	var details := {"votes": votes.duplicate(), "tied": tied.size() > 1, "rolls": {}}
	if tied.size() > 1:
		var rule := int(_dialogue_vote["rule"])
		if rule == VoteRule.ROLL_OFF:
			var high_roll := -1
			for p in votes.keys():
				var roll := randi_range(1, 20)
				details["rolls"][p] = roll
				if roll > high_roll:
					high_roll = roll
					best_choice = int(votes[p])
		else:
			best_choice = int(votes.get(1, tied[0])) # Host tiebreak

	_dialogue_vote["active"] = false
	details["resolved"] = true
	details["winner"] = best_choice
	details["assist_bonus"] = get_dialogue_assist_total()
	dialogue_vote_resolved.emit(best_choice, details)
	return details


# =============================================================================
# Player 2 Spawning & Network Sync
# =============================================================================

func _spawn_p2(actor_key: String, is_remote: bool) -> Node:
	_despawn_p2()
	var p1 := get_player(1)
	var parent_node: Node = p1.get_parent() if p1 != null else get_tree().current_scene
	if parent_node == null:
		return null

	var p2 := PlayerScript.new()
	p2.name = "Player2"
	p2.player_index = 2
	p2.action_prefix = "p2_"
	p2.is_remote_controlled = is_remote
	p2.actor_key = actor_key
	if p1 is Node2D:
		p2.global_position = (p1 as Node2D).global_position + Vector2(32.0, 0.0)
	parent_node.add_child(p2)
	players[2] = p2
	if EventBus:
		EventBus.player_joined.emit(2, p2)
	return p2


func _despawn_p2() -> void:
	var p2 := get_player(2)
	if p2 != null:
		players.erase(2)
		p2.queue_free()
		if EventBus:
			EventBus.player_left.emit(2)


func _physics_process(delta: float) -> void:
	if not is_online() or _remote_peer_id == 0:
		return
	_sync_accum += delta
	if _sync_accum < 0.05: # 20 Hz state sync
		return
	_sync_accum = 0.0
	var local_p := get_player(1)
	if local_p is Actor2D:
		var actor := local_p as Actor2D
		var anim_name := str(actor.sprite.animation) if actor.sprite != null else "idle"
		_rpc_sync_remote_player.rpc_id(
			_remote_peer_id,
			actor.global_position,
			actor.velocity,
			actor.facing,
			anim_name,
			actor.stat_block.hp,
			actor.stat_block.st
		)


@rpc("any_peer", "unreliable_ordered")
func _rpc_sync_remote_player(pos: Vector2, vel: Vector2, dir: int, anim_name: String, hp_val: float, st_val: float) -> void:
	var remote_p := get_player(2)
	if remote_p is Actor2D:
		var actor := remote_p as Actor2D
		actor.global_position = actor.global_position.lerp(pos, 0.45)
		actor.velocity = vel
		actor.set_facing(dir)
		actor.play_anim(anim_name)
		actor.stat_block.hp = hp_val
		actor.stat_block.st = st_val


func _on_room_changed(room_id: String, spawn_point: String) -> void:
	if mode == CoopMode.ONLINE_HOST and _remote_peer_id != 0:
		_rpc_sync_room.rpc_id(_remote_peer_id, room_id, spawn_point)


@rpc("authority", "reliable")
func _rpc_sync_room(room_id: String, spawn_point: String) -> void:
	if WorldManager and WorldManager.current_room_id != room_id:
		WorldManager.load_room(room_id, spawn_point)


func _on_peer_connected(peer_id: int) -> void:
	_remote_peer_id = peer_id
	_spawn_p2("player.shen_zhao", true)
	if mode == CoopMode.ONLINE_HOST and WorldManager and not WorldManager.current_room_id.is_empty():
		_rpc_sync_room.rpc_id(peer_id, WorldManager.current_room_id, "default")
	if EventBus:
		EventBus.toast_requested.emit("P2 已加入联机房间！", "gold")


func _on_peer_disconnected(peer_id: int) -> void:
	if peer_id == _remote_peer_id:
		_remote_peer_id = 0
		_despawn_p2()
		if EventBus:
			EventBus.toast_requested.emit("P2 已断开联机。", "warn")


func _on_connected_to_server() -> void:
	_remote_peer_id = 1
	_spawn_p2("player.shen_zhao", true)
	if EventBus:
		EventBus.toast_requested.emit("已成功连接到联机主机！", "gold")


func _on_server_disconnected() -> void:
	leave_coop()
	if EventBus:
		EventBus.toast_requested.emit("与联机主机断开连接。", "warn")


# =============================================================================
# Player 2 Input Bindings (Gamepad + Numpad Fallback)
# =============================================================================

func _install_p2_input_bindings(joy_id: int) -> void:
	var btn_map := {
		"p2_move_left": [JOY_BUTTON_DPAD_LEFT, KEY_KP_4],
		"p2_move_right": [JOY_BUTTON_DPAD_RIGHT, KEY_KP_6],
		"p2_move_down": [JOY_BUTTON_DPAD_DOWN, KEY_KP_5],
		"p2_jump": [JOY_BUTTON_A, KEY_KP_0],
		"p2_attack_light": [JOY_BUTTON_X, KEY_KP_1],
		"p2_attack_heavy": [JOY_BUTTON_Y, KEY_KP_2],
		"p2_dodge": [JOY_BUTTON_B, KEY_KP_3],
		"p2_guard": [JOY_BUTTON_LEFT_SHOULDER, KEY_KP_7],
		"p2_skill_ultimate": [JOY_BUTTON_RIGHT_SHOULDER, KEY_KP_8],
		"p2_interact": [JOY_BUTTON_DPAD_UP, KEY_KP_9],
	}
	for act in btn_map.keys():
		if not InputMap.has_action(act):
			InputMap.add_action(act, 0.22)
		InputMap.action_erase_events(act)

		var jb := InputEventJoypadButton.new()
		jb.device = joy_id
		jb.button_index = btn_map[act][0]
		InputMap.action_add_event(act, jb)

		var k := InputEventKey.new()
		k.keycode = btn_map[act][1]
		InputMap.action_add_event(act, k)

	# Left Stick axes for P2 movement
	for axis_spec in [
		["p2_move_left", JOY_AXIS_LEFT_X, -1.0],
		["p2_move_right", JOY_AXIS_LEFT_X, 1.0],
		["p2_move_down", JOY_AXIS_LEFT_Y, 1.0],
	]:
		var jm := InputEventJoypadMotion.new()
		jm.device = joy_id
		jm.axis = axis_spec[1]
		jm.axis_value = axis_spec[2]
		InputMap.action_add_event(axis_spec[0], jm)


func _exit_tree() -> void:
	if _peer != null:
		_peer.close()
		_peer = null
