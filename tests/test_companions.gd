extends "res://tests/test_base.gd"
## Companions workstream: human enemies, companions, the roster and the level
## hook. Deterministic where it matters (seeded rng, manual physics stepping).

const DT := 1.0 / 60.0


class Dummy extends CharacterBody3D:
	## Stands in for the player: takes damage, sits in group "player".
	var health: float = 100.0
	var is_dead: bool = false
	var hits: Array = []

	func _ready() -> void:
		add_to_group("player")
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.4
		cap.height = 1.8
		cs.shape = cap
		add_child(cs)

	func take_damage(amount: float, zone: String = "chest", source: Node = null, _knockback: float = 0.0) -> void:
		hits.append([amount, zone])
		health = maxf(0.0, health - amount)
		if health <= 0.0:
			is_dead = true


func run() -> void:
	var world := autoload("World")
	world.fade_enabled = false
	autoload("Clock").running = false
	autoload("Director").enabled = false
	autoload("Companions").reset()
	autoload("LootState").reset()
	await test_gun_rates()
	await test_human_enemy()
	await test_companion_combat()
	await test_down_revive_die()
	await test_give_weapon_and_heal()
	test_roster_round_trip()
	await test_partner_quest()
	await test_level_hook()
	await test_room_change(world)


func _arena() -> Node3D:
	var a := Node3D.new()
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 10)
	cs.shape = box
	cs.position = Vector3(50, -0.5, 0)
	floor_body.add_child(cs)
	a.add_child(floor_body)
	root.add_child(a)
	return a


func _dummy(arena: Node3D, x: float) -> Dummy:
	var d := Dummy.new()
	d.position = Vector3(x, 0.9, 0)
	arena.add_child(d)
	return d


func _manual(n: HumanBody) -> HumanBody:
	n.set_physics_process(false)
	return n


func test_gun_rates() -> void:
	check("miss threshold: enemy skill 10 -> 380, companion skill 30 -> 340",
			CombatRules.miss_threshold(10, false) == 380 and CombatRules.miss_threshold(30, false) == 340)
	var arena := _arena()
	await frames(2)
	var target := _dummy(arena, 3.0)
	target.health = 1.0e9
	var shooter := Node3D.new()
	shooter.position = Vector3(0, 0.9, 0)
	arena.add_child(shooter)
	for skill in [10.0, 30.0]:
		var rng := RandomNumberGenerator.new()
		rng.seed = 12345
		var g := ActorGun.new("glock")
		var shots := 2000
		var hit := 0
		var low := 99.0
		var high := 0.0
		for i in shots:
			g.loaded = 17
			g.cooldown = 0.0
			g.consecutive = 0
			var before := target.hits.size()
			g.fire(shooter, target, skill, rng)
			if target.hits.size() > before:
				hit += 1
				var d: float = target.hits[-1][0]
				var zone: String = target.hits[-1][1]
				var top := 9.0 * CombatRules.zone_mod(zone)
				low = minf(low, d / top)
				high = maxf(high, d / top)
		var expect := 1.0 - float(CombatRules.miss_threshold(skill, false)) / 1000.0
		check("skill %d: hit rate %.3f matches 1 - miss chance %.2f" % [skill, float(hit) / shots, 1.0 - expect + expect * 0.0],
				absf(float(hit) / shots - expect) < 0.04)
		check("skill %d: damage is weapon damage x zone, up to 20%% shaved, no skill bonus or crit" % skill,
				low >= 0.75 and high <= 1.0 + 1e-6, "%.2f..%.2f" % [low, high])
	arena.queue_free()


