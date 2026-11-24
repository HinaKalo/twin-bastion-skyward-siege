class_name UnitArtRenderer
extends RefCounted
## Draws creeps, soldiers and heroes from PixelCreepSprites with facing, walk cycles, flight bob, attack lunges,
## hit flash, status icons (slow / burn / stun / shield / haste) and compact HP + shield bars.

static var _last_x: Dictionary = {} # uid -> last x (for facing)
static var _facing_left: Dictionary = {} # uid -> bool


static func get_portrait(pid: int) -> Texture2D:
	return PixelCreepSprites.get_frame("hero_p%d" % pid, 0, pid)


static func creep_draw_size(enemy_id: String) -> float:
	return float(PixelCreepSprites.get_width(enemy_id))


static func _phase(uid: String) -> float:
	return float(hash(uid) % 997) * 0.013


static func _update_facing(uid: String, x: float) -> bool:
	if _last_x.size() > 600:
		_last_x.clear()
		_facing_left.clear()
	var prev := float(_last_x.get(uid, x))
	if x < prev - 0.05:
		_facing_left[uid] = true
	elif x > prev + 0.05:
		_facing_left[uid] = false
	_last_x[uid] = x
	return bool(_facing_left.get(uid, false))


static func draw_creep(canvas: CanvasItem, c: Dictionary, flash: bool, t: float) -> void:
	var eid := str(c["enemy_id"])
	var uid := str(c.get("uid", ""))
	var cp: Vector2 = c["pos"]
	var fly := bool(c["is_flying"])
	var boss := bool(c.get("is_boss", false))
	var w := float(PixelCreepSprites.get_width(eid))
	var stunned := float(c.get("stun_timer", 0.0)) > 0.0
	var blocked := str(c.get("blocked_by", "")) != ""
	var slow := float(c.get("slow_timer", 0.0)) > 0.0
	var speed_k := float(c.get("slow_factor", 1.0)) if slow else 1.0
	var ph := _phase(uid)
	var anim_rate := (9.0 if fly else 6.0) * speed_k
	var pose := _active_pose(c, t)
	var moving := not blocked and float(c.get("speed", 0.0)) > 0.0
	var frame := int(floor(t * anim_rate + ph * 10.0)) if moving and not stunned else 0
	var left := _update_facing(uid, cp.x)
	if not pose.is_empty():
		left = float((c["pose_target"] as Vector2).x) < cp.x
		frame = 2 if pose == "strike" else 0
	var tex := PixelCreepSprites.get_frame(eid, frame, 0, left)
	var lift := 0.0
	if fly and not bool(c.get("diving", false)):
		lift = 12.0 + sin(t * 4.0 + ph) * 2.0
	var squash := 1.0
	if boss and not stunned:
		squash = 1.0 + 0.04 * sin(t * 5.0 + ph)
	# shadow
	var sh_w := w * (0.45 if fly else 0.62)
	_ellipse(canvas, cp + Vector2(0, 2), Vector2(sh_w, sh_w * 0.32), Color(0, 0, 0, 0.30 if fly else 0.36))
	if boss:
		var ar := w * 0.62 + 1.5 * sin(t * 6.0)
		canvas.draw_arc(cp + Vector2(0, 2), ar, 0.0, TAU, 28, Color(1.0, 0.25, 0.28, 0.55), 1.2)
	# haste trail
	if float(c.get("haste_timer", 0.0)) > 0.0:
		for k in range(3):
			var off := Vector2(-6.0 - k * 4.0, -w * 0.3 - k * 2) * (Vector2(-1, 1) if left else Vector2.ONE)
			canvas.draw_line(cp + off, cp + off + Vector2(-5 if not left else 5, 0), Color(1.0, 0.45, 0.30, 0.6), 1.0)
	var accent := Color(0.7, 0.91, 1.0) if pose == "frost_roar" else Color(0.98, 0.72, 0.49)
	var dest := _pose_rect(cp, w, w * squash, lift, pose, left, c, t)
	var mod := Color.WHITE
	if flash:
		mod = Color(3.0, 3.0, 3.0)
	elif stunned:
		mod = Color(0.75, 0.90, 1.25)
	elif slow:
		mod = Color(0.65, 0.88, 1.15)
	if blocked and not stunned:
		dest.position.x += sin(t * 18.0 + ph) * 0.8
	canvas.draw_texture_rect(tex, dest, false, mod)
	if not pose.is_empty():
		_draw_action_pixels(canvas, cp - Vector2(0, lift + w * 0.45), left, w, pose, accent)
	if float(c.get("shield", 0.0)) > 0.0:
		var sc := cp - Vector2(0, dest.size.y * 0.5 - 2.0 + lift)
		canvas.draw_arc(sc, w * 0.55, 0.0, TAU, 24, Color(0.55, 0.85, 1.0, 0.55 + 0.2 * sin(t * 6.0)), 1.2)
	# bars
	var top := dest.position.y - 3.0
	var bw := 22.0 if boss else 12.0
	var hp_pct := clampf(float(c["hp"]) / maxf(1.0, float(c["max_hp"])), 0.0, 1.0)
	if hp_pct < 0.999 or boss or float(c.get("shield", 0.0)) > 0.0:
		var br := Rect2(cp.x - bw * 0.5, top, bw, 2)
		canvas.draw_rect(br.grow(1), Color(0.05, 0.04, 0.06, 0.9))
		canvas.draw_rect(Rect2(br.position, Vector2(bw * hp_pct, 2)), Color(1.0, 0.30, 0.30) if hp_pct > 0.3 else Color(1.0, 0.65, 0.2))
		var ms := float(c.get("max_shield", 0.0))
		if ms > 0.0 and float(c.get("shield", 0.0)) > 0.0:
			canvas.draw_rect(Rect2(br.position + Vector2(0, -3), Vector2(bw * clampf(float(c["shield"]) / ms, 0.0, 1.0), 1)), Color(0.55, 0.88, 1.0))
		top -= 3.0
	# status icons
	var icons: Array[String] = []
	if stunned:
		icons.append("stun")
	if slow:
		icons.append("snow")
	if float(c.get("dot_timer", 0.0)) > 0.0:
		icons.append("flame")
	if float(c.get("shred_timer", 0.0)) > 0.0:
		icons.append("armor")
	var ix := cp.x - (icons.size() - 1) * 4.0
	for i in range(icons.size()):
		canvas.draw_texture_rect(PixelIcons.get_icon(icons[i]), Rect2(Vector2(ix + i * 8.0 - 3.5, top - 8.0), Vector2(7, 7)), false)


