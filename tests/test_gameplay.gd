extends "res://tests/test_base.gd"
## Gameplay workstream: the seams between combat, zombies, stats, items and the
## player. Everything here drives real nodes (the player scene, zombies,
## bullets), not stubs. Balance numbers are printed as "[BALANCE]" lines and
## are the baseline recorded in docs/gameplay.md.

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const BulletScn := preload("res://scenes/weapons/bullet.tscn")

var world: Node3D
var player: CharacterBody3D
var killed: Array = []
var damaged: Array = []


func run() -> void:
	autoload("Events").enemy_killed.connect(func(r, d, xp): killed.append([r, d, xp]))
	autoload("Events").player_damaged.connect(func(a, _s): damaged.append(a))
	await test_kill_xp()
	await test_armor()
	await test_grab()
	await test_vitals()
	await test_movement()
	_cleanup()


# --- helpers ----------------------------------------------------------------

func fresh_stats() -> void:
	autoload("Stats").reset()
	autoload("Survival").reset()
	autoload("Inventory").reset()
	autoload("Director").reset()


## A floor and the real player scene at x=0, facing +x. Zombies are spawned
## with spawn() and frozen unless the test needs them to act.
func make_world() -> void:
	_cleanup()
	world = Node3D.new()
	root.add_child(world)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 1, 10)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0, -0.5, 0)
	world.add_child(floor_body)
	player = (load(PLAYER_SCENE) as PackedScene).instantiate()
	player.position = Vector3(0, 1.0, 0)
	world.add_child(player)
	player.rng.seed = 11
	killed.clear()
	damaged.clear()


func _cleanup() -> void:
	Engine.time_scale = 1.0
	if world != null and is_instance_valid(world):
		world.free()
	world = null


func spawn(ref: String, x: float, danger: int = 1, frozen: bool = true) -> Zombie:
	var z := Zombie.spawn(world, ref, danger, x)
	z.rng.seed = 7
	if frozen:
		z.set_physics_process(false)
	return z


func give_gun(ref: String) -> Weapon:
	var gun := Weapon.from_ref(ref)
	var inv := autoload("Inventory")
	inv.add_item(gun.display_name, 1.0)
	inv.add_item(gun.ammo_item_name(), 0.1, 60)
	player.call("_set_equipped", ref)
	return gun


func tap(action: String) -> void:
	Input.action_press(action)
	await frames(2)
	Input.action_release(action)
	await frames(2)


# --- 1. kill XP end to end ----------------------------------------------------

func test_kill_xp() -> void:
	fresh_stats()
	make_world()
	await frames(10) # land
	var stats := autoload("Stats")

	# Punch: the real swing, through the hand hitbox (the zombie stands at arm's length).
	var z := spawn("zombieSlow", 0.85)
	z.health = 1.0
	player.call("_start_punch")
	await seconds(0.5)
	check("punch kills and emits enemy_killed(ref, danger, xp) once",
			killed == [["zombieSlow", 1, 10]], str(killed))
	check("punch kill pays 10 XP (round((1*5+5)*1))", stats.xp == 10, str(stats.xp))

	# Shove chain: three shoves of 1 damage each.
	killed.clear()
	z = spawn("zombieSlow", 1.0)
	z.health = 3.0
	var shoves := 0
	while is_instance_valid(z) and not z.is_dead() and shoves < 6:
		player.shove_cooldown = 0.0
		player.call("_shove")
		shoves += 1
		await frames(1)
	check("shove chain kills in 3 shoves", shoves == 3, str(shoves))
	check("shove kill emits once and pays 10 more XP", killed == [["zombieSlow", 1, 10]] and stats.xp == 20,
			"%s xp=%d" % [str(killed), stats.xp])

	# Bullet: a G17 round through the bullet scene (miss rolls apply, so keep firing).
	killed.clear()
	var gun := give_gun("glock")
	z = spawn("zombieSlow", 3.0)
	z.health = 1.0
	var shots := 0
	while is_instance_valid(z) and not z.is_dead() and shots < 30:
		player.attack_cooldown = 0.0
		player.call("_fire_round", gun)
		shots += 1
		await seconds(0.25)
	check("bullet kills the zombie", z == null or not is_instance_valid(z) or z.is_dead(), "shots=%d" % shots)
	check("bullet kill emits enemy_killed exactly once", killed == [["zombieSlow", 1, 10]], str(killed))
	check("bullet kill pays 10 more XP (no double count)", stats.xp == 30, str(stats.xp))

	# Anti-farming: level - danger > 4 pays nothing; exactly 4 still pays.
	killed.clear()
	stats.level = 5
	stats.xp = 0
	z = spawn("zombieSlow", 3.0, 1)
	z.take_damage(1000.0, "head", player)
	check("level 5 vs danger 1 (diff 4) still pays 10", stats.xp == 10, str(stats.xp))
	stats.level = 6
	stats.xp = 0
	z = spawn("zombieSlow", 3.0, 1)
	z.take_damage(1000.0, "head", player)
	check("level 6 vs danger 1 (diff 5) pays nothing but the event still fires",
			stats.xp == 0 and killed.size() == 2 and killed[1] == ["zombieSlow", 1, 10], "%d %s" % [stats.xp, str(killed)])
	z = spawn("zombieSlow", 3.0, 2)
	z.take_damage(1000.0, "head", player)
	check("level 6 vs danger 2 pays round((2*5+5)*1) = 15", stats.xp == 15, str(stats.xp))

	# Level-up: XP resets, points granted, health restored to the new maximum.
	stats.level = 1
	stats.xp = 95
	stats.attribute_points = 0
	stats.skill_points = 0
	player.refresh_vitals()
	player.take_damage(30.0)
	z = spawn("zombieSlow", 3.0, 1)
	z.take_damage(1000.0, "head", player)
	check("level-up: level 2, XP reset, 1 attribute and 10 skill points",
			stats.level == 2 and stats.xp == 0 and stats.attribute_points == 1 and stats.skill_points == 10,
			"L%d xp=%d" % [stats.level, stats.xp])
	check("level-up raises max health to 65 and restores health and perm health",
			player.max_health == 65.0 and player.health == 65.0 and player.perm_health == 65.0,
			"%s %s/%s" % [player.max_health, player.health, player.perm_health])
	check("100 * L^2 threshold: level 1 needs 100, level 5 needs 2500", stats.level_xp(1) == 100 and stats.level_xp(5) == 2500)


