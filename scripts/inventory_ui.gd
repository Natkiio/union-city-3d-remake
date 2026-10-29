extends CanvasLayer
## Full inventory screen: press "toggle_inventory" (I) to view/hide
## everything the player is carrying. Items are clickable: click a
## row to select it (highlighted white, matching the world hover
## style), then click [Use] (if the item has an effect) or [Drop].
## Pauses the game while open, like the trunk menu.

@onready var items_list: VBoxContainer = $Panel/ItemsList
@onready var total_weight_label: Label = $Panel/TotalWeightLabel
@onready var weight_bar: ProgressBar = $Panel/WeightBar
@onready var action_row: HBoxContainer = $Panel/ActionRow
@onready var use_button: Button = $Panel/ActionRow/UseButton
@onready var equip_button: Button = $Panel/ActionRow/EquipButton # primary slot
var secondary_button: Button
@onready var drop_button: Button = $Panel/ActionRow/DropButton

var selected_item: String = ""
var button_group := ButtonGroup.new()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	use_button.pressed.connect(_on_use_pressed)
	equip_button.pressed.connect(_on_slot_pressed.bind("primary"))
	secondary_button = Button.new()
	secondary_button.name = "SecondaryButton"
	secondary_button.theme = equip_button.theme
	secondary_button.pressed.connect(_on_slot_pressed.bind("secondary"))
	action_row.add_child(secondary_button)
	action_row.move_child(secondary_button, equip_button.get_index() + 1)
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
		var player := get_tree().get_first_node_in_group("player")
		for item_name in Inventory.items.keys():
			var data: Dictionary = Inventory.items[item_name]
			var row := Button.new()
			row.flat = true
			row.toggle_mode = true
			row.button_group = button_group
			row.alignment = HORIZONTAL_ALIGNMENT_LEFT
			var tag := Inventory.tag_for(item_name)
			var tag_text := "  [%s]" % tag if tag != "" else ""
			var slot: String = Inventory.slot_of(item_name)
			if slot != "":
				tag_text += "  [%s]" % slot.to_upper()
			if Weapon.find_by_name(item_name) != null and _is_equipped(player, item_name):
				tag_text += "  (equipped)"
			row.text = "%s  x%d%s  —  %.1f lbs" % [item_name, data["count"], tag_text, data["weight"] * data["count"]]
			row.button_pressed = (item_name == selected_item)
			_style_row(row)
			row.pressed.connect(_on_row_pressed.bind(item_name))
			items_list.add_child(row)

	_refresh_weight()

	action_row.visible = selected_item != ""
	if selected_item != "":
		use_button.text = "[Use] %s" % selected_item
		use_button.disabled = not Inventory.is_usable(selected_item)
		drop_button.text = "[Drop] %s" % selected_item

		var is_weapon: bool = Weapon.find_by_name(selected_item) != null
		equip_button.visible = is_weapon
		secondary_button.visible = is_weapon
		if is_weapon:
			equip_button.text = ("[Clear Primary]" if Inventory.slot_of(selected_item) == "primary" else "[Set Primary]")
			secondary_button.text = ("[Clear Secondary]" if Inventory.slot_of(selected_item) == "secondary" else "[Set Secondary]")
	else:
		equip_button.visible = false
		secondary_button.visible = false


func _refresh_weight() -> void:
	var total := Inventory.total_weight()
	var limit := Inventory.carry_limit()
	var over := total > limit
	total_weight_label.text = "Weight: %.1f / %.1f lbs%s" % [total, limit, "  OVERLOADED" if over else ""]
	weight_bar.max_value = maxf(limit, 0.01)
	weight_bar.value = minf(total, weight_bar.max_value)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.75, 0.15, 0.1) if over else Color(0.35, 0.5, 0.25)
	weight_bar.add_theme_stylebox_override("fill", fill)
	total_weight_label.add_theme_color_override("font_color",
		Color(0.8, 0.1, 0.05) if over else Color(0.5, 0.12, 0.1))

## True if `item_name` is the weapon the player currently has equipped.
func _is_equipped(player: Node, item_name: String) -> bool:
	if player == null or not ("equipped_weapon" in player) or player.equipped_weapon == "fist":
		return false
	var weapon := Weapon.find_by_name(item_name)
	return weapon != null and weapon.ref == player.equipped_weapon

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
	if Inventory.use_item(selected_item):
		print("[Inventory] used 1 %s" % selected_item)
	else:
		print("[Inventory] %s cannot be used now" % selected_item)

## Sets or clears a weapon slot for the selected item. Setting the primary
## also takes it in hand; setting the secondary only readies it (key 3).
func _on_slot_pressed(slot: String) -> void:
	if selected_item == "" or not Inventory.has_item(selected_item):
		return
	var player := get_tree().get_first_node_in_group("player")
	if player == null or not player.has_method("_set_equipped"):
		return
	if Inventory.slot_of(selected_item) == slot:
		Inventory.clear_slot(slot)
		if _is_equipped(player, selected_item):
			player._set_equipped("fist")
		print("[Inventory] cleared %s slot" % slot)
	else:
		Inventory.assign_slot(slot, selected_item)
		if slot == "primary":
			player.equip_slot("primary")
		print("[Inventory] %s -> %s slot" % [selected_item, slot])
	_refresh()

func _on_drop_pressed() -> void:
	if selected_item == "" or not Inventory.has_item(selected_item):
		return
	var dropped := selected_item
	var player := get_tree().get_first_node_in_group("player")
	var was_equipped := _is_equipped(player, dropped)
	Inventory.remove_item(selected_item, 1)
	if was_equipped and not Inventory.has_item(dropped) and player.has_method("_set_equipped"):
		player._set_equipped("fist")
	print("[Inventory] dropped 1 %s" % dropped)
