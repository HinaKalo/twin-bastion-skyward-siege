class_name ActionArenaSim
extends RefCounted
## Deterministic headless action-combat simulation ("动作校场" core).
##
## Fixed 60 Hz ticks. Fighters (player seats) run ActionGraph + ActionRunner + DefenseState on a
## FramePlatformer body; targets are dummies / shielded soldiers / juggle-able enemies; hazards are
## thorn beds. Contacts are resolved by HitResolver (pogo before hazard damage). Hitstop freezes only
## the attacker and the struck target through a SimClock — the rest of the arena keeps running.
##
## Tests and the playable arena sample drive the exact same code, so migration fixtures can be
## written as "press these buttons on these ticks, expect this state" without calling damage APIs.

signal combat_event(event: Dictionary)

var clock: SimClock = SimClock.new(60)
var platformer: FramePlatformer = FramePlatformer.new()
var resolver: HitResolver = HitResolver.new()
var geo: Dictionary = {"solid": [], "platforms": [], "ladders": []}
var fighters: Dictionary = {}   # seat:int -> Dictionary
var targets: Dictionary = {}    # id -> Dictionary
var hazards: Array[Dictionary] = []
var events: Array[Dictionary] = []
var event_limit: int = 512
var base_graph: ActionGraph = null
var _event_seq: int = 0


func set_geometry(solid: Array, platforms: Array = [], ladders: Array = []) -> void:
	geo = {"solid": solid.duplicate(), "platforms": platforms.duplicate(), "ladders": ladders.duplicate()}


func add_hazard(id: String, rect: Rect2, damage: float = 10.0, surface: String = "thorns") -> void:
	hazards.append({"id": id, "rect": rect, "damage": damage, "surface": surface})


## Adds a player seat. `weapon` is a weapon definition dictionary (content/data/action/weapons/*).
func add_fighter(seat: int, at: Vector2, graph: ActionGraph, weapon: Dictionary = {}) -> Dictionary:
	var g := graph.with_weapon(weapon) if not weapon.is_empty() else graph
	var body := FrameBody.new("p%d" % seat, at)
	body.grounded = platformer.is_standing(body, geo)
	var f := {
		"seat": seat, "id": "p%d" % seat, "body": body, "runner": ActionRunner.new(g), "defense": DefenseState.new(),
		"weapon": weapon, "hp": 100.0, "max_hp": 100.0, "dodge": 0, "dodge_cd": 0, "dodge_dir": 1, "dash_tail": 0,
		"guard_down": false, "hit_registry": {}, "charge": 0.0, "last_input": {},
	}
	fighters[seat] = f
	return f


func set_weapon(seat: int, weapon: Dictionary) -> void:
	var f: Dictionary = fighters[seat]
	var runner: ActionRunner = f["runner"]
	var g: ActionGraph = base_graph if base_graph != null else runner.graph
	runner.set_graph(g.with_weapon(weapon))
	f["weapon"] = weapon


## Adds a target. kind: dummy | soldier | shield | rat ... `tier`: 1 fodder, 2 soldier, 3 rival, 4 elite.
func add_target(id: String, at: Vector2, opts: Dictionary = {}) -> Dictionary:
	var body := FrameBody.new(id, at)
	body.half_w = float(opts.get("half_w", 9.0))
	body.height = float(opts.get("height", 30.0))
	body.facing = int(opts.get("facing", -1))
	body.grounded = platformer.is_standing(body, geo)
	var t := {
		"id": id, "body": body, "hp": float(opts.get("hp", 100.0)), "max_hp": float(opts.get("hp", 100.0)),
		"tier": int(opts.get("tier", 1)), "shield": bool(opts.get("shield", false)), "static": bool(opts.get("static", false)),
		"juggle": 0, "stagger": 0, "dead": false, "hits": 0, "surface": str(opts.get("surface", "body")),
	}
	targets[id] = t
	return t


