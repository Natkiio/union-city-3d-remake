extends "res://tests/test_base.gd"
## End-to-end playthrough, headless and seeded. Drives the real scenes with
## input actions wherever the game reads input (moving, interacting, firing,
## reloading, pausing, quick keys); headless has no real mouse, so aim is fed
## as mouse-motion events at the projected target. Prints each step.
##
## main menu -> New Game -> character creation -> Ballincollig (section 16)
## -> Fred's tutorial quest, 3 kills, level up -> a building, search, a weapon
## equipped, fired and reloaded -> pause, save, load, exact state check ->
## sleep in a safehouse -> map travel to the next unlocked section -> death ->
## death screen -> main menu with a clean state.

const TIME_LIMIT_MSEC := 60000
const SEED := 20261029

var world: Node
var run_scene: Node = null
var player: Node3D = null
var t0: int = 0


func step(text: String) -> void:
	print("[STEP %5.1fs] %s" % [(Time.get_ticks_msec() - t0) / 1000.0, text])


func run() -> void:
	t0 = Time.get_ticks_msec()
	seed(SEED)
	world = autoload("World")
	world.fade_enabled = false
	autoload("Director").enabled = false # spawns are scripted below
	autoload("Quests").auto_play_cutscenes = true
	GameFlow.scene_changer = func(path: String): _change_scene.call_deferred(path)

	await _menu_and_creation()
	await _fred_and_kills()
	await _building_and_weapon()
	await _save_and_load()
	await _safehouse_sleep()
	await _map_travel()
	await _death()

	GameFlow.scene_changer = Callable()
	autoload("SaveGame").delete_slot(2) # leave the shared test save dir empty
	var took := Time.get_ticks_msec() - t0
	step("done in %.1f s" % (took / 1000.0))
	check("playthrough finishes in under 60 s", took < TIME_LIMIT_MSEC, "%d ms" % took)


# --- scene plumbing (change_scene_to_file does not work from -s) -------------

func _change_scene(path: String) -> void:
	if current_scene != null:
		current_scene.queue_free()
		current_scene = null
	await frames(1)
	await load_scene(path)


func _wait_scene(path: String, max_frames: int = 120) -> Node:
	for i in max_frames:
		if current_scene != null and current_scene.scene_file_path == path and current_scene.is_inside_tree():
			return current_scene
		await frames(1)
	return null


func _tap(action: String, hold: int = 2) -> void:
	Input.action_press(action)
	await frames(hold)
	Input.action_release(action)
	await frames(2)


func _event(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	Input.flush_buffered_events()
	await frames(1)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)
	Input.flush_buffered_events()
	await frames(1)


## Walks (runs, when far) with the move actions until the player is within
## `tol` of x.
func _walk_to(x: float, tol: float = 0.25, max_frames: int = 900) -> bool:
	for i in max_frames:
		var dx := x - player.global_position.x
		if absf(dx) <= tol:
			break
		if absf(dx) > 3.0 and player.stamina > 5.0:
			Input.action_press("run")
		else:
			Input.action_release("run")
		var act := "move_right" if dx > 0.0 else "move_left"
		var other := "move_left" if dx > 0.0 else "move_right"
		Input.action_release(other)
		Input.action_press(act)
		await frames(1)
	Input.action_release("move_left")
	Input.action_release("move_right")
	Input.action_release("run")
	await frames(2)
	return absf(x - player.global_position.x) <= tol + 0.2


## Headless has no pointer: send a mouse motion at the target's screen point.
func _aim_at(target: Vector3) -> void:
	var cam := root.get_viewport().get_camera_3d()
	if cam == null:
		return
	var ev := InputEventMouseMotion.new()
	ev.position = cam.unproject_position(target)
	ev.global_position = ev.position
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _use_link(marker_name: String) -> bool:
	var l: WorldLink = world.level().link_named(marker_name)
	if l == null:
		return false
	var before: String = world.room_id
	await _walk_to(l.global_position.x, 0.12)
	await _tap("interact")
	await frames(3)
	return world.room_id != before or _ui_top() != null


func _ctl() -> UIController:
	return get_first_node_in_group("ui_controller") as UIController


func _ui_top() -> Control:
	var c := _ctl()
	return c.top() if c != null else null


func _close_level_up() -> void:
	var c := _ctl()
	if c != null and c.is_open() and c.top().has_signal("done"):
		c.top().done.emit()
		await frames(2)


# --- steps ---------------------------------------------------------------------

