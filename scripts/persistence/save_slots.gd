extends Control
## Slot picker. Embed scenes/ui/save_slots.tscn, set `mode` and call open().
## Save mode lists the 3 manual slots (overwrite asks for confirmation); load
## mode also lists the autosave and disables empty slots. Delete asks too.
## Signals: slot_chosen(n) after a confirmed pick (the control does NOT save or
## load itself unless `auto_apply` is true), closed when dismissed.

signal slot_chosen(n: int)
signal closed

enum Mode { SAVE, LOAD }

@export var mode: Mode = Mode.LOAD
## When true the control calls SaveGame.save_slot / load_slot itself on pick.
@export var auto_apply: bool = false

var _list: VBoxContainer
var _title: Label
var _status: Label
var _confirm: ConfirmationDialog
var _pending_slot: int = -1
var _pending_delete: bool = false
var _save: Node = null  # the SaveGame node; replaceable in tests


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if _save == null:
		_save = get_node_or_null("/root/SaveGame")
	_build()
	refresh()


func open(new_mode: Mode) -> void:
	mode = new_mode
	visible = true
	if _list != null:
		refresh()


func set_save_node(node: Node) -> void:
	_save = node


func close() -> void:
	visible = false
	closed.emit()


func _build() -> void:
	if _list != null:
		return
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(520, 0)
	add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 22)
	box.add_child(_title)
	_list = VBoxContainer.new()
	box.add_child(_list)
	_status = Label.new()
	box.add_child(_status)
	var back := Button.new()
	back.name = "BackButton"
	back.text = "Back"
	back.pressed.connect(close)
	box.add_child(back)
	_confirm = ConfirmationDialog.new()
	_confirm.process_mode = Node.PROCESS_MODE_ALWAYS
	_confirm.confirmed.connect(_on_confirmed)
	add_child(_confirm)


func _slot_numbers() -> Array:
	var out: Array = []
	if mode == Mode.LOAD:
		out.append(0)
	for i in range(1, 4):
		out.append(i)
	return out


func slot_label(n: int) -> String:
	var title := "Autosave" if n == 0 else "Slot %d" % n
	var info: Dictionary = _save.slot_info(n)
	if info.is_empty():
		return "%s  -  empty" % title
	if info.get("corrupt", false):
		return "%s  -  unreadable" % title
	var when := Time.get_datetime_string_from_unix_time(int(info["saved_unix"]), true)
	return "%s  -  %s  Lv %d  %s  %s  played %s  (%s)" % [title, info["name"], info["level"],
		info["location"], info["clock_text"], Playtime.format(info["playtime_seconds"]), when]


func refresh() -> void:
	_title.text = "Save game" if mode == Mode.SAVE else "Load game"
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	for n in _slot_numbers():
		var row := HBoxContainer.new()
		row.name = "Row%d" % n
		var pick := Button.new()
		pick.name = "Pick"
		pick.text = slot_label(n)
		pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pick.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var has: bool = _save.has_slot(n)
		pick.disabled = (mode == Mode.LOAD and not has)
		pick.pressed.connect(choose.bind(n))
		row.add_child(pick)
		var del := Button.new()
		del.name = "Delete"
		del.text = "Delete"
		del.disabled = not has
		del.pressed.connect(request_delete.bind(n))
		row.add_child(del)
		_list.add_child(row)


## Same as pressing a slot. Overwriting a used slot in save mode asks first.
func choose(n: int) -> void:
	if mode == Mode.SAVE and n == 0:
		return  # the autosave slot is not a manual target
	if mode == Mode.SAVE and _save.has_slot(n):
		_pending_slot = n
		_pending_delete = false
		_confirm.dialog_text = "Overwrite slot %d?" % n
		_confirm.popup_centered()
		return
	_finish_pick(n)


func request_delete(n: int) -> void:
	_pending_slot = n
	_pending_delete = true
	_confirm.dialog_text = "Delete this save?"
	_confirm.popup_centered()


## Accepts whatever confirmation is pending (the dialog's OK button).
func _on_confirmed() -> void:
	var n := _pending_slot
	_pending_slot = -1
	if n < 0:
		return
	if _pending_delete:
		_save.delete_slot(n)
		refresh()
	else:
		_finish_pick(n)


func _finish_pick(n: int) -> void:
	if auto_apply:
		var ok: bool = _save.save_slot(n) if mode == Mode.SAVE else _save.load_slot(n)
		_status.text = "" if ok else "Failed: %s" % _save.last_error()
		if not ok:
			return
	slot_chosen.emit(n)
	refresh()
