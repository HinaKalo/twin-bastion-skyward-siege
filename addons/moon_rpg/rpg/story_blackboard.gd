extends Node
## Narrative Blackboard & Story Arc State Machine (StoryBlackboard).
##
## Combines a typed reactive Blackboard (variables, numeric counters/affinity,
## story tags/knowledge, and choice history) with declarative multi-track
## Story Arc Finite State Machines (defined in code or `content/data/story_arcs.json`).
##
## Any change to the blackboard automatically re-evaluates Story Arc transitions
## via ScriptBridge (GDScript Expression or Lua) and notifies reactive watchers.

var vars: Dictionary = {} # key -> Variant (bool/int/float/String)
var tags: Dictionary = {} # tag_name -> true
var choices: Dictionary = {} # decision_id -> option_id
var arcs: Dictionary = {} # arc_id -> { state, states, history }

var _var_watchers: Dictionary = {} # key -> Array[Callable]
var _arc_watchers: Dictionary = {} # "arc_id:state" -> Array[Callable]


func _ready() -> void:
	load_arcs_from_registry()


func reset_all() -> void:
	vars.clear()
	tags.clear()
	choices.clear()
	arcs.clear()
	load_arcs_from_registry()


func load_arcs_from_registry() -> void:
	if DataRegistry == null:
		return
	var defs: Dictionary = DataRegistry.story_arcs
	for arc_id in defs.keys():
		define_arc(str(arc_id), defs[arc_id])


# =============================================================================
# 1. Blackboard Variables, Counters & Tags
# =============================================================================

func set_var(key: String, value: Variant, auto_eval: bool = true) -> void:
	var old_val: Variant = vars.get(key, null)
	if old_val == value and vars.has(key):
		return
	vars[key] = value
	_notify_var_watchers(key, old_val, value)
	if EventBus:
		EventBus.blackboard_changed.emit(key, old_val, value)
	if auto_eval:
		evaluate_arcs()


func get_var(key: String, default_value: Variant = null) -> Variant:
	return vars.get(key, default_value)


func has_var(key: String) -> bool:
	return vars.has(key)


func inc(key: String, delta: float = 1.0) -> float:
	var next_val := float(vars.get(key, 0.0)) + delta
	var stored: Variant = int(next_val) if is_equal_approx(next_val, round(next_val)) else next_val
	set_var(key, stored)
	return next_val


func dec(key: String, delta: float = 1.0) -> float:
	return inc(key, -delta)


func add_tag(tag_name: String) -> void:
	if tag_name.is_empty() or tags.has(tag_name):
		return
	tags[tag_name] = true
	if EventBus:
		EventBus.blackboard_changed.emit("tag:" + tag_name, false, true)
	evaluate_arcs()


func remove_tag(tag_name: String) -> void:
	if not tags.has(tag_name):
		return
	tags.erase(tag_name)
	if EventBus:
		EventBus.blackboard_changed.emit("tag:" + tag_name, true, false)
	evaluate_arcs()


func has_tag(tag_name: String) -> bool:
	return bool(tags.get(tag_name, false))


# =============================================================================
# 2. Player Choice Recording & Querying
# =============================================================================

## Records a major player decision and optionally applies immediate blackboard effects:
##   effects = { "vars": {"karma": 10}, "inc": {"affinity.old_lu": 15}, "tags": ["spared_boss"] }
func record_choice(decision_id: String, option_id: String, effects: Dictionary = {}) -> void:
	choices[decision_id] = option_id
	if effects.has("vars") and typeof(effects["vars"]) == TYPE_DICTIONARY:
		for k in effects["vars"].keys():
			set_var(str(k), effects["vars"][k], false)
	if effects.has("inc") and typeof(effects["inc"]) == TYPE_DICTIONARY:
		for k in effects["inc"].keys():
			var nv := float(vars.get(str(k), 0.0)) + float(effects["inc"][k])
			vars[str(k)] = int(nv) if is_equal_approx(nv, round(nv)) else nv
	if effects.has("tags") and typeof(effects["tags"]) == TYPE_ARRAY:
		for t in effects["tags"]:
			tags[str(t)] = true
	if EventBus:
		EventBus.blackboard_changed.emit("choice:" + decision_id, "", option_id)
	evaluate_arcs()