func fighter(seat: int) -> Dictionary:
	return fighters.get(seat, {})


func runner_of(seat: int) -> ActionRunner:
	return fighters[seat]["runner"]


func body_of(seat: int) -> FrameBody:
	return fighters[seat]["body"]


# =============================================================================
# Tick
# =============================================================================

## inputs: { seat: { x, y, jump, jump_held, light, heavy, dodge, guard (held) } }
func step(inputs: Dictionary = {}) -> Dictionary:
	var contacts: Array = []
	for seat in fighters.keys():
		_step_fighter(fighters[seat], inputs.get(seat, {}), contacts)
	for tid in targets.keys():
		_step_target(targets[tid])
	var resolved := resolver.resolve(contacts)
	for c in resolved:
		_apply_contact(c)
	clock.step_once()
	return state()


func _step_fighter(f: Dictionary, inp: Dictionary, contacts: Array) -> void:
	var fid := str(f["id"])
	var body: FrameBody = f["body"]
	var runner: ActionRunner = f["runner"]
	var defense: DefenseState = f["defense"]
	var frozen := clock.is_frozen(fid)
	var dir := Vector2i(int(signf(float(inp.get("x", 0.0)))), int(signf(float(inp.get("y", 0.0)))))
	runner.begin_tick(dir, body.grounded, frozen)
	if bool(inp.get("light", false)):
		runner.press("light")
	if bool(inp.get("heavy", false)):
		runner.press("heavy")
	if bool(inp.get("dodge", false)):
		runner.press("dodge")
	var guard_held := bool(inp.get("guard", false))
	if guard_held and not bool(f["guard_down"]):
		defense.press_guard()
	elif not guard_held and bool(f["guard_down"]):
		defense.release_guard()
	f["guard_down"] = guard_held
	f["last_input"] = inp
	if frozen:
		runner.step() # keeps the buffer (TTL paused) while frozen
		if bool(inp.get("jump", false)):
			body.jump_buf = FramePlatformer.JUMP_BUFFER_TICKS # jump decided during hitstop is kept
		return
	defense.tick()
	if int(f["dodge_cd"]) > 0:
		f["dodge_cd"] = int(f["dodge_cd"]) - 1
	if int(f["dash_tail"]) > 0:
		f["dash_tail"] = int(f["dash_tail"]) - 1

	# Dodge (defensive cancel): recovery or hit-confirm window, never mid-whiff.
	if runner.trace.has("dodge") and int(f["dodge"]) <= 0 and int(f["dodge_cd"]) <= 0 and runner.can_cancel_defensively():
		runner.trace.consume("dodge", "dodge")
		runner.cancel_to_free("dodge")
		f["dodge"] = 9
		f["dodge_cd"] = 30
		f["dodge_dir"] = dir.x if dir.x != 0 else body.facing
		body.facing = int(f["dodge_dir"])
		runner.facing = body.facing
		defense.start_dodge(8, 6)
		_emit({"phase": "startup", "kind": "dodge", "seat": f["seat"], "attacker": fid})
	elif runner.trace.has("dodge") and int(f["dodge"]) <= 0:
		runner.trace.mark_blocked("dodge", "cancel_window" if runner.is_busy() else "cooldown")

	runner.flags["dash_tail"] = int(f["dash_tail"]) > 0 or (int(f["dodge"]) > 0 and int(f["dodge"]) <= 5)
	runner.flags["counter"] = defense.counter > 0
	runner.facing = body.facing if not runner.is_busy() else runner.facing
	var evs := runner.step()
	for e in evs:
		if e["type"] == "start" or e["type"] == "cancel":
			if int(f["dodge"]) > 0:
				f["dodge"] = 0
				f["dash_tail"] = 0
			f["hit_registry"] = {}
			body.facing = runner.facing
			_emit({"phase": "startup", "kind": e["type"], "move": e["move"], "from": e.get("from", ""), "from_age": e.get("from_age", 0), "seat": f["seat"], "attacker": fid})
			if e["move"] == "counter":
				defense.counter = 0
	if int(f["dodge"]) > 0:
		f["dodge"] = int(f["dodge"]) - 1
		if int(f["dodge"]) == 0:
			f["dash_tail"] = 7

	# Motion
	var mv: MoveDef = runner.move
	var age := runner.age
	var minput := {"x": dir.x, "y": dir.y, "jump_pressed": bool(inp.get("jump", false)), "jump_held": bool(inp.get("jump_held", inp.get("jump", false))),
		"can_leave": runner.can_jump_cancel(), "turn": runner.turn_allowed()}
	if mv != null:
		minput["x"] = 0
		minput["turn"] = false
		if mv.has_tag("launcher") and runner.launched:
			minput["follow"] = true
		if mv.has_tag("air") and not body.grounded and age < mv.active_end():
			minput["hang"] = true
		if mv.has_tag("dive") and age >= mv.windup - 1:
			minput["dive"] = true
			minput["dive_follow"] = runner.follow
		var rm: Variant = mv.root_motion_at(age)
		if rm != null:
			body.vel.x = (rm as Vector2).x * float(runner.facing)
			minput["hold_x"] = true
		elif age == mv.windup - 1:
			body.vel.x += float(runner.facing) * float(mv.hit.get("step", 0.0)) * 3.8
	if int(f["dodge"]) > 0:
		body.vel.x = float(f["dodge_dir"]) * 300.0
		minput["hold_x"] = true
		minput["x"] = 0
	var kind_before := body.jump_kind
	platformer.step(body, minput, geo)
	if body.jump_kind != kind_before and body.jump_kind in ["ground", "follow", "wall", "double", "ladder"] and runner.is_busy():
		runner.cancel_to_free("jump")
	if body.landed_this_tick:
		runner.refresh_air()
	if not runner.is_busy():
		runner.facing = body.facing

	# Strikes vs targets
	mv = runner.move
	if mv != null and mv.is_active_at(runner.age):
		var seg := mv.segment_at(runner.age)
		for tid in targets.keys():
			var t: Dictionary = targets[tid]
			if bool(t["dead"]):
				continue
			var key := "%d|%d|%s" % [runner.serial, seg, tid]
			if (f["hit_registry"] as Dictionary).has(key):
				continue
			if _in_strike_range(f, mv, t):
				f["hit_registry"][key] = true
				var tb: FrameBody = t["body"]
				var surface := str(t["surface"])
				if bool(t["shield"]) and signf(body.pos.x - tb.pos.x) == float(tb.facing) and int(t["stagger"]) <= 0:
					surface = "shield_front"
				contacts.append({"attacker": fid, "target": tid, "kind": "strike", "attack_tag": _attack_tag(f, mv),
					"surface_tag": surface, "distance": absf(tb.pos.x - body.pos.x), "seat": f["seat"], "move": mv.id})
		# Dive vs hazards (blade reaches the thorns before the body does)
		if mv.has_tag("dive"):
			for h in hazards:
				var hr: Rect2 = h["rect"]
				if body.pos.x + body.half_w > hr.position.x and body.pos.x - body.half_w < hr.end.x and body.pos.y >= hr.position.y - 34.0 and body.pos.y <= hr.position.y + 13.0:
					contacts.append({"attacker": fid, "target": str(h["id"]), "kind": "strike", "attack_tag": "dive", "surface_tag": str(h["surface"]), "distance": 0.0, "seat": f["seat"], "move": mv.id})
	# Body vs hazards
	for h in hazards:
		if body.rect().intersects(h["rect"]):
			contacts.append({"attacker": str(h["id"]), "target": fid, "kind": "hazard", "attack_tag": "body", "surface_tag": str(h["surface"]), "distance": 0.0, "damage": float(h["damage"]), "seat": f["seat"]})


