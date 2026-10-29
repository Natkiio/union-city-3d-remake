extends "res://tests/test_base.gd"
## Combat: pure formula checks with doc numbers, then scene checks.

const NEW_TARGET_SRC := """
extends CharacterBody3D
var health := 30.0
var armor := {}
var enemy_ref := "zombieSlow"
var danger_level := 3
var hits: Array = []
var staggers: Array = []
func xp_value() -> int:
	return 25
func take_damage(amount: float, zone: String = "chest", source: Node = null, knockback: float = 0.0) -> void:
	hits.append([amount, zone, knockback])
	health -= amount
func apply_stagger(direction: float, distance: float) -> void:
	staggers.append([direction, distance])
"""
const OLD_TARGET_SRC := """
extends CharacterBody3D
var health := 30.0
var hits: Array = []
var staggers: Array = []
func take_damage(amount: float) -> void:
	hits.append(amount)
	health -= amount
func apply_stagger(direction: float, distance: float) -> void:
	staggers.append([direction, distance])
"""

var killed_events: Array = []
var shot_events: Array = []
var died_events: int = 0
var _shooter: Node3D


func run() -> void:
	_test_constants()
	_test_ranged()
	_test_melee()
	_test_health_stamina()
	_test_weapons()
	await _test_scene()
	await _test_death()


func _rng(seed_value: int = 1) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


func _test_constants() -> void:
	var c: Dictionary = autoload("Data").table("constants")["constants"]
	check("zone mods match constants.json",
		c["hitHeadMod"] == CombatRules.zone_mod("head") and c["hitChestMod"] == CombatRules.zone_mod("chest")
		and c["hitBellyMod"] == CombatRules.zone_mod("belly") and c["hitLegsMod"] == CombatRules.zone_mod("legs"))
	check("crit/miss/perm constants match",
		c["criticalDamage"] == CombatRules.CRIT_DAMAGE and c["critLuckReduction"] == CombatRules.CRIT_LUCK_DIV
		and c["critSkillReduction"] == CombatRules.CRIT_SKILL_DIV and c["missChance"] == CombatRules.MISS_CHANCE
		and c["permHealthDmgMod"] == CombatRules.PERM_HEALTH_DIV and c["skillDamageMod"] == CombatRules.SKILL_DAMAGE_MOD
		and c["skillDamageModMelee"] == CombatRules.MELEE_SKILL_MOD and c["minStumbleDist"] == CombatRules.MIN_STUMBLE_PX
		and c["staminaBase"] == CombatRules.STAMINA_BASE and c["staminaJump"] == CombatRules.STAMINA_COST_JUMP)


