extends "res://tests/test_base.gd"
## Two containers with overlapping triggers: one E press opens only the nearest.


func run() -> void:
	var scn := Node3D.new()
	root.add_child(scn)
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	scn.add_child(player)
	var scene: PackedScene = load("res://scenes/loot/container.tscn")
	var a = scene.instantiate()
	var b = scene.instantiate()
	a.setup("test/a", {"desc": "Box", "cnt": []}, "anywhere", 1)
	b.setup("test/b", {"desc": "Box", "cnt": []}, "anywhere", 1)
	scn.add_child(a)
	scn.add_child(b)
	a.position = Vector3(10.0, 0, 0)
	b.position = Vector3(10.8, 0, 0)
	player.global_position = Vector3(10.2, 0, 0)
	a.player_in_range = player
	b.player_in_range = player
	check("nearer container is a", a.wants_interact() and not b.wants_interact())
	player.global_position = Vector3(10.7, 0, 0)
	check("nearer container is b", b.wants_interact() and not a.wants_interact())

	# a wide box and a narrow neighbour: facing the wide box's edge still opens the wide box
	a.position = Vector3(20.0, 0, 0)
	a.title = "Bookcase" # wide
	b.title = "Bag" # narrow
	var half: float = a.visual_for("Bookcase")["size"].x * 0.5
	b.position = Vector3(20.0 + half + 0.15, 0, 0)
	var px := 20.0 + half - 0.05 # inside a's span, nearer b's centre
	player.global_position = Vector3(px, 0, 0)
	check("facing a wide box beats a closer centre", a.reach_distance(px) == 0.0 and a.wants_interact() and not b.wants_interact(),
			"a=%f b=%f" % [a.reach_distance(px), b.reach_distance(px)])
	# same x, front row beats back row
	a.position = Vector3(30.0, 0, 0)
	b.position = Vector3(30.0, 0, 0)
	a.recess_z = -2.05
	b.recess_z = -1.4
	player.global_position = Vector3(30.0, 0, 0)
	check("front row wins a tie", b.wants_interact() and not a.wants_interact())
