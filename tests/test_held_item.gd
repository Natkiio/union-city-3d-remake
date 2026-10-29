extends "res://tests/test_base.gd"
func run() -> void:
	var world := autoload("World")
	world.fade_enabled = false
	autoload("Clock").running = false
	autoload("Director").enabled = false
	world.reset()
	var scn = await load_scene("res://scenes/main.tscn")
	await frames(3)
	var p: Node3D = scn.get_player()
	check("no held item with fists", p.get_node_or_null("HeldItem") == null or not p.get_node("HeldItem").visible)
	autoload("Inventory").add_item("G17 Pistol", 2.0, 1)
	Input.action_press("equip_gun"); await frames(2); Input.action_release("equip_gun"); await frames(3)
	var h: Node3D = p.get_node_or_null("HeldItem")
	check("pistol shows a held item", h != null and h.visible and h.get_child_count() >= 2)
	check("held item sits on the lane near the player", h != null and is_zero_approx(h.global_position.z) and absf(h.global_position.x - p.global_position.x) < 1.0, str(h.global_position if h else null))
