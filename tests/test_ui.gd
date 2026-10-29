extends "res://tests/test_base.gd"
## UI: settings persistence, game flow, HUD readouts and layout, map screen,
## sleep gating, pause menu, death summary, level-up popup.

const WORLD_SRC := """extends Node
var current: Dictionary = {"section": "9", "danger": 4, "safehouse": false}
var travelled_to: String = ""
var started: bool = false
func map_nodes() -> Array:
	return []
func travel_to(id: String) -> void:
	travelled_to = id
func start_new_game() -> void:
	started = true
"""
const SAVE_SRC := """extends Node
var loaded: int = -1
var saved: int = -1
func has_slot(n: int) -> bool:
	return n == 1
func slot_info(n: int) -> Dictionary:
	return {"name": "Aoife", "level": 3, "location": "Shandon", "clock": "Day 2"}
func load_slot(n: int) -> bool:
	loaded = n
	return true
func save_slot(n: int) -> bool:
	saved = n
	return true
"""

var changed_scenes: Array = []
var quit_called: bool = false


func _stub(src: String) -> Node:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	var n := Node.new()
	n.set_script(s)
	root.add_child(n)
	return n


func run() -> void:
	GameFlow.scene_changer = func(p: String): changed_scenes.append(p)
	GameFlow.quitter = func(): quit_called = true
	await _settings()
	await _menu_flow()
	await _hud()
	await _map()
	await _sleep_and_pause()
	await _death_and_levelup()
	GameFlow.scene_changer = Callable()
	GameFlow.quitter = Callable()
	GameFlow.world_override = null
	GameFlow.save_override = null


func _settings() -> void:
	Settings.path = "user://test_settings.cfg"
	DirAccess.remove_absolute(Settings.path)
	Settings.reload()
	check("settings default head shots off", Settings.get_value("head_shots_only") == false)
	Settings.set_value("head_shots_only", true)
	Settings.set_value("mode", "runngun")
	Settings.set_value("volume_Sfx", 0.25)
	check("settings save ok", Settings.save())
	Settings.reload()
	check("settings persisted head shots", Settings.get_value("head_shots_only") == true)
	check("settings persisted mode", Settings.get_value("mode") == "runngun")
	check("settings persisted volume", is_equal_approx(float(Settings.get_value("volume_Sfx")), 0.25))
	Settings.apply(self)
	check("apply sets Survival mode", autoload("Survival").mode == "runngun")
	check("apply sets Sfx bus volume", absf(autoload("Sfx").get_volume("Sfx") - 0.25) < 0.02)
	var scr := SettingsScreen.new()
	root.add_child(scr)
	await frames(2)
	check("settings screen reflects mode", scr.mode_pick.selected == 1)
	scr.head_shots.button_pressed = false
	scr.sliders["brightness"].value = 0.8
	var closed_flag := [false]
	scr.closed.connect(func(): closed_flag[0] = true)
	scr.close()
	Settings.reload()
	check("settings screen saved on close", Settings.get_value("head_shots_only") == false
		and is_equal_approx(float(Settings.get_value("brightness")), 0.8) and closed_flag[0])
	scr.queue_free()
	# restore defaults so later checks see survivor mode
	Settings.set_value("mode", "survivor")
	Settings.set_value("volume_Sfx", 1.0)
	Settings.apply(self)
	DirAccess.remove_absolute(Settings.path)
	Settings.reload()


func _menu_flow() -> void:
	var menu: Control = await load_scene("res://scenes/ui/main_menu.tscn")
	check("menu has four buttons", menu.new_button != null and menu.continue_button != null
		and menu.settings_button != null and menu.quit_button != null)
	check("continue disabled with no saves", menu.continue_button.disabled)
	menu.settings_button.pressed.emit()
	await frames(2)
	check("settings opens from menu", menu.overlay is SettingsScreen)
	menu.overlay.close()
	await frames(2)
	check("settings closes back to menu", menu.overlay == null)

	menu.new_button.pressed.emit()
	await frames(3)
	var create: Node = menu.overlay
	check("new game opens character creation", create != null and create.has_signal("confirmed"))
	changed_scenes.clear()
	GameFlow.world_override = _stub(WORLD_SRC)  # keep the real World out of the menu test
	create.confirmed.emit()
	await frames(2)

	var w := _stub(WORLD_SRC)
	GameFlow.world_override = w
	changed_scenes.clear()
	GameFlow.start_world(self)
	check("start_world calls World.start_new_game", w.started and changed_scenes.is_empty())

	var sv := _stub(SAVE_SRC)
	GameFlow.save_override = sv
	menu.queue_free()
	menu = await load_scene("res://scenes/ui/main_menu.tscn")
	check("continue enabled when a slot exists", not menu.continue_button.disabled)
	menu.continue_button.pressed.emit()
	await frames(2)
	var slots: SlotList = menu.overlay
	check("continue opens slot list", slots != null)
	check("empty slot disabled, filled enabled",
		slots.body.get_node("Slot0").disabled and not slots.body.get_node("Slot1").disabled)
	check("filled slot shows info", slots.body.get_node("Slot1").text.contains("Aoife"))
	changed_scenes.clear()
	slots.body.get_node("Slot1").pressed.emit()
	check("load calls SaveGame.load_slot and enters game", sv.loaded == 1 and changed_scenes == [GameFlow.RUN_SCENE])
	menu.quit_button.pressed.emit()
	check("quit goes through quitter", quit_called)
	menu.queue_free()
	w.queue_free()
	sv.queue_free()
	GameFlow.world_override = null
	GameFlow.save_override = null
	await frames(2)


