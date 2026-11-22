extends Node
## Global Session Autoload for Twin Bastion TD.
## Coordinates Play Mode (SOLO_AI / LOCAL_2P / LAN_HOST / LAN_CLIENT),
## Selected Campaign Stage, Persistent MetaProgress, NetSessionManager, and ReplaySession.

enum PlayMode { SOLO_AI, LOCAL_2P, LAN_HOST, LAN_CLIENT }

var play_mode: int = PlayMode.SOLO_AI
var selected_stage_id: String = "stage_1_twin_bridge"
var local_player_id: int = 1 # 1 for Host/Solo/Local, 2 for LAN Client
var meta := MetaProgress.new()
var net: NetSessionManager
var replay := ReplaySession.new()


func _ready() -> void:
	meta.load_from_disk()
	net = NetSessionManager.new()
	add_child(net)


func is_ai_partner_enabled() -> bool:
	return play_mode == PlayMode.SOLO_AI


func get_mode_label() -> String:
	match play_mode:
		PlayMode.SOLO_AI: return "单人 + AI搭档"
		PlayMode.LOCAL_2P: return "同屏双人 (2P)"
		PlayMode.LAN_HOST: return "局域网房主 (P1)"
		PlayMode.LAN_CLIENT: return "局域网加入 (P2)"
		_: return "合作模式"
