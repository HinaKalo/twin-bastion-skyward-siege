class_name DefenseState
extends RefCounted
## Frame-based defensive windows: perfect guard, release grace, re-press lockout, facing
## requirement, chip guard, perfect evade (rewarded once per dodge) and invulnerability.
## Ported from Tideforge `motion.gd` / `model.hurt()`; used by both the headless arena sim and
## Hurtbox2D so the same rules apply in tests and in game.

var guard_window: int = 10       # ticks after pressing guard that count as perfect
var release_grace: int = 3       # perfect still counts this many ticks after an early release
var repress_lockout: int = 17    # re-guarding sooner than this never yields a perfect
var chip_ratio: float = 0.32
var leniency: int = 0            # accessibility: extra perfect-guard ticks

var evade_window_frames: int = 8
var dodge_invuln_frames: int = 6

var guard_held: bool = false
var guard_t: int = 99
var guard_grace: int = 0
var since_release: int = 999
var evade_window: int = 0
var evade_rewarded: bool = false
var inv: int = 0
var counter: int = 0             # counter-attack window after a perfect guard


func press_guard() -> void:
	guard_held = true
	guard_t = 99 if since_release < repress_lockout else 0


func release_guard() -> void:
	if guard_held and guard_t <= guard_window + leniency:
		guard_grace = release_grace
	guard_held = false
	since_release = 0


func start_dodge(evade_frames: int = -1, invuln_frames: int = -1) -> void:
	var was_inv := inv > 0
	evade_window = 0 if was_inv else (evade_frames if evade_frames >= 0 else evade_window_frames)
	evade_rewarded = false
	inv = maxi(inv, invuln_frames if invuln_frames >= 0 else dodge_invuln_frames)


func tick() -> void:
	if guard_held and guard_t < 99:
		guard_t += 1
	if not guard_held:
		since_release += 1
	if guard_grace > 0:
		guard_grace -= 1
	if evade_window > 0:
		evade_window -= 1
	if inv > 0:
		inv -= 1
	if counter > 0:
		counter -= 1


func is_perfect_guard_now(facing_ok: bool) -> bool:
	if not facing_ok:
		return false
	return (guard_held and guard_t <= guard_window + leniency) or guard_grace > 0


## Resolves an incoming strike. `src`: { damage, facing_ok, floor_trap, unblockable }.
## Returns { result: perfect_evade|invuln|perfect_guard|guard|hit, damage, reward: bool }.
func resolve_incoming(src: Dictionary) -> Dictionary:
	var dmg := float(src.get("damage", 1.0))
	var facing_ok := bool(src.get("facing_ok", true))
	var floor_trap := bool(src.get("floor_trap", false))
	if evade_window > 0 and not floor_trap:
		if not evade_rewarded:
			evade_rewarded = true
			inv = maxi(inv, 10)
			return {"result": "perfect_evade", "damage": 0.0, "reward": true}
		return {"result": "invuln", "damage": 0.0, "reward": false}
	if inv > 0:
		return {"result": "invuln", "damage": 0.0, "reward": false}
	if not bool(src.get("unblockable", false)) and not floor_trap:
		if is_perfect_guard_now(facing_ok):
			guard_grace = 0
			inv = maxi(inv, 24)
			counter = 65
			return {"result": "perfect_guard", "damage": 0.0, "reward": true}
		if guard_held and facing_ok:
			inv = maxi(inv, 18)
			return {"result": "guard", "damage": maxf(1.0, round(dmg * chip_ratio)), "reward": false}
	return {"result": "hit", "damage": dmg, "reward": false}


func serialize() -> Dictionary:
	return {"guard_held": guard_held, "guard_t": guard_t, "guard_grace": guard_grace, "since_release": since_release,
		"evade_window": evade_window, "evade_rewarded": evade_rewarded, "inv": inv, "counter": counter}
