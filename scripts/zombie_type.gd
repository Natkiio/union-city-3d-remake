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