func _test_ranged() -> void:
	check("spread skill: crouched +25, moving -20, jumping -50",
		CombatRules.spread_skill(7, true, false, false) == 32 and CombatRules.spread_skill(7, false, true, false) == -13
		and CombatRules.spread_skill(7, false, false, true) == -43)
	check("spread degrees glock standing", is_equal_approx(CombatRules.spread_degrees(7, 0.4, 0), 93.0 / 25.0 * 0.4))
	check("spread grows with consecutive rounds", is_equal_approx(CombatRules.spread_degrees(7, 0.4, 14) - CombatRules.spread_degrees(7, 0.4, 0), 2.0))
	check("spread is better crouched", CombatRules.spread_degrees(32, 0.4, 0) < CombatRules.spread_degrees(7, 0.4, 0))
	var r := _rng(7)
	var inside := true
	for i in 200:
		inside = inside and absf(CombatRules.spread_offset(r, 3.0)) <= deg_to_rad(3.0) + 0.0001
	check("spread offset stays within +-spread", inside)
	check("miss threshold skill 7 standing = 386", CombatRules.miss_threshold(7, false) == 386)
	check("miss threshold crouched = 379", CombatRules.miss_threshold(7, true) == 379)
	r = _rng(11)
	var misses := 0
	for i in 20000:
		if CombatRules.roll_miss(r, 7):
			misses += 1
	check("miss rate near 38.6%", absf(misses / 20000.0 - 0.386) < 0.02, "rate=%.3f" % (misses / 20000.0))
	check("chainsaw never misses", not CombatRules.roll_miss(_rng(), -500, false, true))
	check("crit chance luck 5 skill 7 = 1%", CombatRules.crit_chance(5, 7) == 1)
	check("crit chance luck 14 skill 77 = 9%", CombatRules.crit_chance(14, 77) == 9)
	r = _rng(3)
	var crits := 0
	for i in 20000:
		if CombatRules.roll_crit(r, 14, 77):
			crits += 1
	check("crit rate near 9%", absf(crits / 20000.0 - 0.09) < 0.01)
	# damage: glock 9, chest, skill 7: 9 minus 0..1 (20% of 9 = 1.8, rounded) then -2
	r = _rng(5)
	var lo := 999.0
	var hi := -999.0
	for i in 500:
		var d := CombatRules.ranged_damage(r, 9, "chest", 7, false)
		lo = minf(lo, d)
		hi = maxf(hi, d)
	check("glock chest damage range 5..7", lo >= 5.0 and hi <= 7.0 and hi > lo, "%s..%s" % [lo, hi])
	var head := CombatRules.ranged_damage(_rng(5), 50, "head", 50, false)
	check("head x1.2 at skill 50 (60 minus up to 12)", head >= 48.0 and head <= 60.0, str(head))
	var legs := CombatRules.ranged_damage(_rng(5), 50, "legs", 50, false)
	check("legs x0.6 at skill 50", legs >= 24.0 and legs <= 30.0, str(legs))
	check("crit triples", CombatRules.ranged_damage(_rng(9), 20, "chest", 50, true) == 3.0 * CombatRules.ranged_damage(_rng(9), 20, "chest", 50, false))
	check("armor multiplies, min 1", CombatRules.ranged_damage(_rng(2), 10, "chest", 50, false, 0.01) == 1.0)
	check("piercing ignores armor", CombatRules.ranged_damage(_rng(2), 10, "chest", 50, false, 0.01, true) >= 8.0)
	check("skill bonus: skill 100 adds round(0.05*50)=3 (3 on top of the roll)",
		CombatRules.ranged_damage(_rng(4), 10, "chest", 100, false) == CombatRules.ranged_damage(_rng(4), 10, "chest", 50, false) + 3.0)
	check("enemy damage skips skill bonus and crit",
		CombatRules.ranged_damage(_rng(4), 10, "chest", 100, true, -1.0, false, false) == CombatRules.ranged_damage(_rng(4), 10, "chest", 50, false, -1.0, false, false))
	check("zone from height", CombatRules.zone_from_height(0.95) == "head" and CombatRules.zone_from_height(0.65) == "chest"
		and CombatRules.zone_from_height(0.4) == "belly" and CombatRules.zone_from_height(0.1) == "legs")
	var kb := 0
	r = _rng(8)
	for i in 10000:
		if CombatRules.roll_knockback(r, 20):
			kb += 1
	check("knockback roll near weapon.knockback %", absf(kb / 10000.0 - 0.20) < 0.02)


func _test_melee() -> void:
	check("unarmed base = round(1 + 5/5) = 2", CombatRules.melee_base(-1, 5, 7) == 2.0)
	check("armed base: bat 10, str 5, skill 7 = 12 - 7 = 5", CombatRules.melee_base(10, 5, 7) == 5.0)
	check("katana at skill 75, str 6 = 42", CombatRules.melee_base(40, 6, 75) == 42.0)
	check("shove base 0.5 + (5/3)/4", is_equal_approx(CombatRules.shove_base(5), 0.5 + 5.0 / 12.0))
	var r := _rng(6)
	var ok := true
	for i in 200:
		var d := CombatRules.melee_final(r, 40, false)
		ok = ok and d >= 36.0 and d <= 40.0
	check("melee shave is at most 10%", ok)
	check("melee min 1", CombatRules.melee_final(_rng(), 0.2, false) == 1.0)
	check("melee crit x3", CombatRules.melee_final(_rng(3), 10, true) == 3.0 * CombatRules.melee_final(_rng(3), 10, false))
	check("melee armor", CombatRules.melee_final(_rng(3), 100, false, 0.5) <= 50.0)
	check("stumble px = 30 + 10 + 5 + round(7/5)", CombatRules.stumble_px(10, 5, 7) == 46.0)
	check("px to units", is_equal_approx(CombatRules.px_to_units(100.0), 100.0 / CombatRules.PX_PER_UNIT))