func _attack_tag(f: Dictionary, mv: MoveDef) -> String:
	return str(mv.hit.get("attack_tag", "dive" if mv.has_tag("dive") else "blade"))


func _in_strike_range(f: Dictionary, mv: MoveDef, t: Dictionary) -> bool:
	var body: FrameBody = f["body"]
	var tb: FrameBody = t["body"]
	var facing := int((f["runner"] as ActionRunner).facing)
	var dx := tb.pos.x - body.pos.x
	var rel := dx * float(facing)
	var both := bool(mv.hit.get("both_sides", false))
	if not both and rel < -19.0:
		return false
	if absf(dx) >= float(mv.hit.get("reach", 40.0)) + tb.half_w:
		return false
	var dy := tb.center().y - body.center().y
	var allow := tb.height * 0.37
	if bool(mv.hit.get("narrow", false)):
		return absf(dy) <= 21.0
	var top := float(mv.hit.get("y_top", 45.0))
	var bottom := float(mv.hit.get("y_bottom", 34.0))
	return dy >= -(top + allow) and dy <= bottom + allow


func _step_target(t: Dictionary) -> void:
	if bool(t["static"]) or bool(t["dead"]):
		return
	var tid := str(t["id"])
	if clock.is_frozen(tid):
		return
	if int(t["stagger"]) > 0:
		t["stagger"] = int(t["stagger"]) - 1
	var tb: FrameBody = t["body"]
	tb.vel.x = move_toward(tb.vel.x, 0.0, 900.0 * clock.step_seconds())
	platformer.step(tb, {"x": 0, "hold_x": true, "turn": false}, geo)
	if tb.grounded and int(t["juggle"]) > 0:
		t["juggle"] = 0


