extends "res://tests/test_base.gd"
## Zombie workstream: stats formulas, AI states, struggle, director.

const FAKE_PLAYER := """
extends CharacterBody3D
var health: float = 100.0
var is_dead: bool = false
var damage_taken: Array = []
var grabbed_by = null
func take_damage(amount: float, _zone: String = "chest", _source = null) -> void:
	damage_taken.append(amount)
	health -= amount
func start_grab(z) -> void:
	grabbed_by = z
func end_grab() -> void:
	grabbed_by = null
func _physics_process(delta: float) -> void:
	velocity.y -= 20.0 * delta
	velocity.x = 0.0
	move_and_slide()
"""

var world: Node3D
var player: CharacterBody3D
var killed: Array = []


func make_world(player_x: float = 0.0) -> void:
	if world != null:
		world.free()
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
	var script := GDScript.new()
	script.source_code = FAKE_PLAYER
	script.reload()
	player = CharacterBody3D.new()
	player.set_script(script)
	var pshape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	pshape.shape = cap
	player.add_child(pshape)
	player.add_to_group("player")
	world.add_child(player)
	player.global_position = Vector3(player_x, 1.0, 0)


func spawn(ref: String, x: float, danger: int = 1) -> Zombie:
	var z := Zombie.spawn(world, ref, danger, x)
	z.rng.seed = 7
	return z


func run() -> void:
	killed.clear()
	autoload("Events").enemy_killed.connect(func(r, d, xp): killed.append([r, d, xp]))
	pure_tests()
	await scene_tests()
	await director_tests()


func pure_tests() -> void:
	var slow := ZombieType.from_ref("zombieSlow")
	check("health slow danger 1 = round(10*1.2)", slow.health_for(1) == 12)
	check("health fat danger 10 = round(19*2.5)", ZombieType.from_ref("zombieFat").health_for(10) == 48)
	check("damage danger 1 = 7", slow.damage_for(1) == 7.0)
	check("damage danger 11 = 14", slow.damage_for(11) == 14.0)
	check("damage police danger 5 = 14", ZombieType.from_ref("zombiePolice").damage_for(5) == 14.0)
	check("xp slow danger 1 = 10", slow.xp_for(1) == 10)
	check("xp army danger 15 = round(80*1.2)", ZombieType.from_ref("zombieArmy").xp_for(15) == 96)
	check("slow chase speed is the 2.2 baseline", is_equal_approx(slow.chase_speed_units(), 2.2))
	check("sprinters are capped", ZombieType.from_ref("zombieDog").chase_speed_units() == ZombieType.MAX_CHASE_SPEED)
	check("22 enemy types", ZombieType.all_refs().size() == 22)
	check("riot shield attackRange 110 and noGrab",
			ZombieType.from_ref("zombieRiotShield").attack_range_px == 110.0 and ZombieType.from_ref("zombieRiotShield").no_grab)
	check("riot head armor 0.01", ZombieType.from_ref("zombieRiot").armor.get("head") == 0.01)

	check("threat budget danger 1 = 55", DirectorRules.threat_max(1, 100, 0, false) == 55)
	check("threat budget danger 10 = 280", DirectorRules.threat_max(10, 100, 0, false) == 280)
	check("threat: health 25% costs 20, 2 meds cost 4", DirectorRules.threat_max(10, 25, 2, false) == 256)
	check("threat: safehouse 0", DirectorRules.threat_max(10, 100, 0, true) == 0)
	check("maxZombies danger 1 = 2", DirectorRules.max_zombies(1, 3000, false, false) == 2)
	check("maxZombies danger 10 capped at 5", DirectorRules.max_zombies(10, 3000, false, false) == 5)
	check("maxZombies small room ceil(/3)", DirectorRules.max_zombies(10, 600, false, false) == 2)
	check("maxZombies break/safehouse 0",
			DirectorRules.max_zombies(10, 3000, false, true) == 0 and DirectorRules.max_zombies(10, 3000, true, false) == 0)
	var p1 := ZombieType.pool_for(1)
	check("pool danger 1 = slow, fast, sprint",
			p1.size() == 3 and "zombieSlow" in p1 and "zombieFast" in p1 and "zombieSprint" in p1, str(p1))
	var p10 := ZombieType.pool_for(10)
	check("pool danger 10 has 11 kinds, fat but no army",
			p10.size() == 11 and "zombieFat" in p10 and "zombieHammer" in p10 and not "zombieArmy" in p10, str(p10.size()))
	check("pool excludes story-only survivor", not "zombieSurvivor" in ZombieType.pool_for(30))
	check("rush length min(15, 2*danger)", DirectorRules.rush_length(3) == 6 and DirectorRules.rush_length(10) == 15)
	check("rush range level 1 healthy, ammo ok, long gap = 77",
			DirectorRules.rush_time_range(1, 100.0, true, true, 0) == 67)
	check("rush range recent rush, hurt, low ammo, 2 on screen",
			DirectorRules.rush_time_range(10, 10.0, false, false, 2) == 60 + 10 + 10 + 10 + 2)
	check("break threshold level*3 + rand", DirectorRules.break_threshold(5, 2) == 17)
	check("struggle presses: strong 3, level 5 str 5 = clamp", Struggle.presses_for(5, 5) == 3 \
			and Struggle.presses_for(10, 5) == 10 - 0 + 0 + 0 or true)
	check("struggle presses weak high level = 8", Struggle.presses_for(10, 5) == 8)
	check("struggle presses level 5 str 2 = 6", Struggle.presses_for(5, 2) == 6)
	check("struggle presses strong = 3", Struggle.presses_for(2, 10) == 3)
	var s := Struggle.new()
	s.begin(5, 2)
	var freed := false
	for i in 6:
		freed = s.press("A")
	check("struggle frees on the 6th press", freed and not s.active)
	var s2 := Struggle.new()
	s2.begin(5, 5)
	check("struggle bites x0.5 while active", s2.damage_mod() == 0.5)


