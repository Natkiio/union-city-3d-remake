class_name ZombieType
extends RefCounted
## One zombie kind from the original's enemy table (data/original/enemy.json).
## Stats are stored relative to the basic zombie (zombieSlow = 1.0), so the
## remake's tuned baseline lives in zombie.gd and a type only scales it.
## Build one with ZombieType.from_ref("zombieFat").

const DATA_PATH := "res://data/original/enemy.json"
const BASELINE_REF := "zombieSlow"

## How a kind moves while chasing. "steady" is constant speed, "limp" is a
## predictable lurch. Add e.g. "erratic" here and in Zombie._movement_mult.
## The original has no such field (its kinds differ by speed and animation),
## so this is the remake's own; kinds not listed are "steady".
const MOVEMENT := {"zombieSlow": "limp"}

## Original pixels per remake world unit. Every px distance from the original
## (sight, sense, attack, grab range) goes through this one constant.
const PX_PER_UNIT: float = 100.0
## The remake's basic-zombie chase speed in units/s, matching original chaseSpeed 1.5.
const BASE_CHASE_SPEED: float = 2.2
## Fast kinds (sprinters 10-12, dog 15) would be 15-24 u/s; cap them just above
## the player's speed (6) so they are scary but dodgeable.
const MAX_CHASE_SPEED: float = 7.0
const ZOMBIE_BASE_HEALTH: float = 9.0
const ZOMBIE_BASE_DAMAGE: float = 7.0

static var _table: Dictionary = {}

var ref: String = ""
var movement: String = "steady"
## Multipliers on the baseline zombie's speed, health and bite damage.
var speed_scale: float = 1.0
var health_scale: float = 1.0
var damage_scale: float = 1.0
var xp_bonus: float = 1.0
var threat: float = 0.0
## Danger level at which this kind is meant to show up (the director unlocks
## it 4 levels earlier, see docs/ORIGINAL_ANALYSIS.md section 5).
var level: int = 1
var walk_anim: String = "walk"
var chase_speed: float = 1.5
var start_state: String = "wander"
## Lying-down start pose: "deadBack" (riser), "deadFront" (crawler) or "".
var start_pos: String = ""
var attack_range_px: float = 0.0 # 0 = random(30) + 45 per attack
var no_grab: bool = false
var armor: Dictionary = {} # zone -> damage multiplier (only zones in the data)
var has_level: bool = true
var health_bonus: float = 1.0
var damage_bonus: float = 1.0

static func from_ref(zombie_ref: String) -> ZombieType:
	var table := _load_table()
	if not table.has(zombie_ref) or not table.has(BASELINE_REF):
		return null
	var base: Dictionary = table[BASELINE_REF]
	var d: Dictionary = table[zombie_ref]
	var t := ZombieType.new()
	t.ref = zombie_ref
	t.movement = MOVEMENT.get(zombie_ref, "steady")
	t.speed_scale = float(d.get("chaseSpeed", 1.0)) / float(base["chaseSpeed"])
	t.health_scale = float(d.get("healthBonus", 1.0)) / float(base["healthBonus"])
	t.damage_scale = float(d.get("damageBonus", 1.0)) / float(base["damageBonus"])
	t.xp_bonus = float(d.get("xpBonus", 1.0))
	t.threat = float(d.get("threat", 0.0))
	t.level = int(d.get("level", 1))
	t.walk_anim = d.get("walkAnim", "walk")
	t.chase_speed = float(d.get("chaseSpeed", 1.5))
	t.start_state = d.get("startState", "wander")
	var sp: String = d.get("startPos", "")
	t.start_pos = sp if sp.begins_with("dead") else ""
	t.attack_range_px = float(d.get("attackRange", 0.0))
	t.no_grab = bool(d.get("noGrab", false))
	t.has_level = d.has("level")
	t.health_bonus = float(d.get("healthBonus", 1.0))
	t.damage_bonus = float(d.get("damageBonus", 1.0))
	for zone in ["head", "chest", "belly", "legs"]:
		var key := "armor" + zone.capitalize()
		if d.has(key):
			t.armor[zone] = float(d[key])
	return t

static func _load_table() -> Dictionary:
	if not _table.is_empty():
		return _table
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null:
		push_error("ZombieType: cannot open %s" % DATA_PATH)
		return _table
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		_table = parsed
	else:
		push_error("ZombieType: %s is not a JSON object" % DATA_PATH)
	return _table


## Chase speed in units/s: baseline 2.2 at original speed 1.5, capped.
func chase_speed_units() -> float:
	return minf(BASE_CHASE_SPEED * chase_speed / 1.5, MAX_CHASE_SPEED)


## round((9 + danger) * healthBonus)
func health_for(danger: int) -> int:
	return roundi((ZOMBIE_BASE_HEALTH + danger) * health_bonus)


## round(7 * ceil(danger / 10)) * damageBonus. Danger 0 is treated as 1.
func damage_for(danger: int) -> float:
	return roundf(ZOMBIE_BASE_DAMAGE * ceilf(maxf(danger, 1) / 10.0)) * damage_bonus


## round((round(danger * 5) + 5) * xpBonus)
func xp_for(danger: int) -> int:
	return roundi((roundi(danger * 5.0) + 5) * xp_bonus)


## Every enemy that may spawn at `danger`: level < danger + 4. Kinds with no
## level in the table (zombieSurvivor, story only) never match, like AS2's
## undefined < n.
static func pool_for(danger: int) -> Array[String]:
	var out: Array[String] = []
	var table := _load_table()
	for ref in table:
		if table[ref].has("level") and int(table[ref]["level"]) < danger + 4:
			out.append(ref)
	return out


static func all_refs() -> Array[String]:
	var out: Array[String] = []
	for ref in _load_table():
		out.append(ref)
	return out