static func draw_soldier(canvas: CanvasItem, s: Dictionary, owner: int, is_hero: bool, moving: bool, target: Vector2, t: float) -> void:
	var sp: Vector2 = s["pos"]
	var uid := str(s.get("uid", ""))
	var ph := _phase(uid)
	var sprite := "soldier"
	var pal_owner := owner
	if is_hero:
		sprite = "hero_p%d" % owner
	elif bool(s.get("is_reinforcement", false)):
		pal_owner = 3
	var left := _update_facing(uid, sp.x)
	if not moving:
		left = target.x < sp.x - 0.5 if absf(target.x - sp.x) > 0.5 else left
	var frame := int(floor(t * 8.0 + ph * 10.0)) if moving else 0
	var pose := _active_pose(s, t)
	if not pose.is_empty():
		left = (s["pose_target"] as Vector2).x < sp.x
		frame = 0
	var tex := PixelCreepSprites.get_frame(sprite, frame, pal_owner, left)
	var lunge := 0.0
	var acd := float(s.get("attack_cd", 0.0))
	if acd > 0.62:
		lunge = (acd - 0.62) * 9.0
	var bob := absf(sin(t * 6.0 + ph)) * 0.8 if not moving else 0.0
	_ellipse(canvas, sp + Vector2(0, 2), Vector2(7.0 if is_hero else 6.0, 2.2), Color(0, 0, 0, 0.34))
	if is_hero:
		canvas.draw_arc(sp + Vector2(0, 2), 8.5, 0.0, TAU, 18, Color(UIKit.pcol(owner).r, UIKit.pcol(owner).g, UIKit.pcol(owner).b, 0.8), 1.2)
	var dest := _pose_rect(sp, 16, 16, bob, pose, left, s, t)
	dest.position.x += lunge if not left else -lunge
	canvas.draw_texture_rect(tex, dest, false)
	if not pose.is_empty() or lunge > 0.6:
		_draw_action_pixels(canvas, sp - Vector2(0, 8), left, 16, pose if not pose.is_empty() else "strike", UIKit.pcol(owner))
	var hp_pct := clampf(float(s["hp"]) / maxf(1.0, float(s["max_hp"])), 0.0, 1.0)
	if hp_pct < 0.999 or is_hero:
		var bw := 12.0 if is_hero else 9.0
		var br := Rect2(sp.x - bw * 0.5, dest.position.y - 2.0, bw, 2 if is_hero else 1)
		canvas.draw_rect(br.grow(1), Color(0.05, 0.04, 0.06, 0.9))
		canvas.draw_rect(Rect2(br.position, Vector2(bw * hp_pct, br.size.y)), UIKit.GOOD)
	if bool(s.get("is_reinforcement", false)):
		var life := float(s.get("lifetime", 0.0))
		if life > 0.0 and life < 3.0 and fmod(t, 0.3) < 0.15:
			canvas.draw_texture_rect(tex, dest, false, Color(1, 1, 1, 0.4))