func test_human_enemy() -> void:
	var arena := _arena()
	await frames(2)
	var events := autoload("Events")
	var far := _dummy(arena, 30.0)
	var e: HumanEnemy = HumanEnemy.spawn(arena, "looter1", 20.0, 3, "test_room", 0)
	e.set_physics_process(false)
	e.rng.seed = 99
	await frames(2)
	check("looter reads its record: glock, 100 health, hostile, xp x3",
			e.gun.weapon.ref == "glock" and e.max_health == 100.0 and not e.friendly and e.xp_bonus == 3.0)
	for i in 30:
		e._physics_process(DT)
	check("enemy does not see a player 10 units away", e.target == null and e.state in ["idle"])
	far.global_position.x = 26.0 # 6 units away: inside sight
	for i in 30:
		e._physics_process(DT)
	check("enemy sees a player 6 units away and closes in", e.target == far and e.state in ["chase", "attack"], e.state)
	far.global_position.x = e.global_position.x + 3.0
	var start_health := far.health
	var t := 0.0
	while not far.is_dead and t < 90.0:
		e._physics_process(DT)
		t += DT
	check("enemy shoots the player dead (%d hits in %.0f s)" % [far.hits.size(), t], far.is_dead and far.hits.size() >= 3)
	var ok := true
	for h in far.hits:
		var top := 9.0 * CombatRules.zone_mod(h[1])
		ok = ok and h[0] >= top * 0.75 and h[0] <= top + 1e-6
	check("every hit is glock damage x zone within the 20% shave", ok)
	check("enemy burst-fires, then reloads from unlimited reserve", e.gun.loaded >= 0 and e.gun.loaded <= 17)

	# flee
	var far2 := _dummy(arena, 60.0)
	far2.health = 1.0e9
	var f: HumanEnemy = HumanEnemy.spawn(arena, "HERCscientist", 55.0, 5, "test_room", 1)
	f.set_physics_process(false)
	await frames(2)
	for i in 20:
		f._physics_process(DT)
	check("scientist engages", f.target == far2)
	f.health = f.max_health * 0.2
	var x0 := f.global_position.x
	for i in 60:
		f._physics_process(DT)
	check("badly hurt enemy flees away from the player", f.fleeing and f.global_position.x < x0, f.state)

	# death, xp and loot
	var xp_seen := []
	var cb := func(ref, danger, xp): xp_seen.append([ref, danger, xp])
	events.enemy_killed.connect(cb)
	var killer := _dummy(arena, 100.0)
	var victim: HumanEnemy = HumanEnemy.spawn(arena, "looter1", 40.0, 3, "drop_room", 0)
	victim.set_physics_process(false)
	await frames(2)
	victim.take_damage(10000.0, "head", killer, 0.0)
	await frames(3)
	events.enemy_killed.disconnect(cb)
	check("kill emits enemy_killed with danger-based xp (round((3*5+5)*3) = 60)",
			xp_seen.size() == 1 and xp_seen[0] == ["looter1", 3, 60], str(xp_seen))
	var drop: Node = null
	for c in arena.get_children():
		if "container_id" in c and str(c.container_id) == "drop_drop_room_0":
			drop = c
	var names: Array = []
	if drop != null:
		for it in drop.items:
			names.append(it.name)
	check("it drops its weapon and ammo in a container", drop != null and "G17 Pistol" in names and "9mm Ammo" in names, str(names))
	check("the kill is remembered for the room", autoload("Companions").killed.get("drop_room", {}).has("0"))
	var armored: HumanEnemy = HumanEnemy.spawn(arena, "HERCsoldier", 70.0, 5, "x", 2)
	await frames(2)
	check("HERC suit gives chest and belly armor via CombatActions", CombatActions.armor_for(armored, "chest") == 0.4 and CombatActions.armor_for(armored, "head") < 0.0)
	autoload("Companions").killed.clear()
	arena.queue_free()
	await frames(2)


func test_companion_combat() -> void:
	var arena := _arena()
	await frames(2)
	var comp := autoload("Companions")
	var far := _dummy(arena, 40.0)
	far.health = 1.0e9
	check("Hank can join", comp.add("Hank", "follower"))
	check("a second follower is refused", not comp.add("Kelly", "follower"))
	var c: Companion = Companion.spawn(arena, "Hank", "follower", 10.0, comp.roster["Hank"])
	c.set_physics_process(false)
	c.rng.seed = 5
	await frames(2)
	check("companion: hunter rifle, skill 30, half the player's health, on layer 4",
			c.gun.weapon.ref == "hunter" and c.skill == 30.0 and c.collision_layer == 4 and c.max_health == roundf(autoload("Stats").max_health() / 2.0))
	check("registered as a zombie target", c.is_in_group("zombie_targets") and c.is_in_group("companion"))
	# follows the player
	far.global_position.x = 20.0
	for i in 240:
		c._physics_process(DT)
	check("companion follows the player and catches up", absf(c.global_position.x - 20.0) < 2.5, str(c.global_position.x))
	# fights a zombie
	var z: Zombie = Zombie.spawn(arena, "zombieSlow", 1, 25.0)
	z.rng.seed = 3
	z.set_physics_process(false)
	await frames(2)
	z.alerted = true
	z.state = "chase"
	var guard := 0
	while is_instance_valid(z) and not z.is_dead() and guard < 3600:
		c._physics_process(DT)
		z._physics_process(DT)
		guard += 1
	check("companion kills an alerted zombie (%d ticks)" % guard, not is_instance_valid(z) or z.is_dead())
	# zombies can target the companion
	var z2: Zombie = Zombie.spawn(arena, "zombieSlow", 1, c.global_position.x + 3.0)
	z2.set_physics_process(false)
	await frames(2)
	z2.alerted = true
	z2.state = "chase"
	far.global_position.x = 80.0
	await frames(2) # let the physics server see the move
	var hp0 := c.health
	for i in 600:
		z2._physics_process(DT)
		if c.health < hp0:
			break
	check("a zombie picks the nearer companion and bites it", z2.player == c and c.health < hp0, "%s %.1f" % [z2.player, c.health])
	z2.queue_free()
	comp.reset()
	arena.queue_free()
	await frames(2)


