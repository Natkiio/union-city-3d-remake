extends "res://tests/test_base.gd"
## The player can press interact on containers and NPCs placed by the level
## builder, not only on doors. Regression for triggers sitting off the Z=0 lane.

const ROOM := "l16_s3_b1_f1_r1" # two containers and the NPC Jackson


func run() -> void:
	var world := autoload("World")
	world.fade_enabled = false
	autoload("Clock").running = false
	autoload("Director").enabled = false
	world.reset()
	var scn = await load_scene("res://scenes/main.tscn")
	await frames(3)
	var player: Node3D = scn.get_player()
	world.enter_room(ROOM)
	await frames(3)
	var level: Level = world.level()

	var containers: Array = []
	var npcs: Array = []
	for n in level.get_children():
		_collect(n, containers, npcs)
	check("room has containers and an NPC", containers.size() >= 2 and npcs.size() >= 1,
		"containers=%d npcs=%d" % [containers.size(), npcs.size()])

	for c in containers:
		await _stand_at(player, c)
		check("container %s sees the player" % c.name, c.player_in_range == player)
	var box: Node3D = containers[0]
	await _stand_at(player, box)
	await _press_interact()
	await seconds(box.SEARCH_TIME + 0.4)
	check("interact opens the container panel", autoload("TrunkUI").visible)
	autoload("TrunkUI").hide()
	get_root_paused(false)

	for n in npcs:
		await _stand_at(player, n)
		check("NPC %s sees the player" % n.name, n.player_in_range == player)
	var npc: Node3D = npcs[0]
	await _stand_at(player, npc)
	await _press_interact()
	var boxes := root.find_children("*", "DialogueBox", true, false)
	check("interact on an NPC opens the dialogue box", boxes.size() > 0 and boxes[0].visible and paused,
		"boxes=%d" % boxes.size())


func get_root_paused(value: bool) -> void:
	paused = value


func _collect(n: Node, containers: Array, npcs: Array) -> void:
	if n.has_method("search_now"):
		containers.append(n)
	elif n.has_method("interact") and n.is_in_group("npc"):
		npcs.append(n)
	for c in n.get_children():
		_collect(c, containers, npcs)


func _stand_at(player: Node3D, target: Node3D) -> void:
	player.global_position = Vector3(target.global_position.x, 0.1, 0.0)
	player.velocity = Vector3.ZERO
	await frames(3)


func _press_interact() -> void:
	Input.action_press("interact")
	await frames(2)
	Input.action_release("interact")
	await frames(2)
