extends Node
## Global inventory singleton (autoloaded as "Inventory").

signal item_added(item_name: String)

var items: Array[String] = []

func add_item(item_name: String) -> void:
	items.append(item_name)
	item_added.emit(item_name)
	print("[Inventory] picked up: %s (total: %d)" % [item_name, items.size()])

func has_item(item_name: String) -> bool:
	return items.has(item_name)

func item_count() -> int:
	return items.size()
