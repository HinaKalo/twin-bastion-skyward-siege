class_name BattleHUD
extends CanvasLayer
## Battle HUD for Twin Bastion: a 22px top bar and a 22px bottom dock, custom-drawn in the pixel style.
## Top bar : P1 block (portrait, HP, gold, kills) | lives, wave, difficulty | P2 block (mirrored)
## Dock    : P1 skill + gift | call-wave (countdown, early bonus) | Synchro gauge | speed | pause | P2 gift + skill
## Buttons are hit-tested manually and reported through `action(id)`.

signal action(id: String)
signal minimap_clicked(world_pos: Vector2)

const TOP_H := 22.0
const DOCK_Y := 248.0
const MM_RECT := Rect2(368, 24, 108, 61)

var director: CoopTDDirector = null
var ai_seat: int = 0 # seat driven by AI (0 = none)
var speed_mult: float = 1.0
var paused: bool = false
var highlight: String = ""
var portraits: Dictionary = {}
var keys: Dictionary = {
	1: {"skill": "Q", "gift": "T", "ult": "R"},
	2: {"skill": "/", "gift": ",", "ult": "RC"},
}
var local_seats: Array[int] = [1, 2]
var banner_text: String = ""
var banner_color: Color = Color(1.0, 0.94, 0.30)
var banner_alpha: float = 0.0
var minimap_visible: bool = true
var world_size: Vector2 = Vector2(480, 270)
var road_polys: Array = []
var view_rect: Rect2 = Rect2()
var alerts: Array = [] # [{pos, ttl}]
var arrival_forecast: Dictionary = {}

var _t: float = 0.0
var _top: _Strip
var _dock: _Strip
var _banner: _Strip
var _mm: _Strip
var _buttons: Array[Dictionary] = []
var _hover: String = ""


class _Strip extends Control:
	var hud: BattleHUD
	var strip_id: String = ""

	func _draw() -> void:
		hud._draw_strip(self, strip_id)

	func _gui_input(event: InputEvent) -> void:
		hud._strip_input(self, strip_id, event)


func _ready() -> void:
	layer = 5
	_top = _Strip.new()
	_top.hud = self
	_top.strip_id = "top"
	_top.position = Vector2.ZERO
	_top.size = Vector2(480, TOP_H)
	_top.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_top)
	_dock = _Strip.new()
	_dock.hud = self
	_dock.strip_id = "dock"
	_dock.position = Vector2(0, DOCK_Y)
	_dock.size = Vector2(480, 270 - DOCK_Y)
	_dock.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dock)
	_banner = _Strip.new()
	_banner.hud = self
	_banner.strip_id = "banner"
	_banner.position = Vector2(0, TOP_H)
	_banner.size = Vector2(480, 16)
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_banner)
	_mm = _Strip.new()
	_mm.hud = self
	_mm.strip_id = "minimap"
	_mm.position = MM_RECT.position
	_mm.size = MM_RECT.size
	_mm.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_mm)


func refresh(delta: float) -> void:
	_t += delta
	_top.queue_redraw()
	_dock.queue_redraw()
	_banner.queue_redraw()
	_mm.visible = minimap_visible and world_size.x > 480.0
	if _mm.visible:
		_mm.queue_redraw()


func is_point_on_hud(p: Vector2) -> bool:
	return p.y < TOP_H or p.y >= DOCK_Y or (_mm != null and _mm.visible and MM_RECT.has_point(p))


# ------------------------------------------------------------------ input