func _hud() -> void:
	autoload("Stats").reset()
	autoload("Survival").reset()
	autoload("Inventory").reset()
	for size in [Vector2i(1280, 720), Vector2i(800, 600)]:
		var vp := SubViewport.new()
		vp.size = size
		vp.disable_3d = true
		root.add_child(vp)
		var hud: CanvasLayer = load("res://scenes/ui/hud.tscn").instantiate()
		autoload("Clock").reset()
		vp.add_child(hud)
		await frames(4)
		check("hud text clock %s" % size, hud.clock_label.text == "Day 1  12:00", hud.clock_label.text)
		check("hud level text", hud.level_label.text.begins_with("Lv 1"), hud.level_label.text)
		check("hud hunger shows Fed", hud.hunger_label.text == "Fed" and hud.sleep_label.text == "Rested")
		check("hud danger line", hud.danger_label.text == "Safe" or hud.danger_label.text.begins_with("Danger"))

		autoload("Survival").hunger = 50.0
		autoload("Survival").sleep = 40.0
		autoload("Clock").advance(90)
		autoload("Stats").add_xp(30, "test")
		autoload("Inventory").add_item("Hammer", 5.0, 1)
		autoload("Events").rush_started.emit()
		autoload("Inventory").add_item("Lead Pipe", 200.0, 1)
		await frames(4)
		check("hud hunger level 3", hud.hunger_label.text == "Starving", hud.hunger_label.text)
		check("hud sleep level 2", hud.sleep_label.text == "Tired", hud.sleep_label.text)
		check("hud clock advanced", hud.clock_label.text == "Day 1  13:30", hud.clock_label.text)
		check("hud xp bar", hud.xp_bar.value == 30.0 and hud.level_label.text.contains("XP 30 / 100"), hud.level_label.text)
		check("hud rush warning", hud.rush_label.visible)
		check("hud overweight warning", hud.weight_label.visible)
		check("hud pickup toast", hud.toast_box.get_child_count() >= 1)
		autoload("Events").rush_ended.emit()
		await frames(2)
		check("hud rush clears", not hud.rush_label.visible)
		autoload("Events").rush_started.emit()
		await frames(4)

		var rects: Dictionary = hud.block_rects()
		var names := rects.keys()
		check("hud blocks present %s" % size, names.size() >= 4, str(names))
		var bounds := Rect2(Vector2.ZERO, Vector2(size))
		var inside := true
		for k in names:
			if not bounds.encloses(rects[k]):
				inside = false
				print("  outside: ", k, rects[k])
		check("hud blocks inside window %s" % size, inside)
		var overlap := false
		for i in names.size():
			for j in range(i + 1, names.size()):
				if rects[names[i]].intersects(rects[names[j]]):
					overlap = true
					print("  overlap: ", names[i], rects[names[i]], names[j], rects[names[j]])
		check("hud blocks do not overlap %s" % size, not overlap)
		autoload("Events").rush_ended.emit()
		autoload("Inventory").reset()
		autoload("Survival").reset()
		autoload("Stats").reset()
		vp.queue_free()
		await frames(2)


func _map() -> void:
	var w := _stub(WORLD_SRC)
	GameFlow.world_override = w
	var m := MapScreen.new()
	m.nodes_override = MapScreen.mock_nodes()
	root.add_child(m)
	await frames(3)
	check("map knows current from World.current", m.current_id == "9")
	check("travel cost bishopstown->city centre = round(260/200) = 1", m.cost_to("12") == 1, str(m.cost_to("12")))
	check("travel cost to Cobh = round((420+30)/200) = 2", m.cost_to("6") == 2, str(m.cost_to("6")))
	m.select("12")
	check("travel enabled for unlocked", not m.travel_button.disabled and m.info.text.contains("Travel time: 1 hour"))
	m.select("6")
	check("locked node disables travel", m.travel_button.disabled and m.info.text.contains("Not open"))
	m.select("9")
	check("current node disables travel", m.travel_button.disabled)
	# click on a node through the canvas
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(360, 220)
	m.canvas.gui_input.emit(click)
	check("click selects node", m.selected_id == "12")
	var got := [""]
	m.travelled.connect(func(id: String): got[0] = id)
	check("travel returns true", m.travel())
	check("travel calls World.travel_to", w.travelled_to == "12" and got[0] == "12")
	m.queue_free()
	w.queue_free()
	GameFlow.world_override = null
	await frames(2)


