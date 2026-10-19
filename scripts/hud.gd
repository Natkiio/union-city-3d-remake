extends CanvasLayer
## Tiny HUD: inventory count, weight, and last picked up item.
## Press "toggle_inventory" (I) for the full inventory screen.
## Bottom-right: equipped weapon, plus the ammo that weapon uses.

@onready var label: Label = $Label
@onready var weapon_label: Label = $WeaponLabel

var player = null
var shown_weapon: String = ""
var shown_ammo: int = -1

func _ready() -> void:
	Inventory.item_added.connect(_on_item_added)
	Inventory.inventory_changed.connect(_on_inventory_changed)
	_refresh("")

func _process(_delta: float) -> void:
	if not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var weapon: String = player.equipped_weapon
	var ammo: int = -1
	var gun := Weapon.from_ref(weapon)
	if gun != null:
		ammo = Inventory.items.get(gun.ammo_item_name(), {}).get("count", 0)
	if weapon == shown_weapon and ammo == shown_ammo:
		return
	shown_weapon = weapon
	shown_ammo = ammo
	_refresh_weapon()

func _on_item_added(item_name: String) -> void:
	_refresh(item_name)

func _on_inventory_changed() -> void:
	_refresh("")

func _refresh(last_item: String) -> void:
	var text := "Items: %d (%.1f lbs)  [I] Inventory" % [Inventory.item_count(), Inventory.total_weight()]
	if last_item != "":
		text += "\nPicked up: %s" % last_item
	label.text = text

func _refresh_weapon() -> void:
	var gun := Weapon.from_ref(shown_weapon)
	if gun != null:
		weapon_label.text = "%s\nAmmo: %d" % [gun.display_name, shown_ammo]
		if shown_ammo == 0:
			weapon_label.add_theme_color_override("font_color", Color.RED)
		else:
			weapon_label.remove_theme_color_override("font_color")
	else:
		weapon_label.text = "Fists"
		weapon_label.remove_theme_color_override("font_color")
