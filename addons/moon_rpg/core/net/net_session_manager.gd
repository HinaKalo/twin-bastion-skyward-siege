class_name NetSessionManager
extends Node
## Lightweight LAN / Localhost Multiplayer Session Manager (Pure GDScript ENet).
## Supports Host / Join / Peer Roster / Reliable Command Broadcast across any
## MoonRPG genre (Tactics, Card, Strategy, Survival, ARPG Co-op), plus an
## offline loopback mode for deterministic headless testing.

enum Role { OFFLINE, HOST, CLIENT }

signal session_started(role: int, port: int)
signal session_closed()
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)
signal command_received(sender_id: int, cmd_type: String, payload: Dictionary)

var role: int = Role.OFFLINE
var active_port: int = 24560
var peers: Dictionary = {} # peer_id -> { name, joined_unix }
var command_history: Array[Dictionary] = []

var _enet: ENetMultiplayerPeer = null


func host_game(port: int = 24560, max_clients: int = 4, host_name: String = "Host") -> bool:
	close_session()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, max_clients)
	if err != OK:
		return false
	_enet = peer
	active_port = port
	role = Role.HOST
	if get_tree() != null:
		multiplayer.multiplayer_peer = peer
		if not multiplayer.peer_connected.is_connected(_on_peer_connected):
			multiplayer.peer_connected.connect(_on_peer_connected)
		if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
			multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	peers[1] = {"name": host_name, "joined_unix": int(Time.get_unix_time_from_system())}
	session_started.emit(role, port)
	return true


func join_game(address: String = "127.0.0.1", port: int = 24560) -> bool:
	close_session()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return false
	_enet = peer
	active_port = port
	role = Role.CLIENT
	if get_tree() != null:
		multiplayer.multiplayer_peer = peer
		if not multiplayer.peer_connected.is_connected(_on_peer_connected):
			multiplayer.peer_connected.connect(_on_peer_connected)
		if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
			multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	session_started.emit(role, port)
	return true


func close_session() -> void:
	if _enet != null:
		_enet.close()
		_enet = null
	if get_tree() != null and multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer = null
	var was_active := (role != Role.OFFLINE)
	role = Role.OFFLINE
	peers.clear()
	if was_active:
		session_closed.emit()


func send_command(cmd_type: String, payload: Dictionary = {}) -> void:
	if role == Role.OFFLINE or get_tree() == null or multiplayer.multiplayer_peer == null:
		# Local loopback delivery for offline / single-player / headless tests
		_deliver_command(1, cmd_type, payload.duplicate(true))
		return
	_rpc_broadcast_command.rpc(cmd_type, payload.duplicate(true))


@rpc("any_peer", "call_local", "reliable")
func _rpc_broadcast_command(cmd_type: String, payload: Dictionary) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	_deliver_command(sender, cmd_type, payload)


func _deliver_command(sender_id: int, cmd_type: String, payload: Dictionary) -> void:
	var rec := {
		"sender_id": sender_id,
		"cmd_type": cmd_type,
		"payload": payload,
		"unix": int(Time.get_unix_time_from_system()),
	}
	command_history.append(rec)
	command_received.emit(sender_id, cmd_type, payload)


func get_role_label() -> String:
	match role:
		Role.HOST: return "房主(端口:%d, 在线:%d)" % [active_port, peers.size()]
		Role.CLIENT: return "已连接客户端(端口:%d)" % active_port
		_: return "离线单机"


func _on_peer_connected(id: int) -> void:
	peers[id] = {"name": "Player_%d" % id, "joined_unix": int(Time.get_unix_time_from_system())}
	peer_joined.emit(id)


func _on_peer_disconnected(id: int) -> void:
	peers.erase(id)
	peer_left.emit(id)
