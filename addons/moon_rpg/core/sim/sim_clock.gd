class_name SimClock
extends RefCounted
## Fixed-step simulation clock with independent time domains and scoped freezes.
##
## - Fixed step (default 60 Hz, configurable) driven by an accumulator, decoupled from
##   display refresh and asset frame rate.
## - Named time domains (movement / damage / story / mechanism / particles / audio / camera / ui)
##   each carry their own scale, so a cinematic slow-mo can slow particles without slowing UI.
## - Scoped freezes (hitstop) target an entity id or region id instead of `Engine.time_scale`,
##   so input sampling, UI, server and spectator cameras keep updating.
## - `frozen_report()` answers "who exactly is frozen on this tick" for editor / debug overlays.

signal ticked(tick: int)

const DEFAULT_DOMAINS := ["movement", "damage", "story", "mechanism", "particles", "audio", "camera", "ui"]
const UNFREEZABLE_DOMAINS := ["ui", "audio"]

var tick_rate: int = 60
var tick: int = 0
var _accumulator: float = 0.0
var _domain_scale: Dictionary = {}
var _freezes: Dictionary = {} # scope_id -> { ticks_left, reason, started_tick }
var _slowmo_scale: float = 1.0
var _slowmo_ticks_left: int = 0
var max_steps_per_frame: int = 8


func _init(rate: int = 60) -> void:
	set_tick_rate(rate)
	for d in DEFAULT_DOMAINS:
		_domain_scale[d] = 1.0


func set_tick_rate(rate: int) -> void:
	tick_rate = clampi(rate, 10, 480)


func step_seconds() -> float:
	return 1.0 / float(tick_rate)


## Converts seconds into whole ticks at the current rate (rounded, min 0).
func seconds_to_ticks(seconds: float) -> int:
	return maxi(0, int(round(seconds * float(tick_rate))))


func ticks_to_seconds(ticks: int) -> float:
	return float(ticks) / float(tick_rate)


## Feeds real elapsed time. Returns how many fixed steps were executed.
func advance(real_delta: float) -> int:
	_accumulator += maxf(0.0, real_delta)
	var dt := step_seconds()
	var steps := 0
	while _accumulator >= dt and steps < max_steps_per_frame:
		_accumulator -= dt
		step_once()
		steps += 1
	if steps >= max_steps_per_frame:
		_accumulator = 0.0
	return steps


## Executes exactly one fixed tick (used by deterministic tests / replays).
func step_once() -> void:
	tick += 1
	var finished: Array = []
	for scope_id in _freezes.keys():
		var f: Dictionary = _freezes[scope_id]
		f["ticks_left"] = int(f["ticks_left"]) - 1
		if int(f["ticks_left"]) <= 0:
			finished.append(scope_id)
	for scope_id in finished:
		_freezes.erase(scope_id)
	if _slowmo_ticks_left > 0:
		_slowmo_ticks_left -= 1
		if _slowmo_ticks_left <= 0:
			_slowmo_scale = 1.0
	ticked.emit(tick)


func register_domain(domain: String, scale: float = 1.0) -> void:
	_domain_scale[domain] = maxf(0.0, scale)


func set_domain_scale(domain: String, scale: float) -> void:
	_domain_scale[domain] = maxf(0.0, scale)


## Effective scale for a domain = domain scale * global cinematic slow-mo (UI / audio exempt).
func domain_scale(domain: String) -> float:
	var s := float(_domain_scale.get(domain, 1.0))
	if not UNFREEZABLE_DOMAINS.has(domain):
		s *= _slowmo_scale
	return s


func domain_delta(domain: String) -> float:
	return step_seconds() * domain_scale(domain)


## Freezes a scope (entity instance id, "region:<id>", "seat:<n>", ...) for `ticks` ticks.
## Re-freezing keeps the longer remaining duration.
func freeze(scope_id: Variant, ticks: int, reason: String = "hitstop") -> void:
	if ticks <= 0:
		return
	var key := str(scope_id)
	var prev: Dictionary = _freezes.get(key, {})
	if not prev.is_empty() and int(prev["ticks_left"]) >= ticks:
		return
	_freezes[key] = {"ticks_left": ticks, "reason": reason, "started_tick": tick}


func unfreeze(scope_id: Variant) -> void:
	_freezes.erase(str(scope_id))


func is_frozen(scope_id: Variant) -> bool:
	return _freezes.has(str(scope_id))


func frozen_ticks_left(scope_id: Variant) -> int:
	var f: Dictionary = _freezes.get(str(scope_id), {})
	return int(f.get("ticks_left", 0))


## Debug answer to "which scopes are frozen on this tick and why".
func frozen_report() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for scope_id in _freezes.keys():
		var f: Dictionary = _freezes[scope_id]
		out.append({"scope": scope_id, "ticks_left": f["ticks_left"], "reason": f["reason"], "since": f["started_tick"]})
	out.sort_custom(func(a: Dictionary, b: Dictionary): return str(a["scope"]) < str(b["scope"]))
	return out


## Explicit cinematic slow-motion (global, opt-in). Not used for hitstop.
func global_slowmo(scale: float, ticks: int) -> void:
	_slowmo_scale = clampf(scale, 0.0, 1.0)
	_slowmo_ticks_left = maxi(0, ticks)
	if _slowmo_ticks_left == 0:
		_slowmo_scale = 1.0


func is_slowmo_active() -> bool:
	return _slowmo_ticks_left > 0


func reset() -> void:
	tick = 0
	_accumulator = 0.0
	_freezes.clear()
	_slowmo_scale = 1.0
	_slowmo_ticks_left = 0


func serialize() -> Dictionary:
	return {"tick_rate": tick_rate, "tick": tick, "domains": _domain_scale.duplicate(), "freezes": _freezes.duplicate(true)}


func deserialize(data: Dictionary) -> void:
	set_tick_rate(int(data.get("tick_rate", tick_rate)))
	tick = int(data.get("tick", 0))
	_domain_scale = (data.get("domains", _domain_scale) as Dictionary).duplicate()
	_freezes = (data.get("freezes", {}) as Dictionary).duplicate(true)
