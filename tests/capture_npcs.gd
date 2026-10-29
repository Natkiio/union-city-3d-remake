extends SceneTree
## Not a test: windowed screenshot of the dressed NPCs next to the player and a
## zombie. godot --path . -s tests/capture_npcs.gd -- out=/tmp/shots [ids=a,b,c]
## Writes npcs.png (street lineup) and npcs_close.png (zoomed on the faces).

const IDS := ["Williams", "DrSmith", "Carol", "Anna", "Dana", "King", "Hank", "Shenice", "Darnel", "looter1", "HERCsoldier", "Clarence"]

func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var out: String = args.get("out", "/tmp")
	var ids: PackedStringArray = str(args.get("ids", ",".join(IDS))).split(",")
	DirAccess.make_dir_recursive_absolute(out)
	await process_frame
	root.get_node("Clock").set_time(12, 0)
	root.get_node("Clock").running = false
	root.get_node("Director").enabled = false
	var world := root.get_node("World")
	world.fade_enabled = false
	var scn: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scn)
	current_scene = scn
	world.enter_room("l16_s3_b0_f0_r1", "x:1100")
	for i in 10:
		await process_frame
	var player: Node3D = scn.get_player()
	var px := player.global_position.x
	var x := px - 3.8
	var npcs: Array = []
	for id in ids:
		var npc: Node3D = load("res://scenes/story/npc.tscn").instantiate()
		npc.setup(id)
		world.level().add_child(npc)
		npc.global_position.x = x
		npc.visible = true
		npc.set_physics_process(false)
		npcs.append(npc)
		x += 0.8
		if absf(x - px) < 0.6:
			x = px + 0.9 # leave room for the player
	var z := Zombie.spawn(world.level(), "zombieSlow", 1, px - 4.8)
	if z != null:
		z.set_physics_process(false)
	for i in 30:
		await process_frame
	var cam := root.get_viewport().get_camera_3d()
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(out.path_join("npcs.png"))
	print("saved npcs.png")
	# close shots: narrow the lens and slide along the line
	var line: Array = npcs.map(func(n): return n.global_position.x)
	var shot := 0
	var cx: float = line[0]
	while cx < line[line.size() - 1] + 0.5 and shot < 6:
		var rig := cam.get_parent()
		if rig != null and rig.has_method("set_physics_process"):
			rig.set_process(false)
			rig.set_physics_process(false)
		cam.fov = 14.0
		cam.global_position = Vector3(cx + 2.0, 1.6, 9.5)
		cam.global_rotation = Vector3.ZERO
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_viewport().get_texture().get_image().save_png(out.path_join("npcs_close%d.png" % shot))
		cx += 4.0
		shot += 1
	quit(0)
