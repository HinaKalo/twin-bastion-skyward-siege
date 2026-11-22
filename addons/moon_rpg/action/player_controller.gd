class_name PlayerController
extends Actor2D
## Dead Cells / Hollow Knight Grade Side-Scrolling ARPG Player Controller.
##
## Features:
## - Data-driven ActionGraph (content/data/action/graphs/*.json) resolved once per fixed tick by
##   ActionRunner: derivations, hit/whiff/blocked cancel windows, chain cap, direction sampling
## - InputTrace buffer: every press is buffered / triggered / expired / blocked(reason)
## - Scoped hitstop: only the attacker and target freeze (MoonSim); presses during the freeze are kept
## - Hollow Knight Down-Attack Pogo Bounce (S + Attack in air resets double jump & bounces)
## - Dead Cells Rally HP recovery on melee counter-attacks
## - Dodge Roll with i-frames + cyan afterimage ghost trail
## - Perfect Parry (0.18s window -> instant enemy posture BREAK!)
## - Full 2P Co-op support (`player_index`, `action_prefix`, `is_remote_controlled`)

enum ActionState { FREE, ATTACK, SKILL, GUARD, DODGE, HURT, DEAD }

@export var player_index: int = 1
@export var action_prefix: String = ""
@export var enable_roll_cancel: bool = true
@export var enable_pogo: bool = true
var is_remote_controlled: bool = false

## Action graph driving attacks. Swap per weapon / character (e.g. graphs/tideforge.json).
@export_file("*.json") var action_graph_path: String = "res://content/data/action/graphs/default.json"
## Optional weapon overlay (content/data/action/weapons/*.json) applied on top of the graph.
@export_file("*.json") var weapon_path: String = ""

var state: int = ActionState.FREE
var action: ActionRunner = ActionRunner.new()
var action_graph: ActionGraph = null

var _state_timer: float = 0.0
var _is_pogo_attack: bool = false
var _dodge_dir: int = 1
var _afterimage_timer: float = 0.0
var _active_skill_def: Dictionary = {}
var _active_hit_frames: Array = []
var _triggered_hit_frames: Dictionary = {}
var _nearby_interactables: Array[Node] = []
var _interact_area: Area2D = null


func _ready() -> void:
	add_to_group("player")
	enable_rally = true
	max_poise = 30.0
	if actor_key.is_empty():
		actor_key = "player.shen_zhao"
	super._ready()

	collision_layer = 4 # layer 3: player
	hitbox.collision_layer = 16 # layer 5: player_hitbox
	hitbox.collision_mask = 8 # layer 4: enemy hurtbox
	hitbox.hit_landed.connect(_on_hitbox_hit_landed)
	hurtbox.collision_layer = 4
	hurtbox.collision_mask = 32 # layer 6: enemy_hitbox

	_setup_interact_detector()
	load_action_graph(action_graph_path, weapon_path)
	hurtbox.perfect_evaded.connect(_on_perfect_evaded)

	if player_index == 1:
		if InventoryManager:
			InventoryManager.bind_player(self, stat_block)
			if InventoryManager.bag.is_empty():
				InventoryManager.reset_starter_kit()
		if EventBus:
			EventBus.player_registered.emit(self)
			EventBus.player_stats_changed.emit()
	else:
		_add_p2_badge()


## (Re)loads the action graph and optional weapon overlay.
func load_action_graph(graph_path: String, weapon_json: String = "") -> bool:
	var g := ActionGraph.load_json(graph_path) if not graph_path.is_empty() else null
	if g == null:
		return false
	if not weapon_json.is_empty() and FileAccess.file_exists(weapon_json):
		var w: Variant = JSON.parse_string(FileAccess.get_file_as_string(weapon_json))
		if typeof(w) == TYPE_DICTIONARY:
			g = g.with_weapon(w)
	action_graph = g
	action.set_graph(g)
	action.facing = facing
	return true


## Snapshot of recent presses and their fate (buffered / triggered / expired / blocked).
func get_input_trace(count: int = 12) -> Array[Dictionary]:
	return action.trace.export_recent(count)


func is_pogo_striking() -> bool:
	return (state == ActionState.ATTACK or state == ActionState.SKILL) and action.move != null and action.move.has_tag("pogo")


func on_pogo_hazard(bounce_velocity: float) -> void:
	motor.apply_pogo_bounce(self, bounce_velocity)
	action.refresh_air()
	hurtbox.start_iframes(0.14)
	trigger_squash(Vector2(0.84, 1.20))


