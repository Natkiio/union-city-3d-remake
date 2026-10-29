class_name SettingsScreen
extends UIScreen
## Volumes, brightness, difficulty toggles and a key list. Writes through
## Settings (user://settings.cfg) and applies immediately.

var sliders: Dictionary = {}
var head_shots: CheckBox
var mode_pick: OptionButton


func _init() -> void:
	screen_title = "Settings"
	panel_min = Vector2(480, 0)


func build() -> void:
	for b in Settings.BUSES:
		var s := _slider(float(Settings.get_value("volume_" + b)))
		s.value_changed.connect(func(v: float): _set("volume_" + b, v))
		sliders["volume_" + b] = s
		add_row("%s volume" % b, s)
	var br := _slider(float(Settings.get_value("brightness")))
	br.value_changed.connect(func(v: float): _set("brightness", v))
	sliders["brightness"] = br
	add_row("Brightness", br)
	head_shots = CheckBox.new()
	head_shots.text = "Head shots only"
	head_shots.button_pressed = bool(Settings.get_value("head_shots_only"))
	head_shots.toggled.connect(func(on: bool): _set("head_shots_only", on))
	body.add_child(head_shots)
	mode_pick = OptionButton.new()
	mode_pick.add_item("Survivor (hunger and sleep)")
	mode_pick.add_item("Run'n'Gun (more ammo)")
	mode_pick.selected = 1 if Settings.get_value("mode") == "runngun" else 0
	mode_pick.item_selected.connect(func(i: int): _set("mode", "runngun" if i == 1 else "survivor"))
	add_row("Mode", mode_pick)
	var keys := GridContainer.new()
	keys.columns = 4
	keys.add_theme_constant_override("h_separation", 14)
	for k in Settings.KEY_HINTS:
		keys.add_child(UITheme.label(k[0], UITheme.FS_SMALL, UITheme.WARN))
		keys.add_child(UITheme.label(k[1], UITheme.FS_SMALL, UITheme.TEXT_DIM))
	body.add_child(keys)
	body.add_child(UITheme.button("Back", close))


func _slider(v: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = v
	s.custom_minimum_size = Vector2(200, 22)
	return s


func _set(key: String, value: Variant) -> void:
	Settings.set_value(key, value)
	Settings.apply(get_tree())


func close() -> void:
	Settings.save()
	super.close()
