extends Node
## Global inventory singleton (autoloaded as "Inventory").
## Items are stackable: name -> {"weight": float, "count": int}.

signal item_added(item_name: String)
signal inventory_changed()

## Items with a defined "use" effect, keyed by name. Everything else
## can still be carried/dropped but has no Use action.
const USE_EFFECTS := {
	"Canned Food": {"type": "heal", "amount": 25.0},
	"Bandages": {"type": "heal", "amount": 15.0},
}

var items: Dictionary = {}

## Rounds loaded in each firearm, keyed by the firearm's item name. Reserve
## ammo is the ammo item's count in items. A firearm with no entry yet is
## treated as full by the player.
var magazines: Dictionary = {}

func get_magazine(item_name: String, default_rounds: int) -> int:
	return magazines.get(item_name, default_rounds)

func set_magazine(item_name: String, rounds: int) -> void:
	magazines[item_name] = rounds

func add_item(item_name: String, weight: float = 1.0, count: int = 1) -> void:
	if items.has(item_name):
		items[item_name]["count"] += count
	else:
		items[item_name] = {"weight": weight, "count": count}
	item_added.emit(item_name)
	inventory_changed.emit()
	print("[Inventory] picked up: %s x%d (unique: %d, total units: %d, %.1f lbs)" % [
		item_name, count, items.size(), item_count(), total_weight()])

func remove_item(item_name: String, count: int = 1) -> void:
	if not items.has(item_name):
		return
	items[item_name]["count"] -= count
	if items[item_name]["count"] <= 0:
		items.erase(item_name)
	inventory_changed.emit()
	print("[Inventory] removed: %s x%d" % [item_name, count])

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
	return USE_EFFECTS.has(item_name)

func get_use_effect(item_name: String) -> Dictionary:
	return USE_EFFECTS.get(item_name, {})

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
