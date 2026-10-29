extends SceneTree
## NOT a test. Windowed screenshot tool for the cutout demo.
##   godot --path . -s tests/capture_demo.gd [-- out_dir [backdrop_preset]]
## Saves stage_<name>.png for every demo stage to out_dir (default: user://) and quits.

const OUT_DEFAULT := "user://"

func _initialize() -> void:
	var out := OUT_DEFAULT
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DisplayServer.window_set_size(Vector2i(1600, 900))
	var demo: Node3D = load("res://scenes/chars/cutout_demo.tscn").instantiate()
	demo.set("frozen", true)
	if args.size() > 1:
		demo.set("backdrop_preset", args[1])
	root.add_child(demo)
	await process_frame
	await process_frame
	for i in demo.STAGES.size():
		demo.show_stage(i)
		for k in 4:
			await process_frame
		var img := root.get_viewport().get_texture().get_image()
		var path := out.path_join("stage_%s.png" % demo.STAGES[i])
		img.save_png(path)
		print("saved ", path, " ", img.get_size())
	quit()
