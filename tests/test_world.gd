extends "res://tests/test_base.gd"
## World workstream: data lookups, level building for every room, links,
## lane rule, Director hand-off, travel, doors and save round trip.

## Links that are one-way in the original's data and art (drops, the woods
## paths of section 15, and a stair whose lower room has no way back up).
const ONE_WAY := [
	"l9_s2_b5_f2_r1:sdwn", "l13_s2_b1_f2_r0:drop", "l15_s3_b0_f0_r301:uprm499",
	"l15_s3_b0_f0_r499:dnrm202", "l15_s3_b0_f0_r499:dnrm200",
]
## Kinds that must lead back to where they came from.
const TWO_WAY := ["door", "entr", "exit", "sup", "sdwn", "strt", "room", "uprm", "dnrm", "ltrm", "rtrm"]
## Lane volume the player and zombies own: |z| below this, above the floor.
const LANE_HALF_Z := 0.45


func run() -> void:
	var world := autoload("World")
	world.fade_enabled = false
	autoload("Clock").running = false
	autoload("Director").enabled = false
	test_ids()
	test_section_data()
	await test_build_all()
	test_links_two_way()
	test_container_ids()
	test_lane_detector()
	test_seams()
	test_safehouse_and_director(world)
	test_travel(world)
	test_map_nodes(world)
	await test_run_scene(world)
	await test_interact_through_door(world)
	await test_locked_doors(world)
	await test_round_trip(world)


func test_ids() -> void:
	var p := WorldData.parse("l16_s3_b1_f1_r2")
	check("parse room id", p.section == "16" and p.street == 3 and p.building == 1 and p.floor == 1 and p.room == 2)
	check("room id round trip", WorldData.room_id("section16", 3, 1, 1, 2) == "l16_s3_b1_f1_r2")
	check("norm section", WorldData.norm_section("l9") == "9" and WorldData.norm_section(12) == "12")
	check("container id format", WorldData.container_id("l16_s3_b1_f1_r1", "cont2") == "l16/s3/b1/f1/r1/cont2")
	check("malformed id", WorldData.parse("nope").is_empty() and not WorldData.has_room("l99_s1_b0_f0_r1"))


func test_section_data() -> void:
	check("start room 16 = startLoc", WorldData.start_room("16") == "l16_s1_b0_f0_r1")
	check("stub section 8 still has a start room", WorldData.start_room("8") == "l8_s1_b0_f0_r1")
	check("danger section 16 street 1 = 0 (street override)", WorldData.danger("l16_s1_b0_f0_r1") == 0)
	check("danger section 16 street 3 = 1", WorldData.danger("l16_s3_b1_f1_r1") == 1)
	check("danger section 7 = 25", WorldData.danger("l7_s1_b0_f0_r1") == 25)
	check("street is outdoors", WorldData.is_outdoors("l16_s3_b0_f0_r1"))
	check("subway (b0, dimmed) is indoors", not WorldData.is_outdoors("l12_s2_b0_f0_r100"))
	check("backyard flagged outside is outdoors", WorldData.is_outdoors("l9_s1_b2_f1_r3"))
	check("safehouse by room flag", WorldData.is_safehouse("l16_s3_b1_f1_r1"))
	check("safehouse by building flag", WorldData.is_safehouse("l16_s3_b1_f2_r2"))
	check("not a safehouse", not WorldData.is_safehouse("l16_s3_b2_f1_r1"))
	check("width from layout", is_equal_approx(WorldData.width_px("l16_s3_b1_f1_r1"), 752.0))
	check("cork street name", WorldData.street_name("l16_s3_b2_f1_r1") == "MAIN STREET")
	var links := WorldData.links("l16_s3_b0_f0_r1")
	var by := {}
	for l in links:
		by[l.name] = l
	check("entrance leads to f1 r1", by.entr2.target == "l16_s3_b2_f1_r1" and by.entr2.spawn.marker == "exit2")
	check("street edge left -> street 2", by.strt1.target == "l16_s2_b0_f0_r1" and by.strt1.spawn.edge == "right")
	check("area exit -> map", by.area1.target == "map")
	var inside := {}
	for l in WorldData.links("l16_s3_b2_f1_r1"):
		inside[l.name] = l
	check("left door -> room 0", inside.door1.target == "l16_s3_b2_f1_r0")
	check("right door -> room 2", inside.door2.target == "l16_s3_b2_f1_r2")
	check("exit -> street at entr2", inside.exit2.target == "l16_s3_b0_f0_r1" and inside.exit2.spawn.marker == "entr2")
	var locked := {}
	for l in WorldData.links("l16_s3_b4_f1_r1"):
		locked[l.name] = l
	check("locked door fields", locked.door2.locked and locked.door2.needs_key and locked.door2.lock_diff == "very hard"
			and locked.door2.door_id == "l16_s3_b4_f1_r1_door2")
	var boarded := {}
	for l in WorldData.links("l6_s1_b0_f0_r1"):
		boarded[l.name] = l
	check("entrance without a building is a dead end", boarded.entr3.target == "")
	check("spawn x clamps to the edge buffer", is_equal_approx(WorldData.spawn_x_px("l16_s3_b1_f1_r1", {"edge": "right"}), 702.0))


