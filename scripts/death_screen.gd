extends CanvasLayer
## Full-screen death sequence: "YOU DIED" fades in over the frozen
## game world, holds, then a black overlay slowly fades in on top of
## everything (world + text) until the screen is solid black, then
## the main menu loads. Runs while the tree is paused, so it needs
## PROCESS_MODE_ALWAYS to actually animate.

@onready var background: ColorRect = $Background
@onready var label: Label = $Label

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

func show_death() -> void:
	visible = true
	background.modulate.a = 0.0
	label.modulate.a = 0.0

	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(label, "modulate:a", 1.0, 0.6)
	tween.tween_interval(1.0)
	tween.tween_property(background, "modulate:a", 1.0, 2.5)
	tween.tween_interval(0.3)
	tween.tween_callback(_go_to_menu)

func _go_to_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
	visible = false
	label.modulate.a = 0.0
	background.modulate.a = 0.0