static func _active_pose(actor: Dictionary, t: float) -> String:
	return str(actor.get("pose", "")) if t < float(actor.get("pose_until", 0.0)) else ""


static func _pose_rect(foot: Vector2, w: float, h: float, lift: float, pose: String, left: bool, actor: Dictionary, t: float) -> Rect2:
	var shift := 0.0
	if not pose.is_empty():
		var begin := float(actor["pose_start"])
		var progress := clampf((t - begin) / maxf(0.016, float(actor["pose_until"]) - begin), 0.0, 1.0)
		var step := floorf(progress * 4.0) * 0.25
		match pose:
			"strike":
				shift = (1.0 - step) * w * 0.12
				h *= 0.90 + 0.10 * step
			"frost_roar", "war_cry", "summon", "cast":
				h *= 1.0 + 0.08 * step
				lift += 3.0 * step
			_:
				shift = -w * 0.12 * step
				h *= 1.0 - 0.10 * step
	return Rect2((foot + Vector2(-w * 0.5 + shift * (-1.0 if left else 1.0), -h + 2.0 - lift)).round(), Vector2(w, roundf(h)))


static func _draw_action_pixels(canvas: CanvasItem, center: Vector2, left: bool, width: float, pose: String, color: Color) -> void:
	var hand := (center + Vector2(width * (0.38 if not left else -0.38), -1)).round()
	var side := -1.0 if left else 1.0
	match pose:
		"strike":
			canvas.draw_line(hand + Vector2(side * 2, 1), hand + Vector2(side * 10, -3), Color(color, 0.65), 2.0)
			canvas.draw_rect(Rect2(hand + Vector2(side * 9, -4), Vector2(2, 2)), Color.WHITE)
		"smash", "draw":
			canvas.draw_line(hand, hand + Vector2(side * -3, -7), color.darkened(0.45), 2.0)
			canvas.draw_rect(Rect2(hand + Vector2(side * -3 - 2, -9), Vector2(5, 3)), color)
		"cast", "summon", "frost_roar", "war_cry":
			canvas.draw_rect(Rect2(hand + Vector2(-1, -5), Vector2(3, 3)), color)
			canvas.draw_rect(Rect2(hand + Vector2(0, -8), Vector2(1, 2)), Color.WHITE)


static func _ellipse(canvas: CanvasItem, center: Vector2, radii: Vector2, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in range(14):
		var a := TAU * float(i) / 14.0
		pts.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	canvas.draw_colored_polygon(pts, col)
