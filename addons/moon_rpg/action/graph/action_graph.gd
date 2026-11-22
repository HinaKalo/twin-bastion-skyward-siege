class_name ActionGraph
extends RefCounted
## Data-driven action graph: moves are nodes, input-triggered edges are derivations.
##
## Resolution happens once per tick and picks at most one move, by input priority then
## edge priority, so simultaneous presses resolve deterministically in the same frame.
## Every refusal is reported with the name of the gating condition so InputTrace can show
## why an input was blocked.
##
## Edge schema:
## { "from": "free" | "<move id>" | "*" | "tag:<tag>",
##   "input": "light" | "heavy" | "ultimate" | ...,
##   "to": "<move id>",
##   "dir": "any" | "neutral" | "up" | "down" | "not_down" | "fwd" | "back" | "side",
##   "dir_sample": "press" (stick at the moment of the press) | "current" | "start_facing",
##   "command": "" | "qcf" | "launcher",
##   "turn": bool  (face the sampled horizontal direction when the move starts),
##   "when": { "grounded": bool, "confirmed": bool, "min_delay": int, "fresh": int,
##             "air_count_lt": int, "launched": bool, "contact": "hit"|"blocked"|"whiff",
##             "after": { "move": id, "within": ticks }, "flags": { name: bool } },
##   "priority": int }

const DEFAULT_INPUT_PRIORITY := ["ultimate", "heavy", "light"]

var id: String = ""
var max_links: int = 5
var hit_cancel_delay: int = 0
var hit_cancel_window: int = 13
var startup_cancel: int = 0
var input_priority: Array = DEFAULT_INPUT_PRIORITY.duplicate()
var moves: Dictionary = {} # id -> MoveDef
var edges: Array[Dictionary] = []
var weapon_id: String = ""


static func from_dict(d: Dictionary) -> ActionGraph:
	var g := ActionGraph.new()
	g.id = str(d.get("id", "graph"))
	g.max_links = int(d.get("max_links", 5))
	g.hit_cancel_delay = int(d.get("hit_cancel_delay", 0))
	g.hit_cancel_window = int(d.get("hit_cancel_window", 13))
	g.startup_cancel = int(d.get("startup_cancel", 0))
	if d.has("input_priority"):
		g.input_priority = (d["input_priority"] as Array).duplicate()
	var md: Dictionary = d.get("moves", {})
	for mid in md.keys():
		g.moves[str(mid)] = MoveDef.from_dict(str(mid), md[mid])
	for e in d.get("edges", []):
		g.add_edge(e)
	return g


static func load_json(path: String) -> ActionGraph:
	if not FileAccess.file_exists(path):
		push_error("[ActionGraph] missing graph file: %s" % path)
		return null
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("[ActionGraph] invalid graph json: %s" % path)
		return null
	return from_dict(parsed)


func add_edge(e: Dictionary) -> void:
	var edge := e.duplicate(true)
	edge["from"] = str(edge.get("from", "free"))
	edge["input"] = str(edge.get("input", "light"))
	edge["dir"] = str(edge.get("dir", "any"))
	edge["dir_sample"] = str(edge.get("dir_sample", "press"))
	edge["command"] = str(edge.get("command", ""))
	edge["priority"] = int(edge.get("priority", 0))
	edge["when"] = (edge.get("when", {}) as Dictionary)
	edges.append(edge)


func get_move(move_id: String) -> MoveDef:
	return moves.get(move_id, null)


## Validation: every edge target / source exists. Returns error strings.
func validate() -> Array[String]:
	var errs: Array[String] = []
	for e in edges:
		var to := str(e.get("to", ""))
		if not moves.has(to):
			errs.append("edge -> unknown move '%s'" % to)
		var from := str(e["from"])
		if from != "free" and from != "*" and not from.begins_with("tag:") and not moves.has(from):
			errs.append("edge from unknown move '%s'" % from)
	return errs


