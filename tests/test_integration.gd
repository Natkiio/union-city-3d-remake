extends "res://tests/test_base.gd"
## Integration: the seams between World, Loot, Quests, the UI and SaveGame,
## driven through the real run scene (scenes/main.tscn) and real nodes.
## See docs/integration.md.

var world: Node
var scn: Node
var player: Node3D


func run() -> void:
	world = autoload("World")
	world.fade_enabled = false
	autoload("Clock").running = false
	autoload("Director").enabled = false
	autoload("Quests").auto_play_cutscenes = false
	autoload("GameState").reset_run()
	world.reset()
	scn = await load_scene("res://scenes/main.tscn")
	await frames(3)
	player = scn.get_player()
	check("run scene has its glue", scn.get_node_or_null("Glue") != null)
	await test_fred_and_markers()
	await test_trigger_zone()
	await test_story_actions()
	await test_containers_persist()
	await test_lockpick_door()
	await test_shop()
	await test_map_and_travel()
	await test_bed()
	await test_settings()
	await test_player_provider()
	await test_quick_keys()
	await test_off_npc()
	test_load_order()
	await test_continue_button()
	await test_menu_reset()


func _glue() -> Node:
	return scn.get_node("Glue")


func _ctl() -> UIController:
	return root.get_tree().get_first_node_in_group("ui_controller") as UIController


func _npc(id: String) -> Node3D:
	var found: Array = world.level().find_children("NPC_" + id, "", true, false)
	return found[0] if not found.is_empty() else null


func _marker(n: Node) -> String:
	var l: Label3D = n.get_node_or_null("QuestMarker")
	return l.text if l != null and l.visible else ""


func test_fred_and_markers() -> void:
	var q := autoload("Quests")
	world.enter_room("l16_s2_b0_f0_r1")
	await frames(3)
	var fred := _npc("Fred")
	check("Fred stands on Old Road (section 16 street 2)", fred != null and fred.visible)
	check("Fred shows ! for the tutorial quest", fred != null and _marker(fred) == "!", _marker(fred) if fred else "")
	# Talk through the real dialogue box and accept.
	player.global_position.x = fred.global_position.x
	await frames(3)
	var box: DialogueBox = fred.interact()
	check("talking to Fred opens a quest offer", box != null and q.status("500") == "available")
	box.choice_made.emit("accept")
	await frames(2)
	check("accepting starts quest 500", q.is_active("500"))
	check("the ! goes once the quest is taken", _marker(fred) == "")
	var toasts_before: int = scn.get_node("HUD").toast_box.get_child_count()
	for i in 3:
		autoload("Events").enemy_killed.emit("zombieSlow", 1, 0)
	await frames(2)
	check("kill progress reaches 3/3", q.kill_count("500") == 3)
	check("kill progress toasts on the HUD", scn.get_node("HUD").toast_box.get_child_count() > toasts_before)
	check("Fred shows ? when the quest can be handed in", _marker(fred) == "?")
	box = fred.interact()
	box.choice_made.emit("turn_in")
	await frames(2)
	check("turning in completes quest 500", q.is_complete("500"))
	if is_instance_valid(box):
		box.close()
	paused = false
	await frames(2)


func test_trigger_zone() -> void:
	var q := autoload("Quests")
	world.enter_room("l16_s2_b0_f0_r1", "x:1900")
	await frames(3)
	check("trig6 has not fired yet", not q.trigger_done("trig6"))
	# Walk into the trigger zone (trig6 spans 2157..2385 px) with the move action.
	Input.action_press("move_right")
	for i in 150:
		await frames(1)
		if q.trigger_done("trig6"):
			break
	Input.action_release("move_right")
	check("walking into a trigger zone fires its trigger", q.trigger_done("trig6"))
	check("its speech shows as a bubble over the player", player.get_node_or_null("SpeechBubble") != null)


