extends Node
## Unified, Ergonomic Top-Level Facade for MoonRPG Engine.
##
## Instead of juggling 11 separate singletons, game scripts can call concise,
## self-documenting methods directly on `MoonRPG`:
##   MoonRPG.give("hp_potion", 2)
##   MoonRPG.say("camp_smith_talk")
##   MoonRPG.goto_room("misty_forest", "from_village")
##   MoonRPG.save("slot_1")
##
## Power users can still access any subsystem directly via properties:
##   MoonRPG.events / MoonRPG.assets / MoonRPG.data / MoonRPG.locale /
##   MoonRPG.scripts / MoonRPG.audio / MoonRPG.inventory / MoonRPG.quests /
##   MoonRPG.dialogue / MoonRPG.world / MoonRPG.save_sys

var debug_hitboxes: bool = false:
	set(value):
		debug_hitboxes = value
		if EventBus:
			EventBus.debug_hitboxes_toggled.emit(value)

var _player_ref: Node = null

## Per-channel comfort / accessibility limits (shake, flash, chroma, rumble, particles, lookahead).
var accessibility: AccessibilitySettings = AccessibilitySettings.new()

# --- Direct Subsystem Accessors ---
var events: Node:
	get: return EventBus
var assets: Node:
	get: return AssetRegistry
var theme: Node:
	get: return ThemeManager
var ui_stack: Node:
	get: return UIStack
var input: Node:
	get: return InputManager
var coop: Node:
	get: return CoopManager
var difficulty: Node:
	get: return DifficultyManager
var data: Node:
	get: return DataRegistry
var locale: Node:
	get: return LocaleManager
var scripts: Node:
	get: return ScriptBridge
var audio: Node:
	get: return AudioManager
var inventory: Node:
	get: return InventoryManager
var quests: Node:
	get: return QuestManager
var story: Node:
	get: return StoryBlackboard
var dialogue: Node:
	get: return DialogueRunner
var world: Node:
	get: return WorldManager
var save_sys: Node:
	get: return SaveManager

var player: Node:
	get:
		if is_instance_valid(_player_ref):
			return _player_ref
		var players := get_tree().get_nodes_in_group("player")
		return players[0] if not players.is_empty() else null


func _ready() -> void:
	_configure_display_sync()
	if EventBus:
		EventBus.player_registered.connect(func(p: Node): _player_ref = p)


## Auto-configures 60Hz VSync 1:1 lock (0.000px jitter on 60Hz displays) vs
## 2D Physics Interpolation (silky smooth on 120Hz/144Hz/240Hz displays).
func _configure_display_sync() -> void:
	var hz := 60.0
	if DisplayServer.get_name() != "headless":
		var scr := DisplayServer.window_get_current_screen()
		var reported := DisplayServer.screen_get_refresh_rate(scr)
		if reported > 0.0:
			hz = reported
	Engine.physics_ticks_per_second = 60
	if hz > 65.0:
		get_tree().physics_interpolation = true
	else:
		Engine.physics_jitter_fix = 0.5
		get_tree().physics_interpolation = false


# =============================================================================
# World & Rooms
# =============================================================================

func goto_room(room_id: String, spawn_point: String = "default", use_fade: bool = true) -> bool:
	if use_fade and EventBus and EventBus.room_transition_requested.get_connections().size() > 0:
		EventBus.room_transition_requested.emit(room_id, spawn_point)
		return true
	return WorldManager.load_room(room_id, spawn_point)


func current_room() -> String:
	return WorldManager.current_room_id


## Teleports any 2D node cleanly without physics-interpolation smearing.
func teleport_node(node: Node2D, pos: Vector2) -> void:
	if not is_instance_valid(node):
		return
	node.global_position = pos
	node.reset_physics_interpolation()


# =============================================================================
# Dialogue, Localization & Toast
# =============================================================================

func say(dialogue_id: String, entry_node: String = "") -> bool:
	return DialogueRunner.start_dialogue(dialogue_id, entry_node)


func say_line(speaker: String, text: String, portrait_key: String = "") -> void:
	DialogueRunner.say_line(speaker, text, portrait_key)


func tr_key(key: String, vars: Dictionary = {}, fallback: String = "") -> String:
	return LocaleManager.tr_key(key, vars, fallback)


func set_locale(locale_code: String) -> bool:
	return LocaleManager.load_locale(locale_code)


func reload_locale() -> bool:
	return LocaleManager.reload_current()


func toast(message: String, style: String = "info") -> void:
	if EventBus:
		EventBus.toast_requested.emit(message, style)


# =============================================================================
# Inventory, Equipment & Gold
# =============================================================================

func give(item_id: String, count: int = 1) -> bool:
	return InventoryManager.add_item(item_id, count)


func take(item_id: String, count: int = 1) -> bool:
	return InventoryManager.remove_item(item_id, count)


func has_item(item_id: String, count: int = 1) -> bool:
	return InventoryManager.has_item(item_id, count)


