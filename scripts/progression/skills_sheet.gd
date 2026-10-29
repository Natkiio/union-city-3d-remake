extends Control
## Read-only attributes and skills sheet. Emits `closed`. Scene: scenes/ui/skills_sheet.tscn

signal closed


func _ready() -> void:
	var box := ProgUI.sheet(self, Vector2(1260, 0))
	var p := PointsPanel.new()
	p.allow_spend = false
	box.add_child(p)
	var btn := UITheme.button("Close", func(): closed.emit())
	btn.custom_minimum_size = Vector2(320, 52)
	btn.add_theme_font_size_override("font_size", 22)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(btn)
	btn.grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("open_skills"):
		get_viewport().set_input_as_handled()
		closed.emit()
