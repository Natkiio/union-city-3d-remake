extends CanvasLayer
## Tiny HUD: inventory count + last picked up item.

@onready var label: Label = $Label

func _ready() -> void:
	Inventory.item_added.connect(_on_item_added)
	_refresh("")

func _on_item_added(item_name: String) -> void:
	_refresh(item_name)

func _refresh(last_item: String) -> void:
	var text := "Items: %d" % Inventory.item_count()
	if last_item != "":
		text += "\nPicked up: %s" % last_item
	label.text = text
