class_name Look
extends RefCounted
## Look dictionaries for the cutout rig. Keys follow npc.json:
## sex skinColour hair hairColour facialHair clothesTop clothesBottom clothesShoe
## faceAccessory torsoAccessory headAccessory backpack weapon.
## Look.normalize() resolves "random", $expr nodes and missing keys, so the rig
## only ever sees plain strings. Colours are a dark, muted comic palette.

const SKIN := {
	"White": Color(0.78, 0.62, 0.52), "Tanned": Color(0.68, 0.50, 0.37),
	"Olive": Color(0.62, 0.52, 0.36), "Black": Color(0.34, 0.22, 0.17),
	"Pale": Color(0.84, 0.74, 0.66),
}
const HAIR := {
	"Black": Color(0.07, 0.06, 0.07), "Blonde": Color(0.74, 0.62, 0.34),
	"Dark Blonde": Color(0.52, 0.42, 0.22), "Brown": Color(0.32, 0.20, 0.12),
	"Dark Brown": Color(0.18, 0.11, 0.08), "Light Brown": Color(0.46, 0.31, 0.18),
	"Grey": Color(0.55, 0.55, 0.57), "Red": Color(0.55, 0.2, 0.1),
}
const HAIR_STYLES := ["none", "bald", "shaved", "cropped", "short1", "short2", "short3", "medium1",
	"medium2", "long1", "ponytail1", "afro", "mohawk", "special1", "special2", "special3"]
const FACIAL := ["none", "shadow", "fullBeard", "1980s", "soulPatch", "lincoln", "goatee"]
const FACE_ACC := ["none", "glasses", "glassesBig", "sunglassesBig", "goggles", "gasMask", "medicalMask", "bandana", "HERCmask"]
const HEAD_ACC := ["none", "capBlue", "armyKevlar", "rebel", "bioHazardHat", "helmetHERC", "crown", "beanie"]
const TORSO_ACC := ["none", "kevlarVest", "kevlarVestArmy", "kevlarVestHERC"]
const TOPS := ["male_tshirtBlue", "male_tshirtRed", "male_tshirtWhite", "male_tshirtBrown", "male_longSleeveBlack",
	"male_longSleeveWhite", "male_longSleeveRed", "male_hoodyBlack", "male_shirtBlue", "male_checkersBlue",
	"male_suitGrey", "male_workApron", "female_longSleeveGreen", "female_tshirtBlue", "female_tshirtRed",
	"female_tshirtWhite", "female_shirtBlue", "female_scrubs"]
const BOTTOMS := ["male_jeansBlue", "male_jeansBlack", "male_pantsBrown", "male_pantsGrey", "female_jeansBlack",
	"female_jeansBlue", "female_pantsBrown", "female_pantsBlack", "male_camoCargo"]
const SHOES := ["shoeBlack", "shoeBrown", "shoeWhite", "shoeArmy"]
const BASE_KEYS := ["sex", "skinColour", "hair", "hairColour", "facialHair", "clothesTop", "clothesBottom",
	"clothesShoe", "faceAccessory", "torsoAccessory", "headAccessory", "backpack", "weapon"]