func test_story_actions() -> void:
	var q := autoload("Quests")
	var inv := autoload("Inventory")
	q.story_action.emit("unlockDoor", ["l16_s3_b4_f1_r1_door2"])
	check("unlockDoor opens the World door", not world.is_door_locked({"locked": true, "door_id": "l16_s3_b4_f1_r1_door2"}))
	q.unlock_door("l12_s2_b1_f1_r2_room101")
	check("a quest-unlocked door is open for World", not world.is_door_locked({"locked": true, "door_id": "l12_s2_b1_f1_r2_room101"}))
	check("the quest unlock reached World's own door state too", world.door_locks.get("l12_s2_b1_f1_r2_room101") == false)
	q._doors.erase("l12_s2_b1_f1_r2_room101")
	world.door_locks.erase("l12_s2_b1_f1_r2_room101")
	var cash0: int = int(inv.items.get("Cash", {}).get("count", 0))
	q._give_item("cash_250")
	check("a cash reward is the Cash item", int(inv.items["Cash"]["count"]) == cash0 + 250 and q.cash == cash0 + 250)
	q.fire_trigger("trig99") # addAlert
	check("alert toasts", _toast_contains("TEST ALERT"))
	q._run_action("startEndingRush", [])
	check("startEndingRush starts an endless Director rush", autoload("Director").ending_rush and autoload("Director").rush_active)
	autoload("Director").reset()
	q._run_action("showEnding", [])
	await frames(2)
	check("showEnding opens the ending screen", _ctl().top() is EndingScreen)
	_ctl().close_all()
	paused = false
	await frames(2)


func _toast_contains(text: String) -> bool:
	for l in scn.get_node("HUD").toast_box.get_children():
		if l is Label and l.text.contains(text):
			return true
	return false


func test_containers_persist() -> void:
	world.enter_room("l16_s3_b1_f1_r1")
	await frames(2)
	var conts: Array = world.level().find_children("Container_*", "", true, false)
	check("one container node per contN", conts.size() == WorldData.containers("l16_s3_b1_f1_r1").size() and conts.size() >= 2)
	var c: Node = conts[0]
	var cname: String = c.name
	c.search_now()
	var ids: Array = []
	for e in c.items:
		ids.append(e["name"])
	world.enter_room("l16_s3_b0_f0_r1")
	await frames(2)
	world.enter_room("l16_s3_b1_f1_r1")
	await frames(2)
	var again: Node = world.level().find_children(cname, "", true, false)[0]
	var ids2: Array = []
	for e in again.items:
		ids2.append(e["name"])
	check("a searched container keeps its contents across visits", again.searched and ids == ids2, "%s / %s" % [ids, ids2])


func test_lockpick_door() -> void:
	var stats := autoload("Stats")
	stats._skills["security"] = 60
	world.enter_room("l12_s2_b1_f1_r2")
	await frames(2)
	world.use_link(world.level().link_named("room101").link)
	await frames(2)
	var ui: Node = null
	for n in root.get_tree().get_nodes_in_group("run_overlay"):
		if n.has_method("set_pin"):
			ui = n
	check("a lockpick door opens the minigame", ui != null and world.room_id == "l12_s2_b1_f1_r2")
	if ui != null:
		Locks.complete(ui.def)
		ui._close(true)
	await frames(2)
	check("a picked lock lets the player walk through", world.room_id == "l12_s2_b1_f1_r101", world.room_id)
	stats._skills["security"] = 7
	paused = false


func test_shop() -> void:
	world.enter_room("l13_s3_b1_f1_r1")
	await frames(2)
	var shop_link: WorldLink = world.level().link_named("shop")
	check("a shop room has a shop counter", shop_link != null)
	world.use_link(shop_link.link)
	await frames(2)
	var shop: Node = null
	for n in root.get_tree().get_nodes_in_group("run_overlay"):
		if n.has_method("open") and "set_id" in n:
			shop = n
	check("the counter opens the shop screen for its set", shop != null and shop.visible and int(shop.set_id) == 1 and paused)
	shop.close()
	await frames(2)
	check("closing the shop frees it and unpauses", not is_instance_valid(shop) and not paused)


