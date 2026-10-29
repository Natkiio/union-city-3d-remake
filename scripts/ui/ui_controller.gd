class_name UIController
extends CanvasLayer
## In-run screen manager. Added by the HUD. Owns the overlay stack, pauses the
## tree while any screen is open, and maps the input actions pause, open_map,
## sleep_wait and open_skills plus Events.level_up to screens.

const LEVEL_UP_SCENE := "res://scenes/ui/level_up.tscn"
const SKILLS_SCENE := "res://scenes/ui/skills_sheet.tscn"

var stack: Array[Control] = []
var _was_paused: bool = false


func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("ui_controller")
	var ev := get_node_or_null("/root/Events")
	if ev != null:
		ev.level_up.connect(func(_lvl: int): open_level_up())


func is_open() -> bool:
	return not stack.is_empty()


func top() -> Control:
	return stack.back() if not stack.is_empty() else null


func open(screen: Control) -> Control:
	if stack.is_empty():
		_was_paused = get_tree().paused
		get_tree().paused = true
	stack.append(screen)
	add_child(screen)
	if screen.has_signal("closed"):
		screen.closed.connect(func(): close(screen))
	elif screen.has_signal("done"):
		screen.done.connect(func(): close(screen))
	return screen


func close(screen: Control) -> void:
	stack.erase(screen)
	if is_instance_valid(screen):
		screen.queue_free()
	if stack.is_empty():
		get_tree().paused = _was_paused


func close_all() -> void:
	for s in stack.duplicate():
		close(s)


func _blocked() -> bool:
	# Another system (trunk, inventory) or the death screen has the game paused.
	var death := get_node_or_null("/root/DeathScreen")
	if death != null and death.visible:
		return true
	return stack.is_empty() and get_tree().paused


func _unhandled_input(event: InputEvent) -> void:
	if _blocked():
		return
	if event.is_action_pressed("pause") and stack.is_empty():
		open_pause()
	elif event.is_action_pressed("open_map"):
		if top() is MapScreen:
			close(top())
		elif stack.is_empty():
			open_map()
	elif event.is_action_pressed("sleep_wait") and stack.is_empty():
		open_sleep()
	elif event.is_action_pressed("open_skills"):
		if top() is Control and top().has_signal("closed") and top().get_script() != null and top().get_script().resource_path.contains("skills"):
			close(top())
		elif stack.is_empty():
			open_skills()
	else:
		return
	get_viewport().set_input_as_handled()


func open_pause() -> Control:
	var m := PauseMenu.new()
	m.choice.connect(func(what: String): _pause_choice(m, what))
	return open(m)


func _pause_choice(menu: PauseMenu, what: String) -> void:
	match what:
		"resume":
			close(menu)
		"save":
			open(SlotList.new("save"))
		"load":
			var sl := SlotList.new("load")
			sl.slot_chosen.connect(func(_n: int): call_deferred("close_all"))
			open(sl)
		"journal":
			open(QuestLog.new())
		"settings":
			open(SettingsScreen.new())
		"menu":
			close_all()
			GameFlow.to_main_menu(get_tree())


func open_map() -> Control:
	return open(MapScreen.new())


func open_sleep() -> Control:
	if not SleepDialog.available(get_tree()):
		var hud := get_tree().get_first_node_in_group("hud")
		if hud != null and hud.has_method("toast"):
			hud.toast("You can only rest in a safehouse.")
		return null
	return open(SleepDialog.new())


func open_skills() -> Control:
	return _open_scene(SKILLS_SCENE)


func open_level_up() -> Control:
	return _open_scene(LEVEL_UP_SCENE)


func _open_scene(path: String) -> Control:
	var s: Node = load(path).instantiate()
	return open(s as Control)
