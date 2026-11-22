class_name CombatFeedback
extends Node
## Handles ARPG combat "juice": Hitstop (brief time-scale freeze),
## AssetRegistry VFX spawning, and floating damage/parry/heal numbers.

const FloatingTextScript := preload("res://addons/moon_rpg/ui/floating_text.gd")

var _hitstop_active: bool = false
## Per-viewer structured feedback (attacker / victim / ally / remote) with event_id dedupe.
var router: FeedbackRouter = FeedbackRouter.new()
## Seats rendered on this machine (local co-op adds seat 2).
var local_seats: Array[int] = [1]


func _ready() -> void:
	if EventBus:
		EventBus.hitstop_requested.connect(_on_hitstop_requested)
		EventBus.vfx_requested.connect(_on_vfx_requested)
		EventBus.floating_text_requested.connect(_on_floating_text_requested)
		EventBus.actor_damaged.connect(_on_actor_damaged)
		EventBus.actor_healed.connect(_on_actor_healed)
		EventBus.actor_parried.connect(_on_actor_parried)
		EventBus.combat_feedback_event.connect(_on_combat_feedback_event)
	router.load_json("res://content/data/action/feedback.json")
	var api := get_node_or_null("/root/MoonRPG")
	if api != null and "accessibility" in api:
		router.accessibility = api.accessibility


## Plays a structured combat event once per local viewer seat (see FeedbackRouter).
func _on_combat_feedback_event(event: Dictionary) -> void:
	var pos: Vector2 = event.get("pos", Vector2.ZERO)
	for seat in local_seats:
		var plan := router.route(event, seat, true)
		if plan.is_empty():
			continue
		if AudioManager and not str(plan["sfx"]).is_empty():
			AudioManager.play_sfx(str(plan["sfx"]))
		if not str(plan["vfx"]).is_empty() and pos != Vector2.ZERO:
			_on_vfx_requested(str(plan["vfx"]), pos, false)
		if float(plan["shake"]) > 0.0 and EventBus:
			EventBus.camera_shake_requested.emit(float(plan["shake"]), 0.14)
		var rum: Array = plan["rumble"]
		if InputManager and (float(rum[0]) > 0.0 or float(rum[1]) > 0.0):
			InputManager.rumble(float(rum[0]), float(rum[1]), float(rum[2]))
		if not str(plan["text"]).is_empty() and pos != Vector2.ZERO:
			_on_floating_text_requested(str(plan["text"]), pos + Vector2(0, -12), "parry")


## Global time-scale slow-down. Reserved for explicit cinematic staging (ultimate, boss kill);
## combat hits use scoped MoonSim freezes instead (Actor2D.request_scoped_hitstop).
func _on_hitstop_requested(duration: float, time_scale: float) -> void:
	if _hitstop_active or duration <= 0.0:
		return
	_hitstop_active = true
	var prev_scale := Engine.time_scale
	Engine.time_scale = clampf(time_scale, 0.02, 1.0)
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = prev_scale
	_hitstop_active = false


func _on_vfx_requested(vfx_key: String, world_pos: Vector2, flip_h: bool) -> void:
	var sf := AssetRegistry.build_vfx_sprite_frames(vfx_key)
	if sf == null:
		return
	var spr := AnimatedSprite2D.new()
	spr.sprite_frames = sf
	spr.global_position = world_pos
	spr.flip_h = flip_h
	spr.z_index = 40
	get_tree().current_scene.add_child(spr)
	spr.play("play")
	spr.animation_finished.connect(spr.queue_free)


func _on_floating_text_requested(text: String, world_pos: Vector2, style: String) -> void:
	var ft: Node2D = FloatingTextScript.new()
	ft.global_position = world_pos + Vector2(randf_range(-6.0, 6.0), randf_range(-4.0, 4.0))
	get_tree().current_scene.add_child(ft)
	ft.setup(text, style)


func _on_actor_damaged(target: Node, _attacker: Node, amount: int, is_crit: bool, hit_pos: Vector2) -> void:
	var style := "crit" if is_crit else "damage"
	var text := "%d!" % amount if is_crit else str(amount)
	_on_floating_text_requested(text, hit_pos, style)
	_on_vfx_requested("hit_spark", hit_pos, false)
	if MoonRPG != null:
		if target != null and target.is_in_group("player"):
			MoonRPG.rumble_preset("hurt")
		else:
			MoonRPG.rumble_preset("crit" if is_crit else "hit")


func _on_actor_healed(_target: Node, amount: int, pos: Vector2) -> void:
	_on_floating_text_requested("+%d" % amount, pos, "heal")


func _on_actor_parried(_defender: Node, _attacker: Node, pos: Vector2) -> void:
	_on_floating_text_requested("PARRY!", pos + Vector2(0, -12), "parry")
	_on_vfx_requested("hit_spark", pos, false)
	if MoonRPG != null:
		MoonRPG.rumble_preset("parry")
