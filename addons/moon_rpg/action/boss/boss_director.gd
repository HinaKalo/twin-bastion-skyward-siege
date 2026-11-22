class_name BossDirector
extends RefCounted
## Multi-phase boss choreography on one data graph: phases, attack sequences, telegraphs,
## mechanisms (valves / switches), damage windows (weak points / openings) and surrender.
##
## - `start_at_phase(id)` jumps to any phase entry for practice (HP set to that phase's entry).
## - Mechanism groups open a damage window; each group declares a solo mode (delayed interlock:
##   all parts by one player within `within` ticks) and a duo mode (parallel: parts by different
##   seats within a sync window). Both are first-class completions.
## - Every damage window is logged: which mechanism / seat opened it, when, how long it stayed
##   open, and why it closed (timeout | phase_change | boss_recovered | surrender | reset).
## - `safe_intervals()` checks that the active telegraphed shapes still leave walkable ground.
##
## Telegraph events carry pose, area, sound and haptic keys together so feedback stays linked.

signal phase_changed(from_id: String, to_id: String)
signal telegraph(attack: Dictionary)
signal window_opened(window_id: String, source: String)
signal window_closed(window_id: String, reason: String)
signal surrendered()

var def: Dictionary = {}
var max_hp: float = 1000.0
var hp: float = 1000.0
var phase_index: int = 0
var tick: int = 0
var state: String = "idle" # idle | fighting | surrendered | defeated
var players: int = 1
var closed_damage_scale: float = 0.2

var _attack_cursor: int = 0
var _attack_timer: int = 0
var _current_attack: Dictionary = {}
var _attack_stage: String = "" # telegraph | active | recovery
var _windows: Dictionary = {} # window_id -> { opened_tick, ticks_left, source, damage_scale }
var _mech_progress: Dictionary = {} # group_id -> { part_id: { tick, seat } }
var window_log: Array[Dictionary] = []
var damage_log: Array[Dictionary] = []


static func load_json(path: String) -> BossDirector:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("[BossDirector] invalid boss json: %s" % path)
		return null
	var b := BossDirector.new()
	b.setup(parsed)
	return b


func setup(d: Dictionary) -> void:
	def = d.duplicate(true)
	max_hp = float(def.get("hp", 1000.0))
	hp = max_hp
	closed_damage_scale = float(def.get("closed_damage_scale", 0.2))


func phases() -> Array:
	return def.get("phases", [])


func phase() -> Dictionary:
	var p := phases()
	return p[phase_index] if phase_index < p.size() else {}


func phase_id() -> String:
	return str(phase().get("id", ""))


func start(player_count: int = 1) -> void:
	players = clampi(player_count, 1, 2)
	state = "fighting"
	tick = 0
	_enter_phase(0, "start")


## Practice entry: begins directly at `id` with HP at that phase's entry threshold.
func start_at_phase(id: String, player_count: int = 1) -> bool:
	for i in range(phases().size()):
		if str(phases()[i].get("id", "")) == id:
			players = clampi(player_count, 1, 2)
			state = "fighting"
			hp = max_hp * float((phases()[i] as Dictionary).get("entry_hp", 1.0))
			_enter_phase(i, "practice")
			return true
	return false


func _enter_phase(i: int, reason: String) -> void:
	var from := phase_id()
	for wid in _windows.keys():
		_close_window(str(wid), "phase_change")
	phase_index = i
	_attack_cursor = 0
	_attack_timer = int(phase().get("opening_delay", 30))
	_current_attack = {}
	_attack_stage = ""
	_mech_progress.clear()
	if from != phase_id() or reason == "practice":
		phase_changed.emit(from, phase_id())


func step() -> void:
	if state != "fighting":
		return
	tick += 1
	for wid in _windows.keys():
		var w: Dictionary = _windows[wid]
		w["ticks_left"] = int(w["ticks_left"]) - 1
		if int(w["ticks_left"]) <= 0:
			_close_window(str(wid), "timeout")
	_step_attacks()


func _step_attacks() -> void:
	var attacks: Array = phase().get("attacks", [])
	if attacks.is_empty():
		return
	_attack_timer -= 1
	if _attack_timer > 0:
		return
	match _attack_stage:
		"", "recovery":
			_current_attack = (attacks[_attack_cursor % attacks.size()] as Dictionary).duplicate(true)
			_attack_cursor += 1
			_attack_stage = "telegraph"
			_attack_timer = int(_current_attack.get("telegraph", 30))
			var tele := _current_attack.duplicate(true)
			tele["phase"] = phase_id()
			tele["tick"] = tick
			telegraph.emit(tele)
		"telegraph":
			_attack_stage = "active"
			_attack_timer = int(_current_attack.get("active", 10))
		"active":
			_attack_stage = "recovery"
			_attack_timer = int(_current_attack.get("recovery", 30))
			if _current_attack.has("opening"):
				var op: Dictionary = _current_attack["opening"]
				open_window(str(op.get("window", "recovery_opening")), "attack:%s" % _current_attack.get("id", ""), int(op.get("ticks", _attack_timer)))


func current_attack() -> Dictionary:
	return {"attack": _current_attack, "stage": _attack_stage, "ticks_left": _attack_timer}


