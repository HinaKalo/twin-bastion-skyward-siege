class_name BattleModule
extends RefCounted
## Base Composable Battle Plugin ("Brick") for TurnBattleEngine.
## Subclass this to plug in Persona 1-More, Trails AT/S-Break, Octopath Shield Break,
## or any custom combat mechanic via `battle.add_module(MyModule.new())`.


func get_module_id() -> String:
	return "base"


func on_battle_start(_engine: Object, _advantage_mode: int) -> void:
	pass


## Optional override to pick the next acting unit (return empty Dictionary to fall back to default).
func select_next_actor(_engine: Object) -> Dictionary:
	return {}


## Mutate `ctx` before damage is applied:
##   ctx = { actor, target, element, mult, is_crit, affinity, absorb, mp_cost, log: Array[String] }
func modify_damage(_engine: Object, _ctx: Dictionary) -> void:
	pass


## React after an action resolves (e.g., set DOWN, grant 1 MORE, apply AT delay push, charge CP).
func on_action_resolved(_engine: Object, _ctx: Dictionary) -> void:
	pass


func on_turn_end(_engine: Object, _actor: Dictionary) -> void:
	pass


## Optional extra commands exposed to UI when this module is active.
func get_extra_commands(_engine: Object, _actor: Dictionary) -> Array[Dictionary]:
	return []
