class_name FramePlatformer
extends RefCounted
## Deterministic fixed-tick side-scroller motor (60 Hz by default), ported from Tideforge
## `motion.gd` tuning so migrated levels keep their feel:
## - 6-tick coyote (ledge leave) and 8-tick jump buffer, counted in ticks not seconds
## - variable jump (release clamps rising speed), apex gravity, fast fall, terminal speed
## - ceiling corner nudge (≤ 5 px), wall kick with direction lock, one-way drop-through
## - ladders: stop at any height, climb across floors, jump off from any rung
## - launcher follow jump, air-attack hang, dive fall speed, rebound (pogo) refresh
##
## Geometry: { "solid": Array[Rect2], "platforms": Array[Rect2], "ladders": Array[Rect2] }.
## Input per tick: { x, y (stick, -1..1, y>0 = down), jump_pressed, jump_held, can_leave,
##                   follow, hang, dive, dive_follow }.

const COYOTE_TICKS := 6
const JUMP_BUFFER_TICKS := 8
const CORNER_NUDGE := 5.0
const WALL_GRACE_TICKS := 5
const WALL_LOCK_TICKS := 7
const DROP_TICKS := 10

var tick_rate: int = 60
var run_speed: float = 132.0
var ground_accel: float = 2400.0
var air_accel: float = 1500.0
var jump_speed: float = -518.0
var double_jump_speed: float = -455.0
var follow_jump_speed: float = -433.0
var follow_jump_vx: float = 148.0
var wall_kick_vx: float = 327.0
var wall_kick_vy: float = -455.0
var release_clamp: float = -253.0
var gravity_rise: float = 1300.0
var gravity_apex: float = 1070.0
var gravity_fall: float = 1770.0
var apex_band: float = 95.0
var terminal_speed: float = 720.0
var hang_gravity: float = 580.0
var hang_cap: float = 91.0
var dive_speed: float = 570.0
var dive_follow_speed: float = 645.0
var wall_slide_cap: float = 118.0
var ladder_speed: float = 84.0
var rebound_speed: float = -409.0


func dt() -> float:
	return 1.0 / float(tick_rate)


## Rebound (pogo off a hazard / enemy head): upward pop + air resources refreshed.
func rebound(b: FrameBody) -> void:
	b.vel.y = rebound_speed
	b.jump_kind = "bounce"
	b.air_jump_available = true
	b.on_ladder = false