const NAMED_TOPS := {
	"armyTop": [Color(0.27, 0.31, 0.19), "long", ["pockets"]],
	"bioHazardTop": [Color(0.72, 0.62, 0.18), "long", ["hazard"]],
	"workApron": [Color(0.5, 0.5, 0.46), "short", ["apron"]],
	"scrubs": [Color(0.22, 0.46, 0.47), "short", []],
	"hospital": [Color(0.62, 0.7, 0.72), "short", ["gown"]],
	"hoodyBlack": [Color(0.12, 0.12, 0.14), "long", ["hood"]],
	"unionSecTop": [Color(0.11, 0.16, 0.28), "long", ["badge"]],
	"HERCtop": [Color(0.16, 0.16, 0.18), "long", ["stripe"]],
	"TLStop": [Color(0.34, 0.12, 0.12), "long", ["stripe"]],
	"checkersBlue": [Color(0.2, 0.28, 0.44), "long", ["plaid"]],
	"suitGrey": [Color(0.36, 0.37, 0.4), "long", ["tie"]],
	"none": [Color(0, 0, 0), "none", ["skin"]],
}
const NAMED_BOTTOMS := {
	"armyBottom": [Color(0.25, 0.29, 0.18), "full"], "camoCargo": [Color(0.3, 0.32, 0.2), "full"],
	"bioHazardPants": [Color(0.7, 0.6, 0.17), "full"], "policeBottom": [Color(0.1, 0.13, 0.22), "full"],
	"HERCbottom": [Color(0.14, 0.14, 0.16), "full"], "TLSBottom": [Color(0.3, 0.11, 0.11), "full"],
	"scrubs": [Color(0.22, 0.46, 0.47), "full"], "jeansBlue": [Color(0.2, 0.28, 0.42), "full"],
	"jeansBlack": [Color(0.12, 0.12, 0.15), "full"], "pantsBrown": [Color(0.33, 0.25, 0.17), "full"],
	"pantsGrey": [Color(0.36, 0.37, 0.4), "full"], "pantsBlack": [Color(0.1, 0.1, 0.12), "full"],
	"none": [Color(0, 0, 0), "none"],
}
const COLOUR_WORDS := {
	"Blue": Color(0.2, 0.3, 0.46), "Red": Color(0.5, 0.17, 0.15), "White": Color(0.76, 0.74, 0.68),
	"Black": Color(0.12, 0.12, 0.14), "Green": Color(0.24, 0.38, 0.26), "Brown": Color(0.38, 0.27, 0.18),
	"Grey": Color(0.4, 0.4, 0.43), "Yellow": Color(0.72, 0.62, 0.2),
}
const SHOE_COL := {"shoeBlack": Color(0.1, 0.1, 0.11), "shoeBrown": Color(0.3, 0.2, 0.12),
	"shoeWhite": Color(0.75, 0.74, 0.7), "shoeArmy": Color(0.17, 0.15, 0.1)}

static var _weapons: Dictionary = {}


static func skin_color(name: String) -> Color:
	return SKIN.get(name, SKIN["White"])


static func hair_color(name: String) -> Color:
	return HAIR.get(name, HAIR["Brown"])


static func _strip(ref: String) -> String:
	for pre in ["male_", "female_"]:
		if ref.begins_with(pre):
			return ref.substr(pre.length())
	return ref


static func _word_colour(ref: String, fallback: Color) -> Color:
	for w in COLOUR_WORDS:
		if ref.contains(w):
			return COLOUR_WORDS[w]
	return fallback


## Returns {c: Color, sleeve: "long"|"short"|"none", over: Array[String]}.
static func top_style(ref: String) -> Dictionary:
	var key := _strip(ref)
	if NAMED_TOPS.has(key):
		var n: Array = NAMED_TOPS[key]
		return {"c": n[0], "sleeve": n[1], "over": n[2]}
	var sleeve := "long" if (key.contains("ong") or key.contains("hoody") or key.contains("shirt") and not key.contains("tshirt")) else "short"
	return {"c": _word_colour(key, Color(0.3, 0.3, 0.33)), "sleeve": sleeve, "over": []}


## Returns {c: Color, kind: "full"|"none"}.
static func bottom_style(ref: String) -> Dictionary:
	var key := _strip(ref)
	if NAMED_BOTTOMS.has(key):
		var n: Array = NAMED_BOTTOMS[key]
		return {"c": n[0], "kind": n[1]}
	if key.contains("army"):
		return {"c": Color(0.25, 0.29, 0.18), "kind": "full"}
	return {"c": _word_colour(key, Color(0.26, 0.26, 0.3)), "kind": "full"}


static func shoe_color(ref: String) -> Color:
	return SHOE_COL.get(ref, Color(0.12, 0.12, 0.13))


static func _weapon_table() -> Dictionary:
	if _weapons.is_empty():
		var f := FileAccess.open("res://data/original/weapon.json", FileAccess.READ)
		if f != null:
			var parsed = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				_weapons = parsed
		if _weapons.is_empty():
			_weapons = {"_": {}}
	return _weapons