func _press(input: String) -> void:
	if InputManager != null and InputManager.has_method("is_action_input_blocked") and InputManager.is_action_input_blocked():
		var e := action.press(input)
		action.trace.mark_blocked(input, "menu")
		e["ttl"] = 1
		return
	action.press(input)


func _act(base_action: String) -> String:
	return action_prefix + base_action


func _add_p2_badge() -> void:
	var badge := Label.new()
	badge.text = "P%d" % player_index
	badge.position = Vector2(-10, -58)
	badge.add_theme_font_size_override("font_size", 7)
	badge.add_theme_color_override("font_color", Color(0.45, 0.92, 1.0))
	badge.add_theme_constant_override("outline_size", 2)
	badge.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	add_child(badge)


func _setup_interact_detector() -> void:
	_interact_area = Area2D.new()
	_interact_area.name = "InteractDetector"
	_interact_area.collision_layer = 0
	_interact_area.collision_mask = 64 # layer 7: interactable
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(46, 48)
	shape.shape = rect
	shape.position = Vector2(0, -24)
	_interact_area.add_child(shape)
	add_child(_interact_area)
	_interact_area.area_entered.connect(_on_interactable_entered)
	_interact_area.area_exited.connect(_on_interactable_exited)


func full_restore() -> void:
	stat_block.full_restore()
	rally_hp = 0.0
	poise = max_poise
	is_posture_broken = false
	is_dead = false
	state = ActionState.FREE
	if EventBus:
		EventBus.player_stats_changed.emit()
		EventBus.actor_healed.emit(self, int(stat_block.get_stat("max_hp")), global_position + Vector2(0, -36))


func _unhandled_input(event: InputEvent) -> void:
	if is_remote_controlled:
		return
	if DialogueRunner != null and DialogueRunner.is_active:
		return
	if is_dead:
		return

	if player_index == 1:
		if event.is_action_pressed("hotbar_1"):
			InventoryManager.use_hotbar(0)
		elif event.is_action_pressed("hotbar_2"):
			InventoryManager.use_hotbar(1)
		elif event.is_action_pressed("hotbar_3"):
			InventoryManager.use_hotbar(2)
		elif event.is_action_pressed("hotbar_4"):
			InventoryManager.use_hotbar(3)

	if event.is_action_pressed(_act("interact")):
		_try_interact()
	elif event.is_action_pressed(_act("jump")):
		if Input.is_action_pressed(_act("move_down")):
			motor.drop_through_one_way(self)
		else:
			motor.request_jump()
	elif event.is_action_released(_act("jump")):
		motor.cut_jump(self)
	elif event.is_action_pressed(_act("dodge")):
		_press("dodge")
	elif event.is_action_pressed(_act("attack_light")):
		_press("light")
	elif event.is_action_pressed(_act("attack_heavy")):
		_press("heavy")
	elif event.is_action_pressed(_act("skill_ultimate")):
		_press("ultimate")
	elif event.is_action_pressed(_act("guard")):
		_press("guard")
	elif event.is_action_released(_act("guard")):
		if state == ActionState.GUARD:
			_stop_guard()


