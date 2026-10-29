extends Control
## Spend-points screen shown after a level-up. Emits `done`. Scene: scenes/ui/level_up.tscn
## Enter or Esc closes it; "+" buttons are keyboard-focusable.

signal done


func _ready() -> void:
	var box := ProgUI.sheet(self, Vector2(1260, 0))
	var panel := PointsPanel.new()
	box.add_child(panel)
	var btn := UITheme.button("Done", func(): done.emit())
	btn.custom_minimum_size = Vector2(320, 52)
	btn.add_theme_font_size_override("font_size", 22)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(btn)
	var hint := UITheme.label("Enter or Esc to close. Hover a stat for details.", UITheme.FS_SMALL, UITheme.TEXT_DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)
	panel.fallback_focus = btn
	btn.grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		done.emit()
