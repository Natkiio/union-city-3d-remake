extends Node
## Autoload "Director". Zombie threat budget, spawn requests, rushes, breaks,
## droppers for the current area. Spec: docs/ORIGINAL_ANALYSIS.md section 5,
## notes in docs/zombies.md. Formulas live in DirectorRules (pure, tested).
##
## Usage: Director.begin_area(danger, width_px, outdoors, safehouse) when the
## player enters a room or street, Director.attach(spawn_root, player) so it
## knows where to put zombies. It then ticks by itself.
## Stateful systems join group "stateful" and implement reset(), to_dict(),
## from_dict(d); see docs/PORT_PLAN.md.

## Real seconds per director tick (the original ticks on its "slow" frame; verify).
const TICK_SECONDS: float = 1.0
## Ambient spawns happen when the tick counter exceeds this (randZomTrigger = 3).
const AMBIENT_EVERY: int = 3
## Half the visible width in units; spawns land outside it.
const VIEW_HALF_WIDTH: float = 9.0
const SPAWN_MIN_PX: int = 50
const SPAWN_VAR_PX: int = 100
## Real seconds per game minute when Clock has no game_minutes (timeScale 50 frames @30fps).
const FALLBACK_SECONDS_PER_MINUTE: float = 50.0 / 30.0

var danger: int = 0
var width_px: float = 3000.0
var outdoors: bool = true
var safehouse: bool = false
var area_id: String = ""
var threat_max: int = 0
var max_zombies: int = 0

var rush_active: bool = false
var rush_start: float = 0.0
var rush_length: int = 0
var last_rush_time: float = 1440.0
var on_break: bool = false
var break_start: float = 0.0
var break_length: int = 0
var spawned_since_break: int = 0
var droppers: int = 0
var last_drop_time: float = 1440.0
var ending_rush: bool = false

var spawn_root: Node3D = null
var player: Node3D = null
var bounds_min: float = -INF
var bounds_max: float = INF
var zombies: Array[Zombie] = []
var rng := RandomNumberGenerator.new()
## Game minute when the player last left each area id (for room-entry spawns).
var area_visits: Dictionary = {}
var enabled: bool = true

var _fallback_minutes: float = 1440.0
var _tick_accum: float = 0.0
var _ambient_counter: int = 0


func _ready() -> void:
	add_to_group("stateful")
	rng.randomize()


func _process(delta: float) -> void:
	if not enabled or spawn_root == null or not is_instance_valid(spawn_root):
		return
	if not _has_clock_minutes():
		_fallback_minutes += delta / FALLBACK_SECONDS_PER_MINUTE
	_tick_accum += delta
	if _tick_accum >= TICK_SECONDS:
		_tick_accum -= TICK_SECONDS
		tick()


func reset() -> void:
	danger = 0
	threat_max = 0
	max_zombies = 0
	rush_active = false
	rush_length = 0
	on_break = false
	spawned_since_break = 0
	droppers = 0
	ending_rush = false
	rush_start = 0.0
	break_start = 0.0
	break_length = 0
	area_visits.clear()
	area_id = ""
	zombies.clear()
	_fallback_minutes = 1440.0
	last_rush_time = 1440.0
	last_drop_time = 1440.0
	_ambient_counter = 0
	_tick_accum = 0.0


func to_dict() -> Dictionary:
	return {
		"last_rush_time": last_rush_time, "rush_active": rush_active, "rush_start": rush_start,
		"on_break": on_break, "break_start": break_start, "break_length": break_length,
		"spawned_since_break": spawned_since_break, "droppers": droppers,
		"last_drop_time": last_drop_time, "area_visits": area_visits.duplicate(),
		"fallback_minutes": _fallback_minutes,
	}


