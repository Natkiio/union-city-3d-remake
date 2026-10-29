class_name LootRules
extends RefCounted
## Container loot generation (ORIGINAL_ANALYSIS section 6) as pure static
## functions. Randomness comes from a caller-supplied RandomNumberGenerator so
## tests can seed it. `rnd(rng, n)` mirrors the original's random(n): an int in
## 0..n-1 (0 when n <= 0).
##
## Entries are plain dictionaries: {ref, name, weight (per unit), count, kind}
## plus `lucky: true` for lucky-roll finds. Weapon mods (`<ref>_<mod>`) are not
## implemented: a modded ref resolves to its base item and keeps `mod`.

const MODS := ["stock", "scope", "specOps", "suppressed", "extendedMag", "military",
	"lightened", "heavy", "sharpened", "dull", "damaged"]
## Kinds that can appear on the lucky (rarity) lists. Junk, ammo and cash never do.
const RARITY_KINDS := ["weapon", "clothing", "food", "meds", "books"]
const CASH_ITEM := "Cash"


static func _const(key: String, fallback: float) -> float:
	var table: Dictionary = _data().table("constants").get("constants", {})
	return float(table.get(key, fallback))


## An autoload by name. Static helper classes use this instead of the global
## identifier so they also compile in headless `-s` runs, where autoloads are
## not registered yet when class_name scripts are parsed.
static func auto(autoload_name: String) -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node(autoload_name)


static func _data() -> Node:
	return auto("Data")


static func rnd(rng: RandomNumberGenerator, n: int) -> int:
	if n <= 0:
		return 0
	return rng.randi() % n


## The original's getRandRange(min, max): round(random() * (max - min)) + min.
static func rand_range_inclusive(rng: RandomNumberGenerator, lo: int, hi: int) -> int:
	return roundi(rng.randf() * (hi - lo)) + lo


# --- Item references ---------------------------------------------------------

## Turns a data ref ("medkit", "ammo9mm_50", "cash_120", "M16A2_scope") into an
## inventory entry, or {} when unknown.
static func resolve(ref: String) -> Dictionary:
	if ref.begins_with("cash_") and ref.substr(5).is_valid_int():
		return {"ref": ref, "name": CASH_ITEM, "weight": 0.0, "count": int(ref.substr(5)), "kind": "cash"}
	if ref.begins_with("ammo") and ref.contains("_") and ref.get_slice("_", 1).is_valid_int():
		var ammo_type := ref.substr(4, ref.rfind("_") - 4)
		return {"ref": ref, "name": Weapon.ammo_name_for(ammo_type), "weight": 0.0,
			"count": int(ref.get_slice("_", 1)), "kind": "ammo"}
	var info := Items.find(ref)
	var mod := ""
	if info.is_empty() and ref.contains("_"):
		var base := ref.substr(0, ref.rfind("_"))
		var suffix := ref.substr(ref.rfind("_") + 1)
		if suffix in MODS:
			info = Items.find(base)
			mod = suffix
	if info.is_empty():
		return {}
	var out := {"ref": ref, "name": info["name"], "weight": info["weight"], "count": 1, "kind": info["kind"]}
	if mod != "":
		out["mod"] = mod
	return out


# --- Pools -------------------------------------------------------------------

## Refs of the `<room_type>Junk` list: junk items by `location`, plus clothing by
## `location` (clothing without one counts as "bedroom").
static func junk_pool(room_type: String) -> Array:
	var out: Array = []
	for info in Items.all("junk"):
		if info["rec"].get("location", "") == room_type:
			out.append(info["ref"])
	for info in Items.all("clothing"):
		if info["ref"] == "none":
			continue
		if info["rec"].get("location", "bedroom") == room_type:
			out.append(info["ref"])
	return out


## Refs of the `rarity<r>` list: items whose rarity is within `rarityLevelCap`
## (5) of r. Only weapons, clothing, food, meds and books; ammo, junk and cash
## are excluded.
static func rarity_pool(r: int) -> Array:
	var cap := int(_const("rarityLevelCap", 5))
	var out: Array = []
	for k in RARITY_KINDS:
		for info in Items.all(k):
			var rec: Dictionary = info["rec"]
			if rec.get("rarity") != null and info["ref"] != "none" and absf(float(rec["rarity"]) - r) <= cap:
				out.append(info["ref"])
	return out


# --- Rolls (each mirrors one step of searchContainer) -------------------------

