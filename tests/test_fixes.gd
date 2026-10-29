extends "res://tests/test_base.gd"
## Issues #35 (walk speed) and #30 (health restored on room change).


func run() -> void:
	var world := autoload("World")
	world.fade_enabled = false
	autoload("Clock").running = false
	autoload("Director").enabled = false
	var gs := autoload("GameState")
	gs.reset_run()
	world.reset()
	var scn = await load_scene("res://scenes/main.tscn")
	await frames(3)
	var player = scn.get_player()
	check("walk speed lowered to 4.5", is_equal_approx(player.SPEED, 4.5))
	check("run is x1.5", is_equal_approx(player.SPEED * player.RUN_SPEED_MULT, 6.75))
	# a plain-slow zombie must stay clearly slower than walking, fast ones than running
	var slow: float = ZombieType.BASE_CHASE_SPEED
	check("player walk outpaces slow zombie", player.SPEED > slow * 1.5)

	player.take_damage(40.0, "chest")
	var h: float = player.health
	var perm: float = player.perm_health
	check("damage applied", h < player.max_health and perm < player.max_health)
	world.enter_room("l16_s3_b0_f0_r1", "entr3")
	await frames(3)
	check("room change keeps health", absf(player.health - h) < 1.0, "%.1f vs %.1f" % [player.health, h])
	check("room change keeps perm health", absf(player.perm_health - perm) < 0.01)

	# a freshly built player (scene reload) restores instead of healing
	var p2 = load("res://scenes/player/player.tscn").instantiate()
	scn.add_child(p2)
	await frames(2)
	check("new player restores vitals", absf(p2.health - h) < 1.0 and absf(p2.perm_health - perm) < 0.01,
			"%.1f/%.1f" % [p2.health, p2.perm_health])
	p2.queue_free()
	await frames(2)

	# travel
	world.travel_to("9")
	await frames(3)
	check("travel keeps health", absf(player.health - h) < 1.0, "%.1f" % player.health)

	# save/load round trip of the state
	var d: Dictionary = gs.to_dict()
	gs.reset()
	gs.from_dict(d)
	check("GameState dict round trip", gs.has_vitals and absf(gs.vit_perm_health - perm) < 0.01)

	# new run heals
	gs.reset_run()
	check("reset_run clears stored vitals", not gs.has_vitals)