## Every room of every section builds; widths and bounds match the data; no
## solid body other than the floor and the two end walls is in the lane.
func test_build_all() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var builder := LevelBuilder.new()
	var sections_ok := 0
	var rooms := 0
	var built := 0
	var width_bad: Array = []
	var lane_bad: Array = []
	var placed_bad: Array = []
	for i in range(1, 17):
		var sec := str(i)
		var start := WorldData.start_room(sec)
		var lv := builder.build(start)
		if lv != null:
			sections_ok += 1
			lv.free()
		for rid in WorldData.rooms_of(sec):
			rooms += 1
			var level := builder.build(rid)
			if level == null:
				continue
			built += 1
			holder.add_child(level)
			if WorldData.has_layout(rid):
				var data_w: float = float(WorldData.layout_table(sec)[rid].width)
				if not is_equal_approx(level.width_px, data_w):
					width_bad.append(rid)
			var right: StaticBody3D = level.get_node("BoundRight")
			if not is_equal_approx(right.get_child(0).global_position.x - 0.2, level.width_units()):
				width_bad.append(rid + " bound")
			for bad in _lane_intruders(level):
				lane_bad.append("%s %s" % [rid, bad])
			var expect_conts := WorldData.containers(rid).size()
			var expect_npcs := WorldData.npcs(rid).size()
			var conts := level.get_node("Things").get_children().filter(func(n): return n.has_meta("container_id")).size()
			var npcs := level.get_node("Things").get_children().filter(func(n): return n.has_meta("npc_id")).size()
			if conts != expect_conts or npcs != expect_npcs:
				placed_bad.append(rid)
			holder.remove_child(level)
			level.free()
	holder.free()
	check("all 16 sections build their start room", sections_ok == 16, "%d/16" % sections_ok)
	check("every room of every section builds", built == rooms and rooms > 280, "%d/%d" % [built, rooms])
	check("level widths and bounds match the data", width_bad.is_empty(), str(width_bad.slice(0, 5)))
	check("nothing but player/zombies collides in the Z=0 lane", lane_bad.is_empty(), str(lane_bad.slice(0, 5)))
	check("one container node per contN and one NPC per NPCs entry", placed_bad.is_empty(), str(placed_bad.slice(0, 5)))


## Solid bodies (not Areas) whose shapes reach into the lane, other than the
## floor (under it) and the bounds (its ends).
func _lane_intruders(level: Node) -> Array:
	var out: Array = []
	for body in level.find_children("*", "CollisionObject3D", true, false):
		if body is Area3D or body.is_in_group("level_floor") or body.is_in_group("level_bounds"):
			continue
		if body is CharacterBody3D and (body.is_in_group("player") or body is Zombie):
			continue
		for cs in body.find_children("*", "CollisionShape3D", true, false):
			if cs.shape == null or cs.disabled:
				continue
			var aabb: AABB = cs.global_transform * cs.shape.get_debug_mesh().get_aabb()
			if aabb.position.z < LANE_HALF_Z and aabb.end.z > -LANE_HALF_Z and aabb.end.y > 0.05 and aabb.position.y < 1.9:
				out.append(str(body.name))
	return out


## The lane check must actually see a solid body standing in the lane.
func test_lane_detector() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var level := LevelBuilder.new().build("l16_s3_b1_f1_r1")
	holder.add_child(level)
	check("built room has no lane intruders", _lane_intruders(level).is_empty())
	var crate := StaticBody3D.new()
	crate.name = "BadCrate"
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1, 1, 1)
	cs.shape = box
	crate.add_child(cs)
	crate.position = Vector3(3, 0.5, -0.2)
	level.add_child(crate)
	check("a crate in the lane is caught", _lane_intruders(level) == ["BadCrate"])
	crate.position.z = -1.2
	check("the same crate recessed is fine", _lane_intruders(level).is_empty())
	holder.free()