func _menu_and_creation() -> void:
	var menu: Node = await load_scene("res://scenes/ui/main_menu.tscn")
	step("main menu")
	check("main menu up", menu.new_button != null)
	menu.new_button.pressed.emit()
	await frames(3)
	var create: Node = menu.overlay
	check("New Game opens character creation", create != null and create.has_method("confirm"))
	var refs: Array = autoload("Data").table("pre").keys()
	refs.sort()
	create._ref = str(refs[0])
	create._name_edit.text = "Dara"
	check("confirm with a background", create.confirm())
	step("character created: %s, background %s" % [autoload("Stats").player_name, autoload("Stats").background])
	run_scene = await _wait_scene(GameFlow.RUN_SCENE)
	check("the run scene opens", run_scene != null)
	await frames(5)
	player = run_scene.get_player()
	player.rng.seed = SEED
	check("new game starts in Ballincollig (section 16)", world.current.get("section") == "16" and world.room_id == "l16_s1_b0_f0_r1")
	check("the story began: quest 900 active", autoload("Quests").is_active("900"))
	for cp in root.find_children("*", "CutscenePlayer", true, false):
		cp.skip()
	await frames(3)
	paused = false
	step("in %s (%s)" % [world.current.name, world.room_id])


## The car trunk on the start street, on the way to Fred: a revolver and
## rounds (fixed contents, no junk roll).
func _loot_trunk() -> void:
	var trunk: Node3D = world.level().find_children("Container_cont1", "", true, false)[0]
	await _walk_to(trunk.global_position.x, 0.12)
	await _tap("interact")
	await seconds(trunk.SEARCH_TIME + 0.3)
	check("the street trunk opens", autoload("TrunkUI").visible)
	autoload("TrunkUI")._take_all()
	await frames(2)
	if autoload("TrunkUI").visible:
		autoload("TrunkUI").close()
	paused = false
	var gun := Weapon.from_ref("tauron")
	check("picked up a firearm from the trunk", gun != null and autoload("Inventory").has_item(gun.display_name),
			str(autoload("Inventory").items.keys()))
	step("looted the car trunk: %s" % ", ".join(autoload("Inventory").items.keys()))


func _fred_and_kills() -> void:
	var q := autoload("Quests")
	await _loot_trunk()
	check("street 1 leads on to street 2", await _use_link("strt1") or world.room_id == "l16_s2_b0_f0_r1")
	if world.room_id != "l16_s2_b0_f0_r1":
		await _use_link("strt2")
	check("walked to Old Road (street 2)", world.room_id == "l16_s2_b0_f0_r1", world.room_id)
	var fred: Node3D = world.level().find_children("NPC_Fred", "", true, false)[0]
	await _walk_to(fred.global_position.x, 0.3)
	check("Fred shows a quest marker", fred.get_node_or_null("QuestMarker") != null and fred.get_node("QuestMarker").text == "!")
	await _tap("interact")
	var box: DialogueBox = _dialogue()
	check("interact talks to Fred", box != null and box.visible)
	box.press_button(0) # ACCEPT
	await frames(3)
	check("tutorial quest 500 accepted", q.is_active("500"))
	step("accepted %s" % q.journal()[0].title if not q.journal().is_empty() else "accepted quest 500")
	paused = false
	await _walk_to(14.0, 0.5)
	var xp0: int = autoload("Stats").xp
	for i in 3:
		await _kill_one(i)
	check("three kills counted", q.kill_count("500") == 3, str(q.kill_count("500")))
	await _walk_to(fred.global_position.x, 0.3)
	await _tap("interact")
	box = _dialogue()
	if box != null and box.visible:
		box.press_button(0) # THEY'RE DONE
		await frames(3)
		if is_instance_valid(box) and box.visible:
			box.close()
	paused = false
	await frames(2)
	check("quest 500 handed in", q.is_complete("500"))
	check("kill and quest XP levelled the player up", autoload("Stats").level >= 2, "level %d xp %d (from %d)" % [autoload("Stats").level, autoload("Stats").xp, xp0])
	await _close_level_up()
	check("level-up screen closes and play resumes", not paused)
	step("level %d" % autoload("Stats").level)


## The visible NPC dialogue (not a cutscene caption), text revealed.
func _dialogue() -> DialogueBox:
	for b in root.find_children("*", "DialogueBox", true, false):
		if b.visible and str(b.model.get("npc", "")) != "":
			b.finish_text()
			return b
	return null


