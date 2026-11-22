class_name SurvivalNeeds
extends RefCounted
## Pure-Data Survival Vitals Model (HP, Hunger, Warmth, Stamina).
## Decays hunger over time, cools/warms body temperature based on ambient temp &
## nearby heat sources (Campfire), applies starvation/freezing ticks, and exposes
## clean eat/rest/damage APIs.

signal vital_critical(vital_name: String, value: float)
signal perished(cause: String)

var hp: float = 100.0
var max_hp: float = 100.0
var hunger: float = 100.0
var warmth: float = 100.0
var stamina: float = 100.0
var is_dead: bool = false

var hunger_decay_per_sec: float = 1.1
var warmth_comfort_temp: float = 12.0


func reset() -> void:
	hp = max_hp
	hunger = 100.0
	warmth = 100.0
	stamina = 100.0
	is_dead = false


func tick(delta: float, ambient_temp: float, heat_bonus: float = 0.0, is_night: bool = false) -> void:
	if is_dead or delta <= 0.0:
		return

	# 1. Hunger decay
	hunger = maxf(0.0, hunger - hunger_decay_per_sec * delta)
	if hunger <= 20.0:
		vital_critical.emit("hunger", hunger)

	# 2. Warmth dynamics (effective temp vs comfort threshold)
	var eff_temp := ambient_temp + heat_bonus
	if eff_temp < warmth_comfort_temp:
		var chill := (warmth_comfort_temp - eff_temp) * (0.45 if is_night else 0.30)
		warmth = maxf(0.0, warmth - chill * delta)
	else:
		var warm_rate := 10.0 if heat_bonus > 0.0 else 3.5
		warmth = minf(100.0, warmth + warm_rate * delta)
	if warmth <= 20.0:
		vital_critical.emit("warmth", warmth)

	# 3. Stamina natural regen when fed & warm
	if hunger > 25.0 and warmth > 25.0:
		stamina = minf(100.0, stamina + 8.0 * delta)

	# 4. Starvation & Freezing HP damage
	if hunger <= 0.0:
		take_damage(3.2 * delta, "starvation")
	if warmth <= 0.0:
		take_damage(4.0 * delta, "freezing")


func spend_stamina(amount: float) -> bool:
	if stamina < amount:
		return false
	stamina = maxf(0.0, stamina - amount)
	return true


func eat(hunger_gain: float, hp_gain: float = 0.0, warmth_gain: float = 0.0) -> void:
	if is_dead:
		return
	hunger = minf(100.0, hunger + maxf(0.0, hunger_gain))
	hp = minf(max_hp, hp + maxf(0.0, hp_gain))
	warmth = minf(100.0, warmth + maxf(0.0, warmth_gain))


func take_damage(amount: float, cause: String = "combat") -> void:
	if is_dead or amount <= 0.0:
		return
	hp = maxf(0.0, hp - amount)
	if hp <= 0.0:
		is_dead = true
		perished.emit(cause)


func serialize() -> Dictionary:
	return {
		"hp": hp, "max_hp": max_hp, "hunger": hunger, "warmth": warmth, "stamina": stamina, "is_dead": is_dead,
	}


func deserialize(data: Dictionary) -> void:
	hp = float(data.get("hp", 100.0))
	max_hp = float(data.get("max_hp", 100.0))
	hunger = float(data.get("hunger", 100.0))
	warmth = float(data.get("warmth", 100.0))
	stamina = float(data.get("stamina", 100.0))
	is_dead = bool(data.get("is_dead", false))
