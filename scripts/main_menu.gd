extends Control
## Title screen: New Game (character creation, then the world), Continue
## (slot list), Settings, Quit. The flow itself lives in GameFlow.

var new_button: Button
var continue_button: Button
var settings_button: Button
var quit_button: Button
var overlay: Control = null


func _ready() -> void:
	theme = UITheme.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Settings.apply(get_tree())
	var bg := ColorRect.new()
	bg.color = UITheme.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(col)
	var title := UITheme.label("CORK CITY", UITheme.FS_TITLE, UITheme.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var sub := UITheme.label("Cork. Samhain week. The Cordon is closed.", UITheme.FS_BODY, UITheme.TEXT_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)
	col.add_child(Control.new())
	new_button = _add(col, "New Game", _on_new)
	continue_button = _add(col, "Continue", _on_continue)
	continue_button.disabled = not GameFlow.any_slot()
	settings_button = _add(col, "Settings", _on_settings)
	quit_button = _add(col, "Quit", _on_quit)
	new_button.grab_focus()


func _add(parent: Node, text: String, cb: Callable) -> Button:
	var b := UITheme.button(text, cb)
	b.custom_minimum_size = Vector2(260, 46)
	parent.add_child(b)
	return b


func _on_new() -> void:
	overlay = GameFlow.new_game(self)


func _on_continue() -> void:
	_open_overlay(SlotList.new("load"))


func _on_settings() -> void:
	_open_overlay(SettingsScreen.new())


func _on_quit() -> void:
	GameFlow.quit(get_tree())


func _open_overlay(screen: UIScreen) -> void:
	overlay = screen
	screen.closed.connect(func():
		screen.queue_free()
		overlay = null
		new_button.grab_focus())
	add_child(screen)