func step(b: FrameBody, input: Dictionary, geo: Dictionary) -> void:
	b.landed_this_tick = false
	b.nudged_this_tick = 0.0
	var ix := int(signf(float(input.get("x", 0.0))))
	var iy := int(signf(float(input.get("y", 0.0))))
	var can_leave := bool(input.get("can_leave", true))

	if bool(input.get("jump_pressed", false)):
		b.jump_buf = JUMP_BUFFER_TICKS
	if b.grounded and not b.on_ladder and not _standing(b, geo):
		b.grounded = false # walked off a ledge
	if b.grounded:
		b.air_ticks = 0
		b.jumped_since_ground = false
	else:
		b.air_ticks += 1
	if b.wall_grace > 0:
		b.wall_grace -= 1
	if b.wall_lock > 0:
		b.wall_lock -= 1
	if b.drop_timer > 0:
		b.drop_timer -= 1

	# ---- Ladder ------------------------------------------------------------
	if b.on_ladder:
		_step_ladder(b, ix, iy, can_leave, geo)
		if b.jump_buf > 0:
			b.jump_buf -= 1
		return
	if b.abilities.get("ladder", true) and iy < 0 and b.jump_buf <= 0:
		var lad := _ladder_at(b, geo)
		if lad.size.x > 0.0:
			_grab_ladder(b, lad)
			return

	# ---- Jump ----------------------------------------------------------------
	var on_platform := b.grounded and _standing_on_platform_only(b, geo)
	if b.jump_buf > 0 and iy > 0 and on_platform:
		b.drop_timer = DROP_TICKS
		b.grounded = false
		b.pos.y += 1.0
		b.jump_buf = 0
	elif b.jump_buf > 0 and can_leave:
		if bool(input.get("follow", false)):
			b.vel.y = follow_jump_speed
			b.vel.x = follow_jump_vx * float(b.facing)
			b.jump_kind = "follow"
			b.jump_buf = 0
			b.jumped_since_ground = true
		elif b.grounded or (b.air_ticks <= COYOTE_TICKS and not b.jumped_since_ground and b.air_ticks > 0):
			b.vel.y = jump_speed
			b.jump_kind = "ground"
			b.jump_buf = 0
			b.grounded = false
			b.jumped_since_ground = true
		elif b.wall_grace > 0 and b.abilities.get("wall_kick", true):
			b.vel.x = -float(b.wall_dir) * wall_kick_vx
			b.vel.y = wall_kick_vy
			b.facing = -b.wall_dir
			b.wall_lock = WALL_LOCK_TICKS
			b.wall_grace = 0
			b.jump_kind = "wall"
			b.jump_buf = 0
			b.jumped_since_ground = true
		elif b.air_jump_available and b.abilities.get("double_jump", false):
			b.vel.y = double_jump_speed
			b.air_jump_available = false
			b.jump_kind = "double"
			b.jump_buf = 0
	if b.jump_buf > 0:
		b.jump_buf -= 1

	# Variable height: releasing jump clamps upward speed.
	if not bool(input.get("jump_held", false)) and b.vel.y < release_clamp and (b.jump_kind == "ground" or b.jump_kind == "double"):
		b.vel.y = release_clamp

	# ---- Horizontal ----------------------------------------------------------
	if b.wall_lock <= 0 and not bool(input.get("hold_x", false)):
		var target := float(ix) * run_speed
		var accel := ground_accel if b.grounded else air_accel
		b.vel.x = move_toward(b.vel.x, target, accel * dt())
		if ix != 0 and bool(input.get("turn", true)):
			b.facing = ix

	# ---- Gravity -------------------------------------------------------------
	if not b.grounded:
		var g := gravity_fall
		if absf(b.vel.y) < apex_band:
			g = gravity_apex
		elif b.vel.y < 0.0:
			g = gravity_rise
		var cap := terminal_speed
		if bool(input.get("hang", false)):
			g = hang_gravity
			cap = hang_cap
		b.vel.y = minf(cap, b.vel.y + g * dt())
		if bool(input.get("dive", false)):
			b.vel.y = maxf(b.vel.y, dive_follow_speed if bool(input.get("dive_follow", false)) else dive_speed)
		if b.wall_grace > 0 and b.vel.y > wall_slide_cap and ix == b.wall_dir:
			b.vel.y = wall_slide_cap

	_move_x(b, geo, ix)
	_move_y(b, geo)


func _move_x(b: FrameBody, geo: Dictionary, ix: int) -> void:
	var dx := b.vel.x * dt()
	if dx == 0.0:
		return
	b.pos.x += dx
	for s in geo.get("solid", []):
		var r: Rect2 = s
		if _overlaps(b.rect(), r):
			if dx > 0.0:
				b.pos.x = r.position.x - b.half_w
				if not b.grounded and ix > 0:
					b.wall_dir = 1
					b.wall_grace = WALL_GRACE_TICKS
			else:
				b.pos.x = r.end.x + b.half_w
				if not b.grounded and ix < 0:
					b.wall_dir = -1
					b.wall_grace = WALL_GRACE_TICKS
			b.vel.x = 0.0