func chose(decision_id: String, option_id: String = "") -> bool:
	if not choices.has(decision_id):
		return false
	if option_id.is_empty():
		return true
	return str(choices[decision_id]) == option_id


func get_choice(decision_id: String, default_value: String = "") -> String:
	return str(choices.get(decision_id, default_value))


# =============================================================================
# 3. Declarative Story Arc State Machines
# =============================================================================

## Defines (or updates) a Story Arc FSM:
##   spec = {
##     "initial": "camp_arrival",
##     "states": {
##       "camp_arrival": {
##         "transitions": [{ "to": "forest_hunt", "when": "tag_accepted_hunt" }]
##       },
##       "forest_hunt": {
##         "on_enter": [{ "type": "bb_tag", "tag": "act1_started" }],
##         "transitions": [{ "to": "hero_ending", "when": "karma >= 10 and tag_forest_cleared" }]
##       }
##     }
##   }
func define_arc(arc_id: String, spec: Dictionary) -> void:
	var initial := str(spec.get("initial", "start"))
	var current := str(arcs[arc_id]["state"]) if arcs.has(arc_id) else initial
	var hist: Array = arcs[arc_id]["history"] if arcs.has(arc_id) else [initial]
	arcs[arc_id] = {
		"state": current,
		"states": spec.get("states", {}).duplicate(true),
		"history": hist,
	}


func get_arc_state(arc_id: String) -> String:
	if not arcs.has(arc_id):
		return ""
	return str(arcs[arc_id]["state"])


func is_arc_in(arc_id: String, state_name: String) -> bool:
	return get_arc_state(arc_id) == state_name


func transition_arc(arc_id: String, target_state: String) -> bool:
	if not arcs.has(arc_id):
		return false
	var arc: Dictionary = arcs[arc_id]
	var prev := str(arc["state"])
	if prev == target_state:
		return false
	arc["state"] = target_state
	(arc["history"] as Array).append(target_state)

	var st_def: Dictionary = arc.get("states", {}).get(target_state, {})
	_run_state_actions(st_def.get("on_enter", []))
	_notify_arc_watchers(arc_id, target_state)
	if EventBus:
		EventBus.story_arc_changed.emit(arc_id, prev, target_state)
	return true


## Evaluates transition conditions on all registered Story Arcs (up to 8 chained hops).
func evaluate_arcs() -> int:
	var total_transitions := 0
	for _pass in range(8):
		var transitioned_this_pass := false
		var ctx := build_eval_context()
		for arc_id in arcs.keys():
			var arc: Dictionary = arcs[arc_id]
			var cur_state := str(arc["state"])
			var st_def: Dictionary = arc.get("states", {}).get(cur_state, {})
			for tr in st_def.get("transitions", []):
				var cond := str(tr.get("when", tr.get("condition", "")))
				var to_state := str(tr.get("to", ""))
				if to_state.is_empty():
					continue
				if cond.is_empty() or ScriptBridge.eval_condition(cond, ctx):
					if transition_arc(str(arc_id), to_state):
						total_transitions += 1
						transitioned_this_pass = true
						break
		if not transitioned_this_pass:
			break
	return total_transitions


## Evaluates an arbitrary story condition expression against the full live Blackboard context.
func check(condition_expr: String, extra_ctx: Dictionary = {}) -> bool:
	var ctx := build_eval_context()
	for k in extra_ctx.keys():
		ctx[str(k)] = extra_ctx[k]
	return ScriptBridge.eval_condition(condition_expr, ctx)


