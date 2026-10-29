extends SceneTree
## Not a test: screenshots the comic-style dialogue boxes (windowed).
##   godot --path . -s tests/capture_dialogue.gd -- out=/tmp/comic_after

func _initialize() -> void:
	var out := "/tmp/comic_after"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.substr(4)
	DirAccess.make_dir_recursive_absolute(out)
	await process_frame
	root.get_node("SaveGame").autosave_enabled = false
	var world := root.get_node("World")
	world.fade_enabled = false
	world.start_new_game()
	for i in 20:
		await process_frame
	# (1) opening captions: run the cutscene until a box is visible
	for shot in ["caption_a", "caption_b", "caption_c"]:
		var found := false
		for i in 400:
			await process_frame
			for n in root.get_children():
				if n is DialogueBox and n.visible and not n.typing:
					found = true
			if found:
				break
		for i in 8:
			await process_frame
		_save(out, shot)
		if shot != "caption_c":
			for i in 90:
				await process_frame
	# (2) Fred's offer, (3) a plain chat
	for n in root.get_children():
		if n is DialogueBox:
			n.close()
	root.get_node("Director").enabled = false
	world.enter_location("16")
	for i in 20:
		await process_frame
	await _talk(world, "Fred", out, "fred")
	await _talk(world, "Anna", out, "chat")
	print("saved")
	quit(0)

func _talk(world: Node, id: String, out: String, tag: String) -> void:
	var scn := current_scene
	var player: Node3D = root.get_tree().get_first_node_in_group("player")
	var npc: Node3D = null
	for c in root.get_tree().get_nodes_in_group("npc"):
		if str(c.get("npc_id")) == id:
			npc = c
	if npc == null:
		var lvl: Node = world.level()
		npc = load("res://scenes/story/npc.tscn").instantiate()
		npc.setup(id)
		lvl.add_child(npc)
		npc.global_position = Vector3(player.global_position.x + 3.0, player.global_position.y, 0)
		npc.set_physics_process(false)
	npc.visible = true
	player.global_position.x = npc.global_position.x - 3.0
	for i in 10:
		await process_frame
	var box := Dialogue.open(root.get_tree(), id)
	if box == null:
		print("no dialogue for ", id)
		return
	for i in 300:
		await process_frame
	_save(out, tag)
	box.close()
	for i in 5:
		await process_frame

func _save(out: String, name: String) -> void:
	root.get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