func _move_y(b: FrameBody, geo: Dictionary) -> void:
	var prev_bottom := b.pos.y
	var dy := b.vel.y * dt()
	if b.grounded and dy >= 0.0:
		b.vel.y = 0.0
		return
	b.pos.y += dy
	if dy < 0.0:
		for s in geo.get("solid", []):
			var r: Rect2 = s
			if not _overlaps(b.rect(), r):
				continue
			# Corner nudge: clipping a ceiling edge by <= CORNER_NUDGE px slides around it.
			var left_overlap := b.rect().end.x - r.position.x
			var right_overlap := r.end.x - b.rect().position.x
			if left_overlap > 0.0 and left_overlap <= CORNER_NUDGE and not _blocked_at(b, geo, Vector2(-left_overlap, 0.0)):
				b.pos.x -= left_overlap
				b.nudged_this_tick = -left_overlap
				continue
			if right_overlap > 0.0 and right_overlap <= CORNER_NUDGE and not _blocked_at(b, geo, Vector2(right_overlap, 0.0)):
				b.pos.x += right_overlap
				b.nudged_this_tick = right_overlap
				continue
			b.pos.y = r.end.y + b.height
			b.vel.y = 0.0
		b.grounded = false
		return
	var landed := false
	for s in geo.get("solid", []):
		var r: Rect2 = s
		if _overlaps(b.rect(), r) and prev_bottom <= r.position.y + 0.5:
			b.pos.y = r.position.y
			landed = true
	if b.drop_timer <= 0:
		for p in geo.get("platforms", []):
			var r2: Rect2 = p
			if b.pos.x + b.half_w > r2.position.x and b.pos.x - b.half_w < r2.end.x and prev_bottom <= r2.position.y + 0.5 and b.pos.y >= r2.position.y:
				b.pos.y = r2.position.y
				landed = true
	if landed:
		if not b.grounded:
			b.landed_this_tick = true
			b.last_fall_speed = b.vel.y
		b.vel.y = 0.0
		b.grounded = true
		b.air_jump_available = true
		b.jump_kind = ""
		b.wall_lock = 0
	else:
		b.grounded = false


func _step_ladder(b: FrameBody, ix: int, iy: int, can_leave: bool, geo: Dictionary) -> void:
	b.vel = Vector2.ZERO
	b.pos.x = b.ladder_x
	if b.jump_buf > 0 and can_leave:
		b.on_ladder = false
		b.vel.y = jump_speed * 0.82
		b.vel.x = float(ix) * run_speed
		if ix != 0:
			b.facing = ix
		b.jump_kind = "ladder"
		b.jump_buf = 0
		b.jumped_since_ground = true
		_move_y(b, geo)
		return
	b.pos.y += float(iy) * ladder_speed * dt()
	var top := b.ladder_rect.position.y
	var bottom := b.ladder_rect.end.y
	if b.pos.y < top:
		# Climbed past the top rung: step onto the floor above.
		b.pos.y = top
		b.on_ladder = false
		b.grounded = true
		return
	if b.pos.y >= bottom:
		b.pos.y = bottom
		b.on_ladder = false
		b.grounded = _standing(b, geo)


func _grab_ladder(b: FrameBody, lad: Rect2) -> void:
	b.on_ladder = true
	b.ladder_rect = lad
	b.ladder_x = lad.get_center().x
	b.pos.x = b.ladder_x
	b.vel = Vector2.ZERO
	b.grounded = false
	b.air_jump_available = true
	b.jump_kind = ""


func _ladder_at(b: FrameBody, geo: Dictionary) -> Rect2:
	for l in geo.get("ladders", []):
		var r: Rect2 = l
		if b.pos.x >= r.position.x and b.pos.x <= r.end.x and b.pos.y > r.position.y and b.pos.y - b.height < r.end.y:
			return r
	return Rect2()


## Public ground probe (used to settle freshly spawned bodies).
func is_standing(b: FrameBody, geo: Dictionary) -> bool:
	return _standing(b, geo)


func _standing(b: FrameBody, geo: Dictionary) -> bool:
	var probe := Rect2(b.pos.x - b.half_w, b.pos.y, b.half_w * 2.0, 1.0)
	for s in geo.get("solid", []):
		if probe.intersects(s):
			return true
	for p in geo.get("platforms", []):
		if probe.intersects(p):
			return true
	return false


func _standing_on_platform_only(b: FrameBody, geo: Dictionary) -> bool:
	var probe := Rect2(b.pos.x - b.half_w, b.pos.y, b.half_w * 2.0, 1.0)
	for s in geo.get("solid", []):
		if probe.intersects(s):
			return false
	for p in geo.get("platforms", []):
		if probe.intersects(p):
			return true
	return false


func _blocked_at(b: FrameBody, geo: Dictionary, offset: Vector2) -> bool:
	var r := b.rect()
	r.position += offset
	for s in geo.get("solid", []):
		if _overlaps(r, s):
			return true
	return false


static func _overlaps(a: Rect2, b: Rect2) -> bool:
	return a.position.x < b.end.x - 0.001 and a.end.x > b.position.x + 0.001 and a.position.y < b.end.y - 0.001 and a.end.y > b.position.y + 0.001