func _test_health_stamina() -> void:
	check("perm health loss round(10/1.85) = 5", CombatRules.perm_health_loss(10) == 5.0)
	check("regen tick: 55/200 * (5 + round(7/5)) / 2", is_equal_approx(CombatRules.regen_per_tick(55, 5, 7), 55.0 / 200.0 * 6.0 / 2.0))
	check("stamina max level 1 end 5 fitness 7 = 69", CombatRules.stamina_max(1, 5, 0, 7) == 69.0)
	check("stamina cost shrinks with fitness", is_equal_approx(CombatRules.stamina_cost(5, 50), 5.0 - 5.0 / 100.0 * 5.0))
	check("stamina regen has a floor of 0.1", CombatRules.stamina_regen(1, 1) == 0.1)
	check("stamina regen round((5+7)/20)=1", CombatRules.stamina_regen(5, 7) == 1.0)


func _test_weapons() -> void:
	var ok := true
	var guns := 0
	for ref in Weapon.all_refs("firearm"):
		var w := Weapon.from_ref(ref)
		ok = ok and w.fire_interval() > 0.0 and w.bullet_speed() > 0.0 and w.rounds_per_shot >= 1
		guns += 1
	check("every firearm has an interval, speed and pellets", ok, "n=%d" % guns)
	var melee_ok := true
	for ref in Weapon.all_refs("melee"):
		var w := Weapon.from_ref(ref)
		melee_ok = melee_ok and w.melee_interval() > 0.0 and (w.skill == "blunt" or w.skill == "blades")
	check("every melee weapon swings by blunt/blades", melee_ok)
	check("shotgun fires 3 pellets", Weapon.from_ref("shotgun").rounds_per_shot == 3)
	check("venom is a 3-round auto burst", Weapon.from_ref("venom").is_auto() and Weapon.from_ref("venom").burst_size == 3)
	check("glock is click-per-shot", not Weapon.from_ref("glock").is_auto())
	check("MP5 holds to fire", Weapon.from_ref("MP5").is_auto())
	check("M24 pierces armor, glock does not", Weapon.from_ref("M24").has_piercing and not Weapon.from_ref("glock").has_piercing)
	check("chainsaw never misses", Weapon.from_ref("chainsaw").never_misses())


func _make_target(src: String, pos: Vector3) -> CharacterBody3D:
	var script := GDScript.new()
	script.source_code = src
	script.reload()
	var body := CharacterBody3D.new()
	body.set_script(script)
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.height = 1.8
	shape.shape = cap
	body.add_child(shape)
	current_scene.add_child(body)
	body.global_position = pos
	return body


func _fire_bullet(ctx: Dictionary, dir: Vector3 = Vector3.RIGHT) -> Node:
	var bullet: Node = load("res://scenes/weapons/bullet.tscn").instantiate()
	current_scene.add_child(bullet)
	bullet.global_position = Vector3(0, 0, 0)
	bullet.setup(dir, _shooter, 10.0, ctx)
	return bullet