func equip(item_id: String, slot_name: String = "") -> bool:
	return InventoryManager.equip_item(item_id, slot_name)


func add_gold(amount: int) -> void:
	InventoryManager.add_gold(amount)


# =============================================================================
# Quests
# =============================================================================

func start_quest(quest_id: String) -> bool:
	return QuestManager.start_quest(quest_id)


func complete_quest(quest_id: String) -> bool:
	return QuestManager.complete_quest(quest_id)


func track_quest(quest_id: String) -> void:
	QuestManager.set_tracked_quest(quest_id)


func quest_state(quest_id: String) -> int:
	return QuestManager.get_state(quest_id)


# =============================================================================
# World Flags & Save/Load
# =============================================================================

func set_flag(flag_name: String, value: Variant = true) -> void:
	SaveManager.set_flag(flag_name, value)


func flag(flag_name: String, default_value: Variant = false) -> Variant:
	return SaveManager.get_flag(flag_name, default_value)


func save(slot_id: String = "slot_1") -> bool:
	return SaveManager.save_game(slot_id)


func load_save(slot_id: String = "slot_1") -> bool:
	return SaveManager.load_game(slot_id)


func has_save(slot_id: String = "slot_1") -> bool:
	return SaveManager.has_save(slot_id)


func autosave(reason: String = "manual") -> String:
	return SaveManager.trigger_autosave(reason)


func list_saves() -> Array[Dictionary]:
	return SaveManager.list_saves()


func set_checkpoint(checkpoint_id: String, room_id: String = "", pos: Vector2 = Vector2.ZERO) -> void:
	SaveManager.set_checkpoint(checkpoint_id, room_id, pos)


func respawn_at_checkpoint() -> bool:
	return SaveManager.respawn_at_checkpoint()


func register_save_provider(section_key: String, serialize_cb: Callable, deserialize_cb: Callable) -> void:
	SaveManager.register_provider(section_key, serialize_cb, deserialize_cb)


func set_difficulty(preset_name: String) -> bool:
	return DifficultyManager.set_preset(preset_name)


func set_dynamic_difficulty(enabled: bool) -> void:
	DifficultyManager.set_dynamic_enabled(enabled)


func difficulty_profile() -> Dictionary:
	return DifficultyManager.get_full_profile()


# =============================================================================
# Asset Packs, Audio & Combat Feedback
# =============================================================================

func use_pack(manifest_path: String, overlay: bool = false) -> bool:
	var ok := AssetRegistry.load_pack(manifest_path, not overlay)
	if ok and ThemeManager:
		ThemeManager.apply_from_pack()
	return ok


func set_font(path: String, pixel_sharp: bool = false) -> bool:
	return ThemeManager.load_font_file(path, pixel_sharp)


func ui_font() -> Font:
	return ThemeManager.get_font()


# =============================================================================
# Gamepad / Input & Rumble
# =============================================================================

func is_gamepad() -> bool:
	return InputManager.is_using_gamepad()


func prompt(action_name: String, bracketed: bool = true) -> String:
	return InputManager.get_prompt(action_name, bracketed)


func rumble(weak: float = 0.25, strong: float = 0.45, duration: float = 0.12) -> void:
	InputManager.rumble(weak, strong, duration)


func rumble_preset(preset_name: String) -> void:
	InputManager.rumble_preset(preset_name)


# =============================================================================
# 2-Player Co-op (Local Couch + Online ENet)
# =============================================================================

func start_local_coop(p2_actor_key: String = "player.shen_zhao", p2_joy_id: int = 0) -> Node:
	return CoopManager.start_local_coop(p2_actor_key, p2_joy_id)


func host_coop(port: int = 7777) -> Error:
	return CoopManager.host_coop(port)


func join_coop(address: String = "127.0.0.1", port: int = 7777) -> Error:
	return CoopManager.join_coop(address, port)


func leave_coop() -> void:
	CoopManager.leave_coop()


func is_coop() -> bool:
	return CoopManager.is_coop()


# =============================================================================
# Narrative Blackboard & Story Branch State Machine
# =============================================================================

func bb_set(key: String, value: Variant) -> void:
	StoryBlackboard.set_var(key, value)


func bb_get(key: String, default_value: Variant = null) -> Variant:
	return StoryBlackboard.get_var(key, default_value)


func bb_inc(key: String, delta: float = 1.0) -> float:
	return StoryBlackboard.inc(key, delta)


func add_tag(tag_name: String) -> void:
	StoryBlackboard.add_tag(tag_name)


func has_tag(tag_name: String) -> bool:
	return StoryBlackboard.has_tag(tag_name)


func choose(decision_id: String, option_id: String, effects: Dictionary = {}) -> void:
	StoryBlackboard.record_choice(decision_id, option_id, effects)


func chose(decision_id: String, option_id: String = "") -> bool:
	return StoryBlackboard.chose(decision_id, option_id)