## Spawns one zombie a few units ahead and punches it to death with the attack
## action, aim fed at its head. Falls back to direct hits if punching stalls.
func _kill_one(i: int) -> void:
	# Zombie.spawn, but with the zombie's own RNG seeded before it is ready.
	var z: Zombie = (load(Zombie.SCENE_PATH) as PackedScene).instantiate()
	z.type_ref = "zombieSlow"
	z.danger_level = 1
	z.rng.seed = SEED + i
	z.position = Vector3(player.global_position.x + 1.6, 1.0, 0.0)
	world.level().spawn_root().add_child(z)
	await frames(2)
	var punches := 0
	for f in 600:
		if not is_instance_valid(z) or z.is_dead():
			break
		if player.is_grabbed():
			await _tap("move_left", 1)
			await _tap("move_right", 1)
		_aim_at(z.global_position + Vector3(0, 0.2, 0))
		if player.global_position.x < z.global_position.x - 0.85:
			Input.action_press("move_right")
		else:
			Input.action_release("move_right")
		if f % 6 == 0:
			Input.action_press("attack")
			punches += 1
		elif f % 6 == 2:
			Input.action_release("attack")
		await frames(1)
	Input.action_release("attack")
	Input.action_release("move_right")
	var by_hand := not is_instance_valid(z) or z.is_dead()
	if not by_hand:
		CombatActions.deal_damage(z, 999.0, "head", player)
	await frames(3)
	step("zombie %d down %s after %d punches, health %.0f" % [i + 1, "by hand" if by_hand else "(direct)", punches, player.health])
	check("zombie %d killed by punching" % (i + 1), by_hand)


func _building_and_weapon() -> void:
	var inv := autoload("Inventory")
	check("enter the Old House", await _use_link("entr1") and world.room_id == "l16_s2_b1_f1_r1", world.room_id)
	var conts: Array = world.level().find_children("Container_*", "", true, false)
	var dresser: Node3D = conts[0]
	await _walk_to(dresser.global_position.x, 0.3)
	await _tap("interact")
	await seconds(dresser.SEARCH_TIME + 0.3)
	check("searching opens the container panel", autoload("TrunkUI").visible)
	var n: int = dresser.items.size()
	autoload("TrunkUI")._take_all()
	await frames(2)
	if autoload("TrunkUI").visible:
		autoload("TrunkUI").close()
	paused = false
	step("searched %s: took %d items" % [dresser.title, n])
	check("container emptied into the inventory", dresser.items.is_empty() and n > 0)
	var gun := Weapon.from_ref("tauron")
	await _tap("equip_gun")
	check("key 2 equips it", player.equipped_weapon == gun.ref, player.equipped_weapon)
	var loaded0: int = inv.get_magazine(gun.display_name, gun.mag_size)
	_aim_at(player.global_position + Vector3(4, 0.3, 0))
	await frames(1)
	await _tap("attack")
	await frames(int(gun.fire_interval() * 60) + 4)
	var loaded1: int = inv.get_magazine(gun.display_name, gun.mag_size)
	check("firing spends a round", loaded1 == loaded0 - 1, "%d -> %d" % [loaded0, loaded1])
	var reserve0: int = inv.items.get(gun.ammo_item_name(), {}).get("count", 0)
	await _tap("reload")
	for i in 900:
		if not player.reloading:
			break
		await frames(1)
	var loaded2: int = inv.get_magazine(gun.display_name, gun.mag_size)
	check("reload refills from the reserve", loaded2 == gun.mag_size and inv.items.get(gun.ammo_item_name(), {}).get("count", 0) < reserve0,
			"%d loaded, reserve %d" % [loaded2, inv.items.get(gun.ammo_item_name(), {}).get("count", 0)])
	step("%s: fired, reloaded to %d/%d" % [gun.display_name, loaded2, gun.mag_size])


func _state_snapshot() -> Dictionary:
	var snap: Dictionary = autoload("SaveGame").snapshot()
	return {"systems": JSON.stringify(snap.systems), "player": JSON.stringify(snap.providers.get("Player", {}))}


func _diff(a: String, b: String) -> String:
	var da: Dictionary = JSON.parse_string(a)
	var db: Dictionary = JSON.parse_string(b)
	var out: Array = []
	for k in da:
		if JSON.stringify(da[k]) != JSON.stringify(db.get(k)):
			out.append("%s: %s -> %s" % [k, JSON.stringify(da[k]).left(300), JSON.stringify(db.get(k)).left(300)])
	return "\n".join(out)