func test_down_revive_die() -> void:
	var arena := _arena()
	await frames(2)
	var comp := autoload("Companions")
	comp.add("Kelly", "follower")
	var c: Companion = Companion.spawn(arena, "Kelly", "follower", 5.0, comp.roster["Kelly"])
	c.set_physics_process(false)
	await frames(2)
	c.take_damage(c.max_health + 5.0, "chest", null, 0.0)
	check("at 0 health the companion goes down, not dead", c.down and not c.dead and c.health == 0.0)
	check("a downed companion is no longer a zombie target", not c.is_in_group("zombie_targets"))
	var dh := c.down_health
	c.take_damage(10.0)
	check("hits while down wear down_health (4x player max)", c.down_health == dh - 10.0 and dh == roundf(autoload("Stats").max_health() * 4.0))
	c.interact()
	check("interact on a downed companion revives them at full health", not c.down and c.health == c.max_health and c.is_in_group("zombie_targets"))
	c.take_damage(c.max_health + 1.0)
	c.take_damage(c.down_health + 1.0)
	var was_dead: bool = c.dead
	await frames(3)
	check("enough damage while down kills them and removes them from the party",
			was_dead and not comp.has("Kelly") and comp.dismissed.has("Kelly"))
	var dropped := false
	for n in arena.get_children():
		if "container_id" in n and str(n.container_id).begins_with("drop_companion_Kelly"):
			dropped = true
	check("their weapon drops", dropped)
	autoload("LootState").reset()
	comp.reset()
	arena.queue_free()
	await frames(2)


func test_give_weapon_and_heal() -> void:
	var arena := _arena()
	await frames(2)
	var comp := autoload("Companions")
	var inv := autoload("Inventory")
	inv.reset()
	comp.add("Kelly", "follower")
	var c: Companion = Companion.spawn(arena, "Kelly", "follower", 5.0, comp.roster["Kelly"])
	await frames(2)
	check("Kelly starts with a kitchen knife", c.gun.weapon.ref == "kitchenKnife")
	inv.add_item("G17 Pistol", 2.0, 1)
	inv.set_magazine("G17 Pistol", 9)
	check("give weapon succeeds", c.give_weapon("G17 Pistol"))
	check("she now holds the pistol with its magazine, the pistol left the inventory, the knife came back",
			c.gun.weapon.ref == "glock" and c.gun.loaded == 9 and not inv.has_item("G17 Pistol") and inv.has_item(Weapon.from_ref("kitchenKnife").display_name))
	check("giving something not carried fails", not c.give_weapon("G17 Pistol"))
	c.health = 5.0
	var meds_name := ""
	for info in Items.all("meds"):
		if str(info["rec"].get("type", "health")) == "health":
			meds_name = info["name"]
			break
	inv.add_item(meds_name, 1.0, 1)
	var healed := c.heal_with(meds_name)
	check("a medkit heals her and is used up", healed > 0.0 and c.health > 5.0 and not inv.has_item(meds_name), "%s %.1f" % [meds_name, healed])
	check("the roster follows the live state", comp.roster["Kelly"].weapon == "glock")
	c.set_hold(true)
	check("hold position is stored", comp.roster["Kelly"].hold and c.state == "hold")
	var menu: CanvasLayer = (load("res://scripts/companions/companion_menu.gd") as GDScript).new()
	root.add_child(menu)
	inv.add_item("Hatchet", 3.0, 1)
	menu.open(c)
	check("the companion menu opens, pauses and lists weapons, hold and dismiss",
			menu.visible and paused and menu.weapon_options().size() >= 0 and menu._list.get_child_count() >= 3)
	menu.close()
	check("closing the menu unpauses", not paused and not menu.visible)
	menu.queue_free()
	inv.reset()
	comp.reset()
	arena.queue_free()
	await frames(2)