func test_map_and_travel() -> void:
	var q := autoload("Quests")
	world.enter_room("l16_s3_b0_f0_r1", "area1")
	await frames(3)
	world.use_link(world.level().link_named("area1").link)
	await frames(2)
	var map := _ctl().top() as MapScreen
	check("the area exit opens the map screen", map != null)
	check("the map shows World.map_nodes", map != null and map.map_nodes.size() == 16 and map.current_id == "16")
	map.select("9")
	check("a locked section cannot be travelled to", map.travel_button.disabled)
	q.unlock_section(9)
	_ctl().close_all()
	await frames(1)
	world.use_link(world.level().link_named("area1").link)
	await frames(2)
	map = _ctl().top() as MapScreen
	map.select("9")
	check("travel shows the cost in hours", not map.travel_button.disabled and map.travel_button.text == "Travel (2 h)", map.travel_button.text)
	check("the far-end option is offered for a section with an endLoc", map.end_check.visible)
	map.end_check.button_pressed = true
	var t0: int = autoload("Clock").game_minutes
	map.travel()
	await frames(3)
	check("travel to the far end lands at the endLoc", world.room_id == WorldData.end_room("9") and autoload("Clock").game_minutes - t0 == 120,
			world.room_id)
	check("map closed and unpaused after travel", not _ctl().is_open() and not paused)


func test_bed() -> void:
	world.enter_room("l16_s3_b1_f1_r1", "abed1")
	await frames(3)
	player.take_damage(20.0)
	var hp0: float = player.health
	world.use_link(world.level().link_named("abed1").link)
	await frames(2)
	var dlg := _ctl().top() as SleepDialog
	check("the bed opens the sleep dialog", dlg != null)
	var sleep0: float = autoload("Survival").sleep
	autoload("Survival").sleep = 60.0
	dlg.set_hours(3)
	dlg.do_rest("sleep")
	await frames(2)
	check("sleeping heals the player (player.rest)", player.health > hp0, "%.1f -> %.1f" % [hp0, player.health])
	check("sleeping lowers sleep need", autoload("Survival").sleep < 60.0)
	autoload("Survival").sleep = sleep0
	paused = false


func test_settings() -> void:
	Settings.path = "user://test_integration_settings.cfg"
	Settings.reload()
	Settings.set_value("brightness", 1.0)
	Settings.apply(self)
	var env: Environment = scn.get_node("WorldEnvironment").environment
	check("brightness setting reaches the environment", env.adjustment_enabled and is_equal_approx(env.adjustment_brightness, 1.4))
	Settings.set_value("brightness", 0.5)
	Settings.apply(self)
	check("brightness 0.5 is neutral", is_equal_approx(env.adjustment_brightness, 1.0))
	# Head shots only: a chest hit on a zombie does 1 damage.
	var z: Node = load("res://scenes/zombie/zombie.tscn").instantiate()
	world.level().spawn_root().add_child(z)
	z.global_position = Vector3(player.global_position.x + 5.0, 0.9, 0.0)
	await frames(2)
	var h0: float = z.health
	Settings.set_value("head_shots_only", true)
	CombatActions.deal_damage(z, 5.0, "chest", player)
	check("head shots only: a chest hit does 1", is_equal_approx(h0 - z.health, 1.0), str(h0 - z.health))
	Settings.set_value("head_shots_only", false)
	z.queue_free()
	DirAccess.remove_absolute(Settings.path)
	Settings.path = Settings.DEFAULT_PATH
	Settings.reload()
	await frames(1)


func test_player_provider() -> void:
	var sg := autoload("SaveGame")
	var inv := autoload("Inventory")
	inv.add_item("G17 Pistol", 2.0, 1)
	player._set_equipped(Weapon.find_by_name("G17 Pistol").ref)
	world.enter_room("l16_s3_b2_f1_r1", "x:400")
	await frames(2)
	player.take_damage(10.0)
	var want := {"health": player.health, "perm": player.perm_health, "weapon": player.equipped_weapon,
			"x": player.global_position.x, "room": world.room_id}
	check("save to a slot from the run", sg.save_slot(2))
	world.enter_room("l16_s1_b0_f0_r1")
	player.full_heal()
	player._set_equipped("fist")
	await frames(2)
	check("load the slot back", sg.load_slot(2))
	await frames(2)
	var got := {"health": player.health, "perm": player.perm_health, "weapon": player.equipped_weapon,
			"x": player.global_position.x, "room": world.room_id}
	check("load restores room, x, health, perm health and weapon",
			got.room == want.room and absf(got.x - want.x) < 0.05 and is_equal_approx(got.health, want.health)
			and is_equal_approx(got.perm, want.perm) and got.weapon == want.weapon, "%s vs %s" % [got, want])

	# From a menu: the run scene is gone when the slot loads.
	GameFlow.scene_changer = func(_p: String): pass
	scn.queue_free()
	await frames(2)
	check("load from a menu leaves the player pending", sg.load_slot(2) and PlayerProvider.has_pending())
	world.enter_loaded_game()
	scn = await load_scene("res://scenes/main.tscn")
	await frames(3)
	player = scn.get_player()
	check("the run scene applies the pending player", not PlayerProvider.has_pending()
			and world.room_id == want.room and is_equal_approx(player.health, want.health) and player.equipped_weapon == want.weapon)
	GameFlow.scene_changer = Callable()
	sg.delete_slot(2)


