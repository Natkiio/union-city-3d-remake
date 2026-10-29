extends "res://tests/test_base.gd"
## Persistence workstream: save format, slots, round trip of every stateful
## system, corruption, migration, atomic write, autosave rules, quick keys,
## slot picker.

const DIR := "user://saves_test"

var sg: Node


class FakeSystem extends Node:
	var value: Dictionary = {"a": 1}
	func _ready() -> void:
		add_to_group("stateful")
	func reset() -> void:
		value = {"a": 1}
	func to_dict() -> Dictionary:
		return {"value": value.duplicate(true)}
	func from_dict(d: Dictionary) -> void:
		value = d.get("value", {}).duplicate(true)


func _clean() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var d := DirAccess.open(DIR)
	for f in d.get_files():
		d.remove(f)


func _write(n: int, text: String) -> void:
	var f := FileAccess.open(sg.slot_path(n), FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _all_dicts() -> Dictionary:
	var out := {}
	for node in root.get_tree().get_nodes_in_group("stateful"):
		if node != sg:
			out[str(node.name)] = node.to_dict()
	return out


func _rich_state() -> void:
	var stats := autoload("Stats")
	stats.set_background(stats.background_refs()[0])
	stats.add_xp(1000000)  # climbs levels
	for i in 4:
		stats.spend_attr("strength")
	for i in 6:
		stats.spend_skill("pistols")
	stats.set_identity("Aoife", "female")
	stats.level = 7
	stats.xp = 321
	autoload("Clock").game_minutes = 1440 + 61 * 24 + 17
	var surv := autoload("Survival")
	surv.hunger = 40.0
	surv.sleep = 12.5
	var inv := autoload("Inventory")
	inv.add_item("Glock 17", 2.0, 1)
	inv.add_item("9mm Ammo", 0.1, 37)
	inv.add_item("Bandage", 0.3, 4)
	inv.set_magazine("Glock 17", 9)
	inv.equipped_clothing = {"top": "Hoodie"}
	inv.book_points = {"pistols": 3}
	var ls := autoload("LootState")
	ls.mark_looted("Street/crate1")
	ls.save_trunk_contents("Street/car", [{"name": "Rope", "weight": 1.5, "count": 2}])
	var d := autoload("Director")
	d.rush_active = true
	d.rush_start = 1700.0
	d.last_rush_time = 1650.0
	d.on_break = true
	d.break_start = 1800.0
	d.break_length = 12
	d.spawned_since_break = 5
	d.droppers = 2
	d.last_drop_time = 1600.0
	d.area_visits = {"l1/street": 1500.0}
	d._fallback_minutes = 1777.5
	autoload("Sfx").set_volume("Master", 0.5)


func run() -> void:
	sg = autoload("SaveGame")
	sg.save_dir = DIR
	sg.autosave_enabled = false
	_clean()
	var events := autoload("Events")
	var game_state := autoload("GameState")

	# --- format helpers ---
	check("normalize whole floats to int", SaveFormat.normalize({"a": 3.0, "b": [2.0, 2.5]}) == {"a": 3, "b": [2, 2.5]})
	check("deep_equal 3 vs 3.0", SaveFormat.deep_equal({"a": 3}, {"a": 3.0}))
	check("deep_equal catches difference", not SaveFormat.deep_equal({"a": [1, 2]}, {"a": [1, 3]}))
	check("playtime format", Playtime.format(3900) == "1h 05m" and Playtime.format(723) == "12m 03s")

	# --- empty slots ---
	check("no slot yet", not sg.has_slot(1) and sg.slot_info(1).is_empty())
	check("bad slot rejected", not sg.save_slot(9) and not sg.has_slot(-1))
	check("load empty slot fails", not sg.load_slot(1))

	# --- round trip ---
	game_state.reset_run()
	_rich_state()
	var fake := FakeSystem.new()
	fake.name = "FakeSystem"
	root.add_child(fake)
	fake.value = {"a": 7, "list": [1, 2.5, "x"]}
	var prov := {"hp": 33.5, "pos": [1.5, 0.0, 0.0], "room": "l1/bar"}
	var restored := [{}]
	sg.register_provider("Player", func(): return prov.duplicate(true), func(d): restored[0] = d)
	sg.playtime.seconds = 3725.0
	var before := _all_dicts()
	check("rich state has stats level 7", before["Stats"]["level"] == 7)
	check("saved", sg.save_slot(2))
	check("slot exists", sg.has_slot(2) and not FileAccess.file_exists(sg.slot_path(2) + ".tmp"))
	var info: Dictionary = sg.slot_info(2)
	check("slot_info name/level", info["name"] == "Aoife" and info["level"] == 7, str(info))
	check("slot_info clock/playtime", info["clock_text"].begins_with("Day ") and is_equal_approx(info["playtime_seconds"], 3725.0), str(info))
	check("slot_info saved_unix", info["saved_unix"] > 1700000000)
	var raw := FileAccess.get_file_as_string(sg.slot_path(2))
	check("file is readable json with version", raw.contains("\"version\": 1") and raw.contains("\"game\": \"cork\"") and raw.contains("\t"))
	var parsed: Dictionary = JSON.parse_string(raw)
	for sname in ["Stats", "Clock", "Survival", "Inventory", "LootState", "Director", "FakeSystem"]:
		check("systems has " + sname, parsed["systems"].has(sname))
	check("SaveGame not saved inside itself", not parsed["systems"].has("SaveGame"))
	check("provider saved", parsed["providers"].has("Player"))

	game_state.reset_run()
	fake.value = {"zzz": 0}
	restored[0] = {}
	check("reset really changed state", autoload("Stats").level == 1 and autoload("Inventory").items.is_empty())
	check("load ok", sg.load_slot(2))
	var after := _all_dicts()
	for sname in before:
		check("round trip " + sname, SaveFormat.deep_equal(before[sname], after[sname]),
			"" if SaveFormat.deep_equal(before[sname], after[sname]) else "\n  before=%s\n  after=%s" % [before[sname], after[sname]])
	check("provider restored", SaveFormat.deep_equal(restored[0], prov), str(restored[0]))
	check("playtime restored", is_equal_approx(sg.playtime.seconds, 3700.0 + 25.0) or absf(sg.playtime.seconds - 3725.0) < 1.0)
	check("inventory counts are ints", typeof(autoload("Inventory").items["9mm Ammo"]["count"]) == TYPE_INT)

	# second round trip is stable
	var again: Dictionary = sg.snapshot()["systems"]
	for sname in before:
		check("second round trip " + sname, SaveFormat.deep_equal(before[sname], again[sname]))

	# --- load order ---
	var order: Array = sg._ordered_names(["World", "Zed", "Stats", "Director", "Aaa", "Clock"])
	check("load order", order == ["Stats", "Clock", "Director", "World", "Aaa", "Zed"], str(order))
	check("World last of listed", sg.LOAD_ORDER[-1] == "World" and sg.LOAD_ORDER[0] == "Stats")

	# --- missing and unknown systems ---
	var snap: Dictionary = sg.snapshot()
	snap["systems"].erase("Survival")
	snap["systems"]["Nonexistent"] = {"x": 1}
	_write(3, JSON.stringify(snap))
	autoload("Survival").hunger = 99.0
	check("load with missing/unknown system", sg.load_slot(3))
	check("missing system uses reset()", autoload("Survival").hunger == 0.0)
	check("others still loaded", autoload("Stats").level == 7)

	# --- corruption: running game untouched ---
	var level_now: int = autoload("Stats").level
	autoload("Inventory").add_item("Marker", 1.0, 1)
	var good := FileAccess.get_file_as_string(sg.slot_path(2))
	var bad_cases := {
		"truncated": good.substr(0, good.length() / 2),
		"empty": "",
		"garbage": "\u0001not json",
		"array root": "[1,2,3]",
		"no version": '{"game":"cork","systems":{}}',
		"future version": '{"game":"cork","version":99,"systems":{}}',
		"wrong game": '{"game":"other","version":1,"systems":{}}',
		"systems not object": '{"game":"cork","version":1,"systems":[1]}',
		"system not object": '{"game":"cork","version":1,"systems":{"Stats":5}}',
		"no migration path": '{"game":"cork","version":-1,"systems":{}}',
	}
	for case_name in bad_cases:
		_write(1, bad_cases[case_name])
		var ok: bool = sg.load_slot(1)
		check("corrupt (%s) returns false" % case_name, not ok)
		check("corrupt (%s) leaves game untouched" % case_name,
			autoload("Inventory").has_item("Marker") and autoload("Stats").level == level_now)
		check("corrupt (%s) slot_info flags it" % case_name, sg.slot_info(1).get("corrupt", false))
	var failed_signal := [""]
	sg.load_failed.connect(func(_n, why): failed_signal[0] = why)
	_write(1, "{")
	sg.load_slot(1)
	check("load_failed signal carries reason", failed_signal[0] != "")

	# --- migration ---
	var old := {"game": "cork", "version": 0, "player": "Old Timer",
		"systems": {"Stats": {"level": 3, "name": "Old Timer"}}}
	_write(1, JSON.stringify(old))
	check("v0 migrates in slot_info", sg.slot_info(1).get("name") == "Old Timer", str(sg.slot_info(1)))
	check("v0 save loads", sg.load_slot(1) and autoload("Stats").level == 3)
	var m := SaveFormat.parse(JSON.stringify({"version": 1, "systems": {}}), {1: func(d): d["version"] = 2; d["migrated"] = true; return d}, 2)
	check("custom migration chain runs", m["ok"] and m["data"].get("migrated", false) and m["data"]["version"] == 2)
	var m2 := SaveFormat.parse(JSON.stringify({"version": 1, "systems": {}}), {}, 2)
	check("missing migration fails cleanly", not m2["ok"])

	# --- atomic write ---
	_write(2, good)
	sg.fs_rename = func(_a, _b): return ERR_FILE_CANT_WRITE
	check("failed rename returns false", not sg.save_slot(2))
	check("old save intact after failed rename", FileAccess.get_file_as_string(sg.slot_path(2)) == good)
	check("no tmp left behind", not FileAccess.file_exists(sg.slot_path(2) + ".tmp"))
	sg.fs_rename = func(a, b): return DirAccess.rename_absolute(a, b)
	var blocker := "user://saves_blocker"
	var bf := FileAccess.open(blocker, FileAccess.WRITE)
	bf.store_string("x")
	bf.close()
	sg.save_dir = blocker
	check("unwritable dir returns false", not sg.save_slot(1))
	sg.save_dir = DIR
	DirAccess.remove_absolute(blocker)
	check("save overwrites existing", sg.save_slot(2) and FileAccess.get_file_as_string(sg.slot_path(2)) != good)

	# --- slot ops ---
	check("delete slot", sg.delete_slot(2) and not sg.has_slot(2))
	check("delete empty slot is false", not sg.delete_slot(2))
	check("autosave slot id", sg.AUTOSAVE_SLOT == 0 and sg.MANUAL_SLOTS == 3)

	# --- autosave rules ---
	sg.autosave_enabled = true
	_clean()
	var saves := [0]
	var cb := func(n): saves[0] += 1
	sg.saved.connect(cb)
	var d := autoload("Director")
	d.rush_active = false
	sg._last_autosave_msec = -1000000
	events.location_entered.emit("l1")
	events.location_entered.emit("l1_b")
	events.location_entered.emit("l1_c")
	check("location autosave debounced to one", saves[0] == 1 and sg.has_slot(0), str(saves[0]))
	saves[0] = 0
	events.level_up.emit(8)
	check("level up autosaves (no debounce)", saves[0] == 1)
	saves[0] = 0
	sg.notify_rest_finished()
	check("rest finished autosaves", saves[0] == 1)
	d.rush_active = true
	check("no autosave during rush", not sg.autosave() and sg.autosave_blocked_reason() == "rush")
	d.rush_active = false
	paused = true
	check("no autosave while paused", not sg.autosave() and sg.autosave_blocked_reason() == "paused")
	paused = false
	events.player_died.emit()
	check("no autosave when dead", not sg.autosave() and sg.autosave_blocked_reason() == "dead")
	events.run_started.emit()
	check("autosave back after run starts", sg.autosave())
	sg._loading = true
	check("no autosave while loading", not sg.autosave())
	sg._loading = false
	saves[0] = 0
	events.location_entered.emit("l1")  # inside debounce window of the autosave above
	check("debounce uses last autosave", saves[0] == 0)
	sg.saved.disconnect(cb)
	sg.autosave_enabled = false

	# --- quick save / load actions ---
	_clean()
	autoload("Inventory").reset()
	autoload("Inventory").add_item("QuickItem", 1.0, 1)
	var ev := InputEventAction.new()
	ev.action = "quick_save"
	ev.pressed = true
	sg._unhandled_input(ev)
	check("quick_save action writes slot 1", sg.has_slot(1))
	autoload("Inventory").reset()
	var ev2 := InputEventAction.new()
	ev2.action = "quick_load"
	ev2.pressed = true
	sg._unhandled_input(ev2)
	check("quick_load action restores", autoload("Inventory").has_item("QuickItem"))
	check("quick_save/quick_load methods", sg.quick_save() and sg.quick_load())

	# --- provider management ---
	sg.unregister_provider("Player")
	check("unregister provider", not sg.has_provider("Player"))
	restored[0] = {}
	sg.load_slot(1)  # file still has a Player section: ignored with a warning
	check("unknown provider ignored", restored[0].is_empty())

	# --- slot picker ---
	_clean()
	autoload("Stats").player_name = "Picker"
	sg.save_slot(2)
	var picker: Control = load("res://scenes/ui/save_slots.tscn").instantiate()
	root.add_child(picker)
	await frames(2)
	var chosen := [-1]
	var closed := [false]
	picker.slot_chosen.connect(func(n): chosen[0] = n)
	picker.closed.connect(func(): closed[0] = true)
	picker.open(picker.Mode.LOAD)
	await frames(2)
	check("load mode lists autosave + 3 slots", picker._list.get_child_count() == 4)
	check("slot label shows name", picker.slot_label(2).contains("Picker"), picker.slot_label(2))
	check("empty slot label", picker.slot_label(3).contains("empty"))
	check("empty slot disabled in load mode", picker._list.get_node("Row3/Pick").disabled)
	picker.choose(2)
	check("load pick emits slot_chosen", chosen[0] == 2)
	picker.open(picker.Mode.SAVE)
	await frames(2)
	check("save mode lists 3 slots", picker._list.get_child_count() == 3)
	chosen[0] = -1
	picker.choose(3)
	check("save to empty slot needs no confirm", chosen[0] == 3)
	chosen[0] = -1
	picker.choose(2)
	check("overwrite asks first", chosen[0] == -1 and picker._pending_slot == 2)
	picker._on_confirmed()
	check("confirm overwrite emits", chosen[0] == 2)
	picker.request_delete(2)
	picker._on_confirmed()
	check("delete via picker", not sg.has_slot(2))
	picker.get_node("*/*/BackButton").pressed.emit() if false else picker.close()
	check("closed signal", closed[0])
	picker.queue_free()

	# cleanup
	fake.queue_free()
	_clean()
	game_state.reset_run()
