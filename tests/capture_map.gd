extends SceneTree
## Not a test: starts a new game, opens the map and saves PNGs. Needs a display.
##   godot --path . -s tests/capture_map.gd -- out=/tmp/mapfix_after [unlock]

func _initialize() -> void:
	var out := "/tmp/mapfix_after"
	var unlock_all := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.substr(4)
		if a == "unlock":
			unlock_all = true
	DirAccess.make_dir_recursive_absolute(out)
	await process_frame
	root.get_node("SaveGame").autosave_enabled = false
	var world := root.get_node("World")
	world.fade_enabled = false
	world.start_new_game()
	for i in 60:
		await process_frame
	if unlock_all:
		for i in range(1, 17):
			root.get_node("Quests").unlock_section(str(i)) if root.get_node("Quests").has_method("unlock_section") else null
	var ctl := get_first_node_in_group("ui_controller")
	var m = ctl.open_map()
	for i in 10:
		await process_frame
	for n in m.map_nodes:
		print(n.id, " ", n.name, " raw=", n.pos, " screen=", m.node_screen_pos(n) if m.has_method("node_screen_pos") else n.pos, " unlocked=", n.unlocked)
	m.select("9")
	for i in 5:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out.path_join("map_%s.png" % ("all" if unlock_all else "fresh")))
	print("saved")
	quit(0)
