class_name RadialMenu
extends RefCounted
## Ring menu that opens around a build pad (one per seat, both seats can have one open).
## Empty pad      -> 4 tower choices.
## Own tower Lv1  -> upgrade / target priority / sell (+ soldier rally for barracks).
## Own tower Lv2  -> two Lv3 branches / priority / sell (+ rally).
## Own tower Lv3  -> priority / sell (+ rally).
## Partner tower  -> read-only inspector.
## Works with mouse (hit testing) and with keyboard / gamepad (directional selection + confirm).

const RADIUS := 25.0
const OPT_R := 9.5

var pid: int = 1
var pad_idx: int = -1
var pad_id: String = ""
var center: Vector2 = Vector2.ZERO
var anchor: Vector2 = Vector2.ZERO
var options: Array[Dictionary] = []
var hover: int = -1
var anim: float = 0.0
var confirm_sell: bool = false
var read_only: bool = false
var title: String = ""


func build(director: CoopTDDirector, idx: int, player_id: int) -> void:
	pid = player_id
	pad_idx = idx
	var pad: Dictionary = director.pads[idx]
	pad_id = str(pad["id"])
	anchor = pad["pos"]
	center = Vector2(clampf(anchor.x, 40.0, 440.0), clampf(anchor.y, 60.0, 210.0))
	options.clear()
	hover = -1
	anim = 0.0
	confirm_sell = false
	read_only = false
	var gold := int(director.gold.get(pid, 0))
	var t := director.get_tower_at_pad(pad_id)
	if t.is_empty():
		title = "建造防御塔"
		var angles := [-135.0, -45.0, 135.0, 45.0]
		for i in range(TowerCatalog.TOWER_IDS.size()):
			var tid: String = TowerCatalog.TOWER_IDS[i]
			var def: Dictionary = director.engine.tower_defs[tid]
			var cost := int(def["cost"])
			options.append({
				"kind": "build", "tower_id": tid, "angle": angles[i], "label": str(def["name"]), "cost": cost,
				"enabled": gold >= cost, "desc": str(def.get("desc", "")), "range": float(def.get("range", 0.0)),
				"cmd": {"action": "build_or_upgrade", "pad_id": pad_id, "tower_id": tid},
				"stats": _def_stats(def),
			})
		return

	var owner := int(director.tower_owners.get(str(t["uid"]), 0))
	title = "%s Lv%d" % [str(t["name"]), int(t["level"])]
	if owner != pid:
		read_only = true
		title = "%s（P%d 的塔）" % [str(t["name"]), owner]
		return
	var ups := director.get_upgrade_options(pad_id)
	if ups.size() == 1:
		var u: Dictionary = ups[0]
		options.append({
			"kind": "upgrade", "icon": "upgrade", "angle": -90.0, "label": "升级：%s" % str(u["name"]), "cost": int(u["cost"]),
			"enabled": gold >= int(u["cost"]), "desc": "全面强化属性", "range": float(t["range"]) + _upgrade_field(director, t, 0, "range_add"),
			"cmd": {"action": "upgrade", "pad_id": pad_id, "branch": 0}, "stats": _upgrade_stats(director, t, 0),
		})
	elif ups.size() >= 2:
		for bi in range(2):
			var u: Dictionary = ups[bi]
			options.append({
				"kind": "branch", "branch": str(u["branch"]), "tower_id": str(t["tower_id"]), "angle": -135.0 if bi == 0 else -45.0,
				"label": str(u["name"]), "cost": int(u["cost"]), "enabled": gold >= int(u["cost"]), "desc": str(u["desc"]),
				"range": float(t["range"]) + _upgrade_field(director, t, bi, "range_add"),
				"cmd": {"action": "upgrade", "pad_id": pad_id, "branch": bi}, "stats": _upgrade_stats(director, t, bi),
			})
	if str(t["role"]) != "barracks":
		var pr := int(t.get("priority", 0))
		options.append({
			"kind": "priority", "icon": "target", "angle": 180.0,
			"label": "目标：%s → %s" % [TowerCatalog.PRIORITY_LABELS[pr], TowerCatalog.PRIORITY_LABELS[(pr + 1) % 4]],
			"cost": 0, "enabled": true, "desc": "切换攻击目标优先级", "range": float(t["range"]),
			"cmd": {"action": "set_priority", "pad_id": pad_id, "priority": (pr + 1) % 4}, "stats": [],
		})
	else:
		options.append({
			"kind": "rally", "icon": "flag", "angle": 180.0, "label": "集结点", "cost": 0, "enabled": true,
			"desc": "点击附近道路，重新部署卫兵", "range": 70.0, "cmd": {}, "stats": [],
		})
	var refund := director.get_sell_refund(pad_id)
	options.append({
		"kind": "sell", "icon": "sell", "angle": 90.0, "label": "出售 +%dG" % refund, "cost": 0, "enabled": true,
		"desc": "返还 70% 投入", "range": 0.0, "cmd": {"action": "sell", "pad_id": pad_id}, "stats": [], "refund": refund,
	})