func _physics_process(delta: float) -> void:
	if is_remote_controlled:
		return
	if DialogueRunner != null and DialogueRunner.is_active:
		motor.step(self, 0.0, 0.0, delta, false)
		play_anim("idle")
		return

	var move_dir := Input.get_axis(_act("move_left"), _act("move_right"))
	var move_spd := stat_block.get_stat("move_spd")
	var stick := Vector2i(
		0 if absf(move_dir) < 0.25 else (1 if move_dir > 0.0 else -1),
		(1 if Input.is_action_pressed(_act("move_down")) else 0) - (1 if InputMap.has_action(_act("move_up")) and Input.is_action_pressed(_act("move_up")) else 0))
	var frozen := is_hitstop_frozen()
	action.flags["pogo_enabled"] = enable_pogo
	action.begin_tick(stick, is_on_floor(), frozen)
	if frozen:
		# Scoped hitstop: hold position, keep buffering presses (TTL paused), resume next tick.
		action.trace.tick(true)
		return

	# Process buffered high-priority defensive cancels (Dead Cells roll/parry cancel!)
	_process_buffered_actions()

	match state:
		ActionState.FREE:
			if absf(move_dir) > 0.05:
				set_facing(1 if move_dir > 0.0 else -1)
			var landed := motor.step(self, move_dir, move_spd, delta, true)
			if motor.just_jumped:
				trigger_squash(Vector2(0.84, 1.18))
			if landed:
				trigger_squash(Vector2(1.18, 0.84))
				if AudioManager:
					AudioManager.play_sfx("sfx.land", -10.0)
			if not is_on_floor() and (motor.coyote_timer <= 0.0 or velocity.y < -15.0):
				play_anim("jump")
			elif absf(move_dir) > 0.05:
				play_anim("run")
			else:
				play_anim("idle")
			stat_block.modify_st(2.5 * delta)
		ActionState.DODGE:
			_state_timer -= delta
			_afterimage_timer -= delta
			if _afterimage_timer <= 0.0:
				_afterimage_timer = 0.065
				spawn_afterimage(Color(0.45, 0.92, 1.0, 0.48), 0.18)
			velocity.x = float(_dodge_dir) * move_spd * 2.15
			velocity.y = 0.0
			move_and_slide()
			if _state_timer <= 0.0:
				state = ActionState.FREE
		ActionState.GUARD:
			motor.step(self, 0.0, 0.0, delta, false)
			if not Input.is_action_pressed(_act("guard")):
				_stop_guard()
		ActionState.ATTACK, ActionState.SKILL:
			motor.step(self, move_dir * 0.30, move_spd, delta, not is_on_floor())
			_update_attack_hitbox()
		ActionState.HURT:
			motor.step(self, 0.0, 0.0, delta, false)
			_state_timer -= delta
			if _state_timer <= 0.0:
				state = ActionState.FREE
		ActionState.DEAD:
			motor.step(self, 0.0, 0.0, delta, false)


func _can_cancel_attack_defensively() -> bool:
	if not enable_roll_cancel:
		return false
	if state != ActionState.ATTACK and state != ActionState.SKILL:
		return false
	# Graph-defined: startup frames, recovery, or hit-confirm window.
	return action.can_cancel_defensively()


func _process_buffered_actions() -> void:
	if state == ActionState.DEAD or state == ActionState.HURT:
		action.trace.tick(false)
		return

	# Highest priority: Dodge / Roll cancel
	if action.trace.has("dodge"):
		if state == ActionState.FREE or state == ActionState.GUARD or _can_cancel_attack_defensively():
			action.trace.consume("dodge", "dodge")
			action.cancel_to_free("dodge")
			_try_dodge()
			action.trace.tick(false)
			return
		action.trace.mark_blocked("dodge", "cancel_window")

	# Guard / Perfect Parry cancel
	if action.trace.has("guard"):
		if state == ActionState.FREE or _can_cancel_attack_defensively():
			action.trace.consume("guard", "guard")
			action.cancel_to_free("guard")
			_try_start_guard()
			action.trace.tick(false)
			return
		action.trace.mark_blocked("guard", "cancel_window")

	# Attacks & skills: the ActionGraph decides derivations and cancel windows.
	if state == ActionState.FREE or state == ActionState.ATTACK or state == ActionState.SKILL:
		if not action.is_busy():
			action.facing = facing
		for e in action.step():
			match str(e["type"]):
				"start", "cancel":
					_begin_move(action.move, str(e["type"]) == "cancel")
				"end":
					_finish_attack()
	else:
		action.trace.tick(false)


func _try_dodge() -> void:
	if state == ActionState.DODGE or state == ActionState.DEAD:
		return
	hitbox.deactivate()
	hurtbox.stop_guard()
	if sprite != null:
		sprite.speed_scale = 1.0
	state = ActionState.DODGE
	_state_timer = 0.25
	_afterimage_timer = 0.0
	var move_dir := Input.get_axis(_act("move_left"), _act("move_right"))
	_dodge_dir = (1 if move_dir > 0.0 else -1) if absf(move_dir) > 0.1 else facing
	set_facing(_dodge_dir)
	hurtbox.start_iframes(0.30)
	hurtbox.start_evade(0.133)
	trigger_squash(Vector2(1.22, 0.82))
	play_anim("dodge", true)
	if AudioManager:
		AudioManager.play_sfx("sfx.dash")


func _try_start_guard() -> void:
	hitbox.deactivate()
	if sprite != null:
		sprite.speed_scale = 1.0
	state = ActionState.GUARD
	hurtbox.start_guard(0.18)
	play_anim("guard", true)


func _stop_guard() -> void:
	hurtbox.stop_guard()
	if state == ActionState.GUARD:
		state = ActionState.FREE


