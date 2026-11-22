class_name DiceRoller
extends RefCounted
## Tabletop Dice & D20 Skill-Check Engine (D&D / BG3 / Monopoly / For The King style).
## Supports deterministic seeded RNG, `NdS+M` notation parsing, Advantage/Disadvantage,
## and full skill check results (natural 20 / natural 1 critical detection).

enum AdvantageMode { NORMAL, ADVANTAGE, DISADVANTAGE }

var _rng := RandomNumberGenerator.new()


func _init(seed_val: int = 0) -> void:
	if seed_val != 0:
		_rng.seed = seed_val
	else:
		_rng.randomize()


func set_seed(seed_val: int) -> void:
	_rng.seed = seed_val


func roll(count: int = 1, sides: int = 6, modifier: int = 0) -> Dictionary:
	var rolls: Array[int] = []
	var sum := 0
	for _i in range(maxi(1, count)):
		var v := _rng.randi_range(1, maxi(2, sides))
		rolls.append(v)
		sum += v
	return {
		"rolls": rolls,
		"sides": sides,
		"modifier": modifier,
		"total": sum + modifier,
	}


## Parses standard tabletop notation like "2d6+3", "1d20-1", "d8".
func parse_and_roll(expr: String) -> Dictionary:
	var s := expr.strip_edges().to_lower().replace(" ", "")
	var d_idx := s.find("d")
	if d_idx < 0:
		return roll(1, 6, int(s))
	var count := int(s.substr(0, d_idx)) if d_idx > 0 else 1
	var rest := s.substr(d_idx + 1)
	var mod := 0
	var sides := 6
	var plus_idx := rest.find("+")
	var minus_idx := rest.find("-")
	if plus_idx >= 0:
		sides = int(rest.substr(0, plus_idx))
		mod = int(rest.substr(plus_idx + 1))
	elif minus_idx >= 0:
		sides = int(rest.substr(0, minus_idx))
		mod = -int(rest.substr(minus_idx + 1))
	else:
		sides = int(rest)
	return roll(maxi(1, count), maxi(2, sides), mod)


## D20 Skill Check with optional Advantage (keep higher) or Disadvantage (keep lower).
func skill_check(dc: int, modifier: int = 0, mode: int = AdvantageMode.NORMAL) -> Dictionary:
	var r1 := _rng.randi_range(1, 20)
	var rolls: Array[int] = [r1]
	var chosen := r1
	if mode != AdvantageMode.NORMAL:
		var r2 := _rng.randi_range(1, 20)
		rolls.append(r2)
		chosen = maxi(r1, r2) if mode == AdvantageMode.ADVANTAGE else mini(r1, r2)
	var total := chosen + modifier
	var nat20 := chosen == 20
	var nat1 := chosen == 1
	var passed := nat20 or (not nat1 and total >= dc)
	return {
		"rolls": rolls,
		"chosen": chosen,
		"modifier": modifier,
		"total": total,
		"dc": dc,
		"nat_20": nat20,
		"nat_1": nat1,
		"passed": passed,
	}
