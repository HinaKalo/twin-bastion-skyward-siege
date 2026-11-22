class_name MoonStateMachine
extends Node
## Lightweight Hierarchical / Finite State Machine for ARPG Actors.

signal state_changed(from_state: String, to_state: String)

@export var initial_state_name: String = "idle"

var current_state: MoonState = null
var current_state_name: String = ""
var previous_state_name: String = ""
var _states: Dictionary = {}


func setup(owner_actor: Node) -> void:
	_states.clear()
	for child in get_children():
		if child is MoonState:
			var s := child as MoonState
			s.state_machine = self
			s.actor = owner_actor
			_states[s.name.to_lower()] = s
	if _states.has(initial_state_name.to_lower()):
		transition_to(initial_state_name.to_lower())


func register_state(state_name: String, state_node: MoonState, owner_actor: Node) -> void:
	state_node.name = state_name
	state_node.state_machine = self
	state_node.actor = owner_actor
	if state_node.get_parent() != self:
		add_child(state_node)
	_states[state_name.to_lower()] = state_node


func transition_to(target_name: String, msg: Dictionary = {}) -> bool:
	var key := target_name.to_lower()
	if not _states.has(key):
		return false
	var prev := current_state_name
	if current_state != null:
		current_state.exit()
	previous_state_name = prev
	current_state = _states[key]
	current_state_name = key
	current_state.enter(msg)
	state_changed.emit(prev, key)
	return true


func _physics_process(delta: float) -> void:
	if current_state != null:
		current_state.physics_update(delta)


func _unhandled_input(event: InputEvent) -> void:
	if current_state != null:
		current_state.handle_input(event)
