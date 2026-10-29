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
