extends Node
## Hot-Swappable Asset Pack Registry.
## Resolves semantic logical keys (e.g., `player.shen_zhao`, `ui.panel_wood`, `bgm.forest`)
## from one or more stacked `pack.json` manifests. Supports runtime PNG strip -> SpriteFrames
## compilation and nine-slice StyleBoxTexture generation with zero editor re-import required.

const DEFAULT_PACK_MANIFEST := "res://content/packs/koei_demo/pack.json"

var active_pack_id: String = ""
var _manifest: Dictionary = {}
var _base_dir: String = ""
var _texture_cache: Dictionary = {}
var _sprite_frames_cache: Dictionary = {}
var _stylebox_cache: Dictionary = {}
var _audio_cache: Dictionary = {}


func _ready() -> void:
	if FileAccess.file_exists(DEFAULT_PACK_MANIFEST):
		load_pack(DEFAULT_PACK_MANIFEST)


func load_pack(manifest_path: String, clear_existing: bool = true) -> bool:
	if not FileAccess.file_exists(manifest_path):
		push_error("[AssetRegistry] Pack manifest not found: %s" % manifest_path)
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("[AssetRegistry] Invalid pack JSON: %s" % manifest_path)
		return false

	if clear_existing:
		_manifest = parsed
		_texture_cache.clear()
		_sprite_frames_cache.clear()
		_stylebox_cache.clear()
		_audio_cache.clear()
	else:
		_merge_pack(_manifest, parsed)

	active_pack_id = str(_manifest.get("pack_id", "custom"))
	_base_dir = str(_manifest.get("base_dir", manifest_path.get_base_dir() + "/assets"))
	return true


func _merge_pack(target: Dictionary, overlay: Dictionary) -> void:
	for section in ["actors", "portraits", "biomes", "props", "icons", "ui", "vfx", "audio"]:
		if not overlay.has(section):
			continue
		if not target.has(section):
			target[section] = {}
		var dst: Dictionary = target[section]
		var src: Dictionary = overlay[section]
		for k in src.keys():
			dst[k] = src[k]


func resolve_path(rel_path: String) -> String:
	if rel_path.begins_with("res://") or rel_path.begins_with("user://"):
		return rel_path
	return "%s/%s" % [_base_dir.trim_suffix("/"), rel_path.trim_prefix("/")]


func load_texture(rel_or_res_path: String) -> Texture2D:
	if rel_or_res_path.is_empty():
		return null
	var full_path := resolve_path(rel_or_res_path)
	if _texture_cache.has(full_path):
		return _texture_cache[full_path]

	var tex: Texture2D = null
	if ResourceLoader.exists(full_path):
		var loaded := ResourceLoader.load(full_path)
		if loaded is Texture2D:
			tex = loaded
	if tex == null:
		var abs_path := ProjectSettings.globalize_path(full_path)
		if FileAccess.file_exists(abs_path):
			var img := Image.load_from_file(abs_path)
			if img != null and not img.is_empty():
				tex = ImageTexture.create_from_image(img)
	if tex != null:
		_texture_cache[full_path] = tex
	else:
		push_warning("[AssetRegistry] Failed to load texture: %s" % full_path)
	return tex


func get_actor_meta(actor_key: String) -> Dictionary:
	return _manifest.get("actors", {}).get(actor_key, {})


func get_actor_pivot(actor_key: String) -> Vector2:
	var meta := get_actor_meta(actor_key)
	var p: Array = meta.get("pivot", [32, 64])
	return Vector2(float(p[0]), float(p[1]))


func get_actor_frame_size(actor_key: String) -> Vector2:
	var meta := get_actor_meta(actor_key)
	var fs: Array = meta.get("frame_size", [64, 64])
	return Vector2(float(fs[0]), float(fs[1]))


func get_action_cues(actor_key: String, action_name: String) -> Dictionary:
	var meta := get_actor_meta(actor_key)
	var act: Dictionary = meta.get("actions", {}).get(action_name, {})
	return act.get("cues", {})


## Dynamically compiles an actor's strip PNGs into a cached Godot SpriteFrames resource.
func build_actor_sprite_frames(actor_key: String) -> SpriteFrames:
	if _sprite_frames_cache.has(actor_key):
		return _sprite_frames_cache[actor_key]

	var meta := get_actor_meta(actor_key)
	if meta.is_empty():
		push_warning("[AssetRegistry] Unknown actor key: %s" % actor_key)
		return null

	var sf := SpriteFrames.new()
	if sf.has_animation("default"):
		sf.remove_animation("default")

	var actions: Dictionary = meta.get("actions", {})
	for action_name in actions.keys():
		var act: Dictionary = actions[action_name]
		var strip_tex := load_texture(str(act.get("file", "")))
		if strip_tex == null:
			continue
		sf.add_animation(action_name)
		sf.set_animation_loop(action_name, bool(act.get("loop", false)))

		var frames_count := int(act.get("frames", 1))
		var fs: Array = act.get("frame_size", meta.get("frame_size", [64, 64]))
		var fw := int(fs[0])
		var fh := int(fs[1])
		var durations: Array = act.get("durations_ms", [])

		var base_ms := 100.0
		if not durations.is_empty():
			base_ms = maxf(16.0, float(durations[0]))
		sf.set_animation_speed(action_name, 1000.0 / base_ms)

		for i in range(frames_count):
			var atlas := AtlasTexture.new()
			atlas.atlas = strip_tex
			atlas.region = Rect2(i * fw, 0, fw, fh)
			var dur_ratio := 1.0
			if i < durations.size() and base_ms > 0.0:
				dur_ratio = maxf(0.1, float(durations[i]) / base_ms)
			sf.add_frame(action_name, atlas, dur_ratio)

	_sprite_frames_cache[actor_key] = sf
	return sf


