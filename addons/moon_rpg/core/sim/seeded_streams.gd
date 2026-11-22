class_name SeededStreams
extends RefCounted
## Domain-split deterministic randomness.
##
## Every draw is a pure function of (run seed, domain, reward point, seat, draw index), so a card
## draw, loot roll or encounter swap reproduces exactly on replay, on the authoritative server,
## or after a reconnect — and rolling one domain never shifts another domain's sequence.

var run_seed: int = 0
var _counters: Dictionary = {} # "domain|point|seat" -> next draw index


func _init(seed_value: int = 0) -> void:
	run_seed = seed_value


## Stable 64-bit-ish hash of the draw key (FNV-1a over the UTF-8 key).
func key_hash(domain: String, reward_point: String = "", seat: int = 0, draw_index: int = 0) -> int:
	var key := "%d|%s|%s|%d|%d" % [run_seed, domain, reward_point, seat, draw_index]
	var h: int = 1469598103934665603
	for b in key.to_utf8_buffer():
		h = h ^ int(b)
		h = (h * 1099511628211) & 0x7FFFFFFFFFFFFFFF
	return h


func _rng_for(domain: String, reward_point: String, seat: int, draw_index: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = key_hash(domain, reward_point, seat, draw_index)
	return rng


## Float in [0, 1) for an explicit draw index.
func roll(domain: String, reward_point: String = "", seat: int = 0, draw_index: int = 0) -> float:
	return _rng_for(domain, reward_point, seat, draw_index).randf()


func roll_int(domain: String, from: int, to: int, reward_point: String = "", seat: int = 0, draw_index: int = 0) -> int:
	return _rng_for(domain, reward_point, seat, draw_index).randi_range(from, to)


## Picks `count` distinct entries from `pool` for a given draw (e.g. a 3-card offer).
func pick_distinct(domain: String, pool: Array, count: int, reward_point: String = "", seat: int = 0, draw_index: int = 0) -> Array:
	var rng := _rng_for(domain, reward_point, seat, draw_index)
	var bag := pool.duplicate()
	var out: Array = []
	while out.size() < count and not bag.is_empty():
		var i := rng.randi_range(0, bag.size() - 1)
		out.append(bag[i])
		bag.remove_at(i)
	return out


## Weighted pick: `table` is Array of { "id", "weight" }.
func pick_weighted(domain: String, table: Array, reward_point: String = "", seat: int = 0, draw_index: int = 0) -> Dictionary:
	var total := 0.0
	for e in table:
		total += maxf(0.0, float((e as Dictionary).get("weight", 1.0)))
	if total <= 0.0:
		return {}
	var r := roll(domain, reward_point, seat, draw_index) * total
	for e in table:
		r -= maxf(0.0, float((e as Dictionary).get("weight", 1.0)))
		if r < 0.0:
			return e
	return table.back()


## Sequential convenience: uses and advances the per-(domain, point, seat) counter.
func next(domain: String, reward_point: String = "", seat: int = 0) -> float:
	var ck := "%s|%s|%d" % [domain, reward_point, seat]
	var idx := int(_counters.get(ck, 0))
	_counters[ck] = idx + 1
	return roll(domain, reward_point, seat, idx)


func draw_index(domain: String, reward_point: String = "", seat: int = 0) -> int:
	return int(_counters.get("%s|%s|%d" % [domain, reward_point, seat], 0))


func serialize() -> Dictionary:
	return {"run_seed": run_seed, "counters": _counters.duplicate()}


func deserialize(data: Dictionary) -> void:
	run_seed = int(data.get("run_seed", run_seed))
	_counters = (data.get("counters", {}) as Dictionary).duplicate()
