extends SceneTree
## Not a test: screenshots the level-up screen and the skills sheet.
##   godot --path . -s tests/capture_levelup.gd -- out=/tmp/levelup_after

func _initialize() -> void:
	var out := "/tmp/levelup_after"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.substr(4)
	DirAccess.make_dir_recursive_absolute(out)
	await process_frame
	var sg := root.get_node_or_null("SaveGame")
	if sg: sg.autosave_enabled = false
	var world := root.get_node("World")
	world.fade_enabled = false
	var stats := root.get_node("Stats")
	if stats.has_method("set_background"):
		stats.set_background("farmer")
	stats.player_name = "Seán"
	world.start_new_game()
	for i in 30:
		await process_frame
	var ui := root.get_tree().get_first_node_in_group("ui_controller")
	for n in root.get_tree().get_nodes_in_group("run_overlay"):
		n.queue_free()
	stats.add_xp(stats.xp_to_next())
	for i in 20:
		await process_frame
	stats.spend_attr("strength")
	stats.spend_skill("blunt")
	stats.spend_skill("blunt")
	for i in 10:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out.path_join("levelup.png"))
	ui.top().done.emit()
	for i in 5:
		await process_frame
	ui.open_skills() if ui.has_method("open_skills") else null
	for i in 20:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out.path_join("sheet.png"))
	print("saved")
	quit(0)
