class_name DialogueBox
extends CanvasLayer
## Dialogue panel. It only displays the model it is handed and reports the
## button the player picked; it knows nothing about quests (see dialogue.gd).
##
## Model keys: npc (id), name, title, text, buttons [{action, label}],
## reward (line under the text), pause (bool, default true),
## auto_close (seconds after the text finishes; for caption lines, 0 = never).
## E or a click finishes the typewriter; once finished, E presses the button
## when there is exactly one. 1, 2, 3 press that button.

signal choice_made(action: String)
signal closed()

const CHARS_PER_SECOND := 90.0

var model: Dictionary = {}
var typing: bool = false
var free_on_close: bool = true

var _name_label: Label
var _title_label: Label
var _text: RichTextLabel
var _reward: Label
var _buttons: HBoxContainer
var _panel: PanelContainer
var _paused_by_me: bool = false
var _auto_left: float = -1.0


static func create() -> DialogueBox:
	return load("res://scenes/story/dialogue_box.tscn").instantiate() as DialogueBox


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 60
	_build()
	visible = false


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -380
	_panel.offset_right = 380
	_panel.offset_top = -360
	_panel.offset_bottom = -24
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.93, 0.89, 0.78)
	style.border_color = Color(0.2, 0.15, 0.1)
	style.set_border_width_all(3)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(14)
	_panel.add_theme_stylebox_override("panel", style)
	_panel.gui_input.connect(_on_panel_input)
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_panel.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	_name_label = Label.new()
	_name_label.add_theme_color_override("font_color", Color(0.15, 0.1, 0.05))
	_name_label.add_theme_font_size_override("font_size", 20)
	head.add_child(_name_label)
	_title_label = Label.new()
	_title_label.add_theme_color_override("font_color", Color(0.4, 0.33, 0.25))
	head.add_child(_title_label)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = false
	_text.scroll_active = true
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.custom_minimum_size = Vector2(0, 190)
	_text.add_theme_color_override("default_color", Color(0.1, 0.07, 0.04))
	_text.add_theme_font_size_override("normal_font_size", 17)
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_text)
	_reward = Label.new()
	_reward.add_theme_color_override("font_color", Color(0.35, 0.22, 0.05))
	box.add_child(_reward)
	_buttons = HBoxContainer.new()
	_buttons.alignment = BoxContainer.ALIGNMENT_END
	_buttons.add_theme_constant_override("separation", 12)
	box.add_child(_buttons)


## Shows a model (replacing any current one) and starts the typewriter.
func show_model(m: Dictionary) -> void:
	if _panel == null:
		_ready()
	var first := not visible
	model = m
	_name_label.text = str(m.get("name", "")).to_upper()
	_title_label.text = ("  " + str(m["title"]).to_upper()) if str(m.get("title", "")) != "" else ""
	_text.text = str(m.get("text", ""))
	_text.visible_ratio = 0.0
	typing = true
	_reward.text = str(m.get("reward", ""))
	_reward.visible = _reward.text != ""
	for c in _buttons.get_children():
		_buttons.remove_child(c)
		c.queue_free()
	var list: Array = m.get("buttons", [])
	for i in list.size():
		var b := Button.new()
		b.text = str(list[i].get("label", "OK"))
		b.pressed.connect(press_button.bind(i))
		b.visible = false
		_buttons.add_child(b)
	_auto_left = -1.0
	visible = true
	if m.get("pause", true) and not _paused_by_me and not get_tree().paused:
		get_tree().paused = true
		_paused_by_me = true
	if first and str(m.get("npc", "")) != "":
		_sys("Events").dialogue_started.emit(str(m["npc"]))
	if str(m.get("text", "")) == "":
		finish_text()


func _process(delta: float) -> void:
	if not visible:
		return
	if typing:
		var total := maxi(_text.get_total_character_count(), 1)
		_text.visible_ratio = minf(1.0, _text.visible_ratio + delta * CHARS_PER_SECOND / total)
		if _text.visible_ratio >= 1.0:
			finish_text()
	elif _auto_left > 0.0:
		_auto_left -= delta
		if _auto_left <= 0.0:
			close()


## Reveals all the text and shows the buttons.
func finish_text() -> void:
	typing = false
	_text.visible_ratio = 1.0
	for b in _buttons.get_children():
		b.visible = true
	var auto := float(model.get("auto_close", 0.0))
	if auto > 0.0:
		_auto_left = auto


## E / click: finish the typewriter, or press the only button.
func advance() -> void:
	if typing:
		finish_text()
	elif (model.get("buttons", []) as Array).size() == 1:
		press_button(0)


func press_button(index: int) -> void:
	var list: Array = model.get("buttons", [])
	if typing or index < 0 or index >= list.size():
		return
	choice_made.emit(str(list[index].get("action", "close")))


func close() -> void:
	if not visible and not _paused_by_me:
		return
	visible = false
	if _paused_by_me:
		get_tree().paused = false
		_paused_by_me = false
	var id := str(model.get("npc", ""))
	if id != "":
		_sys("Events").dialogue_ended.emit(id)
	closed.emit()
	if free_on_close:
		queue_free()


func _input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey or event is InputEventMouseButton):
		return
	if event.is_action_pressed("interact"):
		advance()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		var idx: int = event.keycode - KEY_1
		if idx >= 0 and idx < 3 and not typing:
			press_button(idx)
			get_viewport().set_input_as_handled()


func _on_panel_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		advance()

static func _sys(system: String) -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node(system)
