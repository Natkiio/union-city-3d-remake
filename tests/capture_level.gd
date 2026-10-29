extends SceneTree
## Not a test: renders rooms windowed and saves PNG screenshots, then quits.
## Lets you look at the level builder's output (see docs/world.md).
##
##   godot --path . -s tests/capture_level.gd -- out=/tmp/shots \
##       shots=l16_s3_b0_f0_r1@1100,l16_s3_b1_f1_r1@300 hour=12
##
## Each shot is <room id>@<player x in px>. Files are named <room id>.png.
## Needs a display (no --headless). Always quits by itself.

func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var out: String = args.get("out", OS.get_user_data_dir())
	var shots: PackedStringArray = str(args.get("shots", "l16_s3_b0_f0_r1@1100")).split(",")
	DirAccess.make_dir_recursive_absolute(out)
	await process_frame
	var clock := root.get_node("Clock")
	if args.has("hour"):
		clock.set_time(int(args.hour), 0)
	clock.running = false
	root.get_node("Director").enabled = false
	var world := root.get_node("World")
	world.fade_enabled = false
	var scn: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scn)
	current_scene = scn
	for s in shots:
		var parts := s.split("@")
		world.enter_room(parts[0], "x:" + (parts[1] if parts.size() > 1 else "300"))
		for i in 20:
			await process_frame
		var img := root.get_viewport().get_texture().get_image()
		var path := out.path_join(parts[0] + ".png")
		img.save_png(path)
		print("saved ", path)
	quit(0)