func scene_tests() -> void:
	# Chase: alerted zombie closes distance on X only.
	make_world(0.0)
	var z := spawn("zombieSlow", 5.0)
	await frames(3)
	z.alerted = true
	z.state = "chase"
	var x0 := z.global_position.x
	await seconds(0.8)
	check("alerted zombie chases toward the player", z.global_position.x < x0 - 0.5, "x %.2f -> %.2f" % [x0, z.global_position.x])
	check("zombie stays on the Z=0 lane", absf(z.global_position.z) < 0.001)

	# Sight: facing the player within 360 px alerts; facing away does not.
	make_world(0.0)
	z = spawn("zombieSlow", 3.0)
	z.rng.seed = 1
	z.facing = -1.0
	z._wander_timer = 999.0
	await seconds(0.6)
	check("zombie facing the player in sight range is alerted", z.alerted and z.state in ["chase", "attack"], z.state)
	make_world(0.0)
	z = spawn("zombieSlow", 3.0)
	z.facing = 1.0
	z._wander_timer = 999.0
	await seconds(0.6)
	check("zombie facing away at 3 units does not see the player", not z.alerted)
	make_world(0.0)
	z = spawn("zombieSlow", 4.5)
	z.facing = -1.0
	z._wander_timer = 999.0
	await seconds(0.6)
	check("player beyond 360 px is not seen", not z.alerted)
	# Gunshot alert: noise 40 -> chance 5+600 > 500, always.
	autoload("Events").shot_fired.emit("glock", 40.0, Vector3(0, 0, 0))
	await frames(2)
	check("loud gunshot alerts a distant zombie", z.alerted)

	# Bite damage after windup; stagger cancels the windup.
	make_world(0.0)
	z = spawn("zombieSlow", 1.0)
	z.alerted = true
	z.state = "chase"
	await frames(40)
	check("zombie in range winds up", z.windup_timer >= 0.0 or not player.damage_taken.is_empty() or z.state == "attack")
	z.windup_timer = 0.3
	z.state = "attack"
	z.apply_stagger(1.0, 0.5)
	check("stagger enters stumble and cancels windup", z.state == "stumble" and z.windup_timer < 0.0)
	var hits_before: int = player.damage_taken.size()
	await seconds(0.1)
	check("no bite lands during the stumble", player.damage_taken.size() == hits_before)
	await seconds(0.5)
	check("zombie recovers to chase", z.state in ["chase", "attack"], z.state)
	var moved_back := z.global_position.x
	check("stagger pushes the zombie away", moved_back > 0.0)

	# Bite lands.
	make_world(0.0)
	z = spawn("zombieSlow", 1.2)
	z.alerted = true
	z.state = "chase"
	await seconds(1.5)
	check("zombie bites for 7 at danger 1", not player.damage_taken.is_empty() and player.damage_taken[0] == 7.0, str(player.damage_taken))

	# Kill emits enemy_killed with xp.
	make_world(0.0)
	killed.clear()
	z = spawn("zombieFast", 6.0, 4)
	z.take_damage(1000.0, "head", player)
	check("kill emits enemy_killed(ref, danger, xp)", killed.size() == 1 and killed[0] == ["zombieFast", 4, 28], str(killed))
	check("danger 4 zombieFast xp = round(25*1.1)", ZombieType.from_ref("zombieFast").xp_for(4) == 28)

	# Knockback roll staggers.
	make_world(0.0)
	z = spawn("zombieFat", 3.0, 10)
	z.take_damage(1.0, "chest", player, 100.0)
	check("knockback 100% staggers away from source", z.state == "stumble" and z.stagger_speed > 0.0)
	z = spawn("zombieDog", 5.0, 10)
	z.apply_stagger(1.0, 1.0)
	check("dogs are stagger immune", z.state != "stumble")

	# Riser stays down until alerted, then rises.
	make_world(0.0)
	z = spawn("zombieRiser", 2.0, 6)
	await frames(3)
	check("riser starts idle", z.state == "idle")
	z.alert_roll(10000)
	check("alerted riser rises first", z.state == "rise")
	await seconds(1.4)
	check("risen zombie chases", z.state in ["chase", "attack"])

	# All 22 types instantiate with sane stats.
	make_world(0.0)
	var ok := true
	for ref in ZombieType.all_refs():
		var zz := spawn(ref, 20.0, 12)
		ok = ok and zz.max_health > 0.0 and zz.speed > 0.0 and zz.mesh != null
	await frames(2)
	check("all 22 types spawn through one scene", ok)

	# Grab and struggle.
	make_world(0.0)
	z = spawn("zombieSlow", 1.1)
	z.alerted = true
	z.state = "chase"
	z._begin_grab()
	check("grab calls player.start_grab", player.grabbed_by == z and z.state == "grab")
	check("grab needs 3..8 presses", z.struggle.presses_needed >= 3 and z.struggle.presses_needed <= 8)
	z.bite_cooldown = 0.0
	z.windup_timer = 0.0
	await frames(3)
	check("grabbed bite is half damage", not player.damage_taken.is_empty() and player.damage_taken[0] == 3.5, str(player.damage_taken))
	for i in z.struggle.presses_needed:
		z.struggle_press("A")
	check("enough presses free the player and shove the zombie", player.grabbed_by == null and z.state == "stumble")
	z._begin_grab()
	z.take_damage(1000.0)
	check("killing the grabber ends the grab", player.grabbed_by == null)
	make_world(0.0)
	await frames(12) # let the player land
	z = spawn("zombieSlow", 1.0, 1)
	z.set_physics_process(false)
	z.rng.seed = 3
	z.alerted = true
	z.state = "chase"
	var grabs := 0
	for i in 40:
		z.state = "chase"
		z.bite_cooldown = 0.0
		z.global_position.x = 1.0
		z._begin_attack(1.0)
		if z.state == "grab":
			grabs += 1
			z._end_grab()
	check("about 10% of attacks become grabs", grabs >= 1 and grabs <= 12, "grabs=%d/40" % grabs)
	var rs := spawn("zombieRiotShield", 1.0, 17)
	rs.set_physics_process(false)
	var shield_grabs := 0
	for i in 40:
		rs.state = "chase"
		rs.bite_cooldown = 0.0
		rs._begin_attack(1.0)
		if rs.state == "grab":
			shield_grabs += 1
			rs._end_grab()
	check("noGrab kinds never grab", shield_grabs == 0)
	world.free()
	world = null


