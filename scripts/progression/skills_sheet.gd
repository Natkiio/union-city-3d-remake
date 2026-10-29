extends Control
## Read-only attributes and skills sheet. Emits `closed`. Scene: scenes/ui/skills_sheet.tscn

signal closed


func _ready() -> void:
	var box := ProgUI.backdrop(self)
	box.add_child(ProgUI.label("%s  (%s)" % [Stats.player_name if Stats.player_name != "" else "Survivor", Stats.background], 24))
	var p := PointsPanel.new()
	p.allow_spend = false
	box.add_child(p)
	box.add_child(ProgUI.button("Close", func(): closed.emit()))