## Applies a weapon definition: per-move field overlays, extra moves / edges, cancel delay.
## Returns a NEW graph; the source graph is untouched so several weapons can share it.
func with_weapon(weapon: Dictionary) -> ActionGraph:
	var g := ActionGraph.new()
	g.id = id
	g.max_links = max_links
	g.hit_cancel_delay = int(weapon.get("cancel_delay", hit_cancel_delay))
	g.hit_cancel_window = int(weapon.get("cancel_window", hit_cancel_window))
	g.startup_cancel = startup_cancel
	g.input_priority = input_priority.duplicate()
	g.weapon_id = str(weapon.get("id", ""))
	for mid in moves.keys():
		g.moves[mid] = (moves[mid] as MoveDef).duplicate_def()
	var extra_moves: Dictionary = weapon.get("extra_moves", {})
	for mid in extra_moves.keys():
		g.moves[str(mid)] = MoveDef.from_dict(str(mid), extra_moves[mid])
	var overlays: Dictionary = weapon.get("moves", {})
	for mid in overlays.keys():
		if g.moves.has(mid):
			(g.moves[mid] as MoveDef).overlay(overlays[mid])
	for e in edges:
		g.add_edge(e)
	for e in weapon.get("edges", []):
		g.add_edge(e)
	return g


func _from_matches(edge_from: String, current: MoveDef) -> bool:
	if current == null:
		return edge_from == "free"
	if edge_from == "*":
		return true
	if edge_from.begins_with("tag:"):
		return current.has_tag(edge_from.substr(4))
	return edge_from == current.id


## Whether the current move may be left for another attack right now.
## Hit-confirmed moves open at contact + hit_delay for hit_window ticks; otherwise the move
## opens at its natural `cancel.whiff` / `cancel.blocked` age (default: end of active frames).
func cancel_open(ctx: Dictionary) -> bool:
	var m: MoveDef = ctx.get("move", null)
	if m == null:
		return true
	var age := int(ctx.get("age", 0))
	var c := m.cancel
	if bool(ctx.get("confirmed", false)):
		var ca := int(ctx.get("contact_age", -1000))
		var delay := int(c.get("hit_delay", hit_cancel_delay))
		var window := int(c.get("hit_window", hit_cancel_window))
		if age >= ca + delay and age <= ca + window:
			return true
	var natural_key := "blocked" if str(ctx.get("contact", "")) == "blocked" else "whiff"
	return age >= int(c.get(natural_key, m.active_end()))


## Defensive cancel (dodge / guard / jump): free, startup frames, recovery, or hit-confirm window.
func defensive_cancel_open(ctx: Dictionary) -> bool:
	var m: MoveDef = ctx.get("move", null)
	if m == null:
		return true
	var age := int(ctx.get("age", 0))
	var startup := int(m.cancel.get("startup", startup_cancel))
	if age < startup:
		return true
	if m.is_recovery(age):
		return true
	if bool(ctx.get("confirmed", false)):
		var ca := int(ctx.get("contact_age", -1000))
		return age >= ca + int(m.cancel.get("hit_delay", hit_cancel_delay)) and age <= ca + int(m.cancel.get("hit_window", hit_cancel_window))
	return false


static func _sample_dir(edge: Dictionary, entry: Dictionary, ctx: Dictionary) -> Vector2i:
	match str(edge["dir_sample"]):
		"current":
			return ctx.get("dir_now", Vector2i.ZERO)
		"start_facing":
			return Vector2i(int(ctx.get("start_facing", 1)), 0)
		_:
			return entry.get("dir", Vector2i.ZERO)


static func _dir_ok(want: String, d: Vector2i, facing: int) -> bool:
	var rel := d.x * facing
	match want:
		"any":
			return true
		"neutral":
			return d == Vector2i.ZERO
		"up":
			return d.y < 0
		"down":
			return d.y > 0
		"not_down":
			return d.y <= 0
		"fwd":
			return rel > 0
		"back":
			return rel < 0
		"side":
			return d.x != 0
		"no_back":
			return rel >= 0
	return true


