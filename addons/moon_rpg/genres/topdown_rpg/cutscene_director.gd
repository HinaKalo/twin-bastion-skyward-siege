class_name CutsceneDirector
extends Node
## Declarative JRPG Cutscene & Story Direction Engine (Persona / Trails in the Sky style).
##
## Plays ordered arrays of declarative steps (from GDScript or JSON):
##   { "type": "letterbox", "enabled": true }
##   { "type": "actor_emote", "actor": "elder", "emote": "alert", "duration": 1.0 }
##   { "type": "actor_move", "actor": "hero", "to": [240, 140], "speed": 90 }
##   { "type": "cam_pan", "to": [260, 140], "duration": 0.6 }
##   { "type": "say", "speaker": "老村长", "text": "欢迎来到边境城镇！", "portrait": "npc.camp_smith" }
##   { "type": "bb_tag", "tag": "intro_cutscene_seen" }

signal cutscene_started(cutscene_id: String)
signal cutscene_finished(cutscene_id: String)

var is_playing: bool = false
var _actors: Dictionary = {} # actor_id -> Node2D
var _camera: Camera2D = null
var _overlay_layer: CanvasLayer = null
var _fade_rect: ColorRect = null
var _bar_top: ColorRect = null
var _bar_bottom: ColorRect = null


func register_actor(actor_id: String, node: Node2D) -> void:
	_actors[actor_id] = node


func set_camera(cam: Camera2D) -> void:
	_camera = cam


func _ensure_overlay() -> void:
	if _overlay_layer != null:
		return
	_overlay_layer = CanvasLayer.new()
	_overlay_layer.layer = 15
	add_child(_overlay_layer)

	_bar_top = ColorRect.new()
	_bar_top.color = Color.BLACK
	_bar_top.position = Vector2(0, -28)
	_bar_top.size = Vector2(480, 28)
	_overlay_layer.add_child(_bar_top)

	_bar_bottom = ColorRect.new()
	_bar_bottom.color = Color.BLACK
	_bar_bottom.position = Vector2(0, 270)
	_bar_bottom.size = Vector2(480, 28)
	_overlay_layer.add_child(_bar_bottom)

	_fade_rect = ColorRect.new()
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.color = Color(0, 0, 0, 0)
	_overlay_layer.add_child(_fade_rect)


## Runs a cutscene step sequence asynchronously.
func play_sequence(steps: Array, cutscene_id: String = "cutscene") -> void:
	if is_playing:
		return
	is_playing = true
	if _camera is MoonCamera2D:
		(_camera as MoonCamera2D).pause_follow = true
	cutscene_started.emit(cutscene_id)

	for step in steps:
		if typeof(step) != TYPE_DICTIONARY:
			continue
		await _execute_step(step)

	if _camera is MoonCamera2D:
		(_camera as MoonCamera2D).pause_follow = false
	is_playing = false
	cutscene_finished.emit(cutscene_id)


func _execute_step(step: Dictionary) -> void:
	var kind := str(step.get("type", ""))
	match kind:
		"wait":
			var dur := float(step.get("duration", 0.5))
			if dur > 0.0 and is_inside_tree():
				await get_tree().create_timer(dur).timeout
		"letterbox":
			_ensure_overlay()
			var en := bool(step.get("enabled", true))
			var tw := create_tween().set_parallel(true)
			tw.tween_property(_bar_top, "position:y", 0.0 if en else -28.0, 0.25)
			tw.tween_property(_bar_bottom, "position:y", 242.0 if en else 270.0, 0.25)
			await tw.finished
		"fade_out":
			_ensure_overlay()
			var tw := create_tween()
			tw.tween_property(_fade_rect, "color:a", 1.0, float(step.get("duration", 0.35)))
			await tw.finished
		"fade_in":
			_ensure_overlay()
			var tw := create_tween()
			tw.tween_property(_fade_rect, "color:a", 0.0, float(step.get("duration", 0.35)))
			await tw.finished
		"cam_pan":
			if is_instance_valid(_camera):
				var arr: Array = step.get("to", [0, 0])
				var target := Vector2(float(arr[0]), float(arr[1]))
				var tw := create_tween()
				tw.tween_property(_camera, "global_position", target, float(step.get("duration", 0.5)))
				await tw.finished
		"cam_zoom":
			if is_instance_valid(_camera):
				var z := float(step.get("zoom", 1.0))
				var tw := create_tween()
				tw.tween_property(_camera, "zoom", Vector2(z, z), float(step.get("duration", 0.4)))
				await tw.finished
		"actor_move":
			var node: Node2D = _actors.get(str(step.get("actor", "")), null)
			if is_instance_valid(node):
				var arr: Array = step.get("to", [node.global_position.x, node.global_position.y])
				var target := Vector2(float(arr[0]), float(arr[1]))
				var spd := maxf(10.0, float(step.get("speed", 90.0)))
				var dur := node.global_position.distance_to(target) / spd
				if dur > 0.01:
					var tw := create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
					tw.tween_property(node, "global_position", target, dur)
					await tw.finished
		"actor_emote":
			var node: Node2D = _actors.get(str(step.get("actor", "")), null)
			if is_instance_valid(node):
				var bubble := EmoteBubble2D.new()
				bubble.position = Vector2(0, -34)
				node.add_child(bubble)
				var dur := float(step.get("duration", 1.0))
				bubble.setup(str(step.get("emote", "alert")), dur)
				if bool(step.get("await", false)) and is_inside_tree():
					await get_tree().create_timer(dur).timeout
		"dialogue":
			if DialogueRunner:
				DialogueRunner.start_dialogue(str(step.get("dialogue_id", "")))
				if EventBus and DialogueRunner.is_active:
					await EventBus.dialogue_ended
		"say":
			if DialogueRunner:
				DialogueRunner.say_line(str(step.get("speaker", "")), str(step.get("text", "")), str(step.get("portrait", "")))
				if EventBus and DialogueRunner.is_active:
					await EventBus.dialogue_ended
		"bgm":
			if AudioManager:
				AudioManager.play_bgm(str(step.get("key", "")))
		"sfx":
			if AudioManager:
				AudioManager.play_sfx(str(step.get("key", "")))
		"bb_tag":
			if StoryBlackboard:
				StoryBlackboard.add_tag(str(step.get("tag", "")))
		"bb_set":
			if StoryBlackboard:
				StoryBlackboard.set_var(str(step.get("key", "")), step.get("value", true))
		"hook":
			if ScriptBridge:
				ScriptBridge.invoke_hook(str(step.get("name", "")), step.get("payload", {}))