func _sleep_and_pause() -> void:
	var w := _stub(WORLD_SRC)
	GameFlow.world_override = w
	check("sleep not available outside safehouse", not SleepDialog.available(self))
	w.current["safehouse"] = true
	check("sleep available in safehouse", SleepDialog.available(self))
	var d := SleepDialog.new()
	root.add_child(d)
	await frames(2)
	d.set_hours(0)
	check("hours clamp low", d.hours == 1)
	d.set_hours(99)
	check("hours clamp high", d.hours == 12)
	d.set_hours(3)
	var sv: Node = autoload("Survival")
	var clk: Node = autoload("Clock")
	sv.sleep = 50.0
	var t0: int = clk.game_minutes
	d.do_rest("sleep")
	check("sleep lowers sleep and passes time", sv.sleep < 50.0 and clk.game_minutes - t0 == 180,
		"%s %d" % [sv.sleep, clk.game_minutes - t0])
	d.queue_free()
	var d2 := SleepDialog.new()
	root.add_child(d2)
	await frames(2)
	d2.set_hours(2)
	var t1: int = clk.game_minutes
	d2.do_rest("wait")
	check("wait passes time", clk.game_minutes - t1 == 120)
	d2.queue_free()

	# controller and pause menu
	var ctl := UIController.new()
	root.add_child(ctl)
	await frames(2)
	var menu: PauseMenu = ctl.open_pause()
	await frames(2)
	check("pause menu pauses the tree", paused and ctl.is_open())
	var took := {"menu": false}
	menu.choice.emit("settings")
	await frames(2)
	check("pause settings opens on top", ctl.top() is SettingsScreen and ctl.stack.size() == 2)
	ctl.close(ctl.top())
	menu.choice.emit("save")
	await frames(2)
	check("pause save opens slot list", ctl.top() is SlotList)
	ctl.close(ctl.top())
	menu.choice.emit("journal")
	await frames(2)
	check("pause journal opens", ctl.top() is QuestLog)
	ctl.close(ctl.top())
	changed_scenes.clear()
	menu.choice.emit("menu")
	await frames(2)
	check("quit to menu changes scene, unpauses", changed_scenes == [GameFlow.MENU_SCENE] and not paused and not ctl.is_open())
	# sleep refused outside a safehouse
	w.current["safehouse"] = false
	check("open_sleep refused outside safehouse", ctl.open_sleep() == null and not ctl.is_open())
	w.current["safehouse"] = true
	check("open_sleep works in safehouse", ctl.open_sleep() is SleepDialog)
	ctl.close_all()
	check("close_all restores pause", not paused)
	var ml := ctl.open_map()
	check("open_map opens map screen", ml is MapScreen)
	ctl.close_all()
	ctl.queue_free()
	w.queue_free()
	GameFlow.world_override = null
	await frames(2)


func _death_and_levelup() -> void:
	var ds: Node = autoload("DeathScreen")
	var ev: Node = autoload("Events")
	var st: Node = autoload("Stats")
	st.reset()
	autoload("Clock").reset()
	ev.run_reset.emit()
	ev.enemy_killed.emit("zombieSlow", 1, 0)
	ev.enemy_killed.emit("zombieFast", 1, 0)
	autoload("Clock").advance(1440 * 2)
	ev.player_died.emit()
	ev.run_reset.emit() # what GameState.reset_run does next
	var txt: String = ds.summary_text()
	check("death summary level", txt.contains("Level 1"), txt)
	check("death summary kills survive the reset", txt.contains("Kills: 2"), txt)
	check("death summary days", txt.contains("Days survived: 2"), txt)
	check("kill counter reset after death", ds.kills == 0)
	ds.summary = {}

	var ctl := UIController.new()
	root.add_child(ctl)
	await frames(2)
	ev.level_up.emit(2)
	await frames(2)
	check("level_up event opens the level-up scene", ctl.is_open() and ctl.top().has_signal("done"))
	ctl.top().done.emit()
	await frames(2)
	check("level-up done closes it and unpauses", not ctl.is_open() and not paused)
	var sk := ctl.open_skills()
	await frames(2)
	check("open_skills opens skills sheet", sk != null and sk.has_signal("closed"))
	sk.closed.emit()
	await frames(2)
	check("skills sheet closes", not ctl.is_open())
	ctl.queue_free()

	var q := QuestLog.new()
	q.entries = [{"id": "900", "name": "Breaking Through", "desc": "Get across the city.", "state": "active"}]
	root.add_child(q)
	await frames(2)
	check("quest log lists entries", q.body.get_child_count() >= 3)
	q.queue_free()
	await frames(2)