func from_dict(d: Dictionary) -> void:
	last_rush_time = d.get("last_rush_time", 1440.0)
	rush_active = d.get("rush_active", false)
	rush_start = d.get("rush_start", 0.0)
	on_break = d.get("on_break", false)
	break_start = d.get("break_start", 0.0)
	break_length = d.get("break_length", 0)
	spawned_since_break = d.get("spawned_since_break", 0)
	droppers = d.get("droppers", 0)
	last_drop_time = d.get("last_drop_time", 1440.0)
	area_visits = d.get("area_visits", {}).duplicate()
	_fallback_minutes = d.get("fallback_minutes", 1440.0)


# --- time and player adapters ----------------------------------------------

func _has_clock_minutes() -> bool:
	return "game_minutes" in Clock


## Game minutes: Clock.game_minutes when the survival workstream provides it,
## else an internal counter advanced in _process.
func now() -> float:
	if _has_clock_minutes():
		return float(Clock.game_minutes)
	return _fallback_minutes


## Skips game time: through Clock when it provides game_minutes, else the
## fallback counter. Used by tests and by sleep/travel callers.
func advance_minutes(minutes: float) -> void:
	if _has_clock_minutes():
		Clock.advance(int(ceil(minutes)))
	else:
		_fallback_minutes += minutes


func _health_pct() -> int:
	if player == null or not is_instance_valid(player) or player.get("health") == null:
		return 100
	var hp: float = player.get("health")
	var mx = player.get("max_health")
	var max_hp: float = mx if mx != null else 100.0
	return roundi(clampf(hp / max_hp, 0.0, 1.0) * 100.0)


func _count_meds() -> int:
	var meds: Dictionary = Data.table("meds")
	var names := {}
	for ref in meds:
		names[meds[ref].get("name", ref)] = true
	var n := 0
	for item_name in Inventory.items:
		if names.has(item_name):
			n += 1
	return n


# --- area -------------------------------------------------------------------

func attach(root: Node3D, player_node: Node3D) -> void:
	spawn_root = root
	player = player_node
	zombies.clear()
	_refresh_limits()


func set_bounds(min_x: float, max_x: float) -> void:
	bounds_min = min_x
	bounds_max = max_x


## Enter an area: recompute the budget and, if the player has been away long
## enough and nothing is around, spawn the room-entry zombies. Returns how many.
func begin_area(new_danger: int, width: float, is_outdoors: bool, is_safehouse: bool, id: String = "") -> int:
	if area_id != "":
		area_visits[area_id] = now()
	danger = new_danger
	width_px = width
	outdoors = is_outdoors
	safehouse = is_safehouse
	area_id = id
	_refresh_limits()
	if id == "" or max_zombies <= 0 or _live_count() > 0:
		return 0
	var last = area_visits.get(id)
	if last != null and now() - float(last) <= DirectorRules.repop_time(outdoors):
		return 0
	area_visits[id] = now()
	var range_n := DirectorRules.room_entry_roll_range(threat_max, outdoors)
	var count := DirectorRules.room_entry_count(threat_max, outdoors, rng.randi() % maxi(range_n, 1), max_zombies)
	var spawned := 0
	for i in count:
		if _try_spawn_random(true) != null:
			spawned += 1
	return spawned


func _refresh_limits() -> void:
	threat_max = DirectorRules.threat_max(danger, _health_pct(), _count_meds(), safehouse)
	max_zombies = DirectorRules.max_zombies(danger, width_px, safehouse, on_break)
	rush_length = 999999 if ending_rush else DirectorRules.rush_length(danger)


# --- accounting -------------------------------------------------------------

func _prune() -> void:
	var alive: Array[Zombie] = []
	for z in zombies:
		if is_instance_valid(z) and not z.is_dead() and not z.is_queued_for_deletion():
			alive.append(z)
	zombies = alive


func _live_count() -> int:
	_prune()
	return zombies.size()


func current_threat() -> float:
	_prune()
	var t := 0.0
	for z in zombies:
		t += z.type.threat
	return t


# --- the director tick ------------------------------------------------------

