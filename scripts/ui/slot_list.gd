class_name SlotList
extends UIScreen
## Save slots. mode "load" loads the slot and enters the game; mode "save"
## writes to it. Talks to SaveGame only through has_slot / slot_info /
## load_slot / save_slot, each guarded with has_method.

signal slot_chosen(n: int)

var mode: String = "load"
var _msg: Label


func _init(slot_mode: String = "load") -> void:
	mode = slot_mode
	screen_title = "Load game" if mode == "load" else "Save game"
	panel_min = Vector2(520, 0)


func build() -> void:
	var sg := GameFlow.save_api()
	var api_ok := GameFlow.saves_available()
	if mode == "save":
		api_ok = sg != null and sg.has_method("save_slot")
	if not api_ok:
		body.add_child(UITheme.label("Saving is not available yet.", UITheme.FS_BODY, UITheme.TEXT_DIM))
	# Slot 0 is the autosave (load only); 1..SLOT_COUNT are manual slots.
	for n in range(0 if mode == "load" else 1, GameFlow.SLOT_COUNT + 1):
		var label := "Autosave" if n == 0 else "Slot %d" % n
		var text := "%s   (empty)" % label
		var filled := false
		if api_ok and sg.has_method("has_slot") and sg.has_slot(n):
			filled = true
			var info: Dictionary = sg.slot_info(n) if sg.has_method("slot_info") else {}
			if info.get("corrupt", false):
				filled = false
				text = "%s   (damaged)" % label
			else:
				text = "%s   %s  Lv %s  %s  %s" % [label, info.get("name", "Survivor"),
					info.get("level", "?"), info.get("location", ""), info.get("clock_text", info.get("clock", ""))]
		var b := UITheme.button(text, func(): _choose(n))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = (not api_ok) or (mode == "load" and not filled)
		b.name = "Slot%d" % n
		body.add_child(b)
	_msg = UITheme.label("", UITheme.FS_SMALL, UITheme.WARN)
	body.add_child(_msg)
	body.add_child(UITheme.button("Back", close))


func _choose(n: int) -> void:
	slot_chosen.emit(n)
	if mode == "load":
		if not GameFlow.load_game(get_tree(), n):
			_msg.text = "Could not load that save."
	else:
		_msg.text = "Saved to slot %d." % n if GameFlow.save_game(n) else "Save failed."
