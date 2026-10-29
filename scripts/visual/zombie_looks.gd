class_name ZombieLooks
extends RefCounted
## Enemy ref (enemy.json) -> look + rig tweaks. One call: ZombieLooks.apply(rig, "zombieFat").
## Silhouette comes from the tweaks (posture, width, armour, weapon); `seed` varies the
## clothes and hair of ordinary zombies so a crowd is not a clone army.

const BASE_TWEAKS := {"zombie": true, "tatter": true, "posture": "stand", "hunch": 0.3, "arms_out": true, "gait": 0.8, "limp": 0.5}

## ref -> {tweaks overrides, look overrides}
const TABLE := {
	"zombieSlow": {"t": {"hunch": 0.38, "gait": 0.7, "limp": 0.7}},
	"zombieFast": {"t": {"hunch": 0.3, "gait": 1.15, "limp": 0.3}},
	"zombieSprint": {"t": {"hunch": 0.5, "gait": 1.0, "limp": 0.0}},
	"zombieRiser": {"t": {"hunch": 0.34, "gait": 1.1, "limp": 0.35}},
	"zombieFat": {"t": {"hunch": 0.2, "gait": 0.7, "width": 1.9, "belly": 0.16, "limp": 0.2},
		"l": {"clothesTop": "male_tshirtWhite", "clothesBottom": "male_pantsGrey"}},
	"zombieFatSprint": {"t": {"hunch": 0.35, "gait": 1.0, "width": 1.9, "belly": 0.16, "limp": 0.0},
		"l": {"clothesTop": "male_tshirtRed", "clothesBottom": "male_pantsBrown"}},
	"zombieRiot": {"t": {"hunch": 0.12, "gait": 0.75, "armor": ["helmet_riot", "chest", "shins", "elbows", "gloves"], "width": 1.15},
		"l": {"clothesTop": "male_HERCtop", "clothesBottom": "male_HERCbottom", "clothesShoe": "shoeBlack", "hair": "none"}},
	"zombieRiotShield": {"t": {"hunch": 0.1, "gait": 0.7, "armor": ["helmet_riot", "chest", "shins", "elbows", "gloves"], "width": 1.15},
		"l": {"clothesTop": "male_HERCtop", "clothesBottom": "male_HERCbottom", "weapon": "shield", "hair": "none"}},
	"zombieRiotNoHelmet": {"t": {"hunch": 0.15, "gait": 0.75, "armor": ["chest", "shins", "elbows", "gloves"], "width": 1.15},
		"l": {"clothesTop": "male_HERCtop", "clothesBottom": "male_HERCbottom", "hair": "cropped"}},
	"zombieArmy": {"t": {"hunch": 0.2, "gait": 0.75, "armor": ["helmet_army", "chest"]},
		"l": {"clothesTop": "male_armyTop", "clothesBottom": "male_armyBottom", "clothesShoe": "shoeArmy", "hair": "none", "backpack": true}},
	"zombieArmySprint": {"t": {"hunch": 0.4, "gait": 1.0, "armor": ["helmet_army", "chest"], "limp": 0.0},
		"l": {"clothesTop": "male_armyTop", "clothesBottom": "male_armyBottom", "clothesShoe": "shoeArmy", "hair": "none"}},
	"zombieArmyNoHelmet": {"t": {"hunch": 0.22, "gait": 0.75, "armor": ["chest"]},
		"l": {"clothesTop": "male_armyTop", "clothesBottom": "male_armyBottom", "clothesShoe": "shoeArmy", "hair": "cropped", "backpack": true}},
	"zombiePolice": {"t": {"hunch": 0.26, "gait": 1.1, "armor": ["cap_police"]},
		"l": {"clothesTop": "male_unionSecTop", "clothesBottom": "male_policeBottom", "clothesShoe": "shoeBlack", "hair": "none"}},
	"zombieCrawl": {"t": {"posture": "crawl", "gait": 0.9, "hunch": 0.0, "arms_out": false, "limp": 0.0}},
	"zombieSurvivor": {"t": {"hunch": 0.22, "gait": 0.9, "limp": 0.3}, "l": {"backpack": true, "clothesTop": "male_hoodyBlack"}},
	"zombieHatchet": {"t": {"hunch": 0.3, "gait": 1.1, "arms_out": false}, "l": {"weapon": "hatchet", "clothesTop": "male_workApron"}},
	"zombieCleaver": {"t": {"hunch": 0.3, "gait": 1.1, "arms_out": false}, "l": {"weapon": "cleaver", "clothesTop": "male_workApron", "hair": "bald"}},
	"zombieHammer": {"t": {"hunch": 0.3, "gait": 1.1, "arms_out": false}, "l": {"weapon": "clawHammer", "clothesTop": "male_checkersBlue"}},
	"zombieHatchetSprint": {"t": {"hunch": 0.5, "gait": 1.0, "arms_out": false, "limp": 0.0}, "l": {"weapon": "hatchet", "clothesTop": "male_workApron"}},
	"zombieCleaverSprint": {"t": {"hunch": 0.5, "gait": 1.0, "arms_out": false, "limp": 0.0}, "l": {"weapon": "cleaver", "clothesTop": "male_workApron", "hair": "bald"}},
	"zombieHammerSprint": {"t": {"hunch": 0.5, "gait": 1.0, "arms_out": false, "limp": 0.0}, "l": {"weapon": "clawHammer", "clothesTop": "male_checkersBlue"}},
	"zombieDog": {"t": {"posture": "dog", "height": 1.3, "hunch": 0.0, "arms_out": false, "limp": 0.0, "gait": 1.0, "tatter": false},
		"l": {"skinColour": "Tanned"}},
}

static var _enemies: Dictionary = {}


static func refs() -> Array:
	return TABLE.keys()


static func _enemy(ref: String) -> Dictionary:
	if _enemies.is_empty():
		var f := FileAccess.open("res://data/original/enemy.json", FileAccess.READ)
		if f != null:
			var p = JSON.parse_string(f.get_as_text())
			if p is Dictionary:
				_enemies = p
	return _enemies.get(ref, {})


## The rig anim to use for "moving" for this enemy: "walk", "run" or "crawl" (from enemy.walkAnim).
static func move_anim(ref: String) -> String:
	var w := str(_enemy(ref).get("walkAnim", "walk"))
	if w == "run":
		return "run"
	if w == "crawl":
		return "crawl"
	return "walk"


static func look_for(ref: String, seed: int = 0) -> Dictionary:
	var l := Look.random(seed + hash(ref))
	var e: Dictionary = TABLE.get(ref, {})
	for k in e.get("l", {}):
		l[k] = e["l"][k]
	l["skinColour"] = l["skinColour"] if ref == "zombieDog" else "White"
	return Look.normalize(l, seed)


static func tweaks_for(ref: String) -> Dictionary:
	var t := BASE_TWEAKS.duplicate(true)
	var e: Dictionary = TABLE.get(ref, {})
	for k in e.get("t", {}):
		t[k] = e["t"][k]
	return t


## Unknown refs get the plain walker. Returns true if the ref was known.
static func apply(rig: CutoutRig, ref: String, seed: int = 0) -> bool:
	var known := TABLE.has(ref)
	rig.look = look_for(ref, seed)
	rig.tweaks = tweaks_for(ref)
	rig.apply_look(look_for(ref, seed))   # normalises + rebuilds
	rig.apply_tweaks(tweaks_for(ref))
	return known