## One director step: breaks, rushes, ambient spawns. Public so tests can drive it.
func tick() -> void:
	_refresh_limits()
	var minute := now()
	var level: int = Stats.level
	if not rush_active and not on_break \
			and spawned_since_break > DirectorRules.break_threshold(level, rng.randi() % maxi(level, 1)):
		spawned_since_break = 0
		on_break = true
		break_start = minute
		var span := maxi(roundi((DirectorRules.LEVEL_CAP - level) * DirectorRules.BREAK_LENGTH_BASE), 1)
		break_length = DirectorRules.break_length(rng.randi() % span)
	if on_break and minute - break_start > break_length:
		on_break = false
	_refresh_limits()

	if not safehouse:
		var range_min := DirectorRules.rush_time_range(level, minute - last_rush_time,
				_health_pct() >= 50, true, _live_count())
		if not rush_active and absf(last_rush_time - minute) > range_min \
				and _live_count() < max_zombies and not on_break:
			last_rush_time = minute
			rush_start = minute
			rush_active = true
			Events.rush_started.emit()
		if rush_active and minute < rush_start + rush_length:
			_try_spawn_random(false) # rush: drop in as long as the budget allows
		if rush_active and minute > rush_start + rush_length:
			last_rush_time = minute
			rush_active = false
			Events.rush_ended.emit()

	if not rush_active and outdoors:
		_ambient_counter += 1
		if _ambient_counter > AMBIENT_EVERY:
			_ambient_counter = 0
			if _live_count() < max_zombies:
				_try_spawn_random(false)
	_update_droppers(minute)


func _update_droppers(minute: float) -> void:
	var bonus := DirectorRules.DROPPER_LOW_HEALTH_BONUS if _health_pct() <= 20 else 0
	var wait := DirectorRules.DROPPER_INTERVAL - bonus + rng.randi() % maxi(DirectorRules.DROPPER_INTERVAL / 3, 1)
	if minute - last_drop_time > wait:
		last_drop_time = minute
		droppers = mini(droppers + 1, DirectorRules.MAX_DROPPERS)


# --- spawning ---------------------------------------------------------------

## Spawns one random pool zombie if the budget allows. `inside` places it
## nearer the player (room entry). Returns it or null.
func _try_spawn_random(inside: bool) -> Zombie:
	if spawn_root == null or player == null or safehouse or danger <= 0:
		return null
	if _live_count() >= max_zombies:
		return null
	var pool := ZombieType.pool_for(danger)
	if pool.is_empty():
		return null
	return spawn_zombie(pool[rng.randi() % pool.size()], inside)


## Budget-checked spawn of a specific kind. Null if over budget or no valid side.
func spawn_zombie(ref: String, inside: bool = false) -> Zombie:
	var t := ZombieType.from_ref(ref)
	if t == null or spawn_root == null or player == null or safehouse:
		return null
	if _live_count() >= max_zombies or not DirectorRules.can_spawn(t.threat, current_threat(), threat_max):
		return null
	var x := _pick_spawn_x(inside)
	if is_nan(x):
		return null
	var z := Zombie.spawn(spawn_root, ref, danger, x)
	z.rng.seed = rng.randi()
	if droppers > 0 and ref != "zombieDog":
		droppers -= 1
		z.carries_loot = true
	zombies.append(z)
	spawned_since_break += 1
	return z


## x for a new zombie: off-screen on a side that is inside the area bounds,
## 50-150 px beyond the view edge. NAN when neither side fits.
func _pick_spawn_x(inside: bool) -> float:
	var px: float = player.global_position.x
	var extra := float(SPAWN_MIN_PX + rng.randi() % SPAWN_VAR_PX) / ZombieType.PX_PER_UNIT
	var half := VIEW_HALF_WIDTH
	if inside:
		half = minf(VIEW_HALF_WIDTH, width_px / ZombieType.PX_PER_UNIT / 2.0) * 0.8
	var right := px + half + extra
	var left := px - half - extra
	var ok_r := right < bounds_max
	var ok_l := left > bounds_min
	if ok_r and ok_l:
		return right if rng.randi() % 2 == 0 else left
	if ok_r:
		return right
	if ok_l:
		return left
	return NAN