## Builds a flat Expression/Lua-safe context dictionary containing all vars, tags, choices, and arc states.
func build_eval_context() -> Dictionary:
	var ctx: Dictionary = {}
	for k in vars.keys():
		var safe := _safe_ident(str(k))
		ctx[safe] = vars[k]
		ctx["bb_" + safe] = vars[k]
	for t in tags.keys():
		ctx["tag_" + _safe_ident(str(t))] = true
	for d in choices.keys():
		ctx["choice_" + _safe_ident(str(d))] = str(choices[d])
	for a in arcs.keys():
		ctx["arc_" + _safe_ident(str(a))] = str(arcs[a]["state"])
	if SaveManager:
		for f in SaveManager.world_flags.keys():
			ctx["flag_" + _safe_ident(str(f))] = SaveManager.world_flags[f]
	return ctx


# =============================================================================
# 4. Reactive Watchers
# =============================================================================

func watch(key: String, callback: Callable) -> void:
	if not _var_watchers.has(key):
		_var_watchers[key] = []
	if not (_var_watchers[key] as Array).has(callback):
		(_var_watchers[key] as Array).append(callback)


func on_arc(arc_id: String, state_name: String, callback: Callable) -> void:
	var composite := "%s:%s" % [arc_id, state_name]
	if not _arc_watchers.has(composite):
		_arc_watchers[composite] = []
	if not (_arc_watchers[composite] as Array).has(callback):
		(_arc_watchers[composite] as Array).append(callback)


func _notify_var_watchers(key: String, old_val: Variant, new_val: Variant) -> void:
	if not _var_watchers.has(key):
		return
	for cb in _var_watchers[key]:
		if cb is Callable and (cb as Callable).is_valid():
			(cb as Callable).call(old_val, new_val)


func _notify_arc_watchers(arc_id: String, state_name: String) -> void:
	var composite := "%s:%s" % [arc_id, state_name]
	if not _arc_watchers.has(composite):
		return
	for cb in _arc_watchers[composite]:
		if cb is Callable and (cb as Callable).is_valid():
			(cb as Callable).call()


func _run_state_actions(actions: Array) -> void:
	for act in actions:
		if typeof(act) != TYPE_DICTIONARY:
			continue
		match str(act.get("type", "")):
			"bb_set":
				vars[str(act.get("key", ""))] = act.get("value", true)
			"bb_inc":
				var k := str(act.get("key", ""))
				vars[k] = float(vars.get(k, 0.0)) + float(act.get("delta", 1.0))
			"bb_tag":
				tags[str(act.get("tag", ""))] = true
			"toast":
				if EventBus:
					EventBus.toast_requested.emit(str(act.get("text", "")), str(act.get("style", "quest")))
			"hook":
				ScriptBridge.invoke_hook(str(act.get("name", "")), act.get("payload", {}))


func _safe_ident(raw: String) -> String:
	return raw.replace(".", "_").replace("-", "_").replace(":", "_")


# =============================================================================
# 5. Serialization (SaveManager Integration)
# =============================================================================

func serialize_state() -> Dictionary:
	var arc_states: Dictionary = {}
	for aid in arcs.keys():
		arc_states[aid] = {
			"state": str(arcs[aid]["state"]),
			"history": (arcs[aid]["history"] as Array).duplicate(),
		}
	return {
		"vars": vars.duplicate(true),
		"tags": tags.keys(),
		"choices": choices.duplicate(true),
		"arcs": arc_states,
	}


func deserialize_state(data: Dictionary) -> void:
	if data.is_empty():
		return
	vars = data.get("vars", {}).duplicate(true)
	tags.clear()
	for t in data.get("tags", []):
		tags[str(t)] = true
	choices = data.get("choices", {}).duplicate(true)
	var saved_arcs: Dictionary = data.get("arcs", {})
	for aid in saved_arcs.keys():
		if arcs.has(str(aid)):
			arcs[str(aid)]["state"] = str(saved_arcs[aid].get("state", arcs[str(aid)]["state"]))
			arcs[str(aid)]["history"] = saved_arcs[aid].get("history", []).duplicate()
