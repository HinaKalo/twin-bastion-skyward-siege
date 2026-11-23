extends SceneTree
## Headless balance harness for Twin Bastion TD.
## Plays every campaign stage on every difficulty with two AI seats and prints a result table.
## Assertions (exit code 1 on failure):
##   - the AI pair wins every Casual run and at least 75% of Normal runs (AI play styles are seeded)
##   - doing nothing (no towers, idle heroes) loses every stage on Normal
## Usage: godot --headless --path . --script res://tests/balance_sim.gd [-- stage=<id> diff=<casual|normal|hard> seeds=<n>]

const DT := 0.05
const MAX_SIM_SEC := 1500.0

var _failures: Array[String] = []
var _ai_hero: bool = true
var _ai_ult: bool = true


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var only_stage := str(args.get("stage", ""))
	var only_diff := str(args.get("diff", ""))
	var seeds := int(args.get("seeds", "4"))
	if args.has("hp"):
		CoopTDDirector.tuning_hp_scale = float(args["hp"])
	if args.has("share"):
		CoopTDDirector.tuning_bounty_share = float(args["share"])
	if args.has("ramp"):
		CoopTDDirector.tuning_wave_ramp = float(args["ramp"])
	_ai_hero = str(args.get("hero", "1")) == "1"
	_ai_ult = str(args.get("ult", "1")) == "1"
	var assert_mode := not (args.has("hp") or args.has("share") or args.has("ramp") or args.has("hero") or args.has("ult"))

	print("=== Twin Bastion TD Balance Sim (dt=%.2f, seeds=%d) ===" % [DT, seeds])
	print("%-22s %-7s %-6s %-9s %-6s %-6s %-11s %-6s" % ["stage", "diff", "mode", "result", "lives", "leaks", "kills P1/P2", "time"])
	for stage in CampaignData.get_stages():
		var sid := str(stage["id"])
		if only_stage != "" and sid != only_stage:
			continue
		for diff in ["casual", "normal", "hard"]:
			if only_diff != "" and diff != only_diff:
				continue
			var wins := 0
			for s in range(seeds):
				var r := simulate(stage, diff, "duo", 1000 + s * 77)
				_print_row(sid, diff, "duo", r)
				if bool(r["won"]):
					wins += 1
			var need := seeds if diff == "casual" else (int(ceil(seeds * 0.75)) if diff == "normal" else 0)
			if wins < need:
				_failures.append("%s/%s: AI duo won only %d/%d (need %d)" % [sid, diff, wins, seeds, need])
			if diff == "hard" and wins == seeds:
				print("  note: %s hard won by every AI style" % sid)
		if only_diff == "" or only_diff == "normal":
			var idle := simulate(stage, "normal", "idle", 4242)
			_print_row(sid, "normal", "idle", idle)
			if bool(idle["won"]):
				_failures.append("%s: winnable with zero towers" % sid)
			var solo := simulate(stage, "normal", "p2only", 4243)
			_print_row(sid, "normal", "p2only", solo)
			if bool(solo["won"]) and int(stage["index"]) >= 2:
				_failures.append("%s: a single AI seat wins alone (co-op not required)" % sid)
		if args.has("endless"):
			var er := simulate(stage, "normal", "duo", 1000, true)
			print("%-22s endless duo reached wave %d" % [sid, int(er["wave"])])

	if not assert_mode:
		print("(tuning run: assertions skipped)")
		quit(0)
		return
	if _failures.is_empty():
		print("=== Balance OK ===")
		quit(0)
	else:
		for f in _failures:
			printerr("[BALANCE FAIL] " + f)
		quit(1)


func simulate(stage: Dictionary, diff: String, mode: String, rng_seed: int, endless: bool = false) -> Dictionary:
	seed(rng_seed)
	var meta := MetaProgress.new()
	meta.save_path = "user://_balance_sim_meta.json"
	var d := CoopTDDirector.new()
	d.setup_stage(stage, meta, diff, endless)
	var ai1 := CoopAIPartner.new(1)
	var ai2 := CoopAIPartner.new(2)
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	for ai in [ai1, ai2]:
		ai.control_hero = _ai_hero
		ai.allow_ult_initiate = _ai_ult
		if rng_seed != 1000:
			ai.randomize_style(rng)
	var t := 0.0
	var first_called := false
	while t < MAX_SIM_SEC:
		if mode == "duo":
			ai1.tick(DT, d)
		if mode == "duo" or mode == "p2only":
			ai2.tick(DT, d)
		if not first_called and t >= 10.0:
			first_called = true
			d.call_next_wave()
		d.tick(DT)
		t += DT
		if d.is_victory() or d.is_defeat():
			break
	return {
		"won": d.is_victory(), "lives": d.engine.lives, "max_lives": d.max_lives, "leaks": d.leaks,
		"k1": int(d.stats[1]["kills"]), "k2": int(d.stats[2]["kills"]), "time": t,
		"wave": d.wave_dir.current_wave_index + 1, "waves": d.wave_dir.get_total_waves(),
		"stars": MetaProgress.compute_stars(d.engine.lives, d.max_lives, diff, d.leaks) if d.is_victory() else 0,
		"gold": [int(d.gold[1]), int(d.gold[2])],
	}


func _print_row(sid: String, diff: String, mode: String, r: Dictionary) -> void:
	var res := ("WIN %d★" % int(r["stars"])) if bool(r["won"]) else ("LOSE w%d/%d" % [int(r["wave"]), int(r["waves"])])
	print("%-22s %-7s %-6s %-9s %2d/%-3d %-6d %4d/%-6d %5.0fs" % [sid, diff, mode, res, int(r["lives"]), int(r["max_lives"]), int(r["leaks"]), int(r["k1"]), int(r["k2"]), float(r["time"])])