# --- 2. armor -----------------------------------------------------------------

## Fires one bullet straight into `z` at `zone` height and returns the damage dealt.
func bullet_damage(z: Zombie, zone: String, piercing: bool, seed_value: int) -> float:
	var ext := CombatActions.body_extent(z)
	var y := ext.y - 0.05 if zone == "head" else (ext.x + ext.y) / 2.0 + 0.25
	var b := BulletScn.instantiate()
	world.add_child(b)
	b.monitoring = false
	b.set_physics_process(false)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	b.setup(Vector3.RIGHT, player, 9.0, {"rng": rng, "adjusted_skill": 10.0, "luck": 5.0,
			"never_miss": true, "piercing": piercing, "is_player": true})
	b.global_position = Vector3(z.global_position.x - 1.0, y, 0.0)
	var before := z.health
	b._on_body_entered(z)
	return before - z.health


func expected_ranged(z: Zombie, zone: String, piercing: bool, seed_value: int) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var crit := CombatRules.roll_crit(rng, 5.0, 10.0)
	return CombatRules.ranged_damage(rng, 9.0, zone, 10.0, crit, CombatActions.armor_for(z, zone), piercing, true)


func test_armor() -> void:
	fresh_stats()
	make_world()
	await frames(5)
	var cases := [["zombieRiotShield", "head", 0.01], ["zombieRiotShield", "chest", 0.01],
			["zombieArmy", "head", 1.0], ["zombieArmy", "chest", 0.01]]
	for c in cases:
		var z := spawn(c[0], 3.0, 17)
		z.max_health = 500.0
		z.health = 500.0
		check("%s armor_for(%s) = %s" % [c[0], c[1], c[2]], is_equal_approx(z.armor_for(c[1]), c[2]))
		var got := bullet_damage(z, c[1], false, 5)
		var want := expected_ranged(z, c[1], false, 5)
		check("%s %s: bullet damage goes through armor (%.1f)" % [c[0], c[1], got], is_equal_approx(got, want), "want %.1f" % want)
		if c[2] < 1.0:
			var z2 := spawn(c[0], 3.0, 17)
			z2.max_health = 500.0
			z2.health = 500.0
			var pierced := bullet_damage(z2, c[1], true, 5)
			check("%s %s: piercing ignores armor (%.1f > %.1f)" % [c[0], c[1], pierced, got], pierced > got and is_equal_approx(pierced, expected_ranged(z2, c[1], true, 5)))
	var plain := spawn("zombieSlow", 3.0)
	check("a plain zombie has no armor (-1)", CombatActions.armor_for(plain, "head") == -1.0)

	# Melee: the same multiplier, applied from the hand height.
	var shield := spawn("zombieRiotShield", 3.0, 17)
	shield.max_health = 500.0
	shield.health = 500.0
	var army := spawn("zombieArmy", 3.0, 17)
	army.max_health = 500.0
	army.health = 500.0
	var ext := CombatActions.body_extent(shield)
	player.rng.seed = 3
	player.call("_melee_strike", [shield], 10.0, "blunt", false, 0.0, ext.y - 0.05)
	check("melee on riot shield head: 10 * 0.01 rounds to the minimum of 1", is_equal_approx(500.0 - shield.health, 1.0), str(500.0 - shield.health))
	player.rng.seed = 3
	player.call("_melee_strike", [army], 10.0, "blunt", false, 0.0, ext.y - 0.05)
	var army_head := 500.0 - army.health
	check("melee on army head (armor 1.0) is not reduced", army_head >= 9.0, str(army_head))
	var army_chest0 := army.health
	player.rng.seed = 3
	player.call("_melee_strike", [army], 10.0, "blunt", false, 0.0, (ext.x + ext.y) / 2.0 + 0.25)
	check("melee on army chest (armor 0.01) does 1", is_equal_approx(army_chest0 - army.health, 1.0), str(army_chest0 - army.health))


