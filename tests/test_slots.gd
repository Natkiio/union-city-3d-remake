extends "res://tests/test_base.gd"
## Primary and secondary weapon slots: assigning, the 2 / 3 / swap keys, the
## inventory menu buttons, clearing on drop, saving.

func _tap(action: String) -> void:
	Input.action_press(action)
	await frames(2)
	Input.action_release(action)
	await frames(2)


func run() -> void:
	var world := autoload("World")
	world.fade_enabled = false
	autoload("Clock").running = false
	autoload("Director").enabled = false
	world.reset()
	var scn = await load_scene("res://scenes/main.tscn")
	await frames(3)
	var player: Node3D = scn.get_player()
	var inv := autoload("Inventory")

	inv.add_item("G17 Pistol", 2.0, 1)
	inv.add_item("Tire Iron", 3.0, 1)
	check("slots start empty", inv.slots["primary"] == "" and inv.slots["secondary"] == "")

	# Key 2 with nothing readied takes the first firearm and readies it.
	await _tap("equip_gun")
	check("key 2 readies the first firearm as primary", inv.slots["primary"] == "G17 Pistol" and player.equipped_weapon == "glock",
		"%s %s" % [inv.slots["primary"], player.equipped_weapon])

	var iron: Weapon = Weapon.find_by_name("Tire Iron")
	check("a melee weapon exists in the table", iron != null)
	if iron != null:
		check("assign a melee weapon to secondary", inv.assign_slot("secondary", "Tire Iron"))
		await _tap("equip_secondary")
		check("key 3 equips the secondary", player.equipped_weapon == iron.ref, player.equipped_weapon)
		await _tap("swap_weapon")
		check("swap goes back to the primary", player.equipped_weapon == "glock", player.equipped_weapon)
		await _tap("swap_weapon")
		check("swap again goes to the secondary", player.equipped_weapon == iron.ref)
	await _tap("equip_fists")
	check("key 1 is still fists", player.equipped_weapon == "fist")

	# A weapon sits in one slot only.
	inv.assign_slot("secondary", "G17 Pistol")
	check("moving a weapon to the other slot clears the first", inv.slots["primary"] == "" and inv.slots["secondary"] == "G17 Pistol")
	check("slot_of finds it", inv.slot_of("G17 Pistol") == "secondary" and inv.slot_of("Tire Iron") == "")
	check("assigning an item not carried fails", not inv.assign_slot("primary", "Katana"))

	# Save round trip and reset.
	var snap: Dictionary = inv.to_dict()
	inv.reset()
	check("reset clears the slots", inv.slots["primary"] == "" and inv.slots["secondary"] == "")
	inv.from_dict(snap)
	check("slots survive a save round trip", inv.slots["secondary"] == "G17 Pistol")

	# Removing the last copy clears the slot.
	inv.remove_item("G17 Pistol", 1)
	check("removing the item clears its slot", inv.slots["secondary"] == "")

	# Inventory menu: set primary through the buttons.
	inv.add_item("G17 Pistol", 2.0, 1)
	var ui := autoload("InventoryUI")
	ui.selected_item = "G17 Pistol"
	ui._on_slot_pressed("primary")
	check("menu Set Primary readies and equips", inv.slots["primary"] == "G17 Pistol" and player.equipped_weapon == "glock")
	ui._on_slot_pressed("primary")
	check("menu Clear Primary unequips", inv.slots["primary"] == "" and player.equipped_weapon == "fist")
	ui.selected_item = ""
