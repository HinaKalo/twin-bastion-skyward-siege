class_name ActionRunner
extends RefCounted
## Per-fighter frame stepper for an ActionGraph.
##
## Owns the current move, its age, contact outcome (hit / blocked / break / whiff), chain depth,
## air-attack count, launcher-follow state and the InputTrace + CommandParser. Pure logic: the
## node layer (PlayerController) or a headless sim (ActionArenaSim) feeds it stick direction,
## grounded state, presses and contact reports, and reads back events.
##
## Per tick: `begin_tick(dir, grounded, frozen)` → node presses `press()` → `step()` returns events:
## { type: "start" | "cancel" | "end" | "active" | "event", move, age, ... }.

var graph: ActionGraph
var trace: InputTrace = InputTrace.new()
var parser: CommandParser = CommandParser.new()

var move: MoveDef = null
var age: int = 0
var facing: int = 1
var start_facing: int = 1
var chain_depth: int = 0
var contact: String = ""        # "", "hit", "blocked", "break"
var contact_age: int = -1000
var confirmed: bool = false
var hits_this_move: int = 0
var air_count: int = 0
var launched: bool = false       # current/last launcher connected (enables follow jump)
var follow: bool = false         # current move is a follow-up after a launcher / air confirm
var last_move: String = ""
var since_end: int = 999999
var serial: int = 0
var tick_count: int = 0
var frozen: bool = false
var grounded: bool = true
var dir_now: Vector2i = Vector2i.ZERO
## Owner-supplied state flags for edge conditions (e.g. counter, dash_tail, ability unlocks).
var flags: Dictionary = {}


func _init(g: ActionGraph = null) -> void:
	graph = g


func set_graph(g: ActionGraph) -> void:
	graph = g
	cancel_to_free("graph_changed")


func is_busy() -> bool:
	return move != null


func current_id() -> String:
	return move.id if move != null else ""


func phase() -> String:
	return move.phase_at(age) if move != null else "free"


func ctx() -> Dictionary:
	return {
		"move": move, "age": age, "confirmed": confirmed, "contact": contact, "contact_age": contact_age,
		"grounded": grounded, "facing": facing, "start_facing": start_facing, "dir_now": dir_now,
		"chain_depth": chain_depth, "air_count": air_count, "launched": launched,
		"last_move": last_move, "since_end": since_end, "command_parser": parser, "flags": flags,
	}


## Feed stick + environment for this tick. Frozen fighters keep their buffer (TTL paused).
func begin_tick(dir: Vector2i, on_ground: bool, is_frozen: bool = false) -> void:
	tick_count += 1
	dir_now = dir
	grounded = on_ground
	frozen = is_frozen
	if not frozen:
		parser.feed(dir)


func press(input: String) -> Dictionary:
	return trace.push(input, tick_count, dir_now, facing)


## Report the outcome of a contact this tick (from HitResolver / Hitbox2D).
## "hit" and "break" confirm the move; "blocked" makes the move use its blocked cancel age.
func report_contact(result: String, target_launched: bool = false) -> void:
	if move == null:
		return
	hits_this_move += 1
	if result == "hit" or result == "break":
		if not confirmed:
			confirmed = true
			contact_age = age
		contact = result
		if move.has_tag("launcher") and target_launched:
			launched = true
	elif contact.is_empty():
		contact = result


## Advances one tick and resolves the buffer. Returns emitted events.
func step() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	trace.tick(frozen)
	if frozen:
		return out
	if move != null:
		age += 1
		for e in move.events_at(age):
			out.append({"type": "event", "move": move.id, "age": age, "event": e})
		if move.is_active_at(age):
			out.append({"type": "active", "move": move.id, "age": age, "segment": move.segment_at(age)})
		if age >= move.total_frames():
			out.append({"type": "end", "move": move.id, "age": age, "contact": contact if not contact.is_empty() else "whiff"})
			_end_move()
	else:
		since_end += 1
	if grounded:
		air_count = 0
	var started := try_resolve()
	if not started.is_empty():
		out.append(started)
	return out


## Resolves buffered attack inputs now (also callable mid-tick after contact reports).
func try_resolve() -> Dictionary:
	if graph == null:
		return {}
	var buffered := trace.pending()
	if buffered.is_empty():
		return {}
	var res := graph.resolve(ctx(), buffered)
	var blocked: Dictionary = res["blocked"]
	for input in blocked.keys():
		trace.mark_blocked(str(input), str(blocked[input]))
	var target: MoveDef = res["move"]
	if target == null:
		return {}
	var edge: Dictionary = res["edge"]
	var entry: Dictionary = res["entry"]
	trace.consume(str(entry["input"]), target.id)
	if not str(edge.get("command", "")).is_empty():
		parser.consume()
	var was := current_id()
	var was_age := age
	var chained := move != null
	var was_confirmed := confirmed
	var was_air_confirmed := move != null and move.has_tag("air") and confirmed
	start_move(target, int(res["facing"]), chained)
	follow = (was_air_confirmed and target.has_tag("dive")) or bool(edge.get("follow", false))
	return {
		"type": "cancel" if chained else "start", "move": target.id, "from": was, "from_age": was_age,
		"input": entry["input"], "confirmed_from": was_confirmed, "edge_priority": edge["priority"],
	}


func start_move(m: MoveDef, new_facing: int = 0, chained: bool = false) -> void:
	if new_facing != 0:
		facing = new_facing
	start_facing = facing
	chain_depth = chain_depth + 1 if chained else 1
	move = m
	age = 0
	contact = ""
	contact_age = -1000
	confirmed = false
	hits_this_move = 0
	serial += 1
	if not chained:
		launched = false
	elif not m.has_tag("air") and not m.has_tag("dive"):
		launched = false
	if m.has_tag("air"):
		air_count += 1


func _end_move() -> void:
	last_move = move.id if move != null else ""
	move = null
	age = 0
	since_end = 0
	chain_depth = 0
	contact = ""
	confirmed = false
	follow = false


## Defensive cancel gate (dodge / guard / jump-out).
func can_cancel_defensively() -> bool:
	if move == null:
		return true
	return graph.defensive_cancel_open(ctx()) if graph != null else true


## Jump cancel: recovery, or a connected launcher after windup + 2 (follow jump).
func can_jump_cancel() -> bool:
	if move == null:
		return true
	if move.is_recovery(age - (4 if move.has_tag("dive") else 0)):
		return true
	return move.has_tag("launcher") and launched and age >= move.windup + 2


func cancel_to_free(reason: String = "interrupted") -> void:
	if move != null:
		last_move = move.id
		since_end = 0
	move = null
	age = 0
	chain_depth = 0
	contact = ""
	confirmed = false
	follow = false
	if reason == "hurt":
		trace.clear("hurt")


## Air resources refresh (landing, pogo rebound).
func refresh_air() -> void:
	air_count = 0


func turn_allowed() -> bool:
	return move == null or not move.is_facing_locked_at(age)


func debug_state() -> Dictionary:
	return {
		"move": current_id(), "age": age, "phase": phase(), "chain": chain_depth, "contact": contact,
		"confirmed": confirmed, "air": air_count, "launched": launched, "follow": follow, "facing": facing,
	}
