extends SceneTree
## Not a test: renders rooms with the player at given spots, saves PNGs.
##   godot --path . -s tests/capture_selectux.gd -- out=/tmp/selectux_after \
##       shots=l16_s3_b1_f1_r1@300,l16_s3_b1_f1_r1@900
## Each shot is <room id>@<player x in px>. Needs a display. Quits by itself.

## Spot: "u<units>", "npc", "link<N>" (nth link), "cont<N>" (nth container).
func _spot_x(world: Node, spot: String) -> float:
	var lvl: Node = world.level()
	if spot == "npc":
		for n in lvl.find_children("*", "", true, false):
			if n.is_in_group("npc"):
				return n.global_position.x
	if spot.begins_with("link"):
		return lvl.links()[int(spot.substr(4))].global_position.x
	if spot.begins_with("cont"):
		var i := int(spot.substr(4))
		for n in lvl.find_children("*", "", true, false):
			if n.has_method("search_now"):
				if i == 0:
					return n.global_position.x
				i -= 1
	return float(spot.substr(1))


func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var out: String = args.get("out", "/tmp/selectux_after")
	var shots: PackedStringArray = str(args.get("shots", "l16_s3_b1_f1_r1@300")).split(",")
	DirAccess.make_dir_recursive_absolute(out)
	await process_frame
	var clock := root.get_node("Clock")
	clock.set_time(12, 0)
	clock.running = false
	root.get_node("Director").enabled = false
	var world := root.get_node("World")
	world.fade_enabled = false
	var scn: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scn)
	current_scene = scn
	var n := 0
	for s in shots:
		var parts := s.split("@")
		world.enter_room(parts[0])
		for i in 5:
			await process_frame
		var spot := parts[1] if parts.size() > 1 else "u1"
		var px := _spot_x(world, spot)
		var p: Node3D = world.player()
		p.global_position = Vector3(px, 0.1, 0.0)
		p.velocity = Vector3.ZERO
		for i in 25:
			await process_frame
		var img := root.get_viewport().get_texture().get_image()
		var path := out.path_join("%02d_%s_%s.png" % [n, parts[0], parts[1] if parts.size() > 1 else "x"])
		img.save_png(path)
		print("saved ", path)
		n += 1
	quit(0)
