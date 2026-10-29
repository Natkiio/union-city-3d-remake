class_name UIScreen
extends Control
## Base for overlay screens: full-rect dim backdrop, centred panel, a title,
## a `closed` signal. Subclasses fill `body` in build(). Works while paused.

signal closed

var body: VBoxContainer
var panel: PanelContainer
var screen_title: String = ""
var panel_min: Vector2 = Vector2(420, 0)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = UITheme.theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = UITheme.DIM
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	panel = PanelContainer.new()
	panel.custom_minimum_size = panel_min
	center.add_child(panel)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	panel.add_child(body)
	if screen_title != "":
		body.add_child(UITheme.label(screen_title, UITheme.FS_HEAD, UITheme.ACCENT_HI))
	build()


func build() -> void:
	pass


func close() -> void:
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		close()


func add_row(left: String, right: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := UITheme.label(left)
	l.custom_minimum_size.x = 150
	row.add_child(l)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	body.add_child(row)
	return row