func _apply_contact(c: Dictionary) -> void:
	var result := str(c["result"])
	var kind := str(c.get("kind", ""))
	if kind == "hazard":
		var f := _fighter_by_id(str(c["target"]))
		if f.is_empty() or result != "hurt":
			_emit({"phase": "contact", "result": result, "reason": c.get("reason", ""), "target": c["target"], "seat": c.get("seat", 0), "source": c["attacker"]})
			return
		var out := (f["defense"] as DefenseState).resolve_incoming({"damage": float(c.get("damage", 10.0)), "floor_trap": true})
		f["hp"] = float(f["hp"]) - float(out["damage"])
		_emit({"phase": "contact", "result": "hurt" if float(out["damage"]) > 0.0 else str(out["result"]), "damage": out["damage"], "target": c["target"], "seat": f["seat"], "source": c["attacker"], "material": "thorns"})
		return
	var af := _fighter_by_id(str(c["attacker"]))
	if af.is_empty():
		return
	var runner: ActionRunner = af["runner"]
	var mv: MoveDef = runner.move
	if mv == null:
		return
	match result:
		"pogo":
			platformer.rebound(af["body"])
			runner.cancel_to_free("pogo")
			runner.refresh_air()
			(af["defense"] as DefenseState).inv = maxi((af["defense"] as DefenseState).inv, 8)
			_emit({"phase": "contact", "result": "pogo", "seat": af["seat"], "attacker": c["attacker"], "target": c["target"], "material": c["surface_tag"]})
		"deflect", "clash", "parry":
			runner.report_contact("blocked")
			clock.freeze(str(c["attacker"]), 4, "blocked")
			_emit({"phase": "contact", "result": result, "seat": af["seat"], "attacker": c["attacker"], "target": c["target"], "move": mv.id, "material": "metal", "reason": c.get("reason", "")})
		"hit":
			var t: Dictionary = targets.get(str(c["target"]), {})
			if t.is_empty():
				return
			var dmg := float(mv.hit.get("damage", 10.0))
			t["hp"] = float(t["hp"]) - dmg
			t["hits"] = int(t["hits"]) + 1
			var tb: FrameBody = t["body"]
			var launched := false
			if mv.has_tag("launcher") and int(t["tier"]) <= 2:
				tb.vel.y = -425.0
				tb.grounded = false
				t["juggle"] = 1
				t["stagger"] = maxi(int(t["stagger"]), 30)
				launched = true
			elif mv.has_tag("air") and int(t["juggle"]) > 0:
				t["juggle"] = int(t["juggle"]) + 1
				tb.vel.y = -212.0 if int(t["juggle"]) < 4 else -85.0
			elif mv.has_tag("dive") and runner.follow and int(t["juggle"]) > 0:
				tb.vel.y = 530.0
			else:
				tb.vel.x = float(runner.facing) * float(mv.hit.get("knockback", 100.0)) * 0.5
			runner.report_contact("hit", launched)
			var hs := int(mv.hit.get("hitstop", 4))
			clock.freeze(str(c["attacker"]), hs, "hitstop")
			clock.freeze(str(c["target"]), hs, "hitstop")
			if float(t["hp"]) <= 0.0:
				t["dead"] = true
			_emit({"phase": "contact", "result": "hit", "seat": af["seat"], "attacker": c["attacker"], "target": c["target"], "move": mv.id,
				"damage": dmg, "nth": c.get("nth", 1), "order": c.get("order", 1), "launched": launched, "material": "flesh"})