## "none" | "pistol" | "long" | "melee" | "shield" for a weapon ref.
static func weapon_class(ref: String) -> String:
	if ref == "" or ref == "none" or ref == "hands" or ref == "fists":
		return "none"
	if ref == "shield":
		return "shield"
	var w: Dictionary = _weapon_table().get(ref, {})
	if w.is_empty():
		return "none"
	if w.get("weaponClass", "") == "firearm":
		var wt: String = str(w.get("weaponType", ""))
		if wt in ["pistolAutomatic", "revolver", "oneHand", "handGrenade"] or w.get("skill", "") == "pistols":
			return "pistol"
		return "long"
	if w.get("weaponType", "") == "fists":
		return "none"
	return "melee"


## Resolves every field to a plain string/bool. `seed` drives "random" values;
## -1 derives it from the content so the same record always looks the same.
static func normalize(d: Dictionary, seed: int = -1) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(d)) if seed < 0 else seed
	var out := {}
	var sex: String = str(d.get("sex", "")).to_lower()
	if sex != "male" and sex != "female":
		sex = "male" if rng.randf() < 0.65 else "female"
	out["sex"] = sex
	out["skinColour"] = _res(d.get("skinColour", "White"), SKIN.keys(), rng)
	out["hairColour"] = _res(d.get("hairColour", "Brown"), HAIR.keys(), rng)
	out["hair"] = _res(d.get("hair", "short1"), HAIR_STYLES, rng)
	out["facialHair"] = _res(d.get("facialHair", "none"), FACIAL, rng)
	if sex == "female":
		out["facialHair"] = "none"
	out["clothesTop"] = _res(d.get("clothesTop", "male_tshirtBlue"), TOPS, rng)
	out["clothesBottom"] = _res(d.get("clothesBottom", "male_jeansBlue"), BOTTOMS, rng)
	out["clothesShoe"] = _res(d.get("clothesShoe", "shoeBlack"), SHOES, rng)
	out["faceAccessory"] = _res(d.get("faceAccessory", "none"), FACE_ACC, rng)
	out["torsoAccessory"] = _res(d.get("torsoAccessory", "none"), TORSO_ACC, rng)
	out["headAccessory"] = _res(d.get("headAccessory", "none"), HEAD_ACC, rng)
	var bp = d.get("backpack", false)
	out["backpack"] = bp == true or str(bp) == "true" or (str(bp) == "random" and rng.randf() < 0.3)
	out["weapon"] = str(d.get("weapon", "none"))
	return out


static func _res(v, options: Array, rng: RandomNumberGenerator) -> String:
	if v is Dictionary:
		return str(options[0]) if options.size() > 0 and options[0] != "none" else "White"
	var s := str(v)
	if s == "random" or s == "":
		return str(options[rng.randi() % options.size()])
	return s


## Crowd generator: a believable random civilian from a seed.
static func random(seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var female := rng.randf() < 0.4
	var d := {
		"sex": "female" if female else "male",
		"skinColour": SKIN.keys()[rng.randi() % 4],
		"hair": HAIR_STYLES[rng.randi() % HAIR_STYLES.size()],
		"hairColour": HAIR.keys()[rng.randi() % HAIR.size()],
		"facialHair": "none" if female or rng.randf() < 0.6 else FACIAL[1 + rng.randi() % (FACIAL.size() - 1)],
		"clothesTop": _pick(TOPS, rng, female),
		"clothesBottom": _pick(BOTTOMS, rng, female),
		"clothesShoe": SHOES[rng.randi() % SHOES.size()],
		"faceAccessory": "none", "torsoAccessory": "none", "headAccessory": "none",
		"backpack": rng.randf() < 0.3, "weapon": "none",
	}
	if rng.randf() < 0.18:
		d["faceAccessory"] = ["glasses", "glassesBig", "sunglassesBig"][rng.randi() % 3]
	if rng.randf() < 0.14:
		d["headAccessory"] = ["capBlue", "beanie", "rebel"][rng.randi() % 3]
	return normalize(d, seed)


static func _pick(list: Array, rng: RandomNumberGenerator, female: bool) -> String:
	var tries := 0
	while true:
		var s: String = list[rng.randi() % list.size()]
		tries += 1
		if tries > 20 or s.begins_with("female_") == female or not s.begins_with("female_") and not female:
			return s
	return list[0]


static func from_npc(rec: Dictionary, seed: int = -1) -> Dictionary:
	var d := {}
	for k in BASE_KEYS:
		if rec.has(k):
			d[k] = rec[k]
	return normalize(d, seed)
