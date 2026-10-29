extends "res://tests/test_base.gd"
## Level-up screen must close and unpause the game when Done is pressed.


func run() -> void:
	var world := autoload("World")
	world.fade_enabled = false
	autoload("Clock").running = false
	autoload("Director").enabled = false
	autoload("GameState").reset_run()
	world.reset()
	await load_scene("res://scenes/main.tscn")
	await frames(3)
	var ui = root.get_tree().get_first_node_in_group("ui_controller")
	check("ui controller exists", ui != null)
	var stats := autoload("Stats")
	stats.add_xp(stats.xp_to_next())
	await frames(5)
	check("paused while level-up open", paused)
	check("one screen open", ui.stack.size() == 1, str(ui.stack.size()))
	var s: Control = ui.top()
	var done_btn: Button = null
	for b in s.find_children("*", "Button", true, false):
		if b.text == "Done":
			done_btn = b
	var vp := root.get_visible_rect().size
	check("Done button is on screen", done_btn != null and done_btn.get_global_rect().end.y <= vp.y,
		"%s in %s" % [done_btn.get_global_rect() if done_btn else "none", vp])
	var btns := s.find_children("*", "Button", true, false)
	print("buttons: ", btns.map(func(b): return b.text))
	for b in btns:
		if b.text == "Done":
			b.pressed.emit()
	await frames(5)
	check("unpaused after Done", not paused)
	check("stack empty", ui.stack.is_empty())

	# Esc also closes a freshly opened level-up screen
	stats.add_xp(stats.xp_to_next())
	await frames(5)
	check("reopened", ui.stack.size() == 1)
	var esc := InputEventAction.new()
	esc.action = "ui_cancel"
	esc.pressed = true
	Input.parse_input_event(esc)
	await frames(5)
	check("Esc closes level-up", ui.stack.is_empty() and not paused)
