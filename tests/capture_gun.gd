extends SceneTree
## Not a test: windowed screenshot of the player holding a gun.
## godot --path . -s tests/capture_gun.gd -- <out_dir>
func _initialize() -> void:
	await physics_frame
	await physics_frame
	var out := "/tmp"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	var world = root.get_node("World")
	world.fade_enabled = false
	root.get_node("Clock").running = false
	root.get_node("Director").enabled = false
	world.reset()
	var scn: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scn)
	current_scene = scn
	for i in 20: await physics_frame
	root.get_node("Inventory").add_item("G17 Pistol", 2.0, 1)
	var p = scn.get_player()
	p.set_physics_process(true)
	Input.action_press("equip_gun")
	for i in 3: await physics_frame
	Input.action_release("equip_gun")
	for i in 40: await physics_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(out + "/gun.png")
	quit()