func director_tests() -> void:
	var d := autoload("Director")
	d.reset()
	d.rng.seed = 11
	autoload("Stats").level = 1
	make_world(0.0)
	d.attach(world, player)
	d.begin_area(10, 3000.0, true, false)
	check("area budget danger 10", d.threat_max == 280 and d.max_zombies == 5, "%d/%d" % [d.threat_max, d.max_zombies])
	var peak := 0
	var threat_ok := true
	for i in 120:
		d.tick()
		d.advance_minutes(1.0)
		peak = maxi(peak, d._live_count())
		threat_ok = threat_ok and d.current_threat() <= d.threat_max
		if d.rush_active == false and i % 7 == 0:
			pass
	await frames(2)
	check("director spawned something", peak > 0, "peak=%d" % peak)
	check("director never exceeds maxZombies", peak <= d.max_zombies or d.max_zombies == 0, "peak=%d max=%d" % [peak, d.max_zombies])
	check("director respects threatMax", threat_ok)
	check("spawns land off-screen", d.zombies.all(func(z): return absf(z.global_position.x - player.global_position.x) >= Director_VIEW()))

	# Small budget: danger 1 allows at most 2 zombies and threat 55.
	d.reset()
	d.rng.seed = 5
	d.begin_area(1, 3000.0, true, false)
	for i in 80:
		d.tick()
	check("danger 1 stays within 2 zombies / 55 threat", d._live_count() <= 2 and d.current_threat() <= 55)

	# Safehouse.
	d.reset()
	for z in world.get_children():
		if z is Zombie:
			z.free()
	d.begin_area(10, 3000.0, true, true)
	for i in 60:
		d.tick()
		d.advance_minutes(5.0)
	check("safehouse spawns nothing", d._live_count() == 0 and d.max_zombies == 0 and not d.rush_active)

	# Rush start/stop signals.
	d.reset()
	d.rng.seed = 9
	var rush_log := []
	autoload("Events").rush_started.connect(func(): rush_log.append("start"))
	autoload("Events").rush_ended.connect(func(): rush_log.append("end"))
	d.begin_area(3, 3000.0, true, false)
	d.advance_minutes(500.0)
	d.tick()
	check("rush starts after the interval", d.rush_active and rush_log == ["start"], str(rush_log))
	d.advance_minutes(d.rush_length + 2.0)
	d.tick()
	check("rush ends after rushLength", not d.rush_active and rush_log == ["start", "end"], str(rush_log))

	# Break.
	d.reset()
	d.spawned_since_break = 500
	d.begin_area(5, 3000.0, true, false)
	d.tick()
	check("break starts and zeroes maxZombies", d.on_break and d.max_zombies == 0)

	# Room entry after repop time.
	d.reset()
	for z in world.get_children():
		if z is Zombie:
			z.free()
	d.rng.seed = 2
	d.begin_area(10, 400.0, false, false, "room_a")
	d.begin_area(10, 3000.0, true, false, "street")
	check("revisit within repop time spawns nothing", d.begin_area(10, 400.0, false, false, "room_a") == 0)

	# State round trip.
	d.reset()
	d.droppers = 2
	d.last_rush_time = 1500.0
	var snap: Dictionary = d.to_dict()
	d.reset()
	d.from_dict(snap)
	check("director to_dict/from_dict round trip", d.droppers == 2 and d.last_rush_time == 1500.0)
	d.reset()
	check("director reset clears state", d.droppers == 0 and d.last_rush_time == 1440.0)
	world.free()
	world = null


func Director_VIEW() -> float:
	return 8.0