func build_vfx_sprite_frames(vfx_key: String) -> SpriteFrames:
	var cache_key := "vfx:" + vfx_key
	if _sprite_frames_cache.has(cache_key):
		return _sprite_frames_cache[cache_key]
	var act: Dictionary = _manifest.get("vfx", {}).get(vfx_key, {})
	if act.is_empty():
		return null
	var strip_tex := load_texture(str(act.get("file", "")))
	if strip_tex == null:
		return null
	var sf := SpriteFrames.new()
	if sf.has_animation("default"):
		sf.remove_animation("default")
	sf.add_animation("play")
	sf.set_animation_loop("play", false)
	var frames_count := int(act.get("frames", 1))
	var fs: Array = act.get("frame_size", [32, 32])
	var fw := int(fs[0])
	var fh := int(fs[1])
	var durations: Array = act.get("durations_ms", [])
	var base_ms := maxf(16.0, float(durations[0])) if not durations.is_empty() else 60.0
	sf.set_animation_speed("play", 1000.0 / base_ms)
	for i in range(frames_count):
		var atlas := AtlasTexture.new()
		atlas.atlas = strip_tex
		atlas.region = Rect2(i * fw, 0, fw, fh)
		sf.add_frame("play", atlas, 1.0)
	_sprite_frames_cache[cache_key] = sf
	return sf


func get_portrait(portrait_key: String) -> Texture2D:
	var rel: String = str(_manifest.get("portraits", {}).get(portrait_key, ""))
	if rel.is_empty():
		return null
	return load_texture(rel)


func get_icon(icon_key: String) -> Texture2D:
	var rel: String = str(_manifest.get("icons", {}).get(icon_key, ""))
	if rel.is_empty():
		return null
	return load_texture(rel)


func get_prop_texture(prop_key: String) -> Texture2D:
	var rel: String = str(_manifest.get("props", {}).get(prop_key, ""))
	if rel.is_empty():
		return null
	return load_texture(rel)


func get_biome_meta(biome_key: String) -> Dictionary:
	return _manifest.get("biomes", {}).get(biome_key, {})


func get_ui_texture(ui_key: String) -> Texture2D:
	var meta: Dictionary = _manifest.get("ui", {}).get(ui_key, {})
	if meta.is_empty():
		return null
	return load_texture(str(meta.get("file", "")))


func get_ui_stylebox(ui_key: String, content_margin: float = 6.0) -> StyleBoxTexture:
	var cache_key := "%s:%0.1f" % [ui_key, content_margin]
	if _stylebox_cache.has(cache_key):
		return _stylebox_cache[cache_key]
	var meta: Dictionary = _manifest.get("ui", {}).get(ui_key, {})
	if meta.is_empty():
		return null
	var tex := load_texture(str(meta.get("file", "")))
	if tex == null:
		return null
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	var ns: Array = meta.get("nine_slice", [4, 4, 4, 4])
	sb.texture_margin_left = float(ns[0])
	sb.texture_margin_top = float(ns[1])
	sb.texture_margin_right = float(ns[2])
	sb.texture_margin_bottom = float(ns[3])
	sb.content_margin_left = content_margin
	sb.content_margin_top = content_margin
	sb.content_margin_right = content_margin
	sb.content_margin_bottom = content_margin
	_stylebox_cache[cache_key] = sb
	return sb


func get_audio_meta(audio_key: String) -> Dictionary:
	return _manifest.get("audio", {}).get(audio_key, {})


func get_font_meta() -> Variant:
	return _manifest.get("font", null)


func load_audio_stream(audio_key: String) -> AudioStream:
	if _audio_cache.has(audio_key):
		return _audio_cache[audio_key]
	var meta := get_audio_meta(audio_key)
	if meta.is_empty():
		return null
	var full_path := resolve_path(str(meta.get("file", "")))
	var stream: AudioStream = null
	if ResourceLoader.exists(full_path):
		var loaded := ResourceLoader.load(full_path)
		if loaded is AudioStream:
			stream = loaded
	if stream == null:
		var abs_path := ProjectSettings.globalize_path(full_path)
		if FileAccess.file_exists(abs_path):
			if full_path.ends_with(".ogg"):
				stream = AudioStreamOggVorbis.load_from_file(abs_path)
			elif full_path.ends_with(".wav"):
				stream = AudioStreamWAV.load_from_file(abs_path)
	if stream != null:
		_audio_cache[audio_key] = stream
	return stream


func clear_caches() -> void:
	_texture_cache.clear()
	_sprite_frames_cache.clear()
	_stylebox_cache.clear()
	_audio_cache.clear()


func list_actors() -> Array[String]:
	var out: Array[String] = []
	for k in _manifest.get("actors", {}).keys():
		out.append(str(k))
	return out


func list_biomes() -> Array[String]:
	var out: Array[String] = []
	for k in _manifest.get("biomes", {}).keys():
		out.append(str(k))
	return out


func list_icons() -> Array[String]:
	var out: Array[String] = []
	for k in _manifest.get("icons", {}).keys():
		out.append(str(k))
	return out


func list_audio() -> Array[String]:
	var out: Array[String] = []
	for k in _manifest.get("audio", {}).keys():
		out.append(str(k))
	return out


func _exit_tree() -> void:
	clear_caches()