# --- 3. grab and struggle -----------------------------------------------------

func test_grab() -> void:
	fresh_stats()
	make_world()
	await frames(12)
	var z := spawn("zombieSlow", 1.1, 1, false)
	z.alerted = true
	z.state = "chase"
	z._begin_grab()
	check("grab: player.is_grabbed and zombie state grab", player.is_grabbed() and z.state == "grab")
	var prompt: Node = null
	for c in player.get_children():
		if c is StrugglePrompt:
			prompt = c
	check("grab shows the struggle prompt with 'Mash A / D'", prompt != null and prompt.prompt_text() == "Mash A / D", str(prompt.prompt_text() if prompt else null))
	check("3 presses needed at level 1 / strength 5", z.struggle.presses_needed == 3)

	var x0: float = player.global_position.x
	Input.action_press("move_right")
	await frames(6)
	Input.action_release("move_right")
	check("movement is locked while grabbed", is_equal_approx(player.global_position.x, x0), "x %.2f -> %.2f" % [x0, player.global_position.x])
	check("D press fed the struggle (1 press)", z.struggle.presses == 1, str(z.struggle.presses))
	await tap("move_left")
	check("A (move_left action) press fed the struggle (2 presses)", z.struggle.presses == 2, str(z.struggle.presses))
	check("prompt progress 2/3", prompt != null and is_equal_approx(prompt.progress(), 2.0 / 3.0))

	# Bite while grabbed is half damage.
	var hp: float = player.health
	z.bite_cooldown = 0.0
	z.windup_timer = 0.0
	await frames(3)
	check("bite during the grab does 3.5 (7 x 0.5)", is_equal_approx(hp - player.health, 3.5), str(hp - player.health))

	await tap("move_right")
	check("third press escapes: released, zombie shoved back and staggered",
			not player.is_grabbed() and z.state == "stumble", "grabbed=%s state=%s" % [player.is_grabbed(), z.state])
	var gone := true
	for c in player.get_children():
		if c is StrugglePrompt and not c.is_queued_for_deletion():
			gone = false
	check("prompt removed after the escape", gone)

	# Killing the grabber ends the grab.
	z.state = "chase"
	z._begin_grab()
	check("grabbed again", player.is_grabbed())
	z.take_damage(1000.0, "head", player)
	check("killing the grabber ends the grab", not player.is_grabbed())

	# Zombies really grab: a chasing zombie next to an idle player, grab rolls at 10%.
	make_world()
	await frames(12)
	z = spawn("zombieSlow", 1.0, 1, false)
	z.rng.seed = 3
	z.alerted = true
	z.state = "chase"
	Engine.time_scale = 8.0
	var waited := 0.0
	while not player.is_grabbed() and waited < 120.0:
		await seconds(1.0)
		waited += 1.0
		player.health = player.max_health
		player.perm_health = player.max_health
	Engine.time_scale = 1.0
	check("a chasing zombie grabs the idle player on its own", player.is_grabbed() and z.state == "grab", "after %.0f s state=%s" % [waited, z.state])
	if player.is_grabbed():
		for i in 8:
			if player.is_grabbed():
				await tap("move_left" if i % 2 == 0 else "move_right")
		check("mashing A / D frees the player", not player.is_grabbed())


# --- 4. stat, item and rest hookups ---------------------------------------------

