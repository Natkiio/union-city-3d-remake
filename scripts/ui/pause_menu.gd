class_name PauseMenu
extends UIScreen
## Pause menu. Emits `choice` with "resume", "save", "load", "journal",
## "settings" or "menu"; the UIController (or a test) acts on it.

signal choice(what: String)


func _init() -> void:
	screen_title = "Paused"
	panel_min = Vector2(300, 0)


func build() -> void:
	for pair in [["Resume", "resume"], ["Save", "save"], ["Load", "load"], ["Journal", "journal"],
			["Settings", "settings"], ["Quit to menu", "menu"]]:
		var what: String = pair[1]
		var b := UITheme.button(pair[0], func(): choice.emit(what))
		b.name = "Btn_" + what
		body.add_child(b)
	(body.get_child(1) as Control).call_deferred("grab_focus")