func _def_stats(def: Dictionary) -> Array:
	if str(def.get("role", "")) == "barracks":
		return ["卫兵 %d 名" % int(def["soldier_count"]), "生命 %d  攻击 %d" % [int(def["soldier_hp"]), int(def["soldier_atk"])]]
	var out := ["伤害 %d  射程 %d" % [int(def["damage"]), int(def["range"])], "攻速 %.2f/秒" % float(def["fire_rate"])]
	return out


func _upgrade_entry(director: CoopTDDirector, t: Dictionary, bi: int) -> Dictionary:
	var ups := director.engine.get_available_upgrades(str(t["uid"]))
	return ups[clampi(bi, 0, ups.size() - 1)] if not ups.is_empty() else {}


func _upgrade_field(director: CoopTDDirector, t: Dictionary, bi: int, key: String) -> float:
	return float(_upgrade_entry(director, t, bi).get(key, 0.0))


func _upgrade_stats(director: CoopTDDirector, t: Dictionary, bi: int) -> Array:
	var u := _upgrade_entry(director, t, bi)
	if u.is_empty():
		return []
	if str(t["role"]) == "barracks":
		var sets: Dictionary = u.get("set", {})
		var lines := ["生命 %d→%d" % [int(t["soldier_hp"]), int(float(t["soldier_hp"]) + float(u.get("soldier_hp_add", 0.0)))],
			"攻击 %d→%d" % [int(t["soldier_atk"]), int(float(t["soldier_atk"]) + float(u.get("soldier_atk_add", 0.0)))]]
		if sets.has("soldier_count"):
			lines.append("卫兵 %d→%d" % [int(t.get("soldier_count", 2)), int(sets["soldier_count"])])
		return lines
	var base_rate := float(t.get("base_fire_rate", t["fire_rate"]))
	return [
		"伤害 %d→%d" % [int(t["damage"]), int(float(t["damage"]) + float(u.get("damage_add", 0.0)))],
		"射程 %d→%d" % [int(t["range"]), int(float(t["range"]) + float(u.get("range_add", 0.0)))],
		"攻速 %.2f→%.2f" % [base_rate, maxf(0.2, base_rate + float(u.get("fire_rate_add", 0.0)))],
	]


func option_pos(i: int) -> Vector2:
	var a := deg_to_rad(float(options[i]["angle"]))
	var k := ease(clampf(anim, 0.0, 1.0), 0.4)
	return center + Vector2(cos(a), sin(a)) * RADIUS * k


func hit(pos: Vector2) -> int:
	for i in range(options.size()):
		if pos.distance_to(option_pos(i)) <= OPT_R + 2.0:
			return i
	return -1


func is_inside(pos: Vector2) -> bool:
	return pos.distance_to(center) <= RADIUS + OPT_R + 4.0


func move_selection(dir: Vector2) -> void:
	if options.is_empty() or dir.length() < 0.3:
		return
	var best := -1
	var best_dot := -2.0
	for i in range(options.size()):
		var a := deg_to_rad(float(options[i]["angle"]))
		var d := Vector2(cos(a), sin(a)).dot(dir.normalized())
		if d > best_dot:
			best_dot = d
			best = i
	if best != hover:
		confirm_sell = false
	hover = best


func get_hovered() -> Dictionary:
	return options[hover] if hover >= 0 and hover < options.size() else {}


func tick(delta: float) -> void:
	anim = minf(1.0, anim + delta * 8.0)


