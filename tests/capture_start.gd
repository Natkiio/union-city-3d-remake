extends SceneTree
## Not a test: screenshots the first seconds after starting a new game.
##   godot --path . -s tests/capture_start.gd -- out=/tmp/startshots

func _initialize() -> void:
	var out := "/tmp/startshots"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.substr(4)
	DirAccess.make_dir_recursive_absolute(out)
	await process_frame
	root.get_node("SaveGame").autosave_enabled = false
	var world := root.get_node("World")
	world.fade_enabled = false
	world.start_new_game()
	for shot in [10, 60, 150]:
		for i in shot:
			await process_frame
		root.get_viewport().get_texture().get_image().save_png(out.path_join("start_%d.png" % shot))
	print("saved")
	quit(0)
