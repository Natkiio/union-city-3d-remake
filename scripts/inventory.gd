extends Node
## Global inventory singleton (autoloaded as "Inventory").
## Items are stackable: name -> {"weight": float, "count": int}.

signal item_added(item_name: String)
signal inventory_changed()
## Emitted when carried weight crosses the carry limit either way.
signal overweight_changed(is_over: bool)

var items: Dictionary = {}

## Rounds loaded in each firearm, keyed by the firearm's item name. Reserve
## ammo is the ammo item's count in items. A firearm with no entry yet is
## treated as full by the player.
var magazines: Dictionary = {}

## Worn clothing by slot (top, bottom, feet, head, ...): slot -> item name.
## Bookkeeping only; clothing stats are not applied anywhere yet.
var equipped_clothing: Dictionary = {}

## Skill points from books that Stats could not take (it has no
## add_skill_points yet): skill -> points.
var book_points: Dictionary = {}

## True while carried weight is over carry_limit(). The movement penalty
## belongs to the player; this is the flag it reads.
var overweight: bool = false

## Weapons readied for the number keys: item names (or "") for key 2 and key 3.
const SLOTS := ["primary", "secondary"]
var slots: Dictionary = {"primary": "", "secondary": ""}

func _ready() -> void:
	add_to_group("stateful")
	Events.stats_changed.connect(_update_overweight)

## Puts a carried weapon in a slot (a weapon can sit in only one slot).
func assign_slot(slot: String, item_name: String) -> bool:
	if not SLOTS.has(slot) or not items.has(item_name):
		return false
	for other in SLOTS:
		if slots[other] == item_name:
			slots[other] = ""
	slots[slot] = item_name
	inventory_changed.emit()
	return true

func clear_slot(slot: String) -> void:
	if SLOTS.has(slot) and slots[slot] != "":
		slots[slot] = ""
		inventory_changed.emit()

## "primary", "secondary" or "" for the slot this item sits in.
func slot_of(item_name: String) -> String:
	for slot in SLOTS:
		if slots[slot] == item_name:
			return slot
	return ""

func reset() -> void:
	items.clear()
	magazines.clear()
	equipped_clothing.clear()
	book_points.clear()
	slots = {"primary": "", "secondary": ""}
	_update_overweight()
	inventory_changed.emit()

func to_dict() -> Dictionary:
	return {"items": items.duplicate(true), "magazines": magazines.duplicate(true),
		"equipped_clothing": equipped_clothing.duplicate(), "book_points": book_points.duplicate(),
		"slots": slots.duplicate()}

func from_dict(d: Dictionary) -> void:
	items = d.get("items", {}).duplicate(true)
	magazines = d.get("magazines", {}).duplicate(true)
	equipped_clothing = d.get("equipped_clothing", {}).duplicate()
	book_points = d.get("book_points", {}).duplicate()
	slots = {"primary": "", "secondary": ""}
	for slot in SLOTS:
		slots[slot] = str(d.get("slots", {}).get(slot, ""))
	_update_overweight()
	inventory_changed.emit()

func get_magazine(item_name: String, default_rounds: int) -> int:
	return magazines.get(item_name, default_rounds)

func set_magazine(item_name: String, rounds: int) -> void:
	magazines[item_name] = rounds

func add_item(item_name: String, weight: float = 1.0, count: int = 1) -> void:
	if items.has(item_name):
		items[item_name]["count"] += count
	else:
		# The default weight means "look it up": use the item table's.
		if is_equal_approx(weight, 1.0) and Items.exists(item_name):
			weight = Items.weight(item_name)
		items[item_name] = {"weight": weight, "count": count}
	item_added.emit(item_name)
	_update_overweight()
	inventory_changed.emit()
	DebugLog.say("Inventory", "picked up: %s x%d (unique: %d, total units: %d, %.1f lbs)" % [
		item_name, count, items.size(), item_count(), total_weight()])

func remove_item(item_name: String, count: int = 1) -> void:
	if not items.has(item_name):
		return
	items[item_name]["count"] -= count
	if items[item_name]["count"] <= 0:
		items.erase(item_name)
		for slot in SLOTS:
			if slots[slot] == item_name:
				slots[slot] = ""
	_update_overweight()
	inventory_changed.emit()
	DebugLog.say("Inventory", "removed: %s x%d" % [item_name, count])

func has_item(item_name: String) -> bool:
	return items.has(item_name)

## Short category tag shown next to an item name in the trunk and inventory
## menus: WEAPON for firearms, AMMO for ammo, "" for everything else.
func tag_for(item_name: String) -> String:
	var weapon := Weapon.find_by_name(item_name)
	if weapon != null and weapon.is_firearm():
		return "WEAPON"
	if item_name.ends_with(" Ammo"):
		return "AMMO"
	return ""

func is_usable(item_name: String) -> bool:
	return ItemUse.is_usable(Items.find(item_name))

## Describes the use effect for an item: {"type": kind, "ref": ...}, or {}.
func get_use_effect(item_name: String) -> Dictionary:
	var info := Items.find(item_name)
	if not ItemUse.is_usable(info):
		return {}
	return {"type": info["kind"], "ref": info["ref"]}

## Uses one of `item_name`: applies the effect from the item tables, consumes
## it (food, meds, books) and emits Events.item_used. Returns false if the
## item is missing, not usable, or the effect does not apply right now (full
## health, not tired, ...).
func use_item(item_name: String) -> bool:
	if not has_item(item_name):
		return false
	var info := Items.find(item_name)
	if not ItemUse.is_usable(info) or not ItemUse.apply(info):
		return false
	if ItemUse.consumes(info):
		remove_item(item_name, 1)
	else:
		inventory_changed.emit()
	Events.item_used.emit(item_name)
	return true

## Carry limit in lbs, from Stats.carry_weight().
func carry_limit() -> float:
	return Stats.carry_weight()

func is_overweight() -> bool:
	return total_weight() > carry_limit()

func _update_overweight() -> void:
	var now := is_overweight()
	if now != overweight:
		overweight = now
		overweight_changed.emit(now)

func item_count() -> int:
	var total := 0
	for key in items:
		total += items[key]["count"]
	return total

func total_weight() -> float:
	var total := 0.0
	for key in items:
		total += items[key]["weight"] * items[key]["count"]
	return total
