extends Node
## Core-Layer Gapless Looping BGM Player (Dual-Deck Crossfade) + Pooled SFX Player.
##
## Guarantees 100% seamless head-to-tail looping for ANY OGG/WAV BGM track:
## - Reads `loop_start_ms` / `loop_end_ms` from AssetRegistry pack metadata
## - Crossfades automatically into the twin AudioStreamPlayer `crossfade_sec`
##   before `loop_end_sec` (eliminating trailing gaps or clicks even on unlooped imports)

const SFX_POOL_SIZE := 8
const DEFAULT_LOOP_CROSSFADE := 0.24

var current_bgm_key: String = ""
var _bgm_volume_db: float = -8.0
var _loop_start_sec: float = 0.0
var _loop_end_sec: float = 0.0
var _loop_crossfade_sec: float = DEFAULT_LOOP_CROSSFADE
var _loop_xfade_in_progress: bool = false

var _bgm_a: AudioStreamPlayer
var _bgm_b: AudioStreamPlayer
var _active_bgm: AudioStreamPlayer
var _bgm_tween: Tween = null
var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_cursor: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_bgm_a = AudioStreamPlayer.new()
	_bgm_b = AudioStreamPlayer.new()
	_bgm_a.finished.connect(func(): _on_bgm_finished(_bgm_a))
	_bgm_b.finished.connect(func(): _on_bgm_finished(_bgm_b))
	add_child(_bgm_a)
	add_child(_bgm_b)
	_active_bgm = _bgm_a

	for _i in range(SFX_POOL_SIZE):
		var p := AudioStreamPlayer.new()
		add_child(p)
		_sfx_pool.append(p)


func play_bgm(audio_key: String, fade_sec: float = 0.45, volume_db: float = -8.0) -> void:
	if audio_key == current_bgm_key and _active_bgm.playing:
		return
	var stream := AssetRegistry.load_audio_stream(audio_key)
	if stream == null:
		return

	# Disable native stream loop when we handle seamless dual-deck crossfade ourselves,
	# while keeping fallback safety via `finished`.
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = false
	elif stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_DISABLED

	var meta := AssetRegistry.get_audio_meta(audio_key)
	_loop_start_sec = maxf(0.0, float(meta.get("loop_start_ms", 0)) / 1000.0)
	var meta_end := float(meta.get("loop_end_ms", 0)) / 1000.0
	var stream_len := stream.get_length()
	_loop_end_sec = meta_end if (meta_end > _loop_start_sec + 0.5 and (stream_len <= 0.0 or meta_end <= stream_len)) else stream_len
	_loop_crossfade_sec = clampf(float(meta.get("crossfade_ms", 240)) / 1000.0, 0.08, 1.0)
	_bgm_volume_db = volume_db
	_loop_xfade_in_progress = false

	_crossfade_to(stream, _loop_start_sec, fade_sec, volume_db)
	current_bgm_key = audio_key


func _crossfade_to(stream: AudioStream, start_pos: float, fade_sec: float, volume_db: float) -> void:
	var next_player := _bgm_b if _active_bgm == _bgm_a else _bgm_a
	var prev_player := _active_bgm

	if _bgm_tween != null and _bgm_tween.is_valid():
		_bgm_tween.kill()
		_bgm_tween = null

	next_player.stream = stream
	next_player.volume_db = -36.0 if (fade_sec > 0.0 and DisplayServer.get_name() != "headless") else volume_db
	next_player.play(start_pos)

	if fade_sec > 0.0 and DisplayServer.get_name() != "headless":
		var base_lin := db_to_linear(volume_db)
		_bgm_tween = create_tween()
		_bgm_tween.tween_method(func(t: float):
			var in_gain := sin(t * PI * 0.5) * base_lin
			var out_gain := cos(t * PI * 0.5) * base_lin
			next_player.volume_db = linear_to_db(maxf(0.0001, in_gain))
			if prev_player.playing:
				prev_player.volume_db = linear_to_db(maxf(0.0001, out_gain))
		, 0.0, 1.0, fade_sec)
		_bgm_tween.tween_callback(func():
			prev_player.stop()
			next_player.volume_db = volume_db
			_loop_xfade_in_progress = false
		)
	else:
		next_player.volume_db = volume_db
		prev_player.stop()
		_loop_xfade_in_progress = false

	_active_bgm = next_player


func _process(_delta: float) -> void:
	if current_bgm_key.is_empty() or not _active_bgm.playing or _active_bgm.stream == null:
		return
	if _loop_xfade_in_progress or _loop_end_sec <= _loop_start_sec + _loop_crossfade_sec:
		return
	var pos := _active_bgm.get_playback_position()
	if pos >= _loop_end_sec - _loop_crossfade_sec:
		_loop_xfade_in_progress = true
		_crossfade_to(_active_bgm.stream, _loop_start_sec, _loop_crossfade_sec, _bgm_volume_db)


func _on_bgm_finished(player: AudioStreamPlayer) -> void:
	if player == _active_bgm and not current_bgm_key.is_empty() and player.stream != null and not _loop_xfade_in_progress:
		player.play(_loop_start_sec)


func stop_bgm(fade_sec: float = 0.3) -> void:
	current_bgm_key = ""
	_loop_xfade_in_progress = false
	if _bgm_tween != null and _bgm_tween.is_valid():
		_bgm_tween.kill()
		_bgm_tween = null
	if not _active_bgm.playing:
		return
	if fade_sec > 0.0 and DisplayServer.get_name() != "headless":
		_bgm_tween = create_tween()
		_bgm_tween.tween_property(_active_bgm, "volume_db", -40.0, fade_sec)
		_bgm_tween.tween_callback(_active_bgm.stop)
	else:
		_active_bgm.stop()


func play_sfx(audio_key: String, volume_db: float = -4.0, pitch_jitter: float = 0.05) -> void:
	var stream := AssetRegistry.load_audio_stream(audio_key)
	if stream == null:
		return
	var player := _sfx_pool[_sfx_cursor]
	_sfx_cursor = (_sfx_cursor + 1) % _sfx_pool.size()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = randf_range(1.0 - pitch_jitter, 1.0 + pitch_jitter) if pitch_jitter > 0.0 else 1.0
	player.play()


func stop_all() -> void:
	current_bgm_key = ""
	_loop_xfade_in_progress = false
	if _bgm_tween != null and _bgm_tween.is_valid():
		_bgm_tween.kill()
		_bgm_tween = null
	if is_instance_valid(_bgm_a):
		_bgm_a.stop()
		_bgm_a.stream = null
	if is_instance_valid(_bgm_b):
		_bgm_b.stop()
		_bgm_b.stream = null
	for p in _sfx_pool:
		if is_instance_valid(p):
			p.stop()
			p.stream = null


func _exit_tree() -> void:
	stop_all()