const FAKE_SETUP := """
extends Node3D
var args: Array = []
var setup_before_tree: bool = false
func setup(a = null, b = null, c = null, d = null) -> void:
	args = [a, b, c, d].filter(func(v): return v != null)
	setup_before_tree = not is_inside_tree()
"""


func _fake_scene() -> PackedScene:
	var script := GDScript.new()
	script.source_code = FAKE_SETUP
	script.reload()
	var n := Node3D.new()
	n.set_script(script)
	var ps := PackedScene.new()
	ps.pack(n)
	n.free()
	return ps


## The container and NPC seams: one instance per entry, setup() called with
## the agreed arguments before the node enters the tree, placed off the lane.
func test_seams() -> void:
	var builder := LevelBuilder.new()
	builder.container_scene = _fake_scene()
	builder.npc_scene = _fake_scene()
	var level := builder.build("l16_s3_b1_f1_r1")
	var things := level.get_node("Things")
	var c1: Node3D = things.get_node("Container_cont1")
	check("container setup(id, def, room type, danger)", c1.args.size() == 4 and c1.args[0] == "l16/s3/b1/f1/r1/cont1"
			and c1.args[1].desc == "Suitcase" and c1.args[2] == "anywhere" and c1.args[3] == 1, str(c1.args))
	check("container setup runs before it enters the tree", c1.setup_before_tree)
	# The container recesses its own body and reaches its trigger to the lane, so its origin is Z=0.
	check("container placed at its art marker", absf(c1.position.x - 0.582) < 0.01 and is_zero_approx(c1.position.z))
	check("one container per contN", things.get_children().filter(func(n): return n.name.begins_with("Container_")).size() == 3)
	var npc: Node3D = things.get_node("NPC_Jackson")
	check("npc setup(npc_id) at NPC_x, off the lane", npc.args == ["Jackson"] and absf(npc.position.x - 3.5) < 0.01 and npc.position.z < -0.5)
	level.free()


func test_links_two_way() -> void:
	var bad: Array = []
	var dead := 0
	var total := 0
	for i in range(1, 17):
		for rid in WorldData.rooms_of(str(i)):
			for l in WorldData.links(rid):
				if l.target == "" :
					dead += 1
					continue
				if l.target == "map" or not (l.kind in TWO_WAY):
					continue
				total += 1
				if ONE_WAY.has("%s:%s" % [rid, l.name]):
					continue
				var back := false
				for l2 in WorldData.links(l.target):
					if l2.target == rid:
						back = true
						break
				if not back:
					bad.append("%s:%s" % [rid, l.name])
	check("door links resolve both ways", bad.is_empty() and total > 400, "%d links, bad %s" % [total, str(bad.slice(0, 6))])
	check("dead ends are only boarded entrances and missing neighbours", dead < 60, str(dead))


func test_container_ids() -> void:
	var dupes: Array = []
	var count := 0
	for i in range(1, 17):
		var seen := {}
		for rid in WorldData.rooms_of(str(i)):
			for c in WorldData.containers(rid):
				count += 1
				if seen.has(c.id):
					dupes.append(c.id)
				seen[c.id] = true
				if not c.id.begins_with("l%d/" % i) or not c.id.ends_with("/" + c.key):
					dupes.append("format " + c.id)
	# 470 in the 15 sections with streets plus 21 in section 1 (read as street 1)
	check("container ids unique and stable across each section", dupes.is_empty() and count == 491, "%d, %s" % [count, str(dupes.slice(0, 4))])


func test_safehouse_and_director(world: Node) -> void:
	var director := autoload("Director")
	var safe: Array = []
	var wrong: Array = []
	for i in range(1, 17):
		for rid in WorldData.rooms_of(str(i)):
			if WorldData.is_safehouse(rid):
				safe.append(rid)
	for rid in safe:
		world.enter_room(rid)
		if not (director.safehouse and director.max_zombies == 0 and world.current.safehouse and world.is_safehouse()):
			wrong.append(rid)
	check("every safehouse room reports safehouse to the Director", wrong.is_empty() and safe.size() > 30, "%d rooms, wrong %s" % [safe.size(), str(wrong)])
	world.enter_room("l16_s3_b0_f0_r1")
	check("street: Director gets danger, width, outdoors, area id",
			director.danger == 1 and is_equal_approx(director.width_px, 3174.1) and director.outdoors
			and not director.safehouse and director.area_id == "l16_s3_b0_f0_r1")
	var keys := ["section", "street", "building", "floor", "room", "danger", "width_px", "outdoors", "safehouse"]
	var has_all := true
	for k in keys:
		has_all = has_all and world.current.has(k)
	check("current has the contract keys", has_all)
	world.enter_room("l16_s3_b2_f1_r1")
	check("room: indoors, building 2 floor 1", not director.outdoors and world.current.building == 2 and world.current.floor == 1)


