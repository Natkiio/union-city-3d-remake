extends CanvasLayer
## The small panel opened by interact on a companion: give a weapon from the
## inventory (swapping theirs back), heal with a meds item, hold or follow,
## dismiss. Pauses the game while open. Registered on demand as /root/CompanionMenu.

var companion: Companion = null
var _panel: PanelContainer
var _list: VBoxContainer
var _title: Label


func _init() -> void:
	layer = 80
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func _ready() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(360, 0)
	add_child(_panel)
	var box := VBoxContainer.new()
	_panel.add_child(box)
	_title = Label.new()
	box.add_child(_title)
	_list = VBoxContainer.new()
	box.add_child(_list)


func open(c: Companion) -> void:
	companion = c
	visible = true
	get_tree().paused = true
	_rebuild()


func close() -> void:
	visible = false
	companion = null
	get_tree().paused = false


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact")):
		get_viewport().set_input_as_handled()
		close()


func _rebuild() -> void:
	for ch in _list.get_children():
		ch.queue_free()
	var c := companion
	_title.text = "%s  HP %d/%d  [%s]" % [str(c.def.get("name", c.npc_id)), int(c.health), int(c.max_health), c.gun.weapon.display_name]
	for item in weapon_options():
		_button("Give: %s" % item, func(): c.give_weapon(item); _rebuild())
	for item in heal_options():
		_button("Heal: %s" % item, func(): c.heal_with(item); _rebuild())
	_button("Follow me" if c.hold else "Hold position", func(): c.set_hold(not c.hold); _rebuild())
	_button("Dismiss", func(): Companions.remove(c.npc_id); close())
	_button("Close", close)


func weapon_options() -> Array:
	var out: Array = []
	for name in Inventory.items:
		if Weapon.find_by_name(name) != null:
			out.append(name)
	return out


func heal_options() -> Array:
	var out: Array = []
	if companion == null or companion.health >= companion.max_health:
		return out
	for name in Inventory.items:
		var info := Items.find(name)
		if not info.is_empty() and info["kind"] == "meds" and str(info["rec"].get("type", "health")) == "health":
			out.append(name)
	return out


func _button(text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	_list.add_child(b)
