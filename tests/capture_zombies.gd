extends SceneTree
## Not a test: windowed screenshot of a room with zombies placed near the player.
##   godot --path . -s tests/capture_zombies.gd -- out=/tmp/zshots room=l16_s3_b1_f1_r1 hour=12

func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var out: String = args.get("out", OS.get_user_data_dir())
	DirAccess.make_dir_recursive_absolute(out)
	await process_frame
	var clock := root.get_node("Clock")
	clock.set_time(int(args.get("hour", 12)), 0)
	clock.running = false
	root.get_node("Director").enabled = false
	var world := root.get_node("World")
	world.fade_enabled = false
	var scn: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scn)
	current_scene = scn
	var room: String = args.get("room", "l16_s3_b1_f1_r1")
	world.enter_room(room, "x:600")
	for i in 20:
		await process_frame
	var p = scn.get_player()
	for dx in [-4.0, -2.0, 3.0, 5.0]:
		Zombie.spawn(world.level().spawn_root(), "zombieSlow", 1, p.global_position.x + dx)
	for i in 30:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out.path_join(room + ".png"))
	print("saved")
	quit(0)
