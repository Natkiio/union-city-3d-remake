extends Node
## Autoload "Clock". Game time, hour/day getters and the lighting preset for
## the current time. Spec: docs/ORIGINAL_ANALYSIS.md sections 4 and 9,
## details in docs/survival.md. Owner: survival workstream.
##
## Time is counted in game minutes. `game_minutes` starts at 1440 like the
## original's gameTime, and the clock face starts at 12:00.

## 50 frames per game minute at 30 fps.
const FRAMES_PER_GAME_MINUTE := 50.0
const ORIGINAL_FPS := 30.0
const SECONDS_PER_GAME_MINUTE := FRAMES_PER_GAME_MINUTE / ORIGINAL_FPS  # ~1.67 s
const START_GAME_MINUTES := 1440
const START_MINUTE_OF_DAY := 720  # 12:00
const MINUTES_PER_DAY := 1440

## Start minute-of-day of each lightTime preset (index 0 = lightTime1). The
## original's chain of if-tests leaves a few one-minute gaps (e.g. exactly
## 06:15); a gap keeps the earlier preset (verify).
const PRESET_STARTS := [
	0, 240, 300, 331, 360, 376, 390, 420, 450, 480, 511, 540, 571,
	780, 960, 991, 1020, 1036, 1051, 1066, 1080, 1096, 1111, 1126, 1140, 1156, 1171, 1200,
]

## Set false to freeze real-time ticking (cutscenes, tests). The tree being
## paused also stops time.
var running: bool = true
var game_minutes: int = START_GAME_MINUTES

var _accum: float = 0.0


func _ready() -> void:
	add_to_group("stateful")


func _process(delta: float) -> void:
	if not running or get_tree().paused:
		return
	_accum += delta
	while _accum >= SECONDS_PER_GAME_MINUTE:
		_accum -= SECONDS_PER_GAME_MINUTE
		advance(1)


## Moves time forward, emitting Events.minute_passed once per minute and
## Events.hour_changed whenever the hour rolls over. Used by ticking,
## sleeping and travel.
func advance(minutes: int) -> void:
	for i in maxi(minutes, 0):
		var old_hour := hour()
		game_minutes += 1
		Events.minute_passed.emit(game_minutes)
		if hour() != old_hour:
			Events.hour_changed.emit(hour())


## Minutes since midnight, 0..1439.
func minute_of_day() -> int:
	return posmod(game_minutes - START_GAME_MINUTES + START_MINUTE_OF_DAY, MINUTES_PER_DAY)


## Hour on a 24 h clock, 0..23.
func hour() -> int:
	return minute_of_day() / 60


func minute() -> int:
	return minute_of_day() % 60


## Day counter, 1 on the first day.
func day() -> int:
	return (game_minutes - START_GAME_MINUTES + START_MINUTE_OF_DAY) / MINUTES_PER_DAY + 1


## "HH:MM" on a 24 h clock.
func time_text() -> String:
	return "%02d:%02d" % [hour(), minute()]


## Jumps to a clock time (same day if still ahead, otherwise the next day).
## Emits the usual signals through advance().
func set_time(hour_24: int, minute_60: int = 0) -> void:
	var target := hour_24 * 60 + minute_60
	var delta := posmod(target - minute_of_day(), MINUTES_PER_DAY)
	advance(delta)


## Preset number 1..28 for a minute of the day.
func preset_id_for(minute_of_day_value: int) -> int:
	var id := 1
	for i in PRESET_STARTS.size():
		if minute_of_day_value >= PRESET_STARTS[i]:
			id = i + 1
	return id


func preset_id() -> int:
	return preset_id_for(minute_of_day())


## The lightTime record for now: {id, name, ra, ga, ba, aa, sightMod, ...}.
## ra/ga/ba are the world's colour multipliers in percent (100 = unchanged,
## the original feeds them to a colour transform). `light_reduction` is the
## percent an indoor room dims the light by.
func lighting_preset(light_reduction: float = 0.0) -> Dictionary:
	return lighting_preset_for(preset_id(), light_reduction)


func lighting_preset_for(id: int, light_reduction: float = 0.0) -> Dictionary:
	var rec: Dictionary = Data.table("world/lightTime%d" % id)
	var out: Dictionary = rec.duplicate()
	out["id"] = id
	for ch in ["ra", "ga", "ba"]:
		var v: float = float(out.get(ch, 100))
		out[ch] = v - roundf(v / 100.0 * light_reduction)
	return out


## Light colour for the sun/ambient: the preset's channels scaled so the
## brightest is 1, keeping only the hue/tint. Brightness is energy().
func light_color(light_reduction: float = 0.0) -> Color:
	return _color_of(lighting_preset(light_reduction))


## 0.1..1 brightness for the current time.
func energy(light_reduction: float = 0.0) -> float:
	return _energy_of(lighting_preset(light_reduction))


func _color_of(p: Dictionary) -> Color:
	var m := maxf(maxf(p.get("ra", 100.0), p.get("ga", 100.0)), maxf(p.get("ba", 100.0), 1.0))
	return Color(p.get("ra", 100.0) / m, p.get("ga", 100.0) / m, p.get("ba", 100.0) / m)


func _energy_of(p: Dictionary) -> float:
	var m := maxf(maxf(p.get("ra", 100.0), p.get("ga", 100.0)), p.get("ba", 100.0))
	return clampf(m / 100.0, 0.1, 1.0)


func reset() -> void:
	game_minutes = START_GAME_MINUTES
	_accum = 0.0


func to_dict() -> Dictionary:
	return {"game_minutes": game_minutes}


func from_dict(d: Dictionary) -> void:
	game_minutes = int(d.get("game_minutes", START_GAME_MINUTES))
	_accum = 0.0
