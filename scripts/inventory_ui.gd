extends CanvasLayer
## Full inventory screen: press "toggle_inventory" (I) to view/hide
## everything the player is carrying, with per-item weight and total.
## Pauses the game while open, like the trunk menu.

@onready var items_list: VBoxContainer = $Panel/ItemsList
@onready var total_weight_label: Label = $Panel/TotalWeightLabel

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

func _process(_delta: float) -> void:
	if TrunkUI.visible:
		return
	if Input.is_action_just_pressed("toggle_inventory"):
		if visible:
			_close()
		else:
			_open()

func _open() -> void:
	_refresh()
	visible = true
	get_tree().paused = true

func _close() -> void:
	visible = false
	get_tree().paused = false

func _refresh() -> void:
	for child in items_list.get_children():
		child.queue_free()
	if Inventory.items.is_empty():
		var empty_row := Label.new()
		empty_row.text = "(empty)"
		items_list.add_child(empty_row)
	else:
		for item_name in Inventory.items.keys():
			var data: Dictionary = Inventory.items[item_name]
			var row := Label.new()
			row.text = "%s  x%d  —  %.1f lbs" % [item_name, data["count"], data["weight"] * data["count"]]
			items_list.add_child(row)
	total_weight_label.text = "Total weight: %.1f lbs" % Inventory.total_weight()
