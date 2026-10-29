extends "res://tests/test_base.gd"
## NPCs are dressed rigs (CharacterLook on male_basic), not boxes.

const MALE := "res://scenes/characters/male_basic.tscn"
const NPC := "res://scenes/story/npc.tscn"
const MAX_MESHES := 12
const MAX_NODES := 80


func run() -> void:
	var world := autoload("World")
	world.fade_enabled = false
	autoload("Clock").running = false
	autoload("Director").enabled = false
	world.reset()
	var scn = await load_scene("res://scenes/main.tscn")
	var quests := autoload("Quests")
	var ids: Array = quests.npc_ids()
	check("npc ids found", ids.size() >= 50, str(ids.size()))

	# 1. every record applies to a fresh rig
	var bad: Array = []
	var holder := Node3D.new()
	root.add_child(holder)
	for id in ids:
		var m: Node3D = load(MALE).instantiate()
		holder.add_child(m)
		CharacterLook.apply(m, quests.npc_def(id))
		var mats: Array = m.get_meta("look_materials", [])
		if mats.size() != 2:
			bad.append(id)
		m.queue_free()
	check("every npc record applies", bad.is_empty(), str(bad))

	# 2. distinct clothes give distinct colours
	var by_name := {}
	for id in ids:
		var d: Dictionary = quests.npc_def(id)
		var n := str(d.get("clothesTop", "")).trim_prefix("male_").trim_prefix("female_")
		if n != "" and n != "none":
			by_name[n] = CharacterLook.top_color(str(d.clothesTop))
	var seen := {}
	var dup: Array = []
	for n in by_name:
		var key: Color = by_name[n]
		if seen.has(key):
			dup.append("%s=%s" % [n, seen[key]])
		seen[key] = n
	check("distinct tops have distinct colours", dup.is_empty(), "%d tops %s" % [by_name.size(), dup])
	check("unknown names fall back to a default",
			CharacterLook.top_color("male_zzz") != Color.BLACK and CharacterLook.bottom_color("zzz") != Color.BLACK
			and CharacterLook.shoe_color("zzz").a == 1.0 and CharacterLook.skin_color("zzz") == CharacterLook.SKIN["white"])
	var skins := {}
	for k in ["White", "Tanned", "Black", "Olive"]:
		skins[CharacterLook.skin_color(k)] = true
	check("skin colours differ", skins.size() == 4)
	var a: Node3D = load(MALE).instantiate()
	var b: Node3D = load(MALE).instantiate()
	holder.add_child(a)
	holder.add_child(b)
	CharacterLook.apply(a, quests.npc_def("Williams"))
	CharacterLook.apply(b, quests.npc_def("DrSmith"))
	var ca: Color = (a.get_meta("look_materials")[0] as ShaderMaterial).get_shader_parameter("top")
	var cb: Color = (b.get_meta("look_materials")[0] as ShaderMaterial).get_shader_parameter("top")
	check("applied surfaces differ (olive vs hazmat yellow)", ca != cb, "%s %s" % [ca, cb])
	var fem: Dictionary = quests.npc_def("Carol")
	var m2: Node3D = load(MALE).instantiate()
	holder.add_child(m2)
	CharacterLook.apply(m2, fem)
	check("female is slimmer", m2.scale.x < 1.0 and a.scale.x == 1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var styles := {}
	for i in 12:
		var r := CharacterLook.random_record(rng)
		var m3: Node3D = load(MALE).instantiate()
		holder.add_child(m3)
		CharacterLook.apply(m3, r)
		styles[str(r.clothesTop) + str(r.hair) + str(r.skinColour)] = true
		m3.queue_free()
	check("random_record gives varied crowds", styles.size() >= 6, str(styles.size()))
	var pl: Node3D = load(MALE).instantiate()
	holder.add_child(pl)
	CharacterLook.apply(pl, CharacterLook.random_record(rng))
	CharacterLook.apply(pl, CharacterLook.random_record(rng)) # re-apply must not pile up
	check("re-apply replaces accessories", pl.find_children("LookBox*", "MeshInstance3D", true, false).size() <= MAX_MESHES)
	holder.queue_free()

	# 3. the scene builds for every NPC id
	var player: Node3D = scn.get_player()
	var worst_meshes := 0
	var worst_nodes := 0
	var build_bad: Array = []
	var idle_bad: Array = []
	var created: Array = []
	for id in ids:
		var n: Node3D = load(NPC).instantiate()
		n.setup(id)
		scn.add_child(n)
		created.append(n)
		var model: Node3D = n.get_node_or_null("Visual/Model")
		if model == null or n.model != model:
			build_bad.append(id)
			continue
		var ap := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if ap == null or ap.current_animation != "Idle" or not ap.is_playing():
			idle_bad.append(id)
		worst_meshes = maxi(worst_meshes, model.find_children("*", "MeshInstance3D", true, false).size())
		worst_nodes = maxi(worst_nodes, n.get_node("Visual").find_children("*", "", true, false).size())
		if n.head_top_y() < 1.5 or n.head_top_y() > 2.4 or not n.is_in_group("world_interactable"):
			build_bad.append(id + ":top")
	check("NPC scene builds for every id", build_bad.is_empty(), str(build_bad))
	check("Idle plays on every NPC", idle_bad.is_empty(), str(idle_bad))
	check("mesh count per NPC small", worst_meshes <= MAX_MESHES, str(worst_meshes))
	check("node count per NPC small", worst_nodes <= MAX_NODES, str(worst_nodes))
	for n in created:
		n.queue_free()
	await frames(2)

	# 4. built by the level builder in at least five rooms
	var rooms: Array = []
	for sec in range(1, 17):
		for r in WorldData.rooms_of(sec):
			if WorldData.npcs(r).size() > 0:
				rooms.append(r)
	check("found rooms with npcs", rooms.size() >= 5, str(rooms.size()))
	var built := 0
	var placed := 0
	var room_bad: Array = []
	for r in rooms.slice(0, 8):
		world.enter_room(r)
		await frames(3)
		var nodes: Array = world.level().find_children("NPC_*", "Area3D", true, false)
		for n in nodes:
			placed += 1
			if n.get_node_or_null("Visual/Model") == null or not n.has_method("head_top_y"):
				room_bad.append(str(n.name))
			if absf(n.global_position.z) < 0.5:
				room_bad.append(str(n.name) + " not recessed")
		if nodes.size() > 0:
			built += 1
	check("NPCs built in >=5 rooms", built >= 5 and room_bad.is_empty(), "rooms=%d npcs=%d bad=%s" % [built, placed, room_bad])

	# 5. visual change keeps interaction working
	world.enter_room("l16_s3_b1_f1_r1")
	await frames(3)
	var level: Level = world.level()
	var npc: Node3D = null
	for n in level.find_children("NPC_*", "Area3D", true, false):
		npc = n
	check("room has an NPC", npc != null)
	if npc != null:
		player.global_position = Vector3(npc.global_position.x + 3.0, 0.1, 0.0)
		await frames(3)
		var away: float = npc.model.rotation.y
		player.global_position = Vector3(npc.global_position.x - 2.0, 0.1, 0.0)
		await frames(3)
		check("faces the player on either side", npc.model.rotation.y != away and npc.model.rotation.y > 0.0,
				"%f %f" % [away, npc.model.rotation.y])
		player.global_position = Vector3(npc.global_position.x, 0.1, 0.0)
		player.velocity = Vector3.ZERO
		await frames(3)
		check("NPC sees the player", npc.player_in_range == player and npc.wants_interact())
		Input.action_press("interact")
		await frames(2)
		Input.action_release("interact")
		await frames(2)
		var boxes := root.find_children("*", "DialogueBox", true, false)
		check("interact opens the dialogue", boxes.size() > 0 and boxes[0].visible and paused)
		paused = false
		npc.set_highlighted(true)
		var mat: ShaderMaterial = npc.model.get_meta("look_materials")[0]
		check("hover brightens the rig", float(mat.get_shader_parameter("boost")) > 0.0 and npc._label.visible)
		npc.set_highlighted(false)
		check("hover clears", float(mat.get_shader_parameter("boost")) == 0.0 and not npc._label.visible)
