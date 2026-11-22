extends Node
## Branching Dialogue Execution Engine.
## Reads dialogue graphs from DataRegistry (`content/dialogues/*.json`),
## resolves speaker lines via LocaleManager (hot-swappable text),
## evaluates conditions via ScriptBridge, and executes node actions.

var is_active: bool = false
var current_dialogue_id: String = ""
var current_node_id: String = ""
var _current_graph: Dictionary = {}
var _current_choices: Array[Dictionary] = []


func start_dialogue(dialogue_id: String, entry_node_id: String = "") -> bool:
	var graph := DataRegistry.get_dialogue(dialogue_id)
	if graph.is_empty():
		push_warning("[DialogueRunner] Unknown dialogue_id: %s" % dialogue_id)
		return false
	_current_graph = graph
	current_dialogue_id = dialogue_id
	is_active = true
	if EventBus:
		EventBus.dialogue_started.emit(dialogue_id)
	var start_id := entry_node_id if not entry_node_id.is_empty() else str(graph.get("start", "start"))
	_enter_node(start_id)
	return true


## Presents a one-off scripted dialogue line without requiring a JSON dialogue graph.
func say_line(speaker: String, text: String, portrait_key: String = "") -> void:
	_current_graph = {
		"id": "_inline_line",
		"start": "only",
		"nodes": {
			"only": {
				"speaker": speaker,
				"portrait_key": portrait_key,
				"text": text,
				"next": "",
			}
		}
	}
	current_dialogue_id = "_inline_line"
	is_active = true
	if EventBus:
		EventBus.dialogue_started.emit(current_dialogue_id)
	_enter_node("only")


func advance(choice_index: int = -1) -> void:
	if not is_active:
		return
	var nodes: Dictionary = _current_graph.get("nodes", {})
	var node: Dictionary = nodes.get(current_node_id, {})
	if node.is_empty():
		end_dialogue()
		return

	if not _current_choices.is_empty():
		var idx := clampi(choice_index, 0, _current_choices.size() - 1)
		var picked: Dictionary = _current_choices[idx]
		_execute_actions(picked.get("actions", []))
		var next_id := str(picked.get("next", ""))
		if next_id.is_empty():
			end_dialogue()
		else:
			_enter_node(next_id)
		return

	var next_node := str(node.get("next", ""))
	if next_node.is_empty():
		end_dialogue()
	else:
		_enter_node(next_node)


func end_dialogue() -> void:
	if not is_active:
		return
	var finished_id := current_dialogue_id
	is_active = false
	current_dialogue_id = ""
	current_node_id = ""
	_current_graph = {}
	_current_choices.clear()
	if EventBus:
		EventBus.dialogue_ended.emit(finished_id)


func _enter_node(node_id: String) -> void:
	var nodes: Dictionary = _current_graph.get("nodes", {})
	if not nodes.has(node_id):
		end_dialogue()
		return

	var node: Dictionary = nodes[node_id]
	# Support conditional router nodes (`type: "branch"`)
	if str(node.get("type", "line")) == "branch":
		for branch in node.get("branches", []):
			var cond := str(branch.get("condition", ""))
			if cond.is_empty() or _eval_condition(cond):
				_enter_node(str(branch.get("next", "")))
				return
		_enter_node(str(node.get("default", "")))
		return

	current_node_id = node_id
	_execute_actions(node.get("actions", []))

	var speaker_key := str(node.get("speaker_key", node.get("speaker", "")))
	var speaker_name := LocaleManager.tr_key(speaker_key, {}, speaker_key)
	var text_key := str(node.get("text_key", ""))
	var text := LocaleManager.tr_key(text_key, _build_eval_context(), str(node.get("text", text_key)))

	_current_choices.clear()
	var presented_choices: Array[Dictionary] = []
	for ch in node.get("choices", []):
		var cond := str(ch.get("condition", ""))
		if not cond.is_empty() and not _eval_condition(cond):
			continue
		_current_choices.append(ch)
		var ck := str(ch.get("text_key", ""))
		presented_choices.append({
			"text": LocaleManager.tr_key(ck, _build_eval_context(), str(ch.get("text", ck))),
		})

	var payload := {
		"dialogue_id": current_dialogue_id,
		"node_id": node_id,
		"speaker": speaker_name,
		"portrait_key": str(node.get("portrait_key", "")),
		"text": text,
		"choices": presented_choices,
	}
	if EventBus:
		EventBus.dialogue_line_presented.emit(payload)


func _build_eval_context() -> Dictionary:
	var ctx: Dictionary = StoryBlackboard.build_eval_context() if StoryBlackboard else {}
	ctx["gold"] = InventoryManager.gold if InventoryManager else 0
	if SaveManager:
		for k in SaveManager.world_flags.keys():
			ctx["flag_" + str(k)] = SaveManager.world_flags[k]
	if QuestManager:
		for qid in DataRegistry.quests.keys():
			ctx["quest_" + str(qid)] = QuestManager.get_state(str(qid))
	return ctx


func _eval_condition(expr: String) -> bool:
	return ScriptBridge.eval_condition(expr, _build_eval_context())


func _execute_actions(actions: Array) -> void:
	for act in actions:
		if typeof(act) != TYPE_DICTIONARY:
			continue
		var kind := str(act.get("type", ""))
		match kind:
			"set_flag":
				if SaveManager:
					SaveManager.set_flag(str(act.get("flag", "")), act.get("value", true))
			"start_quest":
				if QuestManager:
					QuestManager.start_quest(str(act.get("quest_id", "")))
			"complete_quest":
				if QuestManager:
					QuestManager.complete_quest(str(act.get("quest_id", "")))
			"give_item":
				if InventoryManager:
					InventoryManager.add_item(str(act.get("item_id", "")), int(act.get("count", 1)))
			"add_gold":
				if InventoryManager:
					InventoryManager.add_gold(int(act.get("amount", 0)))
			"heal_player":
				var players := get_tree().get_nodes_in_group("player")
				if not players.is_empty() and players[0].has_method("full_restore"):
					players[0].full_restore()
			"save_game":
				if SaveManager:
					SaveManager.save_game(str(act.get("slot", "slot_1")))
			"bb_set":
				if StoryBlackboard:
					StoryBlackboard.set_var(str(act.get("key", "")), act.get("value", true))
			"bb_inc":
				if StoryBlackboard:
					StoryBlackboard.inc(str(act.get("key", "")), float(act.get("delta", 1.0)))
			"bb_tag":
				if StoryBlackboard:
					StoryBlackboard.add_tag(str(act.get("tag", "")))
			"bb_choice":
				if StoryBlackboard:
					StoryBlackboard.record_choice(str(act.get("decision_id", "")), str(act.get("option", "")), act.get("effects", {}))
			"arc_goto":
				if StoryBlackboard:
					StoryBlackboard.transition_arc(str(act.get("arc", "")), str(act.get("state", "")))
			"hook":
				ScriptBridge.invoke_hook(str(act.get("name", "")), act.get("payload", {}))
