extends Control
## Spend-points screen shown after a level-up. Emits `done`. Scene: scenes/ui/level_up.tscn
## The Done button sits above the scrolling list so it is always reachable.

signal done


func _ready() -> void:
	var box := ProgUI.backdrop(self)
	var head := HBoxContainer.new()
	head.add_child(ProgUI.label("Level up!", 28))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	head.add_child(ProgUI.button("Done", func(): done.emit()))
	box.add_child(head)
	box.add_child(ProgUI.scrolled(PointsPanel.new()))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		done.emit()
