class_name DirectorRules
extends RefCounted
## Pure formulas of the zombie director (docs/ORIGINAL_ANALYSIS.md sec. 5).
## No state, no nodes: the Director autoload feeds these.

const THREAT_MULTIPLIER: int = 25
const THREAT_ADDITION: int = 30
const MAX_ZOMBIES_ABS: int = 5
const SMALL_ROOM_WIDTH_PX: float = 600.0
const RUSH_LENGTH_BASE: int = 2
const RUSH_LENGTH_MAX: int = 15
const BASE_RUSH_TIME: int = 3
const LEVEL_CAP: int = 30
const BREAK_THRESHOLD: int = 3
const BREAK_LENGTH_BASE: float = 0.75
const REPOP_TIME: float = 90.0 # game minutes; halved outdoors
const DROPPER_INTERVAL: int = 20
const DROPPER_LOW_HEALTH_BONUS: int = 5
const MAX_DROPPERS: int = 2


## Threat budget for an area. health_pct is 0-100, meds the number of
## medical items carried. Safehouse or danger 0 gives 0.
static func threat_max(danger: int, health_pct: int, meds: int, safehouse: bool) -> int:
	if safehouse or danger <= 0:
		return 0
	var t := roundi(THREAT_MULTIPLIER * danger + THREAT_ADDITION)
	for limit in [90, 70, 50, 30, 10]:
		if health_pct < limit:
			t -= 5
	t -= 2 * meds
	return maxi(t, 0)


## min(5, round(danger / 2 + 1)); ceil(/3) in rooms <= 600 px wide; 0 in a
## safehouse, at danger 0 or during a break.
static func max_zombies(danger: int, width_px: float, safehouse: bool, on_break: bool) -> int:
	if safehouse or danger <= 0 or on_break:
		return 0
	var m := mini(roundi(danger / 2.0 + 1.0), MAX_ZOMBIES_ABS)
	if width_px <= SMALL_ROOM_WIDTH_PX:
		m = ceili(m / 3.0)
	return m


static func rush_length(danger: int) -> int:
	return mini(RUSH_LENGTH_BASE * danger, RUSH_LENGTH_MAX)


## Game minutes that must pass between rushes.
static func rush_time_range(level: int, since_last_rush: float, healthy: bool, ammo_ok: bool, on_screen: int) -> int:
	var r := BASE_RUSH_TIME * (30 - level)
	if since_last_rush < 30.0:
		r += 10
	r += -10 if healthy else 10
	r += -10 if ammo_ok else 10
	return r + on_screen


## A break starts once more than this many zombies spawned since the last one.
static func break_threshold(level: int, rand_level: int) -> int:
	return roundi(level * BREAK_THRESHOLD + rand_level)


## Break length in game minutes; rand_value is random((30 - level) * 0.75).
static func break_length(rand_value: int) -> int:
	return roundi(rand_value + BREAK_LENGTH_BASE)


## Zombies spawned on entering a room that has been empty long enough.
static func room_entry_count(threat_max_value: int, outdoors: bool, rand_value: int, max_z: int) -> int:
	return mini(rand_value, max_z)


static func room_entry_roll_range(threat_max_value: int, outdoors: bool) -> int:
	return roundi(threat_max_value / (3.0 if outdoors else 10.0))


static func repop_time(outdoors: bool) -> float:
	return REPOP_TIME * (0.5 if outdoors else 1.0)


static func can_spawn(enemy_threat: float, current_threat: float, threat_max_value: float) -> bool:
	return enemy_threat + current_threat <= threat_max_value
