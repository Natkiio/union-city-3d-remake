extends CanvasLayer
## Trunk inventory menu: pauses the game, lists the trunk's items.
## [1-9] takes a single numbered item, [A] takes everything,
## [E] exits.

var current_trunk: Node = null

@onready var items_list: VBoxContainer = $TrunkPanel/ItemsList
@onready var total_weight_label: Label = $TrunkPanel/TotalWeightLabel

func _ready() -> void:
	visible = false

func open(trunk: Node) -> void:
	current_trunk = trunk
	_refresh()
	visible = true
	get_tree().paused = true
	print("[Trunk] opened, %d items" % current_trunk.items.size())

func close() -> void:
	if current_trunk and current_trunk.has_method("suppress_interact"):
		current_trunk.suppress_interact()
	visible = false
	current_trunk = null
	get_tree().paused = false
	print("[Trunk] closed")

func _refresh() -> void:
	for child in items_list.get_children():
		child.queue_free()
	var total := 0.0
	for i in range(current_trunk.items.size()):
		var item: Dictionary = current_trunk.items[i]
		var row := Label.new()
		row.text = "[%d] %s  —  %.1f lbs" % [i + 1, item["name"], item["weight"]]
		items_list.add_child(row)
		total += item["weight"]
	if current_trunk.items.is_empty():
		var empty_row := Label.new()
		empty_row.text = "(empty)"
		items_list.add_child(empty_row)
	total_weight_label.text = "Total weight: %.1f lbs" % total

func _input(event: InputEvent) -> void:
	if not visible or current_trunk == null:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_A:
			_take_all()
		elif event.keycode == KEY_E:
			close()
		elif event.keycode >= KEY_1 and event.keycode <= KEY_9:
			_take_single(event.keycode - KEY_1)

func _take_all() -> void:
	var taken: Array = current_trunk.take_all()
	for item in taken:
		Inventory.add_item(item["name"], item["weight"])
	print("[Trunk] took %d items" % taken.size())
	_refresh()

func _take_single(index: int) -> void:
	if index < 0 or index >= current_trunk.items.size():
		return
	var item: Dictionary = current_trunk.take_item(index)
	Inventory.add_item(item["name"], item["weight"])
	print("[Trunk] took 1 item: %s" % item["name"])
	_refresh()