func _begin_move(m: MoveDef, chained: bool = false) -> void:
	if m == null:
		return
	hitbox.deactivate()
	_is_pogo_attack = m.has_tag("pogo")
	var sdef := DataRegistry.get_skill(m.skill_id) if not m.skill_id.is_empty() else {}
	if sdef.is_empty():
		sdef = DataRegistry.get_skill(m.id)
	if sdef.is_empty():
		sdef = DataRegistry.get_skill("light_1")

	var st_cost := float(sdef.get("st_cost", 0.0))
	if st_cost > 0.0 and stat_block.st < st_cost:
		action.cancel_to_free("st")
		hitbox.deactivate()
		state = ActionState.FREE
		if EventBus:
			EventBus.toast_requested.emit("ST 凭依值不足！", "warn")
		return
	if st_cost > 0.0:
		stat_block.modify_st(-st_cost)
		if EventBus:
			EventBus.player_stats_changed.emit()

	set_facing(action.facing)
	_active_skill_def = sdef
	var is_skill := m.has_tag("skill") or m.has_tag("ultimate")
	state = ActionState.SKILL if is_skill else ActionState.ATTACK
	var anim_name := m.anim if not m.anim.is_empty() else str(sdef.get("anim", "attack_light"))
	var duration := float(m.total_frames()) / 60.0
	_triggered_hit_frames.clear()

	# Forward micro-lunge gives melee swings physical momentum
	var lunge := float(sdef.get("lunge_x", 0.0))
	if lunge > 0.0 and is_on_floor():
		velocity.x = float(facing) * lunge

	var cues := AssetRegistry.get_action_cues(actor_key, anim_name)
	_active_hit_frames = []
	if cues.has("accent"):
		_active_hit_frames.append(int(cues["accent"]))
	if cues.has("secondAccent"):
		_active_hit_frames.append(int(cues["secondAccent"]))
	if _active_hit_frames.is_empty():
		_active_hit_frames = [3]

	trigger_squash(Vector2(1.12, 0.92))
	var anim_len := get_anim_duration(anim_name)
	if sprite != null:
		if anim_len > 0.0 and duration > 0.0:
			sprite.speed_scale = clampf(anim_len / duration, 1.0, 2.4)
		else:
			sprite.speed_scale = 1.0
	play_anim(anim_name, true)
	if AudioManager:
		AudioManager.play_sfx(str(sdef.get("sfx", "sfx.swing_light")))
	if is_skill:
		if EventBus:
			EventBus.camera_shake_requested.emit(4.8, 0.22)
			EventBus.vfx_requested.emit("slash", global_position + Vector2(facing * 26, -24), facing < 0)
		if MoonRPG:
			MoonRPG.rumble_preset("ultimate")


func _update_attack_hitbox() -> void:
	if sprite == null:
		return
	var f := sprite.frame
	if _active_hit_frames.has(f) and not _triggered_hit_frames.has(f):
		_triggered_hit_frames[f] = true
		var mult := float(_active_skill_def.get("damage_mult", 1.0))
		var st_gain := float(_active_skill_def.get("st_gain", 10.0))
		var poise_dmg := float(_active_skill_def.get("poise_dmg", 14.0))
		var kb_x := float(_active_skill_def.get("knockback_x", 110.0))
		var kb_y := float(_active_skill_def.get("knockback_y", -60.0))
		var box_w := float(_active_skill_def.get("range_x", 44.0))
		var box_h := float(_active_skill_def.get("range_y", 34.0))
		var res := compute_damage_against(null, mult, str(_active_skill_def.get("formula", "")))
		var box_offset := Vector2(0.0, 10.0) if _is_pogo_attack else Vector2(facing * (box_w * 0.5 + 6.0), -24.0)
		hitbox.activate({
			"damage": res["damage"],
			"damage_mult": mult,
			"is_crit": res["is_crit"],
			"knockback": Vector2(facing * kb_x, kb_y),
			"st_gain": st_gain,
			"poise_dmg": poise_dmg,
			"hitstop": float(_active_skill_def.get("hitstop", 0.04)),
			"is_pogo": _is_pogo_attack,
		}, Vector2(box_w, box_h), box_offset)
	elif not _active_hit_frames.has(f) and hitbox.monitoring:
		hitbox.deactivate()