func test_quick_keys() -> void:
	var sg := autoload("SaveGame")
	world.enter_room("l16_s3_b0_f0_r1", "x:900")
	await frames(2)
	_action("quick_save")
	await frames(2)
	check("quick_save key writes slot 1", sg.has_slot(1))
	world.enter_room("l16_s1_b0_f0_r1")
	await frames(2)
	_action("quick_load")
	await frames(3)
	check("quick_load key restores the room", world.room_id == "l16_s3_b0_f0_r1" and absf(player.global_position.x - 9.0) < 0.1,
			"%s %.2f" % [world.room_id, player.global_position.x])
	sg.delete_slot(1)


func _action(action_name: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action_name
	ev.pressed = true
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func test_menu_reset() -> void:
	var changed: Array = []
	GameFlow.scene_changer = func(p: String): changed.append(p)
	autoload("Quests").start("001")
	var box := DialogueBox.create()
	root.add_child(box)
	await frames(1)
	GameFlow.to_main_menu(self)
	await frames(2)
	check("quit to menu resets World", world.room_id == "" and world.current.is_empty())
	check("quit to menu resets Quests", not autoload("Quests").is_active("001"))
	check("quit to menu frees run overlays", not is_instance_valid(box))
	check("quit to menu goes to the menu scene", changed == [GameFlow.MENU_SCENE])
	GameFlow.scene_changer = Callable()


func test_off_npc() -> void:
	var q := autoload("Quests")
	world.enter_room("l11_s3_b0_f0_r1")
	await frames(2)
	var barry := _npc("newBarry")
	check("an NPC whose state is off is placed but hidden", barry != null and not barry.visible)
	q.set_npc_on("newBarry", true)
	await frames(1)
	check("turnOnNPC shows it", barry.visible)
	q.set_npc_on("newBarry", false)


func test_load_order() -> void:
	var order: Array = autoload("SaveGame")._ordered_names(["World", "Companions", "Stats", "Quests", "Zeta"])
	check("World loads last, after unlisted systems", order.back() == "World" and order.front() == "Stats", str(order))


## Continue on the title screen: slot list -> SaveGame.load_slot -> the run
## scene opens with the saved room and player.
func test_continue_button() -> void:
	var sg := autoload("SaveGame")
	world.enter_room("l16_s3_b2_f1_r1", "x:300")
	await frames(2)
	sg.save_slot(3)
	var changed: Array = []
	GameFlow.scene_changer = func(p: String): changed.append(p)
	var menu: Control = load("res://scenes/ui/main_menu.tscn").instantiate()
	root.add_child(menu)
	await frames(2)
	check("Continue is enabled with a save", not menu.continue_button.disabled)
	world.enter_room("l16_s1_b0_f0_r1")
	scn.queue_free()
	await frames(2)
	menu.continue_button.pressed.emit()
	await frames(2)
	var slots: SlotList = menu.overlay
	check("the slot list shows the autosave row and slot 3", slots.body.get_node_or_null("Slot0") != null
			and not slots.body.get_node("Slot3").disabled)
	slots.body.get_node("Slot3").pressed.emit()
	await frames(2)
	check("Continue loads the slot and opens the run scene", changed == [GameFlow.RUN_SCENE] and world.room_id == "l16_s3_b2_f1_r1",
			"%s %s" % [changed, world.room_id])
	menu.queue_free()
	scn = await load_scene("res://scenes/main.tscn")
	await frames(3)
	player = scn.get_player()
	check("the run scene puts the player where the save was", absf(player.global_position.x - 3.0) < 0.05, str(player.global_position.x))
	GameFlow.scene_changer = Callable()
	sg.delete_slot(3)