func _test_scene() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	current_scene = holder
	_shooter = Node3D.new()
	holder.add_child(_shooter)
	var events := autoload("Events")
	events.enemy_killed.connect(func(ref, danger, xp): killed_events.append([ref, danger, xp]))
	events.shot_fired.connect(func(ref, noise, pos): shot_events.append([ref, noise, pos]))
	events.player_died.connect(func(): died_events += 1)

	# Bullet hits a contract-style target, zone from height, no miss.
	var target := _make_target(NEW_TARGET_SRC, Vector3(3, 0, 0))
	var bullet := _fire_bullet({"never_miss": true, "rng": _rng(1), "adjusted_skill": 7})
	await frames(20)
	check("bullet damages target via take_damage(amount, zone, source, kb)", target.hits.size() == 1 and target.hits[0][0] > 0.0,
		str(target.hits))
	check("bullet at chest height reports a body zone", target.hits.size() == 1 and target.hits[0][1] in ["chest", "belly"], str(target.hits))
	check("bullet is freed after hit", not is_instance_valid(bullet))

	# Head shot: fire high.
	target.hits.clear()
	var high := _fire_bullet({"never_miss": true, "rng": _rng(1), "adjusted_skill": 7})
	high.global_position = Vector3(0, 0.8, 0)
	await frames(20)
	check("high shot is a head hit", target.hits.size() == 1 and target.hits[0][1] == "head", str(target.hits))

	# A guaranteed miss passes through (rng-driven: skill -1000 -> threshold huge).
	target.hits.clear()
	var whiff := _fire_bullet({"rng": _rng(1), "adjusted_skill": -1000})
	await frames(20)
	check("missed round deals no damage", target.hits.is_empty())
	if is_instance_valid(whiff):
		whiff.queue_free()
	target.queue_free()

	# Old one-argument take_damage still works, with push applied for knockback.
	var old := _make_target(OLD_TARGET_SRC, Vector3(3, 0, 0))
	var hit_old := _fire_bullet({"never_miss": true, "rng": _rng(1), "adjusted_skill": 7, "knockback": 100.0})
	await frames(20)
	check("old take_damage(amount) target is damaged", old.hits.size() == 1)
	check("old target gets staggered on a knockback hit", old.staggers.size() == 1 and old.staggers[0][0] == 1.0)
	old.queue_free()

	# The real zombie scene (current one-argument take_damage) works too.
	var zed: CharacterBody3D = load("res://scenes/zombie/zombie.tscn").instantiate()
	current_scene.add_child(zed)
	zed.global_position = Vector3(3, 0.9, 0)
	await frames(3)
	var zhp: float = zed.health
	_fire_bullet({"never_miss": true, "rng": _rng(1), "adjusted_skill": 7})
	await frames(20)
	check("real zombie takes bullet damage", zed.health < zhp, "%s -> %s" % [zhp, zed.health])
	zed.queue_free()
	await frames(2)

	# Wall (no take_damage) stops bullets.
	var wall := StaticBody3D.new()
	var ws := CollisionShape3D.new()
	ws.shape = BoxShape3D.new()
	wall.add_child(ws)
	current_scene.add_child(wall)
	wall.global_position = Vector3(2, 0, 0)
	var behind := _make_target(NEW_TARGET_SRC, Vector3(5, 0, 0))
	await frames(2)
	var wall_bullet := _fire_bullet({"never_miss": true, "rng": _rng(1)})
	await frames(20)
	check("wall frees the bullet", not is_instance_valid(wall_bullet))
	check("target behind the wall is untouched", behind.hits.is_empty())
	wall.queue_free()

	# Kill reports.
	behind.health = 1.0
	killed_events.clear()
	CombatActions.deal_damage(behind, 5.0, "head", null, 0.0)
	check("kill emits enemy_killed(ref, danger, xp)", killed_events.size() == 1 and killed_events[0] == ["zombieSlow", 3, 25], str(killed_events))
	behind.queue_free()

	# Player scene.
	var inv := autoload("Inventory")
	inv.reset()
	inv.add_item("G17 Pistol", 2.0, 1)
	inv.add_item("9mm Ammo", 0.1, 40)
	var player: CharacterBody3D = load("res://scenes/player/player.tscn").instantiate()
	holder.add_child(player)
	player.global_position = Vector3(0, 0, 0)
	await frames(5)
	player._set_equipped("glock")
	player.facing_dir = 1.0
	var loaded_before: int = inv.get_magazine("G17 Pistol", 17)
	shot_events.clear()
	player._fire_round(Weapon.from_ref("glock"))
	check("firing spends one loaded round", inv.get_magazine("G17 Pistol", 17) == loaded_before - 1)
	check("firing emits shot_fired with weapon noise", shot_events.size() == 1 and shot_events[0][0] == "glock" and shot_events[0][1] == 10.0, str(shot_events))
	check("consecutive rounds counter rises", player.consecutive_rounds == 1)
	check("reserve is untouched by firing", inv.items["9mm Ammo"]["count"] == 40)
	player._start_reload(Weapon.from_ref("glock"))
	check("reload starts", player.reloading)
	player._tick_reload(5.0, Weapon.from_ref("glock"))
	check("reload refills magazine from reserve", inv.get_magazine("G17 Pistol", 17) == 17 and inv.items["9mm Ammo"]["count"] == 39,
		"mag=%d reserve=%d" % [inv.get_magazine("G17 Pistol", 17), inv.items["9mm Ammo"]["count"]])

	# Shotgun pellets
	inv.add_item("Shotgun", 4.0, 1)
	inv.add_item("shotgun Ammo", 0.1, 10)
	var before := holder.get_child_count()
	player._set_equipped("shotgun")
	player._fire_round(Weapon.from_ref("shotgun"))
	check("shotgun spawns 3 pellets for one round", holder.get_child_count() - before == 3, "n=%d" % (holder.get_child_count() - before))
	player._set_equipped("fist")

	# Shove staggers.
	var shovee := _make_target(OLD_TARGET_SRC, Vector3(1.0, 0, 0))
	player.shove_cooldown = 0.0
	player.stamina = player.stamina_max
	var st_before: float = player.stamina
	player._shove()
	await frames(1)
	check("shove damages (min 1) and staggers", shovee.hits.size() == 1 and shovee.hits[0] >= 1.0 and shovee.staggers.size() == 1
		and shovee.staggers[0][1] > 0.0, str(shovee.hits) + str(shovee.staggers))
	check("shove costs stamina", player.stamina < st_before)
	Engine.time_scale = 1.0
	shovee.queue_free()

	# Punch uses the unarmed formula (2 damage at base stats, shaved to >= 1).
	var puncher := _make_target(OLD_TARGET_SRC, Vector3(1.0, 0, 0))
	player._melee_strike([puncher], CombatRules.melee_base(-1, 5, 7), "blunt", false, 100.0)
	# A crit (random) triples the hit, so the ceiling is 2 x 3.
	check("unarmed punch deals 1-2 (6 on a crit)", puncher.hits.size() == 1 and puncher.hits[0] >= 1.0 and puncher.hits[0] <= 6.0, str(puncher.hits))
	Engine.time_scale = 1.0
	puncher.queue_free()

	# Health layers.
	player.is_dead = false
	player.health = player.max_health
	player.perm_health = player.max_health
	player.take_damage(10.0, "chest", null)
	check("damage lowers health and perm_health by round(d/1.85)", player.health == player.max_health - 10.0
		and player.perm_health == player.max_health - 5.0)
	player._regen_delay_ticks = 0
	player._tick_vitals(60.0)
	check("regen restores health only up to perm_health", is_equal_approx(player.health, player.perm_health))
	player.heal(100.0)
	check("heal restores both layers", player.health == player.max_health and player.perm_health == player.max_health)
	var s0: float = player.stamina
	player._use_stamina(CombatRules.STAMINA_COST_JUMP)
	check("jump cost reduces stamina", player.stamina < s0 - 4.9)
	player._tick_vitals(60.0)
	check("stamina regenerates to max", is_equal_approx(player.stamina, player.stamina_max))
	player.queue_free()
	await frames(2)


func _test_death() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	current_scene = holder
	var inv := autoload("Inventory")
	inv.add_item("Bandages", 0.5, 2)
	var player: CharacterBody3D = load("res://scenes/player/player.tscn").instantiate()
	holder.add_child(player)
	await frames(3)
	died_events = 0
	player.take_damage(9999.0)
	check("lethal damage kills and emits player_died", player.is_dead and died_events == 1)
	check("death resets run state via GameState", inv.items.is_empty())
	get_root_unpause()


func get_root_unpause() -> void:
	paused = false
	var ds := autoload("DeathScreen")
	ds.visible = false
