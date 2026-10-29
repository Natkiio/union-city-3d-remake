extends Control
## Read-only attributes and skills sheet. Emits `closed`. Scene: scenes/ui/skills_sheet.tscn

signal closed


func _ready() -> void:
	var box := ProgUI.backdrop(self)
	var head := HBoxContainer.new()
	head.add_child(ProgUI.label("%s  (%s)" % [Stats.player_name if Stats.player_name != "" else "Survivor", Stats.background], 24))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	head.add_child(ProgUI.button("Close", func(): closed.emit()))
	box.add_child(head)
	var p := PointsPanel.new()
	p.allow_spend = false
	box.add_child(ProgUI.scrolled(p))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("open_skills"):
		get_viewport().set_input_as_handled()
		closed.emit()
