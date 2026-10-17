extends CanvasLayer
## Tiny HUD: inventory count, weight, and last picked up item.
## Press "toggle_inventory" (I) for the full inventory screen.

@onready var label: Label = $Label

func _ready() -> void:
	Inventory.item_added.connect(_on_item_added)
	Inventory.inventory_changed.connect(_on_inventory_changed)
	_refresh("")

func _on_item_added(item_name: String) -> void:
	_refresh(item_name)

func _on_inventory_changed() -> void:
	_refresh("")

func _refresh(last_item: String) -> void:
	var text := "Items: %d (%.1f lbs)  [I] Inventory" % [Inventory.item_count(), Inventory.total_weight()]
	if last_item != "":
		text += "\nPicked up: %s" % last_item
	label.text = text
