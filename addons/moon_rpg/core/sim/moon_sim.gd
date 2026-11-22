extends Node
## `MoonSim` autoload: the engine-wide fixed-step SimClock plus scoped hitstop.
##
## Advances one tick per physics frame (project physics rate is 60 Hz), always processes
## (even when the tree is paused) so UI / network keep sampling while gameplay is frozen.
## Gameplay nodes ask `MoonSim.is_frozen(self)` instead of relying on `Engine.time_scale`.

var clock: SimClock = SimClock.new(60)
## Shared enemy attack tokens (melee / ranged / on-screen danger budgets).
var attack_tokens: AttackTokenPool = AttackTokenPool.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	clock.set_tick_rate(Engine.physics_ticks_per_second)


func _physics_process(_delta: float) -> void:
	if get_tree().paused:
		return
	clock.step_once()


func current_tick() -> int:
	return clock.tick


func freeze(target: Variant, ticks: int, reason: String = "hitstop") -> void:
	clock.freeze(scope_of(target), ticks, reason)


func is_frozen(target: Variant) -> bool:
	return clock.is_frozen(scope_of(target))


func frozen_report() -> Array[Dictionary]:
	return clock.frozen_report()


func seconds_to_ticks(seconds: float) -> int:
	return clock.seconds_to_ticks(seconds)


## Scope id for nodes is their instance id; strings ("region:boss_arena") pass through.
static func scope_of(target: Variant) -> String:
	if target is Object:
		return "obj:%d" % (target as Object).get_instance_id()
	return str(target)
