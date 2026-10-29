extends Control
## Spend-points screen shown after a level-up. Emits `done`. Scene: scenes/ui/level_up.tscn

signal done


func _ready() -> void:
	var box := ProgUI.backdrop(self)
	box.add_child(ProgUI.label("Level up!", 28))
	box.add_child(PointsPanel.new())
	box.add_child(ProgUI.button("Done", func(): done.emit()))