## Returns the name of the first failing condition, or "" when the edge passes.
func edge_block_reason(edge: Dictionary, entry: Dictionary, ctx: Dictionary) -> String:
	var facing := int(ctx.get("facing", 1))
	var d := _sample_dir(edge, entry, ctx)
	var w: Dictionary = edge["when"]
	if w.has("grounded") and bool(w["grounded"]) != bool(ctx.get("grounded", true)):
		return "grounded" if bool(w["grounded"]) else "air"
	var cmd := str(edge["command"])
	if not cmd.is_empty():
		var parser: CommandParser = ctx.get("command_parser", null)
		var got := parser.command_for(d) if parser != null else ""
		if got != cmd:
			return "command"
	if not _dir_ok(str(edge["dir"]), d, facing):
		return "dir"
	if w.has("confirmed") and bool(w["confirmed"]) != bool(ctx.get("confirmed", false)):
		return "confirmed"
	if w.has("contact") and str(w["contact"]) != str(ctx.get("contact", "")):
		return "contact"
	if w.has("launched") and bool(w["launched"]) != bool(ctx.get("launched", false)):
		return "launched"
	if w.has("air_count_lt") and int(ctx.get("air_count", 0)) >= int(w["air_count_lt"]):
		return "air_count"
	var m: MoveDef = ctx.get("move", null)
	if w.has("min_delay") and m != null and int(ctx.get("age", 0)) < m.active_end() + int(w["min_delay"]):
		return "min_delay"
	if w.has("fresh") and int(entry.get("age", 0)) > int(w["fresh"]):
		return "fresh"
	if w.has("flags"):
		var flags: Dictionary = ctx.get("flags", {})
		for fk in (w["flags"] as Dictionary).keys():
			if bool(flags.get(fk, false)) != bool(w["flags"][fk]):
				return "flag:%s" % fk
	if w.has("after"):
		var a: Dictionary = w["after"]
		if str(ctx.get("last_move", "")) != str(a.get("move", "")) or int(ctx.get("since_end", 999999)) > int(a.get("within", 0)):
			return "after"
	return ""


## Resolves buffered inputs against the graph for this tick.
## `buffered`: InputTrace entries (oldest first). Returns:
## { "edge": Dictionary|{}, "entry": Dictionary|{}, "move": MoveDef|null, "facing": int,
##   "blocked": { input -> reason } }
func resolve(ctx: Dictionary, buffered: Array) -> Dictionary:
	var result := {"edge": {}, "entry": {}, "move": null, "facing": int(ctx.get("facing", 1)), "blocked": {}}
	var current: MoveDef = ctx.get("move", null)
	var by_input: Dictionary = {}
	for e in buffered:
		by_input[str(e["input"])] = e
	var order: Array = input_priority.duplicate()
	for k in by_input.keys():
		if not order.has(k):
			order.append(k)
	for input in order:
		if not by_input.has(input):
			continue
		var entry: Dictionary = by_input[input]
		var cands: Array[Dictionary] = []
		for edge in edges:
			if str(edge["input"]) == input and _from_matches(str(edge["from"]), current):
				cands.append(edge)
		if cands.is_empty():
			result["blocked"][input] = "no_edge"
			continue
		if current != null:
			if int(ctx.get("chain_depth", 0)) >= max_links:
				result["blocked"][input] = "chain_cap"
				continue
			if not cancel_open(ctx):
				result["blocked"][input] = "cancel_window"
				continue
		cands.sort_custom(func(a: Dictionary, b: Dictionary): return int(a["priority"]) > int(b["priority"]))
		var first_reason := ""
		for edge in cands:
			var reason := edge_block_reason(edge, entry, ctx)
			if reason.is_empty():
				var target: MoveDef = moves.get(str(edge["to"]), null)
				if target == null:
					reason = "missing_move"
				else:
					var new_facing := int(ctx.get("facing", 1))
					if bool(edge.get("turn", false)):
						var sd := _sample_dir(edge, entry, ctx)
						if sd.x != 0:
							new_facing = sd.x
					result["edge"] = edge
					result["entry"] = entry
					result["move"] = target
					result["facing"] = new_facing
					return result
			if first_reason.is_empty():
				first_reason = reason
		result["blocked"][input] = first_reason
	return result


func to_dict() -> Dictionary:
	var md := {}
	for mid in moves.keys():
		md[mid] = (moves[mid] as MoveDef).to_dict()
	return {
		"id": id, "max_links": max_links, "hit_cancel_delay": hit_cancel_delay, "hit_cancel_window": hit_cancel_window,
		"startup_cancel": startup_cancel, "input_priority": input_priority.duplicate(), "moves": md, "edges": edges.duplicate(true),
	}
