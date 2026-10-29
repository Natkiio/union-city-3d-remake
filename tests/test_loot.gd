extends "res://tests/test_base.gd"
## Loot workstream: container generation, search, persistence, locks and the
## lockpick logic, shops, container panel. Seeded, headless.

var _searched: Array = []


func _rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


func _names(items: Array) -> Array:
	var out: Array = []
	for e in items:
		out.append(e["name"])
	return out


func run() -> void:
	var inv := autoload("Inventory")
	var stats := autoload("Stats")
	var ls := autoload("LootState")
	var events := autoload("Events")
	var data := autoload("Data")
	stats.reset()
	inv.reset()
	ls.reset()
	events.container_searched.connect(func(id): _searched.append(id))

	# --- resolve ---
	var cash := LootRules.resolve("cash_120")
	check("resolve cash", cash["name"] == "Cash" and cash["count"] == 120 and cash["weight"] == 0.0)
	var ammo := LootRules.resolve("ammo9mm_50")
	check("resolve ammo uses inventory ammo name", ammo["name"] == "9mm Ammo" and ammo["count"] == 50)
	check("resolve 556 ammo", LootRules.resolve("ammo556_20")["name"] == "5.56 Ammo")
	check("resolve table item", LootRules.resolve("medkit")["name"] != null and not LootRules.resolve("medkit").is_empty())
	var modded := LootRules.resolve("M16A2_scope")
	check("resolve modded weapon falls back to base", modded.get("mod", "") == "scope" and modded["name"] == LootRules.resolve("M16A2")["name"])
	check("resolve unknown is empty", LootRules.resolve("nope_nothing").is_empty())

	# --- numbers from the doc ---
	check("lucky chance 75+luck*5+search*2", LootRules.lucky_chance(7, 5) == 114 and LootRules.lucky_chance(50, 10) == 225)
	check("cash index max ceil((danger*3.3+luck)/1.5)", LootRules.cash_index_max(10, 5) == 26 and LootRules.cash_index_max(30, 20) == 80)
	check("cash index max capped by 1001", LootRules.cash_index_max(5000, 0) == ceili(1001 / 1.5))
	var rates := LootRules.drop_rates()
	check("drop rates", rates["ammo"] == 40 and rates["food"] == 30 and rates["medical"] == 30 and rates["clothing"] == 25 and rates["weapons"] == 2 and rates["cash"] == 33)
	check("run'n'gun ammo rate x1.4", LootRules.drop_rates(true)["ammo"] == 56)
	check("search xp 5+level+ceil(smarts/30)", LootRules.search_xp(1, 10) == 7 and LootRules.search_xp(4, 61) == 12)

	# --- pools ---
	var kitchen := LootRules.junk_pool("kitchen")
	var kitchen_ok := not kitchen.is_empty()
	for ref in kitchen:
		var info := Items.find(ref)
		if info.is_empty() or info["rec"].get("location", "bedroom") != "kitchen":
			kitchen_ok = false
	check("kitchen junk pool is all kitchen items", kitchen_ok, str(kitchen.size()))
	check("unknown room type has an empty junk pool", LootRules.junk_pool("lounge").is_empty())
	var pool9 := LootRules.rarity_pool(9)
	var pool_ok := not pool9.is_empty()
	for ref in pool9:
		var info := Items.find(ref)
		if info["kind"] == "junk" or absf(float(info["rec"]["rarity"]) - 9) > 5:
			pool_ok = false
	check("rarity pool within cap and never junk", pool_ok, str(pool9.size()))
	check("PPM9 (rarity 4) is on rarity 1, G17-class (9) is not", "PPM9" in LootRules.rarity_pool(1) and not ("glock" in LootRules.rarity_pool(1)))

	# --- seeded rolls ---
	var nonempty := 0
	for i in 4000:
		if not LootRules.roll_junk("kitchen", 0, _rng(1000 + i)).is_empty():
			nonempty += 1
	var frac := nonempty / 4000.0
	check("junk roll hits ~51% * (5/6) at searching 0", frac > 0.38 and frac < 0.47, "%.3f" % frac)
	var any_junk := false
	for i in 300:
		if not LootRules.roll_junk("kitchen", 100, _rng(i)).is_empty():
			any_junk = true
	check("searching 100 never finds junk (count rounds to 0)", not any_junk)
	var lucky_hits := 0
	for i in 5000:
		if not LootRules.roll_lucky(5, 7, 5, _rng(50000 + i)).is_empty():
			lucky_hits += 1
	var lf := lucky_hits / 5000.0
	check("lucky roll ~ 115/1000", lf > 0.08 and lf < 0.15, "%.3f" % lf)
	var rar_ok := true
	for i in 500:
		var r := LootRules.lucky_rarity(30, 20, _rng(i))
		if r < 1 or r > 30:
			rar_ok = false
	check("lucky rarity within 1..30", rar_ok)
	var cash_ok := true
	var cash_seen := 0
	for i in 600:
		var ref := LootRules.roll_cash(10, 5, _rng(900 + i))
		if ref != "":
			cash_seen += 1
			var n := int(ref.substr(5))
			if n < 1 or n > 26:
				cash_ok = false
	check("cash amount index within 1..max", cash_ok)
	check("cash roll hits ~34%", cash_seen > 150 and cash_seen < 260, str(cash_seen))

	# --- generate ---
	var nj_def := {"desc": "Trunk", "cnt": ["tireIron_damaged", "tauron_damaged", "ammo9mm_5"], "noJunk": true}
	var nj_ok := true
	for i in 200:
		var got := LootRules.generate(nj_def, "anywhere", 20, {"searching": 0, "luck": 20}, _rng(i))
		if got.size() != 3:
			nj_ok = false
	check("noJunk skips junk, lucky and cash", nj_ok)
	var j_def := {"desc": "Cupboard", "cnt": ["medkit"]}
	var a := LootRules.generate(j_def, "kitchen", 10, {"searching": 7, "luck": 5}, _rng(77))
	var b := LootRules.generate(j_def, "kitchen", 10, {"searching": 7, "luck": 5}, _rng(77))
	check("same seed gives same contents", JSON.stringify(a) == JSON.stringify(b))
	var cash_in_kitchen := false
	var cash_in_anywhere := false
	var grew := false
	for i in 400:
		for e in LootRules.generate(j_def, "kitchen", 10, {"searching": 7, "luck": 5}, _rng(i)):
			if e["kind"] == "cash":
				cash_in_kitchen = true
		var any_items := LootRules.generate(j_def, "anywhere", 10, {"searching": 7, "luck": 5}, _rng(i))
		if any_items.size() > 1:
			grew = true
		for e in any_items:
			if e["kind"] == "cash":
				cash_in_anywhere = true
	check("cash only appears in 'anywhere' rooms", cash_in_anywhere and not cash_in_kitchen)
	check("junk/lucky add items beyond the fixed list", grew)
	var shuffled_differs := false
	var big := {"cnt": ["medkit", "glock", "M1911", "M9", "PPM9", "tauron", "shotgun", "MP5"], "noJunk": true}
	var base_order := _names(LootRules.generate(big, "anywhere", 1, {}, _rng(1)))
	for i in range(2, 12):
		if _names(LootRules.generate(big, "anywhere", 1, {}, _rng(i))) != base_order:
			shuffled_differs = true
	check("contents are shuffled", shuffled_differs)

	# --- locks: formulas ---
	check("required skills 15/30/45/60/75", [Locks.required_skill("very easy"), Locks.required_skill("easy"), Locks.required_skill("normal"), Locks.required_skill("hard"), Locks.required_skill("very hard")] == [15, 30, 45, 60, 75])
	check("pin counts 1/2/2/3/3", [Locks.pin_count("very easy"), Locks.pin_count("easy"), Locks.pin_count("normal"), Locks.pin_count("hard"), Locks.pin_count("very hard")] == [1, 2, 2, 3, 3])
	check("half width = adj/5*k", is_equal_approx(Locks.half_width(30, "normal"), 6.9) and is_equal_approx(Locks.half_width(20, "very hard"), 2.5))
	check("half width capped at 10", Locks.half_width(100, "very easy") == 10.0)
	check("force chance round((adj+luck)*k)", Locks.force_chance(40, 5, "normal") == 52 and Locks.force_chance(40, 5, "very hard") == 28)
	check("force chance capped at 95", Locks.force_chance(100, 20, "very easy") == 95)
	check("skill gate is required - 25", Locks.can_attempt(20, "normal") and not Locks.can_attempt(19, "normal"))
	check("difficulty label", Locks.difficulty_label(45, "normal") == "normal" and Locks.difficulty_label(80, "normal") == "very easy" and Locks.difficulty_label(0, "normal") == "very hard")
	check("security xp 25+level+ceil(smarts/30)", Locks.security_xp(3, 45) == 30)
	var fr := _rng(5)
	check("force roll is random(100)+1 <= chance", Locks.force_roll(100, fr) and not Locks.force_roll(0, fr))

	# --- pick game logic ---
	var g := PickGame.create(60, 5, "hard", _rng(3))
	check("pick game: pin count and width", g.pin_count() == 3 and is_equal_approx(g.half_width, minf(10.0, 60 / 5.0 * 0.85)))
	var centers_ok := true
	for c in g.centers:
		if c < PickGame.RANGE_TOP or c > PickGame.RANGE_BOTTOM:
			centers_ok = false
	check("pin centres stay in range", centers_ok)
	g.tick(1.0, true)
	check("holding push raises the pin to the top", g.heights[0] == PickGame.PIN_TOP)
	g.tick(2.0, false)
	check("releasing lets it fall to the bottom", g.heights[0] == PickGame.PIN_BOTTOM)
	g.heights[0] = g.centers[0] + g.half_width + 1.0
	check("miss outside the sweet spot", g.lock_pin() == PickGame.Outcome.MISS and g.current == 0 and g.misses == 1)
	g.heights[0] = g.centers[0]
	check("hit moves to next pin", g.lock_pin() == PickGame.Outcome.HIT and g.current == 1)
	g.heights[1] = g.centers[1] + g.half_width + 2.0
	g.lock_pin()
	check("miss steps back and drops both pins", g.current == 0 and g.heights[0] == PickGame.PIN_BOTTOM)
	g.heights[0] = g.centers[0]; g.lock_pin()
	g.heights[1] = g.centers[1]; g.lock_pin()
	g.heights[2] = g.centers[2] - g.half_width
	check("edge of the sweet spot counts, last pin completes", g.lock_pin() == PickGame.Outcome.COMPLETE and g.complete)
	var vh := PickGame.create(100, 5, "very hard", _rng(8))
	vh.heights[0] = vh.centers[0]; vh.lock_pin()
	vh.heights[1] = vh.centers[1]; vh.lock_pin()
	vh.heights[2] = vh.centers[2] + 50.0
	vh.lock_pin()
	check("very hard: a miss on pin 3 steps back two", vh.current == 0 and vh.heights[0] == PickGame.PIN_BOTTOM)

	# --- lock flow: keys, refusal, force ---
	var door := {"id": "l16_s3_b1_f1_r1_door1", "door_id": "l16_s3_b1_f1_r1_room2", "locked": true, "lock_diff": "hard", "needs_key": true, "can_force": false}
	var res: Array = []
	var cb := func(ok: bool): res.append(ok)
	check("keyed door without key is denied", Locks.try_open(door, root, cb) == Locks.Result.DENIED and res == [false] and Locks.last_denied_reason == "KEY REQUIRED")
	inv.add_item("Test Key", 0.0, 1)
	res.clear()
	check("matching key opens and is consumed", Locks.try_open(door, root, cb) == Locks.Result.OPENED and res == [true] and not inv.has_item("Test Key"))
	check("unlock persists in LootState", Locks.is_unlocked(door) and ls.get_lock(door["id"])["unlocked"])
	res.clear()
	check("an unlocked lock opens without a key", Locks.try_open(door, root, cb) == Locks.Result.OPENED and res == [true])
	var wrong := {"id": "x_door", "door_id": "l16_s3_b1_f1_r1_room2", "locked": true, "lock_diff": "normal", "needs_key": true}
	inv.add_item("Test Key", 0.0, 1)
	check("key finds its door by door_id", Locks.find_key(wrong) == "Test Key")
	var other := {"id": "x_door2", "door_id": "somewhere_else", "locked": true, "lock_diff": "normal", "needs_key": true}
	check("key for another door is not found", Locks.find_key(other) == "")
	inv.reset()
	var hard_lock := {"id": "cont_hard", "locked": true, "lock_diff": "very hard", "can_force": true}
	var adj: int = stats.adjusted_skill("security")
	check("default security skill is below the very hard gate", not Locks.can_attempt(adj, "very hard"), "adj %d" % adj)
	res.clear()
	check("skill gate denies with a message", Locks.try_open(hard_lock, root, cb) == Locks.Result.DENIED and Locks.last_denied_reason.begins_with("SECURITY SKILL TOO LOW"))
	var f_lock := {"id": "force_me", "locked": true, "lock_diff": "easy", "can_force": true}
	var chance := Locks.force_chance(adj, stats.attr("luck"), "easy")
	var expect_ok := Locks.force_roll(chance, _rng(21))
	var xp_before: int = stats.xp
	var got_ok := Locks.force(f_lock, _rng(21))
	check("force follows the seeded roll", got_ok == expect_ok)
	if got_ok:
		check("force success unlocks and gives security XP", Locks.is_unlocked(f_lock) and stats.xp > xp_before)
	else:
		check("force failure breaks the lock for good", Locks.is_broken(f_lock) and not Locks.is_unlocked(f_lock))
	# Find one seed of each outcome to prove both branches.
	var s_ok := -1
	var s_bad := -1
	for sd in 200:
		var rr := Locks.force_roll(chance, _rng(sd))
		if rr and s_ok < 0:
			s_ok = sd
		if not rr and s_bad < 0:
			s_bad = sd
	var l_ok := {"id": "force_ok", "locked": true, "lock_diff": "easy"}
	var l_bad := {"id": "force_bad", "locked": true, "lock_diff": "easy"}
	check("force success branch", Locks.force(l_ok, _rng(s_ok)) and Locks.is_unlocked(l_ok))
	check("force failure branch breaks permanently", not Locks.force(l_bad, _rng(s_bad)) and Locks.is_broken(l_bad))
	res.clear()
	check("broken lock refuses everything", Locks.try_open(l_bad, root, cb) == Locks.Result.DENIED and Locks.last_denied_reason == "LOCK IS BROKEN")

	# --- minigame through its scene ---
	stats.from_dict({"attrs": {"intellect": 10, "luck": 5}, "skills": {"security": 40}})
	var pick_lock := {"id": "pick_me", "locked": true, "lock_diff": "easy", "can_force": true}
	res.clear()
	var xp0: int = stats.xp
	var lvl0: int = stats.level
	var r0 := Locks.try_open(pick_lock, root, cb)
	check("pickable lock starts the minigame", r0 == Locks.Result.STARTED and paused)
	var ui = null
	for c in root.get_children():
		if c.has_method("set_pin"):
			ui = c
	check("lockpick scene is up with an easy lock", ui != null and ui.game != null and ui.game.pin_count() == 2)
	if ui != null:
		ui.game.heights[0] = ui.game.centers[0]
		ui.set_pin()
		check("first pin set, second pending", ui.game.current == 1 and res.is_empty())
		ui.game.heights[1] = ui.game.centers[1]
		ui.set_pin()
		await frames(2)
		check("completing the pins unlocks, calls back, unpauses", res == [true] and Locks.is_unlocked(pick_lock) and not paused)
		check("pick success grants security XP", stats.xp > xp0 or stats.level > lvl0)
	stats.reset()

	# --- container from a real room def ---
	var l16: Dictionary = data.table("world/l16")
	var cdef: Dictionary = l16["s1"]["b0"]["f0"]["r1"]["cont1"]
	var room: Dictionary = l16["s1"]["b0"]["f0"]["r1"]
	var cid := "l16_s1_b0_f0_r1_cont1"
	var c1 = load("res://scenes/loot/container.tscn").instantiate()
	c1.setup(cid, cdef, room["type"], 1)
	root.add_child(c1)
	await frames(2)
	check("container builds visual, trigger, hover", c1.get_node("Body") != null and c1.get_node("Trigger") is Area3D and c1.get_node("Hover").is_in_group("hoverable"))
	check("body is recessed behind the lane, trigger reaches Z=0", c1.get_node("Body").position.z < -0.5 and c1.get_node("Trigger").position.z + (c1.get_node("Trigger/Shape") as CollisionShape3D).shape.size.z * 0.5 >= 0.0)
	check("trunk desc gets a visual", load("res://scripts/loot/container.gd").visual_for("Trunk")["size"] is Vector3 and load("res://scripts/loot/container.gd").visual_for("Fridge")["size"].y > 1.5)
	check("not searched yet, not locked", not c1.searched and not c1.is_locked() and c1.items.is_empty())
	var xp_a: int = stats.xp
	_searched.clear()
	check("search_now builds contents once", c1.search_now() and c1.items.size() == 3 and not c1.search_now())
	check("search grants XP and emits container_searched", stats.xp == xp_a + LootRules.search_xp(stats.level, stats.adjusted_skill("smarts")) and _searched == [cid])
	var first_names := _names(c1.items)
	var taken = c1.take_item(0)
	check("take_item returns the entry", taken["name"] == first_names[0] and c1.items.size() == 2)
	c1.queue_free()
	await frames(2)
	var c2 = load("res://scenes/loot/container.tscn").instantiate()
	c2.setup(cid, cdef, room["type"], 1)
	root.add_child(c2)
	await frames(2)
	check("partial take persists across a reload", c2.searched and _names(c2.items) == first_names.slice(1))
	var rest = c2.take_all()
	check("take_all empties and persists", rest.size() == 2 and c2.items.is_empty() and ls.get_container(cid)["items"].is_empty())
	check("searching again does not regenerate", not c2.search_now())
	c2.queue_free()
	await frames(2)

	# --- locked container from real data ---
	var l11: Dictionary = data.table("world/l11")
	var ldef: Dictionary = l11["s3"]["b1"]["f0"]["r505"]["cont4"]
	var c3 = load("res://scenes/loot/container.tscn").instantiate()
	c3.setup("l11_s3_b1_f0_r505_cont4", ldef, "anywhere", 11)
	root.add_child(c3)
	await frames(2)
	check("locked footlocker reads its lock", c3.is_locked() and c3.lock_def()["lock_diff"] == "normal" and c3.lock_def()["can_force"])
	Locks.unlock(c3.lock_def())
	check("unlocking clears is_locked", not c3.is_locked())
	c3.queue_free()

	# --- persistence round trip (through JSON, like a save file) ---
	ls.set_container("a_cont", {"searched": true, "items": [{"name": "Medkit", "weight": 2.0, "count": 3, "kind": "meds"}]})
	ls.set_lock("a_door", {"unlocked": true, "broken": false})
	var snap: Dictionary = JSON.parse_string(JSON.stringify(ls.to_dict()))
	ls.reset()
	check("LootState reset clears containers and locks", ls.containers.is_empty() and ls.locks.is_empty())
	ls.from_dict(snap)
	check("LootState round trip", ls.has_container("a_cont") and ls.get_lock("a_door")["unlocked"] and int(ls.get_container("a_cont")["items"][0]["count"]) == 3)
	check("LootState is stateful", ls.is_in_group("stateful"))
	var c4 = load("res://scenes/loot/container.tscn").instantiate()
	c4.setup("a_cont", {"desc": "Bin", "cnt": []}, "anywhere", 1)
	root.add_child(c4)
	await frames(2)
	check("JSON floats come back as int counts", c4.items[0]["count"] is int and c4.items[0]["count"] == 3)
	c4.queue_free()

	# --- container panel ---
	inv.reset()
	var tui := autoload("TrunkUI")
	var c5 = load("res://scenes/loot/container.tscn").instantiate()
	c5.setup("panel_test", {"desc": "Locker", "cnt": ["medkit", "cash_40", "ammo9mm_12"], "noJunk": true}, "anywhere", 1)
	root.add_child(c5)
	await frames(2)
	c5.search_now()
	tui.open(c5)
	await frames(2)
	check("panel opens, pauses, shows the container title", tui.visible and paused and tui.title_label.text == "LOCKER")
	check("panel lists every item", tui.items_list.get_child_count() == 3)
	tui._take_single(0)
	check("take one moves it to the inventory", c5.items.size() == 2 and inv.item_count() >= 1)
	tui._take_all()
	check("take all gets cash as an inventory item", Shop.cash() == 40 and inv.items["9mm Ammo"]["count"] == 12)
	tui.close()
	check("panel close unpauses", not tui.visible and not paused)
	c5.queue_free()
	# Weight feedback: a heavy item over the limit is flagged.
	inv.reset()
	var c6 = load("res://scenes/loot/container.tscn").instantiate()
	c6.setup("heavy_test", {"desc": "Boxes", "cnt": [], "noJunk": true}, "anywhere", 1)
	root.add_child(c6)
	await frames(2)
	c6.searched = true
	c6.items = [{"name": "Anvil", "weight": float(inv.carry_limit()) + 10.0, "count": 1, "kind": "junk"}]
	tui.open(c6)
	await frames(2)
	var row: Button = tui.items_list.get_child(0)
	check("over-limit item is flagged in the panel", row.text.contains("over limit"))
	tui.close()
	c6.queue_free()
	inv.reset()

	# --- shop ---
	check("discount: smarts 100 halves, 0 pays full", Shop.discount_cost(600, 100) == 300 and Shop.discount_cost(600, 0) == 600 and Shop.discount_cost(75, 7) == 73)
	var st1 := Shop.stock(1)
	check("shopSet1 stock is 8-9 priced rows in slot order", st1.size() >= 8 and st1.size() <= 9 and st1[0]["num"] == 1 and st1[0]["cost"] == 600 and st1[0]["item"].get("mod", "") == "scope")
	check("shopSet2 loads", Shop.stock(2).size() >= 6)
	check("ammo row stacks its box", _names(st1.map(func(r): return r["item"])).has("5.56 Ammo"))
	check("no cash, no purchase", not Shop.buy(st1[5]) and not inv.has_item(st1[5]["item"]["name"]))
	Shop.add_cash(1000)
	check("cash is an inventory item", Shop.cash() == 1000 and inv.items["Cash"]["weight"] == 0.0)
	var medkit_row: Dictionary = st1[5]
	var paid := Shop.price(medkit_row["cost"])
	check("buy deducts discounted price and adds the item", Shop.buy(medkit_row) and Shop.cash() == 1000 - paid and inv.has_item(medkit_row["item"]["name"]))
	check("sell price is half the base cost", Shop.sell_price(medkit_row["item"]["name"]) == 37)
	var before := Shop.cash()
	check("sell pays out and removes the item", Shop.sell(medkit_row["item"]["name"]) and Shop.cash() == before + 37 and not inv.has_item(medkit_row["item"]["name"]))
	check("unsellable items stay put", Shop.sell_price("Scrap Paper") == 0 and not Shop.sell("Scrap Paper"))
	check("spending more than you have fails", not Shop.spend_cash(999999))
	var shop_ui = load("res://scenes/ui/shop.tscn").instantiate()
	root.add_child(shop_ui)
	await frames(2)
	shop_ui.open(1)
	check("shop screen opens with the stock", shop_ui.visible and paused and shop_ui._buy_list.get_child_count() == st1.size())
	shop_ui.close()
	check("shop screen closes", not shop_ui.visible and not paused)
	shop_ui.queue_free()
	inv.reset()
	ls.reset()
