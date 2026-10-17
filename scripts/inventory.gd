extends Node
## Global inventory singleton (autoloaded as "Inventory").
## Items are stackable: name -> {"weight": float, "count": int}.

signal item_added(item_name: String)

var items: Dictionary = {}

func add_item(item_name: String, weight: float = 1.0, count: int = 1) -> void:
	if items.has(item_name):
		items[item_name]["count"] += count
	else:
		items[item_name] = {"weight": weight, "count": count}
	item_added.emit(item_name)
	print("[Inventory] picked up: %s x%d (unique: %d, total units: %d, %.1f lbs)" % [
		item_name, count, items.size(), item_count(), total_weight()])

func has_item(item_name: String) -> bool:
	return items.has(item_name)

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
