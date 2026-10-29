extends "res://tests/test_base.gd"
## Survival workstream: clock, hunger/sleep, Items lookup, item use, weight limit.

class FakePlayer extends Node:
	var health: float = 20.0
	var perm_health: float = 20.0
	func heal(amount: float) -> void:
		health = minf(55.0, health + amount)


func run() -> void:
	var clock := autoload("Clock")
	var surv := autoload("Survival")
	var inv := autoload("Inventory")
	var stats := autoload("Stats")
	var events := autoload("Events")
	var data := autoload("Data")
	clock.running = false
	clock.reset()
	surv.reset()
	surv.set_mode("survivor")
	inv.reset()

	# --- Clock ---
	check("clock starts at 12:00", clock.time_text() == "12:00" and clock.day() == 1 and clock.game_minutes == 1440)
	check("seconds per game minute is 50/30", is_equal_approx(clock.SECONDS_PER_GAME_MINUTE, 50.0 / 30.0))
	var hours_seen: Array = []
	var mins_seen := [0]
	events.hour_changed.connect(func(h): hours_seen.append(h))
	events.minute_passed.connect(func(_m): mins_seen[0] += 1)
	clock.advance(60)
	check("advance 60 -> 13:00, one hour signal", clock.time_text() == "13:00" and hours_seen == [13] and mins_seen[0] == 60, str(hours_seen))
	clock.advance(11 * 60 + 30)
	check("rollover to day 2 00:30", clock.time_text() == "00:30" and clock.day() == 2, clock.time_text())
	check("hour signal passed 0", hours_seen.has(0) and hours_seen.has(23))
	clock.set_time(9, 30)
	check("set_time 09:30", clock.time_text() == "09:30")
	var snap: Dictionary = clock.to_dict()
	clock.advance(500)
	clock.from_dict(snap)
	check("clock to_dict/from_dict", clock.time_text() == "09:30")

	# --- Lighting presets (03:00 / 09:30 / 17:00 / 22:00) ---
	check("preset at 03:00 is 1", clock.preset_id_for(3 * 60) == 1)
	check("preset at 09:30 is 12", clock.preset_id_for(9 * 60 + 30) == 12)
	check("preset at 09:31 is 13", clock.preset_id_for(9 * 60 + 31) == 13)
	check("preset at 17:00 is 17", clock.preset_id_for(17 * 60) == 17)
	check("preset at 22:00 is 28", clock.preset_id_for(22 * 60) == 28)
	check("preset at 13:00 is 14", clock.preset_id_for(13 * 60) == 14)
	check("preset at 12:30 is 13", clock.preset_id_for(12 * 60 + 30) == 13)
	var mono := true
	for m in range(1, 1440):
		if clock.preset_id_for(m) < clock.preset_id_for(m - 1):
			mono = false
	check("preset ids never go backwards in a day", mono)
	check("all 28 presets are reachable", clock.preset_id_for(1439) == 28 and clock.preset_id_for(0) == 1)
	clock.set_time(3, 0)
	var p: Dictionary = clock.lighting_preset()
	check("preset dict at 03:00", p["id"] == 1 and p["ra"] == 20 and p["ba"] == 25, str(p))
	check("indoor reduction dims", clock.lighting_preset_for(13, 50.0)["ra"] == 50.0)
	var night: float = clock.energy()
	clock.set_time(14, 0)
	check("day is brighter than night", clock.energy() > night and clock.energy() == 1.0 and night < 0.3, "%s %s" % [night, clock.energy()])
	check("light_color tops out at 1", maxf(clock.light_color().r, maxf(clock.light_color().g, clock.light_color().b)) == 1.0)
	var all_ok := true
	for i in range(1, 29):
		all_ok = all_ok and not data.table("world/lightTime%d" % i).is_empty()
	check("all 28 lightTime tables load", all_ok)

	# --- Hunger and sleep ---
	clock.set_time(12, 0)
	surv.reset()
	clock.advance(100)
	check("hunger +0.15 per minute", is_equal_approx(surv.hunger, 15.0) and is_equal_approx(surv.sleep, 15.0), str(surv.hunger))
	check("penalty formula", surv.penalty_for(70) == 0 and surv.penalty_for(79) == 3 and surv.penalty_for(100) == 10 and surv.penalty_for(71) == 0 and surv.penalty_for(72) == 1)
	surv.hunger = 85.0
	surv.sleep = 100.0
	surv._update_penalties()
	check("hunger penalty 5, sleep penalty 10", surv.hunger_penalty() == 5 and surv.sleep_penalty() == 10)
	check("indicator levels round(v/25)", surv.hunger_state() == 3 and surv.sleep_state() == 4)
	surv.set_mode("runngun")
	var h0: float = surv.hunger
	clock.advance(60)
	check("runngun: no hunger, no penalty", surv.hunger == h0 and surv.hunger_penalty() == 0 and surv.sleep_penalty() == 0)
	surv.set_mode("survivor")
	surv.hunger = 99.9
	clock.advance(10)
	check("hunger clamps at 100", surv.hunger == 100.0)
	surv.eat(30)
	check("eat lowers hunger", is_equal_approx(surv.hunger, 70.0))
	surv.eat(500)
	check("hunger floors at 0", surv.hunger == 0.0)
	surv.sleep = 80.0
	surv.reduce_sleep(2.5)
	check("sleep aid lowers sleep by round(2.5*10)=25", is_equal_approx(surv.sleep, 55.0), str(surv.sleep))
	surv.hunger = 0.0
	surv.sleep = 50.0
	var t0: int = clock.game_minutes
	surv.sleep_hours(4)
	check("sleep 4h: time +240, sleep -40, hunger +24", clock.game_minutes - t0 == 240 and is_equal_approx(surv.sleep, 10.0) and is_equal_approx(surv.hunger, 24.0), "%s %s" % [surv.sleep, surv.hunger])
	surv.wait_hours(2)
	check("wait 2h: meters unchanged", is_equal_approx(surv.sleep, 10.0) and is_equal_approx(surv.hunger, 24.0))
	var sd: Dictionary = surv.to_dict()
	surv.reset()
	surv.from_dict(sd)
	check("survival to_dict/from_dict", is_equal_approx(surv.hunger, 24.0) and surv.mode == "survivor")
	surv.reset()
	check("survival reset", surv.hunger == 0.0 and surv.sleep == 0.0)

	# --- Items lookup ---
	var kinds := {"weapon": 0, "clothing": 0, "food": 0, "meds": 0, "books": 0, "junk": 0, "questItem": 0}
	var unresolved: Array = []
	for k in kinds:
		for key in data.table(k):
			var rec: Dictionary = data.table(k)[key]
			var row := Items.in_table(k, key)
			kinds[k] += 1
			var by_name := Items.find(rec.get("name", ""))
			var by_key := Items.find(key)
			if row.is_empty() or by_name.is_empty() or by_key.is_empty() or not is_equal_approx(row["weight"], float(rec.get("weight", 0.0))):
				unresolved.append("%s:%s" % [k, key])
	check("every row of every table resolves", unresolved.is_empty() and Items.all().size() == kinds.values().reduce(func(a, b): return a + b), str(unresolved))
	check("Items.find by name and ref agree", Items.find("Bandages")["ref"] == "bandage" and Items.find("bandage")["name"] == "Bandages")
	check("Items.kind", Items.kind("Bandages") == "meds" and Items.kind("Canned Beans") == "food" and Items.kind("Handgun Owner") == "books" and Items.kind("9mm Ammo") == "ammo" and Items.kind("zzz") == "")
	check("Items.kind weapon and clothing", Items.kind("glock") == "weapon" and Items.kind("Cigarettes") == "junk" and Items.kind("Bolt Cutters") == "questItem")
	check("Items.weight", Items.weight("Bandages") == 0.5 and Items.weight("nonexistent", 2.5) == 2.5)
	check("every clothing row has a slot", Items.all("clothing").all(func(i): return i["rec"].has("wearLocation")))

	# --- Inventory: weight default and regression ---
	inv.reset()
	inv.add_item("Medkit")
	check("add_item default weight comes from Items", inv.items["Medkit"]["weight"] == Items.weight("Medkit"))
	inv.add_item("Weird Thing", 2.0, 2)
	inv.add_item("Weird Thing")
	check("explicit weight kept and stacks", inv.items["Weird Thing"]["weight"] == 2.0 and inv.items["Weird Thing"]["count"] == 3)
	inv.remove_item("Weird Thing", 3)
	check("remove_item / has_item", not inv.has_item("Weird Thing") and inv.has_item("Medkit"))
	check("tag_for still works", inv.tag_for("G17 Pistol") in ["WEAPON", ""] and inv.tag_for("9mm Ammo") == "AMMO")
	inv.set_magazine("G17 Pistol", 7)
	check("magazines still work", inv.get_magazine("G17 Pistol", 15) == 7)
	check("usable flags", inv.is_usable("Bandages") and inv.is_usable("Canned Beans") and not inv.is_usable("Cigarettes") and not inv.is_usable("Bolt Cutters"))

	# --- Using items, doc numbers (stub Stats: all skills 7 -> adjusted 7) ---
	var surv_adj: int = stats.adjusted_skill("survival")
	var beans := Items.find("Canned Beans")
	var expect_food: int = roundi(20 + surv_adj / 5.0)
	check("food amount = round(bonus + survival/5)", ItemUse.food_amount(beans) == expect_food, str(expect_food))
	inv.reset()
	surv.reset()
	surv.hunger = 50.0
	inv.add_item("Canned Beans", 0.5)
	var used_names: Array = []
	events.item_used.connect(func(n): used_names.append(n))
	check("use food (survivor) returns true", inv.use_item("Canned Beans"))
	check("food lowered hunger, consumed, signalled", is_equal_approx(surv.hunger, 50.0 - expect_food) and not inv.has_item("Canned Beans") and used_names == ["Canned Beans"])
	check("using a missing item fails", not inv.use_item("Canned Beans"))

	var player := FakePlayer.new()
	player.add_to_group("player")
	root.add_child(player)
	surv.set_mode("runngun")
	inv.add_item("Canned Beans", 0.5)
	player.health = 20.0
	player.perm_health = 20.0
	inv.use_item("Canned Beans")
	check("food (runngun) heals health and perm_health", player.health == 20.0 + expect_food and player.perm_health == 20.0 + expect_food, str(player.health))
	surv.set_mode("survivor")

	var band := Items.find("Bandages")
	var expect_med: int = roundi(roundi(5 + stats.adjusted_skill("firstAid") / 2.0) / 100.0 * stats.max_health())
	check("med heal = round((bonus + firstAid/2)/100*max)", ItemUse.med_heal(band) == expect_med, str(expect_med))
	check("medkit heals more than bandages", ItemUse.med_heal(Items.find("Medkit")) > ItemUse.med_heal(band))
	player.health = 20.0
	player.perm_health = 20.0
	inv.add_item("Bandages")
	check("use meds heals", inv.use_item("Bandages") and player.health == 20.0 + expect_med and player.perm_health == 20.0 + expect_med and not inv.has_item("Bandages"))
	player.perm_health = stats.max_health()
	inv.add_item("Bandages")
	check("meds refused when perm health is full", not inv.use_item("Bandages") and inv.has_item("Bandages"))
	surv.sleep = 0.0
	inv.add_item("No ZZZ")
	check("sleep aid refused when not tired", not inv.use_item("No ZZZ"))
	surv.sleep = 60.0
	check("sleep aid used", inv.use_item("No ZZZ") and is_equal_approx(surv.sleep, 35.0))
	player.free()

	var book := Items.find("Handgun Owner")
	var expect_book: int = 3 + ceili(stats.adjusted_skill("smarts") / 33.0)
	check("book points = bonus + ceil(smarts/33)", ItemUse.book_points(book) == expect_book, str(expect_book))
	inv.add_item("Handgun Owner")
	check("book used and consumed", inv.use_item("Handgun Owner") and not inv.has_item("Handgun Owner"))
	check("book points recorded when Stats has no add_skill_points",
		stats.has_method("add_skill_points") or inv.book_points.get("pistols", 0) == expect_book, str(inv.book_points))
	var sp := Items.find("Future Weaponry")
	check("book skill follows the table key", sp["key"] == "specialWeapons")

	var jacket: Dictionary = Items.all("clothing").filter(func(i): return i["rec"].get("wearLocation") == "top" and i["name"] != "NONE")[0]
	inv.add_item(jacket["name"])
	check("clothing equips into its slot, not consumed", inv.use_item(jacket["name"]) and inv.equipped_clothing.get("top") == jacket["name"] and inv.has_item(jacket["name"]))
	var cs: Dictionary = inv.to_dict()
	inv.use_item(jacket["name"])
	check("using worn clothing takes it off", not inv.equipped_clothing.has("top"))
	inv.from_dict(cs)
	check("equipped clothing saved", inv.equipped_clothing.get("top") == jacket["name"])
	check("weapons and junk are not usable", not inv.use_item("Cigarettes"))

	# --- Weight limit ---
	inv.reset()
	var flips: Array = []
	inv.overweight_changed.connect(func(o): flips.append(o))
	var limit: float = inv.carry_limit()
	check("carry_limit comes from Stats", limit == stats.carry_weight())
	inv.add_item("Brick", limit - 1.0)
	check("under the limit: flag off", not inv.overweight and flips.is_empty())
	inv.add_item("Anvil", 2.0)
	check("over the limit: flag on, signal once", inv.overweight and flips == [true], str(flips))
	inv.remove_item("Anvil")
	check("back under: flag off", not inv.overweight and flips == [true, false])
	inv.reset()

	# --- UI scene loads with the weight bar ---
	var ui: Node = autoload("InventoryUI")
	check("inventory UI has weight bar", ui.get_node_or_null("Panel/WeightBar") != null)
	inv.add_item("Brick", limit + 5.0)
	ui._open()
	var bar: ProgressBar = ui.get_node("Panel/WeightBar")
	var fill: StyleBoxFlat = bar.get_theme_stylebox("fill")
	check("weight bar red over limit", fill.bg_color.r > 0.6 and fill.bg_color.g < 0.3 and "OVERLOADED" in ui.total_weight_label.text)
	ui._close()
	inv.reset()
	# --- DayNight node ---
	var scene_root := Node3D.new()
	var light := DirectionalLight3D.new()
	var we := WorldEnvironment.new()
	we.environment = Environment.new()
	var dn := DayNight.new()
	scene_root.add_child(light)
	scene_root.add_child(we)
	scene_root.add_child(dn)
	root.add_child(scene_root)
	clock.set_time(3, 0)
	dn.apply_now()
	var night_e: float = light.light_energy
	clock.set_time(14, 0)
	dn.apply_now()
	check("DayNight finds light and env, tints by time", dn.sun == light and dn.world_environment == we and light.light_energy > night_e and we.environment.ambient_light_energy == 1.0, "%s %s" % [night_e, light.light_energy])
	scene_root.free()
	clock.running = true