func _on_hitbox_hit_landed(_hurtbox: Hurtbox2D, payload: Dictionary) -> void:
	action.report_contact("hit")
	if EventBus:
		EventBus.combat_feedback_event.emit({
			"event_id": "p%d:%d:%d" % [player_index, action.serial, action.hits_this_move],
			"phase": "contact", "result": "hit", "material": "flesh", "attacker_seat": player_index,
			"target_seat": 0, "pos": payload.get("hit_pos", global_position), "move": action.current_id(),
		})
	# 1. Hollow Knight Down-Attack Pogo Bounce!
	if bool(payload.get("is_pogo", false)):
		var bounce := float(_active_skill_def.get("pogo_bounce", -280.0))
		motor.apply_pogo_bounce(self, bounce)
		trigger_squash(Vector2(0.84, 1.20))
	else:
		# Subtle horizontal recoil on melee contact
		var recoil := float(_active_skill_def.get("recoil_x", 36.0))
		if recoil > 0.0:
			motor.apply_knockback(Vector2(-facing * recoil, 0.0))

	# 2. Dead Cells Rally HP counter-attack heal!
	if enable_rally and rally_hp > 0.0:
		var dmg := float(payload.get("damage", 10.0))
		recover_rally(maxf(4.0, dmg * 0.28))


func _finish_attack() -> void:
	hitbox.deactivate()
	_is_pogo_attack = false
	if sprite != null:
		sprite.speed_scale = 1.0
	state = ActionState.FREE


func _on_hit_received(payload: Dictionary) -> void:
	super._on_hit_received(payload)
	if EventBus:
		EventBus.player_stats_changed.emit()
	if not is_dead and not bool(payload.get("guarded", false)):
		hitbox.deactivate()
		action.cancel_to_free("hurt")
		state = ActionState.HURT
		_state_timer = 0.22
		hurtbox.start_iframes(0.68)
		play_anim("hurt", true)


func _on_perfect_evaded(_payload: Dictionary) -> void:
	spawn_afterimage(Color(1.0, 0.95, 0.55, 0.6), 0.25)
	stat_block.modify_st(12.0)
	if EventBus:
		EventBus.combat_feedback_event.emit({
			"event_id": "p%d:evade:%d" % [player_index, Engine.get_physics_frames()],
			"phase": "contact", "result": "perfect_evade", "target_seat": player_index, "pos": global_position + Vector2(0, -24),
		})
		EventBus.player_stats_changed.emit()


func _on_parried_hit(payload: Dictionary) -> void:
	super._on_parried_hit(payload)
	play_anim("deflect", true)
	if EventBus:
		EventBus.player_stats_changed.emit()


func _die(killer: Node) -> void:
	super._die(killer)
	state = ActionState.DEAD
	if EventBus:
		EventBus.toast_requested.emit("你倒下了……正在检查点复活", "warn")
	await get_tree().create_timer(1.5).timeout
	if SaveManager:
		SaveManager.respawn_at_checkpoint()
	else:
		full_restore()


func _on_interactable_entered(area: Area2D) -> void:
	if not _nearby_interactables.has(area):
		_nearby_interactables.append(area)
	_refresh_interact_prompt()


func _on_interactable_exited(area: Area2D) -> void:
	_nearby_interactables.erase(area)
	_refresh_interact_prompt()


func _refresh_interact_prompt() -> void:
	_nearby_interactables = _nearby_interactables.filter(func(n): return is_instance_valid(n))
	if EventBus == null:
		return
	if _nearby_interactables.is_empty():
		EventBus.interact_prompt_changed.emit(false, "")
	else:
		var target := _nearby_interactables[0]
		var label := str(target.call("get_interact_label")) if target.has_method("get_interact_label") else "交互 [E]"
		EventBus.interact_prompt_changed.emit(true, label)


func _try_interact() -> void:
	_nearby_interactables = _nearby_interactables.filter(func(n): return is_instance_valid(n))
	if _nearby_interactables.is_empty():
		return
	var target := _nearby_interactables[0]
	if target.has_method("interact"):
		target.interact(self)


func serialize_state() -> Dictionary:
	return {
		"stats": stat_block.serialize(),
		"position": [global_position.x, global_position.y],
	}


func deserialize_state(data: Dictionary) -> void:
	if data.is_empty():
		return
	if data.has("stats"):
		stat_block.deserialize(data["stats"])
	if InventoryManager:
		InventoryManager.reapply_all_stat_modifiers()
	if data.has("position") and typeof(data["position"]) == TYPE_ARRAY and data["position"].size() == 2:
		global_position = Vector2(float(data["position"][0]), float(data["position"][1]))
	if EventBus:
		EventBus.player_stats_changed.emit()