func open_window(window_id: String, source: String, ticks: int = -1) -> void:
	var wdefs: Dictionary = phase().get("windows", {})
	var wd: Dictionary = wdefs.get(window_id, {})
	var t := ticks if ticks > 0 else int(wd.get("ticks", 180))
	if _windows.has(window_id):
		_windows[window_id]["ticks_left"] = maxi(int(_windows[window_id]["ticks_left"]), t)
		return
	_windows[window_id] = {"opened_tick": tick, "ticks_left": t, "source": source, "damage_scale": float(wd.get("damage_scale", 1.0))}
	window_opened.emit(window_id, source)


func _close_window(window_id: String, reason: String) -> void:
	if not _windows.has(window_id):
		return
	var w: Dictionary = _windows[window_id]
	window_log.append({
		"window": window_id, "phase": phase_id(), "opened_by": w["source"], "opened_tick": w["opened_tick"],
		"closed_tick": tick, "duration": tick - int(w["opened_tick"]), "close_reason": reason,
	})
	_windows.erase(window_id)
	window_closed.emit(window_id, reason)


func is_window_open(window_id: String = "") -> bool:
	return not _windows.is_empty() if window_id.is_empty() else _windows.has(window_id)


func damage_window_log() -> Array[Dictionary]:
	return window_log.duplicate(true)


## Mechanism part triggered by `seat`. Returns the window id opened, or "".
func trigger_mechanism(group_id: String, part_id: String, seat: int = 1) -> String:
	var groups: Dictionary = phase().get("mechanisms", {})
	if not groups.has(group_id):
		return ""
	var g: Dictionary = groups[group_id]
	var parts: Array = g.get("parts", [])
	if not parts.has(part_id):
		return ""
	if not _mech_progress.has(group_id):
		_mech_progress[group_id] = {}
	var prog: Dictionary = _mech_progress[group_id]
	prog[part_id] = {"tick": tick, "seat": seat}
	var mode_def: Dictionary = g.get("duo", {}) if players >= 2 else g.get("solo", {})
	var within := int(mode_def.get("within", 300))
	# Drop parts that went stale (interlock delay or sync window exceeded).
	for pid in prog.keys():
		if tick - int(prog[pid]["tick"]) > within:
			prog.erase(pid)
	for pid in parts:
		if not prog.has(pid):
			return ""
	if str(mode_def.get("mode", "interlock")) == "parallel":
		var seats := {}
		for pid in prog.keys():
			seats[int(prog[pid]["seat"])] = true
		if seats.size() < int(mode_def.get("seats", 2)):
			return ""
	var wid := str(g.get("opens", "weak_point"))
	var src := "mechanism:%s(%s)" % [group_id, str(mode_def.get("mode", "interlock"))]
	open_window(wid, src, int(g.get("window_ticks", -1)))
	_mech_progress.erase(group_id)
	return wid


## Applies damage; outside any open window the boss takes `closed_damage_scale` (armour).
## Returns the effective damage and logs where the opportunity came from.
func apply_damage(amount: float, source: String = "", seat: int = 1) -> float:
	if state != "fighting":
		return 0.0
	var scale := closed_damage_scale
	var via := "armour"
	for wid in _windows.keys():
		var s := float(_windows[wid]["damage_scale"])
		if s >= scale:
			scale = s
			via = str(wid)
	var eff := amount * scale
	hp = maxf(0.0, hp - eff)
	damage_log.append({"tick": tick, "phase": phase_id(), "amount": amount, "effective": eff, "via": via, "source": source, "seat": seat})
	_check_transitions()
	return eff


func _check_transitions() -> void:
	var ratio := hp / maxf(1.0, max_hp)
	var sur: Dictionary = def.get("surrender", {})
	if not sur.is_empty() and ratio <= float(sur.get("hp_below", 0.0)):
		for wid in _windows.keys():
			_close_window(str(wid), "surrender")
		state = "surrendered"
		surrendered.emit()
		return
	if hp <= 0.0:
		for wid in _windows.keys():
			_close_window(str(wid), "defeated")
		state = "defeated"
		return
	var next := phase_index + 1
	if next < phases().size() and ratio <= float((phases()[next] as Dictionary).get("entry_hp", 0.0)):
		_enter_phase(next, "hp")


## Safe ground check: given an arena span and the active attack area rects (x ranges), returns
## uncovered intervals at least `min_width` wide. Empty result = no safe zone (design error).
func safe_intervals(arena_from: float, arena_to: float, min_width: float = 24.0, extra_areas: Array = []) -> Array:
	var covered: Array = []
	var areas: Array = extra_areas.duplicate()
	if _attack_stage == "active" or _attack_stage == "telegraph":
		for a in _current_attack.get("areas", []):
			areas.append(a)
	for a in areas:
		covered.append([float(a[0]), float(a[0]) + float(a[2])])
	covered.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	var out: Array = []
	var cursor := arena_from
	for c in covered:
		if float(c[0]) - cursor >= min_width:
			out.append([cursor, float(c[0])])
		cursor = maxf(cursor, float(c[1]))
	if arena_to - cursor >= min_width:
		out.append([cursor, arena_to])
	return out


## Opportunity report for balance comparisons (e.g. low-upgrade vs high-upgrade routes).
func opportunity_report() -> Dictionary:
	var total_open := 0
	for w in window_log:
		total_open += int(w["duration"])
	var dealt_in_window := 0.0
	var dealt_armour := 0.0
	for d in damage_log:
		if str(d["via"]) == "armour":
			dealt_armour += float(d["effective"])
		else:
			dealt_in_window += float(d["effective"])
	return {"windows": window_log.size(), "open_ticks": total_open, "damage_in_windows": dealt_in_window, "damage_vs_armour": dealt_armour, "ticks": tick, "state": state}
