extends SceneTree
## Base for headless tests. A test is a script that extends this file and
## overrides run():
##
##   extends "res://tests/test_base.gd"
##   func run() -> void:
##       check("one is one", 1 == 1)
##
## Run one:  godot --headless --path . -s tests/test_foo.gd
## Run all:  tools/run_tests.sh
## Exit code is the number of failed checks (capped at 1).

var results: Array = []


func check(test_name: String, ok: bool, detail: String = "") -> void:
	results.append([test_name, ok, detail])
	print("[%s] %s %s" % ["PASS" if ok else "FAIL", test_name, detail])


func frames(n: int) -> void:
	for i in n:
		await physics_frame


func seconds(t: float) -> void:
	await create_timer(t, true, true).timeout


## Instantiates a scene as the current scene (change_scene_to_file does not
## work from a -s script). Returns the instance.
func load_scene(path: String) -> Node:
	var scn: Node = load(path).instantiate()
	root.add_child(scn)
	current_scene = scn
	await frames(5)
	return scn


## Autoload by name, e.g. autoload("Inventory").
func autoload(autoload_name: String) -> Node:
	return root.get_node(autoload_name)


func run() -> void:
	pass


func _initialize() -> void:
	await frames(2) # autoloads are not inside the tree yet during _initialize
	# Tests must never write real saves: no autosaves, and a throwaway directory.
	var sg: Node = root.get_node_or_null("SaveGame")
	if sg != null:
		sg.autosave_enabled = false
		sg.save_dir = "user://test_saves"
	await run()
	var fails := 0
	for r in results:
		if not r[1]:
			fails += 1
	print("=== %d checks, %d failed" % [results.size(), fails])
	quit(1 if fails > 0 else 0)
