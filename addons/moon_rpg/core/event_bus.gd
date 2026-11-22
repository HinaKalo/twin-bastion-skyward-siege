extends Node
## Global strongly-typed event bus for MoonRPG Engine.
## Decouples combat, inventory, quests, dialogue, world transitions, and UI.

# --- Combat & Actor Signals ---
signal player_registered(player: Node)
signal actor_damaged(target: Node, attacker: Node, amount: int, is_crit: bool, hit_pos: Vector2)
signal actor_healed(target: Node, amount: int, pos: Vector2)
signal actor_parried(defender: Node, attacker: Node, pos: Vector2)
signal actor_died(actor: Node, killer: Node)
signal enemy_killed(enemy_id: String, enemy_node: Node)
signal camera_shake_requested(intensity: float, duration: float)
signal hitstop_requested(duration: float, time_scale: float)
## Scoped hitstop: freezes only the listed nodes / scope ids for `ticks` fixed ticks (MoonSim).
signal scoped_hitstop_requested(targets: Array, ticks: int, reason: String)
## Structured combat feedback event routed through FeedbackRouter (see action/feedback_router.gd).
signal combat_feedback_event(event: Dictionary)
signal floating_text_requested(text: String, world_pos: Vector2, style: String)
signal vfx_requested(vfx_key: String, world_pos: Vector2, flip_h: bool)

# --- Stats & Buffs ---
signal player_stats_changed()
signal status_effects_changed(actor: Node)

# --- Inventory, Equipment & Mastery ---
signal inventory_changed()
signal equipment_changed(slot_name: String, item_id: String)
signal hotbar_changed(slot_index: int, item_id: String)
signal item_collected(item_id: String, amount: int)
signal mastery_updated(item_id: String, xp: int, max_xp: int, unlocked: bool)
signal gold_changed(new_gold: int)

# --- Quests & Objectives ---
signal quest_started(quest_id: String)
signal quest_updated(quest_id: String)
signal quest_completed(quest_id: String)
signal tracked_quest_changed(quest_id: String)

# --- Dialogue & World Flags ---
signal dialogue_started(dialogue_id: String)
signal dialogue_line_presented(payload: Dictionary)
signal dialogue_ended(dialogue_id: String)
signal world_flag_changed(flag_name: String, value: Variant)
signal blackboard_changed(key: String, old_value: Variant, new_value: Variant)
signal story_arc_changed(arc_id: String, from_state: String, to_state: String)
signal locale_reloaded(locale_code: String)

# --- World & Minimap ---
signal room_transition_requested(room_id: String, spawn_point: String)
signal room_changed(room_id: String, spawn_point: String)
signal room_discovered(room_id: String)
signal interact_prompt_changed(visible: bool, label: String)
signal toast_requested(message: String, style: String)
signal debug_hitboxes_toggled(enabled: bool)
signal input_device_changed(device_type: String, brand: String)
signal player_joined(player_index: int, player: Node)
signal player_left(player_index: int)
signal coop_mode_changed(mode_name: String)

# --- Save / Load ---
signal game_saved(slot_id: String)
signal game_loaded(slot_id: String)
signal checkpoint_updated(checkpoint_id: String, room_id: String)
signal difficulty_changed(preset: String, pressure: float)
