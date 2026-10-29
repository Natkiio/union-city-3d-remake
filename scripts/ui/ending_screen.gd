class_name EndingScreen
extends UIScreen
## Shown by the story's showEnding action (the last trigger of quest 919):
## the end of the run, a short summary and the way back to the main menu.

signal to_menu


func _init() -> void:
	screen_title = "The End"
	panel_min = Vector2(520, 0)


func build() -> void:
	var tree := get_tree()
	var stats := tree.root.get_node_or_null("Stats")
	var clock := tree.root.get_node_or_null("Clock")
	var text := "The Cordon is down. You made it out of Cork."
	if stats != null and clock != null:
		text += "\n\nLevel %d, day %d." % [stats.level, clock.day()]
	var l := UITheme.label(text, UITheme.FS_BODY, UITheme.TEXT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 480
	body.add_child(l)
	var b := UITheme.button("Main menu", func():
		to_menu.emit()
		GameFlow.to_main_menu(get_tree()))
	b.name = "Btn_menu"
	body.add_child(b)


## The ending cannot be dismissed with Esc; only the button leaves.
func _unhandled_input(_event: InputEvent) -> void:
	pass
