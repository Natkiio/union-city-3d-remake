extends Control
## Title screen: Start begins a fresh game (and resets any run state
## left over from a previous life), Quit exits the app.

@onready var start_button: Button = $Panel/VBox/StartButton
@onready var quit_button: Button = $Panel/VBox/QuitButton

func _ready() -> void:
	start_button.pressed.connect(_on_start_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	start_button.grab_focus()

func _on_start_pressed() -> void:
	_reset_run_state()
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_quit_pressed() -> void:
	get_tree().quit()

func _reset_run_state() -> void:
	Inventory.items.clear()
	Inventory.inventory_changed.emit()
	LootState.looted.clear()
	LootState.trunk_contents.clear()
	GameState.has_pending_spawn = false
	GameState.equipped_weapon = "fist"
