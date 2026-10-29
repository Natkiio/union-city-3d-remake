class_name ItemUse
extends RefCounted
## What using an item does, driven by the item tables (spec: section 7,
## "Using items"). Pure rules plus calls into Stats, Survival and the player;
## Inventory.use_item() wraps this with consumption and the item_used event.

const BOOK_SMARTS_DIVISOR := 33   # bookSmartsMod
const BOOK_SKILL_CAP := 100


## True if the item kind has a Use action at all (weapons equip instead).
static func is_usable(info: Dictionary) -> bool:
	if info.is_empty():
		return false
	return info["kind"] in ["food", "meds", "books", "clothing"]


## Amount a food item restores: round(bonus + adjustedSkill(survival) / 5).
static func food_amount(info: Dictionary) -> int:
	return roundi(float(info["rec"].get("bonus", 0)) + _stats().adjusted_skill("survival") / 5.0)


## Percent-of-max-health a health med restores:
## round((bonus + adjustedSkill(firstAid) / 2) / 100 * healthMax).
static func med_heal(info: Dictionary) -> int:
	var pct := roundi(float(info["rec"].get("bonus", 0)) + _stats().adjusted_skill("firstAid") / 2.0)
	return roundi(pct / 100.0 * _stats().max_health())


## Skill points a book gives: bonus + ceil(adjustedSkill(smarts) / 33).
static func book_points(info: Dictionary) -> int:
	return int(info["rec"].get("bonus", 0)) + ceili(_stats().adjusted_skill("smarts") / float(BOOK_SMARTS_DIVISOR))


## Applies the effect. Returns true if the item was used (and should be
## consumed). Clothing equips and is never consumed; see `consumes()`.
static func apply(info: Dictionary) -> bool:
	match info.get("kind", ""):
		"food":
			return _use_food(info)
		"meds":
			return _use_meds(info)
		"books":
			return _use_book(info)
		"clothing":
			return _equip_clothing(info)
	return false


static func consumes(info: Dictionary) -> bool:
	return info.get("kind", "") in ["food", "meds", "books"]


static func _autoload(autoload_name: String) -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node(autoload_name)


static func _stats() -> Node:
	return _autoload("Stats")


static func _survival() -> Node:
	return _autoload("Survival")


static func _inventory() -> Node:
	return _autoload("Inventory")


static func _player() -> Node:
	return (Engine.get_main_loop() as SceneTree).get_first_node_in_group("player")


static func _heal(amount: float) -> void:
	var player := _player()
	if player == null:
		return
	if player.has_method("heal"):
		player.heal(amount)
	if "perm_health" in player:
		player.perm_health = minf(player.perm_health + amount, _stats().max_health())


static func _use_food(info: Dictionary) -> bool:
	var amount := food_amount(info)
	if _survival().is_survivor():
		_survival().eat(amount)
	else:
		_heal(amount)   # Run'n'Gun: food heals both layers
	return true


static func _use_meds(info: Dictionary) -> bool:
	match info["rec"].get("bonusStat", ""):
		"health":
			var player := _player()
			if player != null:
				if "perm_health" in player:
					if player.perm_health >= _stats().max_health():
						return false
				elif "health" in player and player.health >= _stats().max_health():
					return false
			_heal(med_heal(info))
			return true
		"sleep":
			# Original gates this on sleep < 100; we gate on sleep > 0 so a
			# rested player does not waste one (verify).
			if not _survival().is_survivor() or _survival().sleep <= 0.0:
				return false
			_survival().reduce_sleep(float(info["rec"].get("bonus", 0)))
			return true
	return false


static func _use_book(info: Dictionary) -> bool:
	var skill: String = info["key"]
	var pts := book_points(info)
	if _stats().has_method("add_skill_points"):
		_stats().add_skill_points(skill, pts)
	else:
		# Stats cannot take points yet: just record them (capped at 100).
		var room := maxi(BOOK_SKILL_CAP - _stats().skill(skill) - _inventory().book_points.get(skill, 0), 0)
		_inventory().book_points[skill] = _inventory().book_points.get(skill, 0) + mini(pts, room)
	return true


static func _equip_clothing(info: Dictionary) -> bool:
	var slot: String = info["rec"].get("wearLocation", "top")
	if _inventory().equipped_clothing.get(slot, "") == info["name"]:
		_inventory().equipped_clothing.erase(slot)   # using worn clothing takes it off
	else:
		_inventory().equipped_clothing[slot] = info["name"]
	return true
