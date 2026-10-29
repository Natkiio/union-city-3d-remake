extends CanvasLayer
## Full-screen death sequence: "YOU DIED" and the run summary fade in over the
## frozen game world, hold, then a black overlay slowly fades in on top of
## everything until the screen is solid black, then the main menu loads.
## Runs while the tree is paused, so it needs PROCESS_MODE_ALWAYS.
##
## The player resets the run (GameState.reset_run) before show_death(), so the
## summary is snapshotted from Events.player_died, which fires first.

@onready var background: ColorRect = $Background
@onready var label: Label = $Label

var summary_label: Label
var kills: int = 0
var summary: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	summary_label = UITheme.label("", UITheme.FS_BODY, UITheme.TEXT)
	summary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	summary_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	summary_label.anchor_top = 0.5
	summary_label.offset_top = 60.0
	summary_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	summary_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	summary_label.modulate.a = 0.0
	add_child(summary_label)
	Events.enemy_killed.connect(func(_r, _d, _x): kills += 1)
	Events.player_died.connect(snapshot)
	Events.run_reset.connect(func(): kills = 0)


## Records level, kills and days for the summary. Called on Events.player_died.
func snapshot() -> void:
	summary = {"level": Stats.level, "kills": kills, "days": maxi(Clock.day() - 1, 0)}


func summary_text() -> String:
	if summary.is_empty():
		snapshot()
	return "Level %d\nKills: %d\nDays survived: %d" % [summary.level, summary.kills, summary.days]


func show_death() -> void:
	visible = true
	background.modulate.a = 0.0
	label.modulate.a = 0.0
	summary_label.text = summary_text()
	summary_label.modulate.a = 0.0

	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(label, "modulate:a", 1.0, 0.6)
	tween.tween_property(summary_label, "modulate:a", 1.0, 0.4)
	tween.tween_interval(1.0)
	tween.tween_property(background, "modulate:a", 1.0, 2.5)
	tween.tween_interval(0.3)
	tween.tween_callback(_go_to_menu)


func _go_to_menu() -> void:
	summary = {}
	GameFlow.to_main_menu(get_tree())
	visible = false
	label.modulate.a = 0.0
	summary_label.modulate.a = 0.0
	background.modulate.a = 0.0