func test_travel(world: Node) -> void:
	var clock := autoload("Clock")
	check("travel hours 16 -> 9 = round((8 + 484.1) / 200) = 2", WorldData.travel_hours("16", "9") == 2)
	check("travel hours 16 -> 13 = round(701.7 / 200) = 4", WorldData.travel_hours("16", "13") == 4)
	check("travel hours 9 -> 5 = round(1314.6 / 200) = 7", WorldData.travel_hours("9", "5") == 7)
	check("travel hours to a section off the map = 0", WorldData.travel_hours("16", "1") == 0)
	world.enter_location("16")
	var before: int = clock.game_minutes
	autoload("Quests").unlock_section("9")  # sections open through quests
	var ok: bool = world.travel_to("9")
	check("travel_to 9 advances the clock 2 h", ok and clock.game_minutes - before == 120, str(clock.game_minutes - before))
	check("travel_to lands at the section's startLoc", world.room_id == "l9_s1_b0_f0_r1" and world.current.section == "9")
	check("travel to a story-link section is refused", not world.travel_to("1") and not world.travel_to("8"))
	check("enter_location at the end uses endLoc", world.enter_location("16", true) and world.room_id == "l16_s3_b0_f0_r1")


func test_map_nodes(world: Node) -> void:
	var nodes: Array = world.map_nodes()
	var by := {}
	for n in nodes:
		by[n.id] = n
	check("map has 16 nodes", nodes.size() == 16)
	check("map node 16 is Ballincollig, danger 1, on the map", by["16"].name == "Ballincollig" and by["16"].danger == 1 and by["16"].pos is Vector2)
	check("map node connections from sections", by["16"].connections == ["9", "13"])
	check("story links are not travelable", not by["1"].travelable and not by["8"].travelable and by["7"].travelable)


func test_run_scene(world: Node) -> void:
	world.reset()
	var scn = await load_scene("res://scenes/main.tscn")
	await frames(3)
	var player: Node3D = scn.get_player()
	var level: Level = world.level()
	check("run scene starts a new game at the Cork start", world.room_id == "l16_s1_b0_f0_r1" and level != null)
	check("player spawns at the start edge on the lane", absf(player.global_position.x - 0.5) < 0.2 and is_zero_approx(player.global_position.z))
	check("Director attached to the level", autoload("Director").spawn_root == level.spawn_root() and autoload("Director").player == player)
	world.enter_room("l16_s3_b0_f0_r1", "entr3")
	await frames(2)
	check("enter_room spawns at a marker", absf(player.global_position.x - 18.369) < 0.05, str(player.global_position.x))
	var cam: Node3D = scn.get_node("CameraRig")
	check("camera limited to the room", cam.limit_min == 0.0 and is_equal_approx(cam.limit_max, 31.741))
	world.enter_room("l16_s3_b2_f1_r1", "exit2")
	await frames(2)
	check("lighting uses the room's light reduction", is_equal_approx(scn.get_node("DayNight").light_reduction, 40.0))
	# walk into the right-hand end wall with the real move action
	world.enter_room("l16_s3_b2_f1_r1", "right")
	await frames(2)
	Input.action_press("move_right")
	await frames(45)
	Input.action_release("move_right")
	var w: float = world.level().width_units()
	check("the floor holds the player", player.global_position.y > 0.5 and player.global_position.y < 1.2, str(player.global_position.y))
	check("the end wall stops the player inside the room", player.global_position.x < w and player.global_position.x > w - 0.8,
			"%.2f of %.2f" % [player.global_position.x, w])
	check("the player stays on the lane", is_zero_approx(player.global_position.z))


