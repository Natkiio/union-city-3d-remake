extends Node
## Autoload "Survival". Hunger and sleep meters, their attribute penalties,
## eating, sleeping and waiting. Spec: docs/ORIGINAL_ANALYSIS.md section 4,
## details in docs/survival.md. Owner: survival workstream.
##
## Both meters run 0 (fine) to 100 (worst). In "runngun" mode they are
## disabled entirely.

signal vitals_changed()

const HUNGER_RATE := 0.15       # per game minute (constants hungerRate)
const SLEEP_RATE := 0.15
const PENALTY_THRESHOLD := 70.0
const MODE_SURVIVOR := "survivor"
const MODE_RUNGUN := "runngun"

var mode: String = MODE_SURVIVOR
var hunger: float = 0.0
var sleep: float = 0.0

var _hunger_penalty: int = 0
var _sleep_penalty: int = 0
var _quiet: bool = false  # true while sleep()/wait() drive the clock themselves


func _ready() -> void:
	add_to_group("stateful")
	Events.minute_passed.connect(_on_minute_passed)


func is_survivor() -> bool:
	return mode == MODE_SURVIVOR


func _on_minute_passed(_game_minute: int) -> void:
	if _quiet or not is_survivor():
		return
	_change(HUNGER_RATE, SLEEP_RATE)


func _change(d_hunger: float, d_sleep: float) -> void:
	hunger = clampf(hunger + d_hunger, 0.0, 100.0)
	sleep = clampf(sleep + d_sleep, 0.0, 100.0)
	_update_penalties()
	vitals_changed.emit()


## round((v - 70) / 3) above 70, else 0.
static func penalty_for(value: float) -> int:
	if value <= PENALTY_THRESHOLD:
		return 0
	return roundi((value - PENALTY_THRESHOLD) / 3.0)


func hunger_penalty() -> int:
	return _hunger_penalty if is_survivor() else 0


func sleep_penalty() -> int:
	return _sleep_penalty if is_survivor() else 0


## 0..4, round(value / 25), for the hunger/sleep state labels.
func hunger_state() -> int:
	return roundi(hunger / 25.0)


func sleep_state() -> int:
	return roundi(sleep / 25.0)


func set_mode(new_mode: String) -> void:
	mode = new_mode if new_mode == MODE_RUNGUN else MODE_SURVIVOR
	_update_penalties()
	vitals_changed.emit()


## Eating in Survivor mode: lowers hunger by `amount` (floor 0).
func eat(amount: float) -> void:
	_change(-amount, 0.0)


## Sleep aids (No ZZZ): lowers sleep by round(amount * 10).
func reduce_sleep(amount: float) -> void:
	_change(0.0, -float(roundi(amount * 10.0)))


## Sleeping for `hours`: time passes, sleep drops by round(hours * 10) and
## hunger rises by round(hours * 60) * 0.1 (6 per hour, slower than awake).
func sleep_hours(hours: int) -> void:
	_quiet = true
	Clock.advance(hours * 60)
	_quiet = false
	if is_survivor():
		_change(roundf(hours * 60.0) * 0.1, -float(roundi(hours * 10.0)))


## Waiting `hours` just moves the clock; the meters do not change.
func wait_hours(hours: int) -> void:
	_quiet = true
	Clock.advance(hours * 60)
	_quiet = false


func _update_penalties() -> void:
	_hunger_penalty = penalty_for(hunger)
	_sleep_penalty = penalty_for(sleep)
	if Stats.has_method("set_penalty"):
		Stats.set_penalty("strength", hunger_penalty())
		Stats.set_penalty("endurance", hunger_penalty())
		Stats.set_penalty("precision", sleep_penalty())
		Stats.set_penalty("intellect", sleep_penalty())
		Events.stats_changed.emit()


func reset() -> void:
	hunger = 0.0
	sleep = 0.0
	_quiet = false
	_update_penalties()
	vitals_changed.emit()


func to_dict() -> Dictionary:
	return {"hunger": hunger, "sleep": sleep, "mode": mode}


func from_dict(d: Dictionary) -> void:
	hunger = float(d.get("hunger", 0.0))
	sleep = float(d.get("sleep", 0.0))
	mode = d.get("mode", MODE_SURVIVOR)
	_update_penalties()
	vitals_changed.emit()
