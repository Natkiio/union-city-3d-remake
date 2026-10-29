class_name Weapon
extends RefCounted
## One weapon from the original game's weapon table
## (data/original/weapon.json): all 57 entries, firearms and melee.
## Fields that only apply to one kind are left at their defaults for the
## other (firearm fields on a melee weapon, material/swing on a gun).
## Build one with Weapon.from_ref("glock") or Weapon.from_ref("katana").

const DATA_PATH := "res://data/original/weapon.json"

static var _table: Dictionary = {}

var ref: String = ""
var display_name: String = ""
## "firearm" or "melee", straight from the table.
var weapon_class: String = ""
var weight: float = 0.0
var rarity: int = 0
var premium: bool = false
var location: String = "anywhere"

## Original weaponType, e.g. "pistolAutomatic", "pumpAction", "smg", "twoHand", "fists".
var weapon_type: String = ""
## Original skill that governs the weapon: pistols, longGuns, automatics,
## specialWeapons for firearms; blunt or blades for melee.
var skill: String = ""

var damage: float = 0.0
var knockback: float = 0.0

# --- Melee only ---
## Hit material from the table: blade, blunt, flesh, wood, and so on.
var material: String = ""
## Swing sound/animation family from the table: blade or wood.
var swing: String = ""

# --- Firearm only ---
## Ammo pool this gun draws from, e.g. "9mm", "shotgun", "556".
var ammo_type: String = ""
## Rounds in a full magazine.
var mag_size: int = 0
## Lower is more accurate (spread scales with it in the original).
var accuracy: float = 0.0
var piercing: int = 0
## True when the table defines `piercing` at all. The original only checks that
## the field exists, so even a value of 0 (grenades) ignores armor.
var has_piercing: bool = false
var recoil: float = 0.0
## Noise is what alerts zombies. Compared against constants noiseRange*.
var weapon_noise: float = 0.0
## Frames to reload a magazine.
var reload_time: int = 0
var round_speed: float = 0.0
## Projectiles per trigger pull (shotgun pellets are 3).
var rounds_per_shot: int = 1
## Rounds fired per trigger pull in burst mode, 0 when not a burst gun.
var burst_size: int = 0
## "auto" or "single".
var fire_mode: String = "single"
var splash_damage: float = 0.0
var splash_size: float = 0.0


## Returns the Weapon for an original ref, or null if the ref is unknown.
static func from_ref(weapon_ref: String) -> Weapon:
	var table := _load_table()
	if not table.has(weapon_ref):
		return null
	return _from_dict(table[weapon_ref])

## The Weapon whose display name matches, e.g. "G17 Pistol". Inventory keys
## weapons by this name, so this is how an inventory entry maps back to data.
static func find_by_name(display: String) -> Weapon:
	var table := _load_table()
	for key in table:
		if table[key].get("name", "") == display:
			return _from_dict(table[key])
	return null

## Inventory name for this weapon's ammo, following the original's
## naming ("9mm Ammo", ".45 Ammo", "5.56 Ammo"). Ammo types the original
## names differently fall back to "<type> Ammo" (verify).
static func ammo_name_for(type: String) -> String:
	match type:
		"9mm":
			return "9mm Ammo"
		"45":
			return ".45 Ammo"
		"556":
			return "5.56 Ammo"
		_:
			return "%s Ammo" % type

func ammo_item_name() -> String:
	return Weapon.ammo_name_for(ammo_type)

## The original runs on 30 fps frames, and reloadTime is in those frames.
const ORIGINAL_FPS: float = 30.0

## Seconds to reload: the whole magazine, or one shell for pump actions.
func reload_seconds() -> float:
	return reload_time / ORIGINAL_FPS

## Pump actions load one shell at a time and can be interrupted by firing.
## Everything else reloads the whole magazine in one go.
func reloads_per_round() -> bool:
	return weapon_type == "pumpAction"