func draw(canvas: CanvasItem, t: float) -> void:
	var col := UIKit.pcol(pid)
	var k := ease(clampf(anim, 0.0, 1.0), 0.4)
	canvas.draw_arc(center, RADIUS * k, 0.0, TAU, 32, Color(col.r, col.g, col.b, 0.35), 1.0)
	canvas.draw_circle(center, 3.0, Color(col.r, col.g, col.b, 0.8))
	if read_only:
		UIKit.draw_text(canvas, center + Vector2(-60, -18), title, 6, col, HORIZONTAL_ALIGNMENT_CENTER, 120)
		return
	for i in range(options.size()):
		var o: Dictionary = options[i]
		var p := option_pos(i)
		var hov := (i == hover)
		var en := bool(o["enabled"])
		var r := OPT_R + (1.5 if hov else 0.0)
		canvas.draw_circle(p + Vector2(0, 1), r + 1.0, Color(0, 0, 0, 0.45))
		var bg := Color(0.10, 0.13, 0.24) if en else Color(0.10, 0.10, 0.13)
		if str(o["kind"]) == "sell" and confirm_sell:
			bg = Color(0.45, 0.10, 0.12)
		canvas.draw_circle(p, r, bg)
		canvas.draw_arc(p, r, 0.0, TAU, 20, UIKit.GOLD if hov else (col if en else Color(0.35, 0.36, 0.42)), 1.4 if hov else 1.0)
		var mod := Color.WHITE if en else Color(0.45, 0.45, 0.50)
		var kind := str(o["kind"])
		if kind == "build" or kind == "branch":
			var branch := str(o.get("branch", ""))
			var tex := PixelTowerSprites.get_tower_texture(str(o["tower_id"]), pid, 3 if branch != "" else 1, branch)
			if tex != null:
				canvas.draw_texture_rect(tex, Rect2(p - Vector2(8, 10), Vector2(16, 18)), false, mod)
		else:
			PixelIcons.draw_icon(canvas, str(o["icon"]), p, 1, mod)
		var cost := int(o.get("cost", 0))
		if cost > 0:
			var ccol := UIKit.GOLD if en else UIKit.BAD
			var tw := UIKit.text_width(str(cost), 6) + 10.0
			var cr := Rect2(p + Vector2(-tw * 0.5, r - 1), Vector2(tw, 8))
			canvas.draw_rect(cr, Color(0.03, 0.03, 0.06, 0.92))
			PixelIcons.draw_icon(canvas, "coin", cr.position + Vector2(4.5, 4), 1, Color(1, 1, 1, 0.95))
			UIKit.draw_text(canvas, cr.position + Vector2(8, 6.5), str(cost), 6, ccol, HORIZONTAL_ALIGNMENT_LEFT, -1, false)
	var h := get_hovered()
	if not h.is_empty():
		_draw_tooltip(canvas, h)


func _draw_tooltip(canvas: CanvasItem, o: Dictionary) -> void:
	var lines: Array = o.get("stats", [])
	var desc := str(o.get("desc", ""))
	var label := str(o["label"])
	if str(o["kind"]) == "sell" and confirm_sell:
		label = "再次确认出售 +%dG" % int(o.get("refund", 0))
	var w := 112.0
	var h := 14.0 + (9.0 if desc != "" else 0.0) + 8.0 * lines.size() + 2.0
	var x := center.x + RADIUS + OPT_R + 6.0
	if x + w > 476.0:
		x = center.x - RADIUS - OPT_R - 6.0 - w
	var y := clampf(center.y - h * 0.5, 26.0, 244.0 - h)
	var r := Rect2(x, y, w, h)
	UIKit.draw_panel(canvas, r, UIKit.pcol(pid))
	UIKit.draw_text(canvas, r.position + Vector2(5, 10), label, 7, UIKit.GOLD)
	var yy := r.position.y + 10.0
	if desc != "":
		yy += 9.0
		UIKit.draw_text(canvas, Vector2(r.position.x + 5, yy), desc, 6, UIKit.TEXT_DIM)
	for line in lines:
		yy += 8.0
		UIKit.draw_text(canvas, Vector2(r.position.x + 5, yy), str(line), 6, UIKit.TEXT)