func _strip_input(strip: Control, sid: String, event: InputEvent) -> void:
	if sid == "minimap":
		var held := event is InputEventMouseMotion and ((event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT) != 0
		var press := event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
		if held or press:
			var lp: Vector2 = (event as InputEventMouse).position
			minimap_clicked.emit(lp / MM_RECT.size * world_size)
			strip.accept_event()
		return
	if event is InputEventMouseMotion:
		_hover = _button_at(sid, (event as InputEventMouseMotion).position)
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var id := _button_at(sid, (event as InputEventMouseButton).position)
		if id != "":
			action.emit(id)
			strip.accept_event()


func _button_at(sid: String, p: Vector2) -> String:
	for b in _buttons:
		if str(b["strip"]) == sid and (b["rect"] as Rect2).has_point(p) and bool(b["enabled"]):
			return str(b["id"])
	return ""


func _register(sid: String, id: String, r: Rect2, enabled: bool) -> void:
	_buttons.append({"strip": sid, "id": id, "rect": r, "enabled": enabled})


# ------------------------------------------------------------------ drawing

func _draw_strip(c: Control, sid: String) -> void:
	if director == null:
		return
	if sid == "banner":
		_draw_banner(c)
	elif sid == "minimap":
		_draw_minimap(c)
	elif sid == "top":
		_buttons = _buttons.filter(func(b): return str(b["strip"]) != "top")
		_draw_top(c)
	else:
		_buttons = _buttons.filter(func(b): return str(b["strip"]) != "dock")
		_draw_dock(c)


func _draw_minimap(c: Control) -> void:
	var sz := MM_RECT.size
	var k := sz / world_size
	c.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.03, 0.04, 0.08, 0.86))
	for poly in road_polys:
		var pts := PackedVector2Array()
		for q in poly:
			pts.append((q as Vector2) * k)
		c.draw_polyline(pts, Color(0.62, 0.52, 0.36, 0.9), 1.0)
	var gate: Vector2 = TerrainBaker.gate_pos(director.stage_def) * k
	c.draw_rect(Rect2(gate - Vector2(2, 3), Vector2(4, 6)), UIKit.GOLD)
	for lane in arrival_forecast:
		var entry: Dictionary = arrival_forecast[lane]
		var p := (entry["pos"] as Vector2) * k
		var col := UIKit.BAD if lane == "portal" or float(entry["seconds"]) <= 5.0 else UIKit.GOLD
		c.draw_arc(p, 3.0 + 0.5 * sin(_t * 6.0), 0.0, TAU, 10, col, 1.0)
	for pad in director.pads:
		if bool(pad.get("ruin", false)) and not director.pad_to_tower_uid.has(str(pad["id"])):
			c.draw_rect(Rect2((pad["pos"] as Vector2) * k - Vector2(1, 1), Vector2(2, 2)), Color(0.45, 0.45, 0.48))
	for uid in director.engine.towers.keys():
		var t: Dictionary = director.engine.towers[uid]
		var col := UIKit.pcol(int(director.tower_owners.get(uid, 1)))
		var tp := (t["pos"] as Vector2) * k
		c.draw_rect(Rect2(tp - Vector2(1.5, 1.5), Vector2(3, 3)), col if float(t.get("hp", 1.0)) > float(t.get("max_hp", 1.0)) * 0.35 else UIKit.BAD)
	for cr in director.engine.creeps:
		var cp := (cr["pos"] as Vector2) * k
		if bool(cr.get("is_boss", false)):
			var blink := 1.0 if fmod(_t, 0.5) < 0.3 else 0.4
			c.draw_rect(Rect2(cp - Vector2(2, 2), Vector2(4, 4)), Color(1.0, 0.25, 0.25, blink))
		else:
			c.draw_rect(Rect2(cp, Vector2(1, 1)), Color(1.0, 0.35, 0.30))
	for pid in [1, 2]:
		var h: Dictionary = director.heroes.get(pid, {})
		if not h.is_empty() and float(h["hp"]) > 0.0:
			var hp := (h["pos"] as Vector2) * k
			c.draw_rect(Rect2(hp - Vector2(1.5, 1.5), Vector2(3, 3)), Color.WHITE)
			c.draw_rect(Rect2(hp - Vector2(1, 1), Vector2(2, 2)), UIKit.pcol(pid))
	for al in alerts:
		var ap := (al["pos"] as Vector2) * k
		var r := 3.0 + fmod(_t * 8.0, 4.0)
		c.draw_arc(ap, r, 0.0, TAU, 10, Color(1.0, 0.3, 0.25, clampf(float(al["ttl"]), 0.0, 1.0)), 1.0)
	if view_rect.size.x > 0.0:
		c.draw_rect(Rect2(view_rect.position * k, view_rect.size * k), Color(1, 1, 1, 0.85), false, 1.0)
	c.draw_rect(Rect2(Vector2.ZERO, sz), UIKit.GOLD_DIM, false, 1.0)
	UIKit.draw_text(c, Vector2(sz.x - 3, sz.y - 2), "M", 5, UIKit.TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_banner(c: Control) -> void:
	if banner_alpha <= 0.01 or banner_text == "":
		return
	var w := minf(470.0, UIKit.text_width(banner_text, 7) + 20.0)
	var r := Rect2(240.0 - w * 0.5, 2, w, 12)
	c.draw_rect(r, Color(0.03, 0.04, 0.09, 0.82 * banner_alpha))
	c.draw_rect(Rect2(r.position, Vector2(r.size.x, 1)), Color(banner_color.r, banner_color.g, banner_color.b, 0.6 * banner_alpha))
	c.draw_rect(Rect2(r.position + Vector2(0, r.size.y - 1), Vector2(r.size.x, 1)), Color(banner_color.r, banner_color.g, banner_color.b, 0.6 * banner_alpha))
	UIKit.draw_text(c, Vector2(r.position.x, r.position.y + 9), banner_text, 7, Color(banner_color.r, banner_color.g, banner_color.b, banner_alpha), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)


func _draw_top(c: Control) -> void:
	c.draw_rect(Rect2(0, 0, 480, TOP_H), Color(0.05, 0.06, 0.13, 0.96))
	c.draw_rect(Rect2(0, TOP_H - 1, 480, 1), UIKit.GOLD_DIM)
	c.draw_rect(Rect2(0, TOP_H - 2, 480, 1), Color(0, 0, 0, 0.5))
	_draw_player_block(c, 1)
	_draw_player_block(c, 2)

	# Center: lives / wave / difficulty
	var lives := director.engine.lives
	var lcol := UIKit.TEXT if float(lives) / float(director.max_lives) > 0.5 else (UIKit.GOLD if lives > 3 else UIKit.BAD)
	var cx := 240.0
	c.draw_rect(Rect2(cx - 78, 2, 156, 17), Color(0.02, 0.03, 0.07, 0.8))
	c.draw_rect(Rect2(cx - 78, 2, 156, 17), Color(UIKit.GOLD_DIM.r, UIKit.GOLD_DIM.g, UIKit.GOLD_DIM.b, 0.5), false, 1.0)
	var pulse := 1.0 + (0.25 * absf(sin(_t * 8.0)) if lives <= 5 else 0.0)
	PixelIcons.draw_icon(c, "heart", Vector2(cx - 68, 10.5), 1, Color(pulse, pulse, pulse))
	UIKit.draw_text(c, Vector2(cx - 61, 14), "%d/%d" % [lives, director.max_lives], 8, lcol)
	PixelIcons.draw_icon(c, "skull", Vector2(cx - 18, 10.5))
	var total := director.wave_dir.get_total_waves()
	var wave_txt := ("第 %d 波" % maxi(1, director.wave_dir.current_wave_index + 1)) if director.endless else ("%d/%d 波" % [maxi(0, director.wave_dir.current_wave_index + 1), total])
	UIKit.draw_text(c, Vector2(cx - 11, 14), wave_txt, 8, UIKit.TEXT)
	var dlabel := str(CoopTDDirector.DIFFICULTIES[director.difficulty]["label"]) + ("·无尽" if director.endless else "")
	var dcol := UIKit.GOOD if director.difficulty == "casual" else (UIKit.BAD if director.difficulty == "hard" else UIKit.GOLD)
	UIKit.draw_text(c, Vector2(cx + 34, 14), dlabel, 7, dcol, HORIZONTAL_ALIGNMENT_CENTER, 42)


func _draw_player_block(c: Control, pid: int) -> void:
	var col := UIKit.pcol(pid)
	var right := pid == 2
	var px := 3.0 if not right else 459.0
	var portrait_r := Rect2(px, 2, 18, 18)
	c.draw_rect(portrait_r, Color(0.02, 0.03, 0.07))
	var tex: Texture2D = portraits.get(pid, null)
	if tex != null:
		c.draw_texture_rect(tex, portrait_r.grow(-1), false)
	c.draw_rect(portrait_r, col, false, 1.0)
	var hero: Dictionary = director.heroes.get(pid, {})
	var dead := not hero.is_empty() and float(hero["hp"]) <= 0.0
	if dead:
		c.draw_rect(portrait_r.grow(-1), Color(0, 0, 0, 0.6))
		UIKit.draw_text(c, Vector2(px, 14), "%d" % ceili(float(hero.get("respawn_timer", 0.0))), 8, UIKit.BAD, HORIZONTAL_ALIGNMENT_CENTER, 18)
	var name_txt := ("P1 岚 · 苍穹游侠" if pid == 1 else "P2 赫 · 绯红圣骑") + (" · AI" if ai_seat == pid else "")
	var nx := px + 22.0 if not right else px - 4.0
	var align := HORIZONTAL_ALIGNMENT_LEFT if not right else HORIZONTAL_ALIGNMENT_RIGHT
	var name_w := 70.0
	UIKit.draw_text(c, Vector2(nx - (name_w if right else 0.0), 9), name_txt, 6, col, align, name_w)
	var hp_pct := 0.0 if hero.is_empty() else float(hero["hp"]) / maxf(1.0, float(hero["max_hp"]))
	var bar_x := nx if not right else nx - 46.0
	UIKit.draw_bar(c, Rect2(bar_x, 13, 46, 3), hp_pct, UIKit.GOOD if hp_pct > 0.35 else UIKit.BAD)
	# gold
	var gx := 100.0 if not right else 380.0
	PixelIcons.draw_icon(c, "coin", Vector2(gx - 26, 11))
	UIKit.draw_text(c, Vector2(gx - 20, 15), str(int(director.gold[pid])), 8, UIKit.GOLD)
	# kills
	var kx := 136.0 if not right else 344.0
	PixelIcons.draw_icon(c, "sword", Vector2(kx - 8, 11), 1, Color(1, 1, 1, 0.85))
	UIKit.draw_text(c, Vector2(kx - 2, 15), str(int(director.stats[pid]["kills"])), 7, UIKit.TEXT_DIM)


func _draw_dock(c: Control) -> void:
	var h := 270.0 - DOCK_Y
	c.draw_rect(Rect2(0, 0, 480, h), Color(0.05, 0.06, 0.13, 0.96))
	c.draw_rect(Rect2(0, 0, 480, 1), UIKit.GOLD_DIM)
	_draw_seat_buttons(c, 1, 4.0)
	_draw_seat_buttons(c, 2, 412.0)

	# Call wave
	var wr := Rect2(72, 3, 66, 16)
	var has_next := director.wave_dir.has_next_wave() or director.endless
	var can_ready := director.can_ready_wave()
	var label := "开战" if director.required_ready_seats == 1 else "就绪"
	if director.wave_dir.current_wave_index >= 0:
		if not has_next:
			label = "最终波"
		elif director.wave_countdown > 0.0:
			label = "休整 %ds" % ceili(director.wave_countdown)
		else:
			label = director.get_wave_phase()
	_button_bg(c, wr, Color(0.80, 0.34, 0.22), "call_wave", can_ready)
	PixelIcons.draw_icon(c, "play", wr.position + Vector2(8, 8), 1, Color.WHITE if has_next else Color(0.5, 0.5, 0.5))
	UIKit.draw_text(c, wr.position + Vector2(14, 11), label, 7, UIKit.TEXT if has_next else UIKit.TEXT_DIM)
	var bonus := director.get_early_call_bonus()
	if director.required_ready_seats == 2 and (can_ready or director.wave_countdown > 0.0):
		for pid in [1, 2]:
			var pos := wr.end - Vector2(19 - pid * 6, 11)
			c.draw_rect(Rect2(pos, Vector2(4, 5)), UIKit.pcol(pid) if director.ready_seats.has(pid) else UIKit.TEXT_DIM.darkened(0.4))
	elif bonus > 0 and can_ready:
		UIKit.draw_text(c, wr.position + Vector2(46, 11), "+%d" % bonus, 6, UIKit.GOLD)
	if director.wave_countdown > 0.0:
		var frac := director.wave_countdown / maxf(1.0, director.countdown_total)
		c.draw_rect(Rect2(wr.position.x + 1, wr.end.y - 2, (wr.size.x - 2) * frac, 1), UIKit.GOLD)
	_register("dock", "call_wave", wr, can_ready)

	# Synchro gauge
	var gr := Rect2(144, 4, 168, 14)
	var pct := director.synchro_charge / 100.0
	var ready := pct >= 1.0
	c.draw_rect(gr.grow(1), UIKit.INK)
	c.draw_rect(gr, Color(0.08, 0.05, 0.14))
	var fw := floorf((gr.size.x) * pct)
	if fw > 0:
		var steps := int(fw / 2.0)
		for i in range(steps):
			var f := float(i) / maxf(1.0, gr.size.x / 2.0)
			var gcol := UIKit.P1.lerp(UIKit.P2, f)
			if ready:
				gcol = gcol.lightened(0.25 + 0.2 * sin(_t * 9.0 + f * 6.0))
			c.draw_rect(Rect2(gr.position.x + i * 2, gr.position.y, 2, gr.size.y), gcol)
		c.draw_rect(Rect2(gr.position.x, gr.position.y, fw, 1), Color(1, 1, 1, 0.35))
	c.draw_rect(gr, UIKit.GOLD if ready else UIKit.GOLD_DIM, false, 1.0)
	var gtxt := "双星合体 %d%%" % int(director.synchro_charge)
	var gcol2 := UIKit.TEXT
	if director.synchro_pending_by != 0:
		var waiting := 3 - director.synchro_pending_by
		gtxt = "等待 P%d 响应 %.1fs" % [waiting, director.synchro_window_timer]
		gcol2 = UIKit.GOLD
	elif ready:
		gtxt = "合体就绪！ %s · %s" % [_key_label(1, "ult"), _key_label(2, "ult")] if ai_seat == 0 else "合体就绪！按 %s 发起" % _key_label(1, "ult")
		gcol2 = Color(1.0, 0.95, 0.55)
	UIKit.draw_text(c, Vector2(gr.position.x, gr.position.y + 10), gtxt, 7, gcol2, HORIZONTAL_ALIGNMENT_CENTER, gr.size.x)
	_register("dock", "ult", gr, ready)

	# Speed & pause
	var sr := Rect2(318, 3, 26, 16)
	_button_bg(c, sr, Color(0.30, 0.40, 0.58), "speed", true)
	PixelIcons.draw_icon(c, "fast", sr.position + Vector2(7, 8))
	UIKit.draw_text(c, sr.position + Vector2(12, 11), "%dx" % int(speed_mult), 6, UIKit.GOLD if speed_mult > 1.0 else UIKit.TEXT)
	_register("dock", "speed", sr, true)
	var pr := Rect2(347, 3, 18, 16)
	_button_bg(c, pr, Color(0.30, 0.40, 0.58), "pause", true)
	PixelIcons.draw_icon(c, "pause", pr.get_center())
	_register("dock", "pause", pr, true)
	UIKit.draw_text(c, Vector2(368, 13), "Esc", 5, UIKit.TEXT_DIM)


func _draw_seat_buttons(c: Control, pid: int, x0: float) -> void:
	var col := UIKit.pcol(pid)
	var is_ai := ai_seat == pid
	var local := local_seats.has(pid)
	var right := pid == 2
	var skill_r := Rect2(x0 + (34.0 if right else 0.0), 3, 30, 16)
	var gift_r := Rect2(x0 + (0.0 if right else 34.0), 3, 30, 16)
	var cd := float(director.hero_skill_cd.get(pid, 0.0))
	var cd_max := float(director.hero_skill_max.get(pid, 1.0))
	var can_skill := cd <= 0.0 and local and not is_ai
	_button_bg(c, skill_r, col, "p%d_skill" % pid, local and not is_ai)
	PixelIcons.draw_icon(c, "meteor" if pid == 1 else "shield", skill_r.position + Vector2(9, 8), 1, Color.WHITE if cd <= 0.0 else Color(0.55, 0.55, 0.6))
	if cd > 0.0:
		var frac := cd / maxf(1.0, cd_max)
		c.draw_rect(Rect2(skill_r.position.x + 1, skill_r.position.y + 1, (skill_r.size.x - 2) * frac, skill_r.size.y - 2), Color(0, 0, 0, 0.45))
		UIKit.draw_text(c, skill_r.position + Vector2(15, 11), "%d" % ceili(cd), 7, UIKit.TEXT)
	elif not is_ai:
		UIKit.draw_keycap(c, skill_r.position + Vector2(22, 8), _key_label(pid, "skill"), 5, col)
	if is_ai:
		UIKit.draw_text(c, skill_r.position + Vector2(15, 11), "AI", 6, UIKit.TEXT_DIM)
	_register("dock", "p%d_skill" % pid, skill_r, can_skill)

	var can_gift := int(director.gold[pid]) >= 50 and local and not is_ai
	_button_bg(c, gift_r, Color(0.70, 0.56, 0.16), "p%d_gift" % pid, local and not is_ai)
	PixelIcons.draw_icon(c, "gift", gift_r.position + Vector2(7, 8), 1, Color.WHITE if can_gift else Color(0.5, 0.5, 0.55))
	UIKit.draw_text(c, gift_r.position + Vector2(12, 11), "50", 6, UIKit.GOLD if can_gift else UIKit.TEXT_DIM)
	if not is_ai and local:
		UIKit.draw_keycap(c, gift_r.position + Vector2(25, 8), _key_label(pid, "gift"), 5, UIKit.TEXT_DIM)
	_register("dock", "p%d_gift" % pid, gift_r, can_gift)


func _button_bg(c: Control, r: Rect2, accent: Color, id: String, enabled: bool) -> void:
	var hov := _hover == id and enabled
	var glow := highlight == id
	var bg := accent.darkened(0.62) if enabled else Color(0.09, 0.10, 0.14)
	if hov:
		bg = accent.darkened(0.42)
	c.draw_rect(r, bg)
	c.draw_rect(Rect2(r.position, Vector2(r.size.x, 1)), Color(1, 1, 1, 0.10))
	var border := UIKit.GOLD if (hov or glow) else (accent.darkened(0.1) if enabled else Color(0.25, 0.27, 0.34))
	c.draw_rect(r, border, false, 1.0)
	if glow:
		var a := 0.5 + 0.5 * sin(_t * 8.0)
		c.draw_rect(r.grow(2), Color(UIKit.GOLD.r, UIKit.GOLD.g, UIKit.GOLD.b, a), false, 1.0)


func _key_label(pid: int, what: String) -> String:
	return str((keys.get(pid, {}) as Dictionary).get(what, "?"))
