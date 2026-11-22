class_name InputRecorder
extends RefCounted
## Sequenced per-tick input capture with per-tick state hashes.
##
## A recording bundles: content version, tick rate, run seed, per-seat input frames
## (each with a monotonically increasing sequence number), per-tick simulation state hash,
## frame events, and optional network conditions. It is the raw material for
## `ReplayCompare.first_divergent_frame()` and for turning a live bug into a repeatable fixture.

var meta: Dictionary = {}
var frames: Array[Dictionary] = [] # { tick, seq, inputs: { seat -> Dictionary }, hash, events: Array }
var _seq: int = 0


func _init(content_version: String = "dev", tick_rate: int = 60, run_seed: int = 0) -> void:
	meta = {"content_version": content_version, "tick_rate": tick_rate, "run_seed": run_seed, "net": {}}


func set_network_conditions(rtt_ms: int, jitter_ms: int = 0, loss_pct: float = 0.0) -> void:
	meta["net"] = {"rtt_ms": rtt_ms, "jitter_ms": jitter_ms, "loss_pct": loss_pct}


## Records one tick. `inputs` maps seat -> input dict. `state` is hashed via `hash_state`.
func record(tick: int, inputs: Dictionary, state: Variant = null, events: Array = []) -> Dictionary:
	_seq += 1
	var f := {
		"tick": tick,
		"seq": _seq,
		"inputs": inputs.duplicate(true),
		"hash": hash_state(state) if state != null else 0,
		"events": events.duplicate(true),
	}
	frames.append(f)
	return f


func size() -> int:
	return frames.size()


func inputs_at(index: int) -> Dictionary:
	if index < 0 or index >= frames.size():
		return {}
	return frames[index]["inputs"]


## Keeps only the last `seconds` of frames (e.g. "pack the last 10 seconds of combat").
func trim_to_last_seconds(seconds: float) -> void:
	var keep := int(round(seconds * float(meta.get("tick_rate", 60))))
	if frames.size() > keep:
		frames = frames.slice(frames.size() - keep)


## Order-independent stable hash for Dictionaries / Arrays / scalars. Floats are quantised
## to 1/1000 so representation noise does not cause false divergences.
static func hash_state(state: Variant) -> int:
	return _canonical(state).hash()


static func _canonical(v: Variant) -> String:
	match typeof(v):
		TYPE_DICTIONARY:
			var d: Dictionary = v
			var keys := d.keys()
			keys.sort_custom(func(a, b): return str(a) < str(b))
			var parts: PackedStringArray = []
			for k in keys:
				parts.append("%s:%s" % [str(k), _canonical(d[k])])
			return "{" + ",".join(parts) + "}"
		TYPE_ARRAY:
			var parts2: PackedStringArray = []
			for e in (v as Array):
				parts2.append(_canonical(e))
			return "[" + ",".join(parts2) + "]"
		TYPE_FLOAT:
			return str(int(round(float(v) * 1000.0)))
		TYPE_VECTOR2:
			var p: Vector2 = v
			return "(%d,%d)" % [int(round(p.x * 1000.0)), int(round(p.y * 1000.0))]
		_:
			return str(v)


func serialize() -> Dictionary:
	return {"meta": meta.duplicate(true), "frames": frames.duplicate(true)}


func deserialize(data: Dictionary) -> void:
	meta = (data.get("meta", {}) as Dictionary).duplicate(true)
	frames.clear()
	for f in data.get("frames", []):
		frames.append((f as Dictionary).duplicate(true))
	_seq = int(frames.back()["seq"]) if not frames.is_empty() else 0
