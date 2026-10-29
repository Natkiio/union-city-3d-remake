class_name StrugglePrompt
extends CanvasLayer
## On-screen prompt while a zombie holds the player: "Mash A / D" and a bar of
## struggle progress. Created by the player on start_grab and freed on end_grab.
## Key names come from the move_left / move_right bindings (Q on AZERTY).

var zombie: Node = null
var label: Label
var bar: ProgressBar
var _text: String = ""


func _ready() -> void:
	layer = 20
	label = Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 0)
	label.position = Vector2(0, 120)
	label.add_theme_font_size_override("font_size", 28)
	add_child(label)
	bar = ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(260, 18)
	bar.position = Vector2(0, 170)
	add_child(bar)
	_update()


func setup(grabber: Node) -> void:
	zombie = grabber
	if label != null:
		_update()


func _process(_delta: float) -> void:
	_update()


## Text for the prompt, e.g. "Mash A / D".
static func prompt_text() -> String:
	return "Mash %s / %s" % [key_name("move_left"), key_name("move_right")]


## Display name of the first key bound to an action ("A"), or the action name.
static func key_name(action: String) -> String:
	if InputMap.has_action(action):
		for ev in InputMap.action_get_events(action):
			if ev is InputEventKey:
				var code: Key = ev.physical_keycode if ev.physical_keycode != KEY_NONE else ev.keycode
				# Physical keycode mapped through the user's layout: Q on AZERTY.
				if DisplayServer.get_name() == "headless":
					return OS.get_keycode_string(code)
				var layout_code: Key = DisplayServer.keyboard_get_keycode_from_physical(code)
				return OS.get_keycode_string(layout_code if layout_code != KEY_NONE else code)
	return action


## Struggle progress 0..1 (0 when there is nothing to show).
func progress() -> float:
	if zombie == null or not is_instance_valid(zombie) or zombie.get("struggle") == null:
		return 0.0
	var s: Struggle = zombie.struggle
	return clampf(float(s.presses) / float(maxi(s.presses_needed, 1)), 0.0, 1.0)


func _update() -> void:
	if label == null:
		return
	if _text == "":
		_text = prompt_text()
	label.text = _text
	bar.max_value = 1.0
	bar.value = progress()
	var width := get_viewport().get_visible_rect().size.x
	label.position.x = (width - label.size.x) / 2.0
	bar.position.x = (width - bar.size.x) / 2.0