func test_vitals() -> void:
	fresh_stats()
	make_world()
	await frames(5)
	var stats := autoload("Stats")
	check("player starts at full Stats.max_health (55)", player.max_health == 55.0 and player.health == 55.0 and player.perm_health == 55.0)
	stats.set_penalty("endurance", 1)
	check("stats_changed lowers max_health and clamps health", player.max_health == 46.0 and player.health == 46.0, str(player.max_health))
	stats.clear_penalties()
	check("clearing the penalty raises the ceiling but heals nothing", player.max_health == 55.0 and player.health == 46.0)
	player.full_heal()

	# perm health + items.
	player.take_damage(10.0)
	check("a hit of 10 leaves perm health at 50 (round(10/1.85) = 5)", player.health == 45.0 and player.perm_health == 50.0)
	var inv := autoload("Inventory")
	inv.add_item("Bandages", 0.5)
	var perm_before: float = player.perm_health
	var used: bool = inv.use_item("Bandages")
	check("Inventory.use_item(Bandages) heals and restores the perm health ceiling",
			used and player.perm_health > perm_before and player.health > 45.0, "perm %.1f -> %.1f health %.1f" % [perm_before, player.perm_health, player.health])
	player.perm_health = 40.0
	player.health = 30.0
	player.heal_perm(5.0)
	check("heal_perm raises only the ceiling", player.perm_health == 45.0 and player.health == 30.0)

	# Resting: per hour round(0.1 * max) + round((fitness + endurance) / 2) health.
	player.perm_health = 20.0
	player.health = 20.0
	player.stamina = 0.0
	var per_hour := roundf(55.0 * 0.1) + roundf((stats.skill("fitness") + 5.0) / 2.0)
	var stam_hour := roundf(player.stamina_max * 0.2) + roundf(stats.skill("fitness") + 5.0)
	player.rest(1)
	check("rest(1): health and perm health +%d, stamina +%d" % [per_hour, stam_hour],
			player.health == 20.0 + per_hour and player.perm_health == 20.0 + per_hour and player.stamina == minf(player.stamina_max, stam_hour),
			"%s %s" % [player.health, player.stamina])
	player.rest(8)
	check("rest(8) fills health, perm health and stamina to the ceilings",
			player.health == 55.0 and player.perm_health == 55.0 and player.stamina == player.stamina_max)
	var no_hunger: float = player.stamina_max

	# Hunger: the original adds hungerPenalty on top of the (already penalised) endurance.
	autoload("Survival").from_dict({"hunger": 100.0, "sleep": 0.0, "mode": "survivor"})
	var pen: int = autoload("Survival").hunger_penalty()
	var expect: float = CombatRules.stamina_max(stats.level, stats.attr("endurance"), pen, stats.adjusted_skill("fitness"))
	check("hunger penalty %d feeds stamina max the way the original formula does" % pen,
			pen == 10 and player.stamina_max == expect, "%s vs %s (rested %s)" % [player.stamina_max, expect, no_hunger])
	check("hunger also lowers max health through endurance", player.max_health < 55.0, str(player.max_health))
	autoload("Survival").reset()


# --- 5. run, crouch, overweight -------------------------------------------------

func test_movement() -> void:
	fresh_stats()
	make_world()
	await frames(12)
	var walk := 6.0
	Input.action_press("move_right")
	await frames(4)
	check("walk speed", is_equal_approx(player.velocity.x, walk), str(player.velocity.x))
	Input.action_press("run")
	await frames(4)
	check("run action runs at x1.5 and spends stamina", is_equal_approx(player.velocity.x, walk * 1.5) and player.running and player.stamina < player.stamina_max,
			"%s %s" % [player.velocity.x, player.stamina])
	Input.action_release("run")
	Input.action_press("crouch")
	await frames(4)
	check("crouch action halves the speed", player.crouched and is_equal_approx(player.velocity.x, walk / 2.0), str(player.velocity.x))
	Input.action_release("crouch")
	await frames(2)

	# Overweight: carry weight is strength * 10 = 50 lbs.
	var inv := autoload("Inventory")
	inv.add_item("Anvil", 80.0)
	check("80 lbs is over the 50 lb limit", inv.overweight)
	await frames(4)
	check("overweight slows movement to the named factor", is_equal_approx(player.velocity.x, walk * player.OVERWEIGHT_SPEED_FACTOR), str(player.velocity.x))
	Input.action_press("jump")
	await frames(4)
	Input.action_release("jump")
	check("overweight cannot jump", player.is_on_floor() and player.velocity.y <= 0.0, str(player.velocity.y))
	Input.action_release("move_right")
	inv.remove_item("Anvil", 1)
	check("dropping the weight restores the speed", not inv.overweight)
	Input.action_press("move_right")
	await frames(4)
	check("full speed again", is_equal_approx(player.velocity.x, walk), str(player.velocity.x))
	Input.action_release("move_right")
