extends CanvasLayer
## Full inventory screen: press "toggle_inventory" (I) to view/hide
## everything the player is carrying. Items are clickable: click a
## row to select it (highlighted white, matching the world hover
## style), then click [Use] (if the item has an effect) or [Drop].
## Pauses the game while open, like the trunk menu.

@onready var items_list: VBoxContainer = $Panel/ItemsList
@onready var total_weight_label: Label = $Panel/TotalWeightLabel
@onready var action_row: HBoxContainer = $Panel/ActionRow
@onready var use_button: Button = $Panel/ActionRow/UseButton
@onready var drop_button: Button = $Panel/ActionRow/DropButton

var selected_item: String = ""
var button_group := ButtonGroup.new()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	use_button.pressed.connect(_on_use_pressed)
	drop_button.pressed.connect(_on_drop_pressed)
	Inventory.inventory_changed.connect(_on_inventory_changed)

func _process(_delta: float) -> void:
	if TrunkUI.visible:
		return
	if get_tree().get_first_node_in_group("player") == null:
		return # no player in this scene (e.g. the main menu) — nothing to show
	if Input.is_action_just_pressed("toggle_inventory"):
		if visible:
			_close()
		else:
			_open()

func _open() -> void:
	selected_item = ""
	_refresh()
	visible = true
	get_tree().paused = true

func _close() -> void:
	visible = false
	get_tree().paused = false

func _on_inventory_changed() -> void:
	if visible:
		_refresh()

func _refresh() -> void:
	for child in items_list.get_children():
		child.queue_free()

	if not Inventory.items.has(selected_item):
		selected_item = ""

	if Inventory.items.is_empty():
		var empty_row := Label.new()
		empty_row.text = "(empty)"
		items_list.add_child(empty_row)
	else:
		for item_name in Inventory.items.keys():
			var data: Dictionary = Inventory.items[item_name]
			var row := Button.new()
			row.flat = true
			row.toggle_mode = true
			row.button_group = button_group
			row.alignment = HORIZONTAL_ALIGNMENT_LEFT
			row.text = "%s  x%d  —  %.1f lbs" % [item_name, data["count"], data["weight"] * data["count"]]
			row.button_pressed = (item_name == selected_item)
			_style_row(row)
			row.pressed.connect(_on_row_pressed.bind(item_name))
			items_list.add_child(row)

	total_weight_label.text = "Total weight: %.1f lbs" % Inventory.total_weight()

	action_row.visible = selected_item != ""
	if selected_item != "":
		use_button.text = "[Use] %s" % selected_item
		use_button.disabled = not Inventory.is_usable(selected_item)
		drop_button.text = "[Drop] %s" % selected_item

func _style_row(row: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0, 0, 0, 0)
	var selected := StyleBoxFlat.new()
	selected.bg_color = Color(1, 1, 1, 0.85)
	selected.corner_radius_top_left = 3
	selected.corner_radius_top_right = 3
	selected.corner_radius_bottom_left = 3
	selected.corner_radius_bottom_right = 3
	row.add_theme_stylebox_override("normal", normal)
	row.add_theme_stylebox_override("hover", selected)
	row.add_theme_stylebox_override("pressed", selected)
	row.add_theme_color_override("font_color", Color(0.2, 0.15, 0.1))
	row.add_theme_color_override("font_hover_color", Color(0.1, 0.1, 0.1))
	row.add_theme_color_override("font_pressed_color", Color(0.1, 0.1, 0.1))

func _on_row_pressed(item_name: String) -> void:
	selected_item = item_name
	_refresh()

func _on_use_pressed() -> void:
	if selected_item == "" or not Inventory.has_item(selected_item):
		return
	var effect: Dictionary = Inventory.get_use_effect(selected_item)
	if effect.is_empty():
		print("[Inventory] %s cannot be used" % selected_item)
		return
	var player := get_tree().get_first_node_in_group("player")
	if effect.get("type") == "heal" and player and player.has_method("heal"):
		player.heal(effect.get("amount", 0.0))
	Inventory.remove_item(selected_item, 1)
	print("[Inventory] used 1 %s" % selected_item)

func _on_drop_pressed() -> void:
	if selected_item == "" or not Inventory.has_item(selected_item):
		return
	var dropped := selected_item
	Inventory.remove_item(selected_item, 1)
	print("[Inventory] dropped 1 %s" % dropped)