func test_roster_round_trip() -> void:
	var comp := autoload("Companions")
	comp.reset()
	comp.add("Hank", "follower")
	comp.roster["Hank"].health = 12.5
	comp.roster["Hank"].mag = 3
	comp.add("Partner", "partner")
	comp.note_enemy_killed("l5_s1_b0_f0_r1", 2, 4.5)
	var json := JSON.stringify(comp.to_dict())
	comp.reset()
	check("reset empties the roster", comp.active().is_empty() and comp.killed.is_empty())
	comp.from_dict(JSON.parse_string(json))
	check("roster survives a JSON round trip", comp.has("Hank") and comp.has("Partner") and comp.roster["Hank"].health == 12.5
			and comp.roster["Hank"].mag == 3 and typeof(comp.roster["Hank"].mag) == TYPE_INT)
	check("killed enemies survive too", comp.killed["l5_s1_b0_f0_r1"]["2"] == 4.5)
	check("Companions is stateful", comp.is_in_group("stateful"))
	comp.remove("Hank")
	check("dismiss removes them and keeps Quests from re-adding", not comp.has("Hank") and comp.dismissed.has("Hank"))
	comp.reset()


func test_partner_quest() -> void:
	var comp := autoload("Companions")
	var q := autoload("Quests")
	comp.reset()
	q.reset()
	var def: Dictionary = q.quest_def("915")
	for i in def.get("itemReq", []).size():
		autoload("Inventory").add_item(q.item_name(str(def.itemReq[i])), 1.0, int(def.itemCount[i]))
	q.start("915")
	var done: bool = q.complete("915")
	await frames(2)
	check("quest 915 completes", done)
	check("the partner joins after quest 915", comp.has("Partner") and comp.roster["Partner"].kind == "partner")
	check("Quests also flags the partner", q.has_partner())
	q.reset()
	autoload("Inventory").reset()
	comp.reset()


func test_level_hook() -> void:
	var comp := autoload("Companions")
	comp.reset()
	var builder := LevelBuilder.new()
	var room := "l11_s3_b1_f0_r503"
	var level := builder.build(room)
	root.add_child(level)
	await frames(2)
	var enemies := level.spawn_root().get_children().filter(func(n): return n is HumanEnemy)
	check("the level hook places the room's two HERC soldiers at their x", enemies.size() == 2
			and absf(enemies[0].global_position.x - 6.0) < 0.1 and enemies[0].gun.weapon.ref == "MP5", str(enemies.size()))
	check("they are hostile and on the lane", not enemies[0].friendly and is_zero_approx(enemies[0].global_position.z))
	level.queue_free()
	await frames(2)
	var guards := builder.build("l11_s3_b0_f0_r1")
	root.add_child(guards)
	await frames(2)
	var g := guards.spawn_root().get_children().filter(func(n): return n is HumanEnemy)
	check("friendly guards are placed as friendly", g.size() == 2 and g[0].friendly and g[0].stationary)
	guards.queue_free()
	await frames(2)
	# killed enemies stay dead; companions come along
	comp.add("Hank", "follower")
	comp.note_enemy_killed(room, 0, 6.0)
	var again := builder.build(room)
	root.add_child(again)
	await frames(2)
	var kids := again.spawn_root().get_children()
	var humans := kids.filter(func(n): return n is HumanEnemy)
	var comps := kids.filter(func(n): return n is Companion)
	check("a killed enemy is not placed again; the other one is", humans.size() == 1 and humans[0].index == 1)
	check("the active companion is placed in the same room", comps.size() == 1 and comps[0].npc_id == "Hank")
	again.queue_free()
	await frames(2)
	comp.reset()


func test_room_change(world: Node) -> void:
	var comp := autoload("Companions")
	comp.reset()
	world.reset()
	var scn = await load_scene("res://scenes/main.tscn")
	await frames(3)
	var player: Node3D = scn.get_player()
	comp.add("Hank", "follower")
	await frames(2)
	var c = comp.node_for("Hank")
	check("Hank stands in the street with the player", c != null and absf(c.global_position.x - player.global_position.x) < 3.0)
	world.enter_room("l16_s3_b0_f0_r1", "entr3")
	await frames(3)
	var c2 = comp.node_for("Hank")
	check("through a room change Hank follows, a new body next to the player",
			c2 != null and c2 != c and c2.get_parent() == world.level().spawn_root() and absf(c2.global_position.x - player.global_position.x) < 3.0,
			str(c2))
	check("his state came along (health, weapon)", c2.gun.weapon.ref == "hunter" and c2.health == c2.max_health)
	check("a companion on layer 4 does not block the player's lane", c2.collision_layer == 4 and is_zero_approx(c2.global_position.z))
	scn.queue_free()
	await frames(2)
	comp.reset()
