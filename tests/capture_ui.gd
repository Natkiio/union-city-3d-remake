extends SceneTree
## Not a test. Saves PNGs of the main menu, HUD and map screen, then quits.
## Run windowed:  godot --path . -s tests/capture_ui.gd -- <output dir>
## Quits by itself after a few seconds.

var out_dir := "/tmp"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	root.size = Vector2i(1280, 720)
	_run()


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	await create_timer(0.3).timeout
	var img := root.get_texture().get_image()
	img.save_png("%s/ui_%s.png" % [out_dir, name])
	print("saved ", name, " ", img.get_size())


func _run() -> void:
	await process_frame
	await process_frame
	var menu: Node = load("res://scenes/ui/main_menu.tscn").instantiate()
	root.add_child(menu)
	await _shot("menu")
	menu.queue_free()
	await process_frame

	# HUD over a fake street colour
	var bg := ColorRect.new()
	bg.color = Color(0.35, 0.42, 0.5)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg_layer := CanvasLayer.new()
	bg_layer.layer = -1
	bg_layer.add_child(bg)
	root.add_child(bg_layer)
	var surv := root.get_node("Survival")
	surv.hunger = 55.0
	surv.sleep = 80.0
	root.get_node("Stats").add_xp(40, "capture")
	root.get_node("Clock").advance(195)
	root.get_node("Inventory").add_item("Hammer", 4.0, 1)
	var hud: CanvasLayer = load("res://scenes/ui/hud.tscn").instantiate()
	root.add_child(hud)
	root.get_node("Events").rush_started.emit()
	root.get_node("Inventory").add_item("Bandages", 0.5, 2)
	await _shot("hud")
	hud.queue_free()
	bg_layer.queue_free()
	await process_frame

	var m := MapScreen.new()
	m.nodes_override = MapScreen.mock_nodes()
	m.current_id = "9"
	root.add_child(m)
	await process_frame
	m.select("5")
	await _shot("map")
	quit()