## An enemy strike against a seat (fixture helper: "the soldier swings at P1 now").
## `from_x` decides whether the defender faces the source.
func enemy_strike(seat: int, from_x: float, damage: float = 12.0, floor_trap: bool = false) -> Dictionary:
	var f: Dictionary = fighters[seat]
	var body: FrameBody = f["body"]
	var facing_ok := signf(from_x - body.pos.x) == float(body.facing) or is_equal_approx(from_x, body.pos.x)
	var out := (f["defense"] as DefenseState).resolve_incoming({"damage": damage, "facing_ok": facing_ok, "floor_trap": floor_trap})
	f["hp"] = float(f["hp"]) - float(out["damage"])
	if str(out["result"]) == "hit":
		(f["runner"] as ActionRunner).cancel_to_free("hurt")
	_emit({"phase": "contact", "result": out["result"], "damage": out["damage"], "seat": seat, "target": f["id"], "source": "enemy", "reward": out["reward"]})
	return out


func _fighter_by_id(fid: String) -> Dictionary:
	for seat in fighters.keys():
		if str(fighters[seat]["id"]) == fid:
			return fighters[seat]
	return {}


func _emit(e: Dictionary) -> void:
	_event_seq += 1
	e["event_id"] = "t%d#%d" % [clock.tick, _event_seq]
	e["tick"] = clock.tick
	events.append(e)
	if events.size() > event_limit:
		events.pop_front()
	combat_event.emit(e)


func events_of(result_or_kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in events:
		if str(e.get("result", "")) == result_or_kind or str(e.get("kind", "")) == result_or_kind:
			out.append(e)
	return out


## Compact deterministic state (for InputRecorder hashing and replay comparison).
func state() -> Dictionary:
	var fs := {}
	for seat in fighters.keys():
		var f: Dictionary = fighters[seat]
		var b: FrameBody = f["body"]
		fs[str(seat)] = {"pos": b.pos, "vel": b.vel, "hp": f["hp"], "run": (f["runner"] as ActionRunner).debug_state()}
	var ts := {}
	for tid in targets.keys():
		var t: Dictionary = targets[tid]
		ts[tid] = {"pos": (t["body"] as FrameBody).pos, "hp": t["hp"], "juggle": t["juggle"]}
	return {"tick": clock.tick, "fighters": fs, "targets": ts}


## Runs `n` ticks with the same input (helper for fixtures).
func run(n: int, inputs: Dictionary = {}) -> void:
	for _i in range(n):
		step(inputs)


## Standard flat arena: floor at y=200 spanning x 0..width.
func build_flat(width: float = 640.0, floor_y: float = 200.0) -> void:
	set_geometry([Rect2(-200.0, floor_y, width + 400.0, 80.0)])
