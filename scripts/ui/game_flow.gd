class_name GameFlow
extends RefCounted
## Game flow: main menu -> character creation -> World.start_new_game(), load,
## and back to the menu. Static, autoload-free. Scene changes and quit go
## through overridable Callables so tests can run the flow without leaving
## their SceneTree.

const MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const CREATE_SCENE := "res://scenes/ui/character_create.tscn"
const RUN_SCENE := "res://scenes/main.tscn"
const SLOT_COUNT := 3

## Callable(path: String); empty means SceneTree.change_scene_to_file.
static var scene_changer: Callable = Callable()
## Callable(); empty means SceneTree.quit.
static var quitter: Callable = Callable()


static func change_scene(tree: SceneTree, path: String) -> void:
	if scene_changer.is_valid():
		scene_changer.call(path)
	else:
		tree.change_scene_to_file(path)


static func quit(tree: SceneTree) -> void:
	if quitter.is_valid():
		quitter.call()
	else:
		tree.quit()


static func _autoload(tree: SceneTree, n: String) -> Node:
	return tree.root.get_node_or_null(n)


## Wipes the previous run and opens character creation as a child of `host`.
## Returns the creation screen. When it emits `confirmed` the world starts.
static func new_game(host: Node) -> Node:
	var gs := _autoload(host.get_tree(), "GameState")
	if gs != null:
		gs.reset_run()
	var screen: Node = load(CREATE_SCENE).instantiate()
	host.add_child(screen)
	if screen.has_signal("confirmed"):
		screen.confirmed.connect(func():
			screen.queue_free()
			start_world(host.get_tree()))
	return screen


## Hands over to the world workstream, or to the old test street until it lands.
static func start_world(tree: SceneTree) -> void:
	var world := _autoload(tree, "World")
	if world != null and world.has_method("start_new_game"):
		world.start_new_game()
	else:
		change_scene(tree, RUN_SCENE)


static func save_api() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return _autoload(tree, "SaveGame") if tree != null else null


static func saves_available() -> bool:
	var sg := save_api()
	return sg != null and sg.has_method("has_slot") and sg.has_method("load_slot")


static func any_slot() -> bool:
	if not saves_available():
		return false
	var sg := save_api()
	for n in SLOT_COUNT:
		if sg.has_slot(n):
			return true
	return false


## Loads slot n and enters the saved room. False if saving is unavailable or
## the load failed.
static func load_game(tree: SceneTree, n: int) -> bool:
	if not saves_available():
		return false
	var sg := save_api()
	if not sg.load_slot(n):
		return false
	var world := _autoload(tree, "World")
	if world != null and world.has_method("enter_loaded_game"):
		world.enter_loaded_game()
	else:
		change_scene(tree, RUN_SCENE)
	return true


static func save_game(n: int) -> bool:
	var sg := save_api()
	return sg != null and sg.has_method("save_slot") and bool(sg.save_slot(n))


static func to_main_menu(tree: SceneTree) -> void:
	tree.paused = false
	change_scene(tree, MENU_SCENE)
