class_name CoopAIPartner
extends RefCounted
## Smart Autonomous P2 Co-op AI Partner for Twin Bastion TD.
## Allows solo players to enjoy the full 2-Player Co-op synergy loop:
## - Builds & upgrades P2 / Shared pads along the south & center lanes
## - Actively chooses complementary tower types near P1 towers to trigger Co-op Combos!
## - Sends +50G to P1 whenever P1 is strapped for gold and P2 has surplus
## - Immediately responds to P1's Synchro Ultimate request!

var decision_interval: float = 1.6
var _timer: float = 0.8


func tick(delta: float, director: CoopTDDirector) -> void:
	if director == null or delta <= 0.0:
		return
	# 1. Instant response to P1's Synchro Ultimate request!
	if director.synchro_pending_by == 1 and director.synchro_charge >= 100.0:
		director.execute_command({"player_id": 2, "action": "synchro_ult"})
		return

	_timer -= delta
	if _timer > 0.0:
		return
	_timer = decision_interval

	var g2 := int(director.gold.get(2, 0))
	var g1 := int(director.gold.get(1, 0))

	# 2. Generous Co-op Gold Transfer if P1 is poor and P2 is rich
	if g1 < 55 and g2 >= 135:
		director.execute_command({"player_id": 2, "action": "transfer_gold", "amount": 50})
		return

	# 3. Build on P2 or Shared empty pad, preferring combo synergy with nearby P1 towers!
	for pad in director.pads:
		var hint := int(pad.get("owner_hint", 0))
		if hint == 1:
			continue
		var pid := str(pad["id"])
		if director.pad_to_tower_uid.has(pid):
			continue
		var chosen := _choose_synergy_tower(pad["pos"] as Vector2, director)
		if g2 >= director.get_tower_cost(chosen):
			director.execute_command({
				"player_id": 2, "action": "build_or_upgrade", "pad_id": pid, "tower_id": chosen,
			})
			return

	# 4. Upgrade an existing P2 tower if all P2 pads are populated
	for pad in director.pads:
		var pid := str(pad["id"])
		if not director.pad_to_tower_uid.has(pid):
			continue
		var tuid := str(director.pad_to_tower_uid[pid])
		if int(director.tower_owners.get(tuid, 1)) != 2:
			continue
		var t: Dictionary = director.engine.towers.get(tuid, {})
		if not t.is_empty() and int(t["level"]) < 3 and g2 >= int(t.get("upgrade_cost", 60)):
			director.execute_command({"player_id": 2, "action": "build_or_upgrade", "pad_id": pid, "tower_id": str(t["tower_id"])})
			return


func _choose_synergy_tower(pad_pos: Vector2, director: CoopTDDirector) -> String:
	# Look for a nearby P1 tower within COMBO_RADIUS and pick its ideal combo partner!
	for uid in director.engine.towers.keys():
		if int(director.tower_owners.get(uid, 1)) != 1:
			continue
		var t: Dictionary = director.engine.towers[uid]
		if (t["pos"] as Vector2).distance_to(pad_pos) <= CoopTDDirector.COMBO_RADIUS:
			var tid := str(t["tower_id"])
			if tid == "frost":
				return "mage"
			elif tid == "mage":
				return "frost"
			elif tid == "arrow":
				return "barracks"
			elif tid == "barracks":
				return "arrow"
	# Otherwise maintain a balanced mix on south lane
	var p2_count := 0
	for o in director.tower_owners.values():
		if int(o) == 2:
			p2_count += 1
	var cycle := ["arrow", "barracks", "mage", "frost"]
	return cycle[p2_count % cycle.size()]
