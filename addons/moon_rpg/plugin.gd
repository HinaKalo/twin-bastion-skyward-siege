@tool
extends EditorPlugin
## MoonRPG Engine EditorPlugin entry point.
## Registers all engine Autoloads cleanly when enabled in a new Godot project.

const AUTOLOADS := [
	["EventBus", "res://addons/moon_rpg/core/event_bus.gd"],
	["ScriptBridge", "res://addons/moon_rpg/core/script_bridge.gd"],
	["LocaleManager", "res://addons/moon_rpg/core/locale_manager.gd"],
	["AssetRegistry", "res://addons/moon_rpg/core/asset_registry.gd"],
	["ThemeManager", "res://addons/moon_rpg/core/theme_manager.gd"],
	["UIStack", "res://addons/moon_rpg/core/ui_stack.gd"],
	["InputManager", "res://addons/moon_rpg/core/input_manager.gd"],
	["CoopManager", "res://addons/moon_rpg/core/coop_manager.gd"],
	["DifficultyManager", "res://addons/moon_rpg/core/difficulty_manager.gd"],
	["DataRegistry", "res://addons/moon_rpg/core/data_registry.gd"],
	["AudioManager", "res://addons/moon_rpg/core/audio_manager.gd"],
	["InventoryManager", "res://addons/moon_rpg/rpg/inventory_manager.gd"],
	["QuestManager", "res://addons/moon_rpg/rpg/quest_manager.gd"],
	["StoryBlackboard", "res://addons/moon_rpg/rpg/story_blackboard.gd"],
	["DialogueRunner", "res://addons/moon_rpg/rpg/dialogue_runner.gd"],
	["WorldManager", "res://addons/moon_rpg/rpg/world_manager.gd"],
	["SaveManager", "res://addons/moon_rpg/core/save_manager.gd"],
	["MoonRPG", "res://addons/moon_rpg/moon_rpg.gd"],
]


func _enter_tree() -> void:
	for entry in AUTOLOADS:
		if not ProjectSettings.has_setting("autoload/" + entry[0]):
			add_autoload_singleton(entry[0], entry[1])


func _exit_tree() -> void:
	pass