## Walk into the entrance trigger, press interact, arrive inside at the exit.
func test_interact_through_door(world: Node) -> void:
	var scn: Node = current_scene
	var player: Node3D = scn.get_player()
	world.enter_room("l16_s3_b0_f0_r1", "entr2")
	await frames(6)
	var entered: Array = []
	var cb := func(id): entered.append(id)
	autoload("Events").location_entered.connect(cb)
	Input.action_press("interact")
	await frames(2)
	Input.action_release("interact")
	await frames(3)
	autoload("Events").location_entered.disconnect(cb)
	check("interact at an entrance enters the building", world.room_id == "l16_s3_b2_f1_r1", world.room_id)
	check("location_entered emitted", entered == ["l16_s3_b2_f1_r1"], str(entered))
	check("spawned at the matching exit", absf(player.global_position.x - 3.569) < 0.05, str(player.global_position.x))
	# and back out through the exit
	await frames(4)
	Input.action_press("interact")
	await frames(2)
	Input.action_release("interact")
	await frames(3)
	check("exit returns to the street at the entrance", world.room_id == "l16_s3_b0_f0_r1" and absf(player.global_position.x - 10.57) < 0.05,
			"%s %.2f" % [world.room_id, player.global_position.x])
	# stairs: up and back down
	world.enter_room("l16_s3_b2_f1_r3", "sup")
	await frames(2)
	world.use_link(world.level().link_named("sup").link)
	check("stairs up go to the same room a floor up, at its stairs down", world.room_id == "l16_s3_b2_f2_r3"
			and absf(player.global_position.x - 4.4) < 0.05)
	world.use_link(world.level().link_named("sdwn").link)
	check("stairs down come back", world.room_id == "l16_s3_b2_f1_r3")
	world.use_link(world.level().link_named("door2").link)
	check("left door goes to the previous room at its right edge", world.room_id == "l16_s3_b2_f1_r2"
			and absf(player.global_position.x - 4.621) < 0.05, "%s %.2f" % [world.room_id, player.global_position.x])


func test_locked_doors(world: Node) -> void:
	var inv := autoload("Inventory")
	var refused: Array = []
	var cb := func(id, reason): refused.append([id, reason])
	world.door_refused.connect(cb)
	world.enter_room("l16_s3_b4_f1_r1", "door2")
	var link: Dictionary = world.level().link_named("door2").link
	world.use_link(link)
	check("key door stays shut without the key", world.room_id == "l16_s3_b4_f1_r1" and refused.size() == 1 and refused[0][1] == "needs key")
	var key_name: String = Data_entry("questItem", "edKey").get("name", "edKey")
	inv.add_item(key_name, 0.0)
	world.use_link(link)
	check("the key opens it and is used up", world.room_id == "l16_s3_b4_f1_r2" and not inv.has_item(key_name))
	check("unlocked state is remembered", world.door_locks.get("l16_s3_b4_f1_r1_door2") == false)
	world.enter_room("l16_s3_b4_f1_r1", "door2")
	world.use_link(world.level().link_named("door2").link)
	check("an unlocked door stays open", world.room_id == "l16_s3_b4_f1_r2")
	# a lockpick door (no key needed) is gated by Locks: skill check, then the minigame
	world.enter_room("l12_s2_b1_f1_r2")
	world.use_link(world.level().link_named("room101").link)
	check("lockpick door is gated by Locks, not opened for free", world.room_id == "l12_s2_b1_f1_r2")
	for n in root.get_children():
		if n.get_script() != null and str(n.get_script().resource_path).ends_with("lock_ui.gd"):
			n.queue_free()
	world.door_refused.disconnect(cb)
	# a boarded entrance refuses
	world.enter_room("l6_s1_b0_f0_r1")
	var dead := {"name": "entr3", "kind": "entr", "target": "", "door_id": "x", "locked": false}
	world.use_link(dead)
	check("a dead-end entrance does nothing", world.room_id == "l6_s1_b0_f0_r1")


func Data_entry(table: String, key: String) -> Dictionary:
	return autoload("Data").entry(table, key)


func test_round_trip(world: Node) -> void:
	var scn: Node = current_scene
	var player: Node3D = scn.get_player()
	world.enter_room("l11_s1_b2_f3_r1", "x:612")
	await frames(2)
	var saved: Dictionary = world.to_dict()
	check("to_dict has room and player x", saved.room_id == "l11_s1_b2_f3_r1" and absf(saved.player_x_px - 612.0) < 3.0, str(saved))
	world.enter_room("l16_s1_b0_f0_r1")
	await frames(2)
	world.from_dict(saved)
	await frames(2)
	check("from_dict puts the player back in the same room", world.room_id == "l11_s1_b2_f3_r1" and world.level().room_id == "l11_s1_b2_f3_r1")
	check("from_dict puts the player back at the same x", absf(player.global_position.x - 6.12) < 0.05, str(player.global_position.x))
	world.reset()
	check("reset clears the location", world.room_id == "" and world.current.is_empty())
