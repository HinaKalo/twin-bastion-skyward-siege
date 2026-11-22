class_name ReplayCompare
extends RefCounted
## Replay utilities: locate the first divergent tick between two recordings, and
## re-run a recording through a deterministic step function to verify or branch it.


## Returns the index of the first frame whose state hash (or inputs) differ, or -1 when equal.
static func first_divergent_frame(a: InputRecorder, b: InputRecorder, compare_inputs: bool = false) -> int:
	var n := mini(a.frames.size(), b.frames.size())
	for i in range(n):
		var fa: Dictionary = a.frames[i]
		var fb: Dictionary = b.frames[i]
		if int(fa["hash"]) != int(fb["hash"]):
			return i
		if compare_inputs and InputRecorder.hash_state(fa["inputs"]) != InputRecorder.hash_state(fb["inputs"]):
			return i
	if a.frames.size() != b.frames.size():
		return n
	return -1


## Re-simulates `source` with `step_fn(inputs: Dictionary) -> Variant(state)` and returns a fresh
## recording. `stop_at` (exclusive) allows branching a new session from any tick.
static func resimulate(source: InputRecorder, step_fn: Callable, stop_at: int = -1) -> InputRecorder:
	var out := InputRecorder.new(str(source.meta.get("content_version", "dev")), int(source.meta.get("tick_rate", 60)), int(source.meta.get("run_seed", 0)))
	var end := source.frames.size() if stop_at < 0 else mini(stop_at, source.frames.size())
	for i in range(end):
		var f: Dictionary = source.frames[i]
		var state: Variant = step_fn.call(f["inputs"])
		out.record(int(f["tick"]), f["inputs"], state)
	return out


## Human-readable divergence summary for logs and bug reports.
static func describe(a: InputRecorder, b: InputRecorder) -> Dictionary:
	var idx := first_divergent_frame(a, b)
	if idx < 0:
		return {"diverged": false}
	var fa: Dictionary = a.frames[idx] if idx < a.frames.size() else {}
	var fb: Dictionary = b.frames[idx] if idx < b.frames.size() else {}
	return {
		"diverged": true,
		"frame_index": idx,
		"tick": int(fa.get("tick", fb.get("tick", -1))),
		"hash_a": int(fa.get("hash", 0)),
		"hash_b": int(fb.get("hash", 0)),
		"content_a": str(a.meta.get("content_version", "")),
		"content_b": str(b.meta.get("content_version", "")),
	}
