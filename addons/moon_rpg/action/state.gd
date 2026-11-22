class_name MoonState
extends Node
## Base class for states inside MoonStateMachine.

var state_machine: Node = null
var actor: Node = null


func enter(_msg: Dictionary = {}) -> void:
	pass


func exit() -> void:
	pass


func physics_update(_delta: float) -> void:
	pass


func handle_input(_event: InputEvent) -> void:
	pass