func arc_state(arc_id: String) -> String:
	return StoryBlackboard.get_arc_state(arc_id)


func check_story(condition_expr: String, extra_ctx: Dictionary = {}) -> bool:
	return StoryBlackboard.check(condition_expr, extra_ctx)


func play_bgm(audio_key: String, fade_sec: float = 0.5) -> void:
	AudioManager.play_bgm(audio_key, fade_sec)


func play_sfx(audio_key: String, volume_db: float = -4.0) -> void:
	AudioManager.play_sfx(audio_key, volume_db)


func shake(intensity: float = 3.0, duration: float = 0.15) -> void:
	if EventBus:
		EventBus.camera_shake_requested.emit(intensity, duration)


## Scoped hitstop: freezes only `targets` (nodes or scope ids) for `ticks` fixed ticks.
## Input sampling, UI, network and spectator cameras keep running.
func hitstop_scoped(targets: Array, ticks: int, reason: String = "hitstop") -> void:
	if EventBus:
		EventBus.scoped_hitstop_requested.emit(targets, ticks, reason)
	var sim := get_node_or_null("/root/MoonSim")
	if sim != null:
		for t in targets:
			sim.freeze(t, ticks, reason)


## Global cinematic slow-down (explicit staging only; combat hits use `hitstop_scoped`).
func hitstop(duration: float = 0.04, time_scale: float = 0.08) -> void:
	if EventBus:
		EventBus.hitstop_requested.emit(duration, time_scale)


# =============================================================================
# Scripting / Formula / Lua Bridge & Content Validation
# =============================================================================

func eval(formula: String, context: Dictionary = {}) -> float:
	return ScriptBridge.eval_formula(formula, context)


func check(condition: String, context: Dictionary = {}) -> bool:
	return ScriptBridge.eval_condition(condition, context)


func hook(hook_name: String, callable: Callable) -> void:
	ScriptBridge.register_hook(hook_name, callable)


func call_hook(hook_name: String, payload: Dictionary = {}) -> Variant:
	return ScriptBridge.invoke_hook(hook_name, payload)


func validate_content() -> Array[String]:
	return DataRegistry.validate_all()


# =============================================================================
# Core VFX, Pixel AA & Stage Run Helpers
# =============================================================================

func apply_pixel_aa(item: CanvasItem) -> void:
	if ThemeManager:
		ThemeManager.apply_pixel_aa(item)


func vfx_slash(parent: Node, pos: Vector2, facing: float = 1.0, radius: float = 34.0, color: Color = Color(1.0, 0.85, 0.45)) -> Node2D:
	return PixelVFX.spawn_slash_arc(parent, pos, facing, radius, color)


func vfx_burst(parent: Node, pos: Vector2, color: Color = Color(1.0, 0.88, 0.45), count: int = 10) -> Node2D:
	return PixelVFX.spawn_burst(parent, pos, color, maxi(1, int(round(accessibility.apply("particles", float(count))))))


func vfx_ambient_motes(parent: Node, bounds: Rect2, count: int = 24, color: Color = Color(1.0, 0.92, 0.58, 0.48)) -> Node2D:
	return PixelVFX.spawn_ambient_motes(parent, bounds, maxi(0, int(round(accessibility.apply("particles", float(count))))), color)


func create_stage_tracker(stage_id: String, total_collectibles: int = 0, start_x: float = 0.0, goal_x: float = 1000.0) -> StageRunTracker:
	var tr := StageRunTracker.new()
	tr.start(stage_id, total_collectibles, start_x, goal_x)
	return tr


# =============================================================================
# Global Save Slot Modal, Quick Save/Load (F5/F9) & Hub Return (F12)
# =============================================================================

var _save_modal: SaveSlotModal = null


func open_save_menu(mode: String = "both") -> SaveSlotModal:
	if _save_modal == null or not is_instance_valid(_save_modal):
		_save_modal = SaveSlotModal.new()
		add_child(_save_modal)
	_save_modal.open_modal(mode)
	return _save_modal


func quick_save(slot_id: String = "slot_1") -> bool:
	var ok := SaveManager.save_game(slot_id) if SaveManager else false
	if ok:
		play_sfx("sfx.quest_clear")
	return ok


func quick_load(slot_id: String = "slot_1") -> bool:
	var ok := SaveManager.load_game(slot_id) if SaveManager else false
	if ok:
		play_sfx("sfx.ui_confirm")
	return ok


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		var kc := (event as InputEventKey).keycode
		if kc == KEY_F5:
			quick_save("slot_1")
			get_viewport().set_input_as_handled()
		elif kc == KEY_F9:
			quick_load("slot_1")
			get_viewport().set_input_as_handled()
		elif kc == KEY_F12:
			if ResourceLoader.exists("res://game/hub/moon_hub.tscn"):
				get_tree().change_scene_to_file("res://game/hub/moon_hub.tscn")
				get_viewport().set_input_as_handled()