func _save_and_load() -> void:
	await _event("pause")
	var c := _ctl()
	check("pause opens the pause menu", _ui_top() is PauseMenu and paused)
	(_ui_top() as PauseMenu).choice.emit("save")
	await frames(2)
	var slots := _ui_top() as SlotList
	slots.body.get_node("Slot2").pressed.emit()
	await frames(2)
	check("saved to slot 2 from the pause menu", autoload("SaveGame").has_slot(2))
	var saved := _state_snapshot()
	c.close_all()
	await frames(2)
	step("saved: %s" % autoload("SaveGame").slot_info(2))
	# Change things, then load it back through the pause menu.
	player.take_damage(9.0)
	var w: float = world.level().width_units()
	await _walk_to(w * 0.25 if player.global_position.x > w * 0.5 else w * 0.75)
	autoload("Inventory").add_item("Water", 1.0, 1)
	autoload("Clock").advance(30)
	await _event("pause")
	(_ui_top() as PauseMenu).choice.emit("load")
	await frames(2)
	(_ui_top() as SlotList).body.get_node("Slot2").pressed.emit()
	var loaded := _state_snapshot() # at once: a frame later stamina has regenerated
	await frames(4)
	check("load restores every system exactly", JSON.parse_string(loaded.systems) == JSON.parse_string(saved.systems), _diff(saved.systems, loaded.systems))
	check("load restores the player exactly", loaded.player == saved.player, "%s vs %s" % [loaded.player, saved.player])
	check("menus closed and play resumes after load", not _ctl().is_open() and not paused)
	step("loaded slot 2")


func _safehouse_sleep() -> void:
	await _use_link("exit1")
	await _use_link("strt2")
	check("reached Main Street (street 3)", world.room_id == "l16_s3_b0_f0_r1", world.room_id)
	check("enter the safehouse", await _use_link("entr1") and world.is_safehouse(), world.room_id)
	player.take_damage(15.0)
	var hp0: float = player.health
	var m0: int = autoload("Clock").game_minutes
	await _use_link("abed1")
	var dlg := _ui_top() as SleepDialog
	check("the bed opens the sleep dialog", dlg != null)
	dlg.set_hours(4)
	dlg.do_rest("sleep")
	await frames(3)
	var slept: int = autoload("Clock").game_minutes - m0
	check("slept 4 hours and healed", slept >= 240 and slept < 245 and player.health > hp0,
			"%d min, %.0f -> %.0f" % [slept, hp0, player.health])
	check("rest autosaves to slot 0", autoload("SaveGame").has_slot(0) or not autoload("SaveGame").autosave_enabled)
	step("slept 4 h in %s" % world.current.name)
	await _use_link("exit1")


func _map_travel() -> void:
	var q := autoload("Quests")
	# The way out of Ballincollig is Ed's bolt cutters (quest 004, which
	# unlocks section 9). The talk quests before it are skipped: Ed is put on
	# that step and the cutters handed over.
	q.set_npc_state("Ed", 2)
	autoload("Inventory").add_item(q.item_name("questBoltCutters"), 1.0, 1)
	q.start("004")
	var ed: Node3D = world.level().find_children("NPC_Ed", "", true, false)[0]
	await _walk_to(ed.global_position.x, 0.3)
	await _tap("interact")
	var box := _dialogue()
	if box != null:
		box.press_button(0)
		await frames(3)
		if is_instance_valid(box) and box.visible:
			box.close()
	paused = false
	check("Ed's quest unlocks Bishopstown (section 9)", q.is_complete("004") and q.is_section_unlocked(9))
	check("the area exit opens the map", await _use_link("area1") and _ui_top() is MapScreen)
	var map := _ui_top() as MapScreen
	var target := ""
	for n in map.map_nodes:
		if n.unlocked and n.travelable and str(n.id) != map.current_id:
			target = str(n.id)
			break
	map.select(target)
	var hours: int = map.cost_to(target)
	var m0: int = autoload("Clock").game_minutes
	map.travel()
	await frames(4)
	var spent: int = autoload("Clock").game_minutes - m0
	check("travelled to the next unlocked section", world.current.get("section") == target and spent >= hours * 60 and spent < hours * 60 + 3,
			"%s, %d h" % [world.room_id, hours])
	step("travelled to section %s (%s), %d h" % [target, world.current.get("section_name", ""), hours])


func _death() -> void:
	var died := [false]
	autoload("Events").player_died.connect(func(): died[0] = true)
	for i in 40:
		if died[0]:
			break
		player.take_damage(10.0)
		await frames(1)
	check("the player dies", died[0])
	await frames(3)
	check("the death screen shows", autoload("DeathScreen").visible)
	step("died; death screen")
	var menu := await _wait_scene(GameFlow.MENU_SCENE, 600)
	check("the death screen returns to the main menu", menu != null)
	await frames(3)
	check("clean state: World", world.room_id == "" and world.current.is_empty())
	check("clean state: Stats", autoload("Stats").level == 1 and autoload("Stats").xp == 0)
	check("clean state: Inventory", autoload("Inventory").items.is_empty())
	check("clean state: Quests", autoload("Quests").active_quests().is_empty() and autoload("Quests").completed_quests().is_empty())
	check("clean state: not paused, no overlays", not paused and get_nodes_in_group("run_overlay").is_empty())
	step("main menu, clean state")
