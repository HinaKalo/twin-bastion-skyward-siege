class_name SurvivalClock
extends RefCounted
## Day/Night Cycle, Season & Weather Clock for Survival / Simulation Games.
## Pure-data, deterministic, and headless-testable.
## Computes ambient temperature, visual day/night lighting tint, rain crop watering,
## and night-threat windows.

enum TimePhase { DAWN, DAY, DUSK, NIGHT }
enum Season { SPRING, SUMMER, AUTUMN, WINTER }
enum Weather { SUNNY, RAIN, STORM, BLIZZARD }

signal day_changed(new_day: int)
signal phase_changed(old_phase: int, new_phase: int)
signal weather_changed(new_weather: int)

var day: int = 1
var hour: float = 7.0 # 0.0 .. 24.0
var seconds_per_game_hour: float = 2.5 # 60 real sec = 1 full 24h day by default
var season: int = Season.SPRING
var weather: int = Weather.SUNNY
var current_phase: int = TimePhase.DAY
var days_per_season: int = 7

var _rng := RandomNumberGenerator.new()


func _init(seed_val: int = 0) -> void:
	if seed_val != 0:
		_rng.seed = seed_val
	else:
		_rng.randomize()
	current_phase = _compute_phase(hour)


func tick(delta: float) -> void:
	if delta <= 0.0 or seconds_per_game_hour <= 0.001:
		return
	hour += delta / seconds_per_game_hour
	while hour >= 24.0:
		hour -= 24.0
		day += 1
		if (day - 1) % days_per_season == 0 and day > 1:
			season = (season + 1) % 4
		_roll_daily_weather()
		day_changed.emit(day)

	var next_p := _compute_phase(hour)
	if next_p != current_phase:
		var old := current_phase
		current_phase = next_p
		phase_changed.emit(old, next_p)


func _compute_phase(h: float) -> int:
	if h >= 5.0 and h < 7.5:
		return TimePhase.DAWN
	elif h >= 7.5 and h < 17.5:
		return TimePhase.DAY
	elif h >= 17.5 and h < 20.0:
		return TimePhase.DUSK
	return TimePhase.NIGHT


func _roll_daily_weather() -> void:
	var r := _rng.randf()
	var next_w := Weather.SUNNY
	if season == Season.WINTER:
		next_w = Weather.BLIZZARD if r < 0.35 else Weather.SUNNY
	else:
		next_w = Weather.STORM if r < 0.12 else (Weather.RAIN if r < 0.38 else Weather.SUNNY)
	if next_w != weather:
		weather = next_w
		weather_changed.emit(weather)


func is_night() -> bool:
	return current_phase == TimePhase.NIGHT


func is_raining() -> bool:
	return weather == Weather.RAIN or weather == Weather.STORM


func get_ambient_temp() -> float:
	var base_temp := 18.0
	match season:
		Season.SUMMER: base_temp = 26.0
		Season.AUTUMN: base_temp = 13.0
		Season.WINTER: base_temp = -2.0
	# Night chill (-11 C) / Dusk chill (-5 C)
	var time_mod := 0.0
	match current_phase:
		TimePhase.DAWN: time_mod = -4.0
		TimePhase.DUSK: time_mod = -5.0
		TimePhase.NIGHT: time_mod = -12.0
	var weather_mod := -4.0 if weather == Weather.RAIN else (-8.0 if weather == Weather.STORM else (-10.0 if weather == Weather.BLIZZARD else 0.0))
	return base_temp + time_mod + weather_mod


func get_crop_growth_mult() -> float:
	if season == Season.WINTER:
		return 0.25
	var m := 1.4 if is_raining() else 1.0
	if is_night():
		m *= 0.65
	return m


func get_ambient_tint() -> Color:
	match current_phase:
		TimePhase.DAWN:
			return Color(0.92, 0.84, 0.86, 0.18)
		TimePhase.DAY:
			return Color(0.45, 0.56, 0.72, 0.12) if is_raining() else Color(0.0, 0.0, 0.0, 0.0)
		TimePhase.DUSK:
			return Color(0.85, 0.45, 0.20, 0.26)
		_:
			return Color(0.04, 0.07, 0.20, 0.54)


func get_phase_label() -> String:
	match current_phase:
		TimePhase.DAWN: return "黎明"
		TimePhase.DAY: return "白天"
		TimePhase.DUSK: return "黄昏"
		_: return "黑夜"


func get_weather_label() -> String:
	match weather:
		Weather.RAIN: return "小雨"
		Weather.STORM: return "暴雨"
		Weather.BLIZZARD: return "暴雪"
		_: return "晴朗"


func serialize() -> Dictionary:
	return {
		"day": day,
		"hour": hour,
		"seconds_per_game_hour": seconds_per_game_hour,
		"season": season,
		"weather": weather,
		"current_phase": current_phase,
	}


func deserialize(data: Dictionary) -> void:
	day = int(data.get("day", 1))
	hour = float(data.get("hour", 7.0))
	seconds_per_game_hour = float(data.get("seconds_per_game_hour", 2.5))
	season = int(data.get("season", Season.SPRING))
	weather = int(data.get("weather", Weather.SUNNY))
	current_phase = int(data.get("current_phase", _compute_phase(hour)))
