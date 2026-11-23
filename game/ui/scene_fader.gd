class_name SceneFader
extends CanvasLayer
## Fade-through-black scene transitions. The fader lives under the tree root, so it survives the scene swap
## and fades the new scene in. Usage: SceneFader.go(get_tree(), "res://game/scenes/campaign_map.tscn")

var _rect: ColorRect
static var _busy: bool = false


static func go(tree: SceneTree, path: String, dur: float = 0.22) -> void:
	if tree == null:
		return
	if _busy:
		return
	var f := SceneFader.new()
	f.layer = 120
	f.process_mode = Node.PROCESS_MODE_ALWAYS
	tree.root.add_child(f)
	f._run(path, dur)


func _run(path: String, dur: float) -> void:
	_busy = true
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.color = Color(0.02, 0.02, 0.05, 0.0)
	_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_rect)
	var tw := create_tween()
	tw.tween_property(_rect, "color:a", 1.0, dur)
	await tw.finished
	get_tree().paused = false
	get_tree().change_scene_to_file(path)
	await get_tree().process_frame
	await get_tree().process_frame
	var tw2 := create_tween()
	tw2.tween_property(_rect, "color:a", 0.0, dur * 1.3)
	await tw2.finished
	_busy = false
	queue_free()
