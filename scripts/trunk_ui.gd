extends CanvasLayer
## Trunk inventory menu: pauses the game, lists the trunk's items.
## Each item row is clickable (takes that one item). [Take All] and
## [Exit] are also clickable buttons. Keyboard still works:
## [1-9] takes a numbered item, [A] takes everything, [E] exits.

var current_trunk: Node = null

@onready var items_list: VBoxContainer = $TrunkPanel/ItemsList
@onready var total_weight_label: Label = $TrunkPanel/TotalWeightLabel
@onready var take_all_button: Button = $TrunkPanel/ActionRow/TakeAllButton
@onready var exit_button: Button = $TrunkPanel/ActionRow/ExitButton

func _ready() -> void:
	visible = false
	take_all_button.pressed.connect(_take_all)
	exit_button.pressed.connect(close)

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
		var row := Button.new()
		row.flat = true
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.text = "[%d] %s  %s  —  %.1f lbs" % [i + 1, _label_for(item), _tag_text(item["name"]), item["weight"]]
		_style_row(row)
		row.pressed.connect(_take_single.bind(i))
		items_list.add_child(row)
		total += item["weight"]
	if current_trunk.items.is_empty():
		var empty_row := Label.new()
		empty_row.text = "(empty)"
		items_list.add_child(empty_row)
	total_weight_label.text = "Total weight: %.1f lbs" % total
	take_all_button.disabled = current_trunk.items.is_empty()

## Trunk entries can stack (e.g. a box of ammo), so show the count when it's more than one.
func _label_for(item: Dictionary) -> String:
	var count: int = item.get("count", 1)
	if count > 1:
		return "%s x%d" % [item["name"], count]
	return item["name"]

func _tag_text(item_name: String) -> String:
	var tag := Inventory.tag_for(item_name)
	return "[%s]" % tag if tag != "" else ""

func _style_row(row: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0, 0, 0, 0)
	var hovered := StyleBoxFlat.new()
	hovered.bg_color = Color(1, 1, 1, 0.85)
	hovered.corner_radius_top_left = 3
	hovered.corner_radius_top_right = 3
	hovered.corner_radius_bottom_left = 3
	hovered.corner_radius_bottom_right = 3
	row.add_theme_stylebox_override("normal", normal)
	row.add_theme_stylebox_override("hover", hovered)
	row.add_theme_stylebox_override("pressed", hovered)
	row.add_theme_color_override("font_color", Color(0.2, 0.15, 0.1))
	row.add_theme_color_override("font_hover_color", Color(0.1, 0.1, 0.1))
	row.add_theme_color_override("font_pressed_color", Color(0.1, 0.1, 0.1))

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
	if current_trunk == null:
		return
	var taken: Array = current_trunk.take_all()
	for item in taken:
		Inventory.add_item(item["name"], item["weight"], item.get("count", 1))
	print("[Trunk] took %d items" % taken.size())
	_refresh()

func _take_single(index: int) -> void:
	if current_trunk == null or index < 0 or index >= current_trunk.items.size():
		return
	var item: Dictionary = current_trunk.take_item(index)
	Inventory.add_item(item["name"], item["weight"], item.get("count", 1))
	print("[Trunk] took 1 item: %s" % item["name"])
	_refresh()
