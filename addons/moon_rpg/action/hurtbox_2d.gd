class_name Hurtbox2D
extends Area2D
## Actor Hurtbox with invulnerability frames (i-frames), Guard damage reduction,
## and ASTLIBRA-style Perfect Parry window detection.

signal hit_received(payload: Dictionary)
signal parried_hit(payload: Dictionary)
## Perfect evade: a hit landed inside the dodge's evade window (rewarded once per dodge).
signal perfect_evaded(payload: Dictionary)

var owner_actor: Node = null
var invulnerable_timer: float = 0.0
var is_guarding: bool = false
var parry_window_timer: float = 0.0
## Releasing guard while the parry window was still open keeps a short perfect grace (3 ticks).
var release_grace_time: float = 0.05
var release_grace_timer: float = 0.0
## Re-pressing guard sooner than this after a release never yields a perfect parry.
var repress_lockout_time: float = 0.28
var _since_release: float = 999.0
## Guard / parry only work against hits from the front (owner_actor.facing).
var require_facing: bool = true
var evade_window_timer: float = 0.0
var _evade_rewarded: bool = false


func _ready() -> void:
	monitoring = false
	monitorable = true
	if get_node_or_null("CollisionShape2D") == null:
		var shape := CollisionShape2D.new()
		shape.name = "CollisionShape2D"
		var rect := RectangleShape2D.new()
		rect.size = Vector2(20, 40)
		shape.shape = rect
		shape.position = Vector2(0, -20)
		add_child(shape)


func _physics_process(delta: float) -> void:
	if invulnerable_timer > 0.0:
		invulnerable_timer = maxf(0.0, invulnerable_timer - delta)
	if parry_window_timer > 0.0:
		parry_window_timer = maxf(0.0, parry_window_timer - delta)
	if release_grace_timer > 0.0:
		release_grace_timer = maxf(0.0, release_grace_timer - delta)
	if evade_window_timer > 0.0:
		evade_window_timer = maxf(0.0, evade_window_timer - delta)
	if not is_guarding:
		_since_release += delta
	if MoonRPG != null and MoonRPG.debug_hitboxes:
		queue_redraw()


func _draw() -> void:
	if MoonRPG == null or not MoonRPG.debug_hitboxes:
		return
	var shape := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape != null and shape.shape is RectangleShape2D:
		var sz := (shape.shape as RectangleShape2D).size
		var rect := Rect2(shape.position - sz * 0.5, sz)
		var col := Color(0.2, 0.9, 1.0, 0.35) if parry_window_timer > 0.0 else (Color(1.0, 0.9, 0.2, 0.28) if invulnerable_timer > 0.0 else Color(0.2, 0.9, 0.35, 0.25))
		draw_rect(rect, col, true)
		draw_rect(rect, Color(col.r, col.g, col.b, 0.9), false, 1.0)


func start_iframes(duration: float) -> void:
	invulnerable_timer = maxf(invulnerable_timer, duration)


func start_guard(parry_window: float = 0.18) -> void:
	is_guarding = true
	parry_window_timer = 0.0 if _since_release < repress_lockout_time else parry_window
	release_grace_timer = 0.0


func stop_guard() -> void:
	if is_guarding and parry_window_timer > 0.0:
		release_grace_timer = release_grace_time
	is_guarding = false
	parry_window_timer = 0.0
	_since_release = 0.0


## Starts a dodge's perfect-evade window (hits inside it are evaded and rewarded once).
func start_evade(window: float = 0.133) -> void:
	evade_window_timer = 0.0 if invulnerable_timer > 0.0 else window
	_evade_rewarded = false


func _attack_from_front(payload: Dictionary) -> bool:
	if not require_facing or owner_actor == null or not ("facing" in owner_actor):
		return true
	var attacker: Variant = payload.get("attacker", null)
	if not (attacker is Node2D) or not (owner_actor is Node2D):
		return true
	var dx := (attacker as Node2D).global_position.x - (owner_actor as Node2D).global_position.x
	return absf(dx) < 1.0 or signf(dx) == float(owner_actor.get("facing"))


func receive_hit(payload: Dictionary) -> void:
	if evade_window_timer > 0.0 and not bool(payload.get("floor_trap", false)):
		if not _evade_rewarded:
			_evade_rewarded = true
			invulnerable_timer = maxf(invulnerable_timer, 0.17)
			perfect_evaded.emit(payload)
		return
	if invulnerable_timer > 0.0:
		return
	var front := _attack_from_front(payload)
	if front and (parry_window_timer > 0.0 or release_grace_timer > 0.0):
		release_grace_timer = 0.0
		parried_hit.emit(payload)
		return
	var resolved := payload.duplicate(true)
	if is_guarding and front:
		resolved["guarded"] = true
		resolved["damage"] = maxf(1.0, float(resolved.get("damage", 1.0)) * 0.25)
		resolved["knockback"] = (resolved.get("knockback", Vector2.ZERO) as Vector2) * 0.35
	hit_received.emit(resolved)