## Step 2. 51% (random(100) <= 50) of round(random(6) - searching/10) items,
## minimum 0, from the room type's junk list.
static func roll_junk(room_type: String, searching: int, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	if rnd(rng, int(_const("randomSearchRange", 100))) > int(_const("randomSearchChance", 50)):
		return out
	var n := maxi(0, roundi(rnd(rng, int(_const("randomSearchUnits", 6))) - searching / 10.0))
	var pool := junk_pool(room_type)
	for i in n:
		if pool.is_empty():
			break
		out.append(pool[rnd(rng, pool.size())])
	return out


## Chance numerator of the lucky roll: round(75 + luck*5 + searching*2), out of
## `luckSearchRange` (1000); the roll is random(1000) <= chance.
static func lucky_chance(searching: int, luck: int) -> int:
	return roundi(_const("luckSearchChance", 75) + luck * 5 + searching * 2)


## Rarity of one lucky item: round(random(danger) + 1) + random(luck/4), capped.
static func lucky_rarity(danger: int, luck: int, rng: RandomNumberGenerator) -> int:
	var r := rnd(rng, danger) + 1
	r += rnd(rng, int(luck / 4.0))
	return mini(r, int(_const("numRarities", 30)))


## Step 3. Returns the refs found (1-2 items when the roll succeeds).
static func roll_lucky(danger: int, searching: int, luck: int, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	if rnd(rng, int(_const("luckSearchRange", 1000))) > lucky_chance(searching, luck):
		return out
	var n := rnd(rng, int(_const("luckSearchUnits", 2))) + 1
	for i in n:
		var pool := rarity_pool(lucky_rarity(danger, luck, rng))
		if not pool.is_empty():
			out.append(pool[rnd(rng, pool.size())])
	return out


## Largest cash index a search can give: round(danger*3.3 + luck), capped at
## `totalCashObj`, then divided by `searchCashMod` (1.5) and rounded up.
static func cash_index_max(danger: int, luck: int) -> int:
	var v := mini(roundi(danger * _const("cashAmountMod", 3.3) + luck), int(_const("totalCashObj", 1001)))
	return ceili(v / _const("searchCashMod", 1.5))


## Step 4 (rooms of type "anywhere" only). Returns a `cash_<n>` ref or "".
static func roll_cash(danger: int, luck: int, rng: RandomNumberGenerator) -> String:
	if rnd(rng, 100) > int(_const("dropRateCash", 33)):
		return ""
	var hi := cash_index_max(danger, luck)
	var amount := rand_range_inclusive(rng, 1, hi)
	return "cash_%d" % amount if amount >= 1 else ""


## Full first-search contents of a container def (a `contN` entry). `player`
## supplies {searching, luck}: the raw searching skill and the luck attribute.
static func generate(def: Dictionary, room_type: String, danger: int, player: Dictionary,
		rng: RandomNumberGenerator) -> Array:
	var searching: int = player.get("searching", 7)
	var luck: int = player.get("luck", 5)
	var items: Array = []
	for ref in def.get("cnt", []):
		var e := resolve(str(ref))
		if not e.is_empty():
			items.append(e)
	if not def.get("noJunk", false):
		for ref in roll_junk(room_type, searching, rng):
			var e := resolve(ref)
			if not e.is_empty():
				items.append(e)
		for ref in roll_lucky(danger, searching, luck, rng):
			var e := resolve(ref)
			if not e.is_empty():
				e["lucky"] = true
				items.append(e)
		if room_type == "anywhere":
			var cash := roll_cash(danger, luck, rng)
			if cash != "":
				items.append(resolve(cash))
	shuffle(items, rng)
	return items


static func shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var t = arr[i]
		arr[i] = arr[j]
		arr[j] = t


# --- Drop rates (section 7) --------------------------------------------------

## Per-roll percentages from constants.json. Ammo is x1.4 in Run'n'Gun. Used by
## zombie drops and any system that wants a "what kind of thing drops" roll.
static func drop_rates(runngun: bool = false) -> Dictionary:
	var ammo := _const("dropRateAmmo", 40)
	if runngun:
		ammo = round(ammo * _const("runNGunAmmoDropMod", 1.4))
	return {"ammo": ammo, "food": _const("dropRateFood", 30), "medical": _const("dropRateMedical", 30),
		"clothing": _const("dropRateClothing", 25), "weapons": _const("dropRateWeapons", 2),
		"cash": _const("dropRateCash", 33)}


## Categories that drop on one roll set: each passes when random(100) < rate.
static func roll_drop_categories(rng: RandomNumberGenerator, runngun: bool = false) -> Array:
	var out: Array = []
	var rates := drop_rates(runngun)
	for cat in rates:
		if rnd(rng, 100) < rates[cat]:
			out.append(cat)
	return out


## Search XP: round(5 + level) + ceil(adjustedSkill(smarts) / 30).
static func search_xp(level: int, adjusted_smarts: int) -> int:
	return roundi(_const("skillUse_search", 5) + level) + ceili(adjusted_smarts / _const("xpSmartsBonusDiv", 30))
