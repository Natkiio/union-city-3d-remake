class_name Gun
extends RefCounted
## One firearm, read from the original game's weapon table
## (data/original/weapon.json). Melee weapons are not wrapped here; they
## stay on the fist/hitbox path. Build one with Gun.from_ref("glock").

const DATA_PATH := "res://data/original/weapon.json"

static var _table: Dictionary = {}

var ref: String = ""
var display_name: String = ""
var weight: float = 0.0
var rarity: int = 0
var premium: bool = false
var location: String = "anywhere"

## Original weaponType, e.g. "pistolAutomatic", "pumpAction", "smg".
var weapon_type: String = ""
## Original skill that governs accuracy and crits: pistols, longGuns, automatics, specialWeapons.
var skill: String = ""

## Ammo pool this gun draws from, e.g. "9mm", "shotgun", "556".
var ammo_type: String = ""
## Rounds in a full magazine.
var mag_size: int = 0

var damage: float = 0.0
## Lower is more accurate (spread scales with it in the original).
var accuracy: float = 0.0
var knockback: float = 0.0
var piercing: int = 0
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


## Returns a Gun for the given original ref, or null if the ref is unknown
## or belongs to a melee weapon.
static func from_ref(weapon_ref: String) -> Gun:
	var table := _load_table()
	if not table.has(weapon_ref):
		return null
	var data: Dictionary = table[weapon_ref]
	if data.get("weaponClass", "") != "firearm":
		return null
	return _from_dict(data)

## Every firearm ref in the original table, in table order.
static func all_refs() -> Array[String]:
	var refs: Array[String] = []
	var table := _load_table()
	for key in table:
		if table[key].get("weaponClass", "") == "firearm":
			refs.append(key)
	return refs

## True for grenades, rockets and other weapons that do area damage.
func is_explosive() -> bool:
	return splash_damage > 0.0

static func _load_table() -> Dictionary:
	if not _table.is_empty():
		return _table
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null:
		push_error("Gun: cannot open %s" % DATA_PATH)
		return _table
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		_table = parsed
	else:
		push_error("Gun: %s is not a JSON object" % DATA_PATH)
	return _table

static func _from_dict(data: Dictionary) -> Gun:
	var gun := Gun.new()
	gun.ref = data.get("ref", "")
	gun.display_name = data.get("name", gun.ref)
	gun.weight = float(data.get("weight", 0.0))
	gun.rarity = int(data.get("rarity", 0))
	gun.premium = bool(data.get("premium", false))
	gun.location = data.get("location", "anywhere")
	gun.weapon_type = data.get("weaponType", "")
	gun.skill = data.get("skill", "")
	gun.ammo_type = data.get("ammoType", "")
	gun.mag_size = int(data.get("maxAmmo", 0))
	gun.damage = float(data.get("damage", 0.0))
	gun.accuracy = float(data.get("accuracy", 0.0))
	gun.knockback = float(data.get("knockback", 0.0))
	gun.piercing = int(data.get("piercing", 0))
	gun.recoil = float(data.get("recoil", 0.0))
	gun.weapon_noise = float(data.get("weaponNoise", 0.0))
	gun.reload_time = int(data.get("reloadTime", 0))
	gun.round_speed = float(data.get("roundSpeed", 0.0))
	gun.rounds_per_shot = int(data.get("roundsPerShot", 1))
	gun.burst_size = int(data.get("roundsPerBurst", 0))
	gun.fire_mode = "auto" if data.get("fireMode", "") == "auto" else "single"
	gun.splash_damage = float(data.get("splashDamage", 0.0))
	gun.splash_size = float(data.get("splashSize", 0.0))
	return gun