## Seconds between shots per weaponType. The original's cadence lives in its
## arm animations, not in weapon.json, so these are our own placeholders
## (verify against the running original).
const FIRE_INTERVALS := {
	"pistolAutomatic": 0.3,
	"revolver": 0.5,
	"smg": 0.1,
	"bullpup": 0.1,
	"assaultRifle": 0.12,
	"lmg": 0.1,
	"chainsaw": 0.1,
	"assaultRifleSlow": 0.4,
	"pumpAction": 0.6,
	"boltAction": 1.0,
	"bigRifle": 1.0,
	"bow": 1.0,
	"handGrenade": 1.0,
	"grenadeLauncher": 1.0,
	"RPG": 1.0,
}
const DEFAULT_FIRE_INTERVAL: float = 0.5
## Seconds between melee swings (placeholders, verify).
const MELEE_INTERVALS := {"fists": 0.5, "oneHand": 0.4, "twoHand": 0.6}
## Types that keep firing while the trigger is held, besides fireMode "auto"
## (venom). The doc only flags venom; the rest are placeholders (verify).
const HOLD_TO_FIRE_TYPES: Array[String] = ["smg", "bullpup", "lmg", "chainsaw"]
## Bullet world speed per unit of the table's roundSpeed (70 -> 30 u/s).
const ROUND_SPEED_SCALE: float = 30.0 / 70.0


func fire_interval() -> float:
	return FIRE_INTERVALS.get(weapon_type, DEFAULT_FIRE_INTERVAL)


func melee_interval() -> float:
	return MELEE_INTERVALS.get(weapon_type, 0.5)


## True when holding the trigger keeps firing.
func is_auto() -> bool:
	return fire_mode == "auto" or weapon_type in HOLD_TO_FIRE_TYPES


## The chainsaw never misses (original special case).
func never_misses() -> bool:
	return ref == "chainsaw"


func bullet_speed() -> float:
	return round_speed * ROUND_SPEED_SCALE if round_speed > 0.0 else 30.0

## Refs in table order. Pass "firearm" or "melee" to filter, or "" for all 57.
static func all_refs(weapon_class_filter: String = "") -> Array[String]:
	var refs: Array[String] = []
	var table := _load_table()
	for key in table:
		if weapon_class_filter == "" or table[key].get("weaponClass", "") == weapon_class_filter:
			refs.append(key)
	return refs

func is_firearm() -> bool:
	return weapon_class == "firearm"

## True for grenades, rockets and other weapons that do area damage.
func is_explosive() -> bool:
	return splash_damage > 0.0

static func _load_table() -> Dictionary:
	if not _table.is_empty():
		return _table
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null:
		push_error("Weapon: cannot open %s" % DATA_PATH)
		return _table
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		_table = parsed
	else:
		push_error("Weapon: %s is not a JSON object" % DATA_PATH)
	return _table

static func _from_dict(data: Dictionary) -> Weapon:
	var weapon := Weapon.new()
	weapon.ref = data.get("ref", "")
	weapon.display_name = data.get("name", weapon.ref)
	weapon.weapon_class = data.get("weaponClass", "")
	weapon.weight = float(data.get("weight", 0.0))
	weapon.rarity = int(data.get("rarity", 0))
	weapon.premium = bool(data.get("premium", false))
	weapon.location = data.get("location", "anywhere")
	weapon.weapon_type = data.get("weaponType", "")
	weapon.skill = data.get("skill", "")
	weapon.damage = float(data.get("damage", 0.0))
	weapon.knockback = float(data.get("knockback", 0.0))
	weapon.material = data.get("material", "")
	weapon.swing = data.get("swing", "")
	weapon.ammo_type = data.get("ammoType", "")
	weapon.mag_size = int(data.get("maxAmmo", 0))
	weapon.accuracy = float(data.get("accuracy", 0.0))
	weapon.piercing = int(data.get("piercing", 0))
	weapon.has_piercing = data.has("piercing")
	weapon.recoil = float(data.get("recoil", 0.0))
	weapon.weapon_noise = float(data.get("weaponNoise", 0.0))
	weapon.reload_time = int(data.get("reloadTime", 0))
	weapon.round_speed = float(data.get("roundSpeed", 0.0))
	weapon.rounds_per_shot = int(data.get("roundsPerShot", 1))
	weapon.burst_size = int(data.get("roundsPerBurst", 0))
	weapon.fire_mode = "auto" if data.get("fireMode", "") == "auto" else "single"
	weapon.splash_damage = float(data.get("splashDamage", 0.0))
	weapon.splash_size = float(data.get("splashSize", 0.0))
	return weapon
