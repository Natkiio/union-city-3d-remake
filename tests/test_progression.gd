extends "res://tests/test_base.gd"
## Progression: attributes, skills, derived stats, XP, levels, backgrounds, serialisation.

func run() -> void:
	var s := autoload("Stats")
	var ev := autoload("Events")
	s.reset()

	check("base attr 5", s.attr("strength") == 5)
	check("base skill 7", s.skill("pistols") == 7)
	check("adjusted skill at attr 5 = 7+8-5 = 10", s.adjusted_skill("pistols") == 10)
	check("max health lvl1 end5 = 55", s.max_health() == 55.0, str(s.max_health()))
	check("carry weight str5 = 50", s.carry_weight() == 50.0)
	check("stamina max base = 1+5+10+56 = 72", s.stamina_max() == 72, str(s.stamina_max()))
	check("stamina regen base = 1", s.stamina_regen() == 1.0)
	check("crit chance base = round(5/7+10/11)=2", s.crit_chance("pistols") == 2)
	check("xp threshold L1 = 100", s.level_xp(1) == 100)
	check("xp threshold L5 = 2500", s.level_xp(5) == 2500)
	check("xp threshold L10 = 10000", s.level_xp(10) == 10000)
	check("xp threshold L29 = 84100", s.level_xp(29) == 84100)

	# attribute 10, skill 7 => 7 + 16 - 5 = 18 (source formula; see docs/progression.md)
	s.from_dict({"attrs": {"precision": 10}})
	check("adjusted skill attr10 = 18", s.adjusted_skill("pistols") == 18, str(s.adjusted_skill("pistols")))
	check("unrelated skill unaffected", s.adjusted_skill("blunt") == 10)
	s.from_dict({"attrs": {"endurance": 10}, "level": 3})
	check("max health end10 lvl3 = 150", s.max_health() == 150.0)

	# penalties
	s.reset()
	s.set_penalty("endurance", 2)
	check("penalty lowers attr", s.attr("endurance") == 3 and s.attr_base("endurance") == 5)
	check("penalty lowers max health", s.max_health() == 39.0, str(s.max_health()))
	s.set_penalty("endurance", 99)
	check("penalty floors at 1", s.attr("endurance") == 1)
	s.set_penalty("endurance", 0)
	check("penalty cleared", s.attr("endurance") == 5)

	# XP and levels
	var seen := {"xp": 0, "lvl": 0, "chg": 0}
	ev.xp_gained.connect(func(a, _r): seen.xp += a)
	ev.level_up.connect(func(l): seen.lvl = l)
	ev.stats_changed.connect(func(): seen.chg += 1)
	s.add_xp(60, "t")
	check("xp accumulates", s.xp == 60 and s.level == 1 and seen.xp == 60)
	s.add_xp(40, "t")
	check("level up at 100, xp resets", s.level == 2 and s.xp == 0 and seen.lvl == 2)
	check("level up grants points", s.attribute_points == 1 and s.skill_points == 10)
	check("stats_changed emitted", seen.chg > 0)
	check("next threshold L2 = 400", s.xp_to_next() == 400)

	# spending
	check("spend_attr works", s.spend_attr("strength") and s.attr("strength") == 6 and s.attribute_points == 0)
	check("spend_attr fails with no points", not s.spend_attr("strength"))
	check("spend_skill works", s.spend_skill("pistols") and s.skill("pistols") == 8 and s.skill_points == 9)
	check("spend_skill rejects attribute name", not s.spend_skill("strength"))
	s.attribute_points = 5
	s._attrs["luck"] = 20
	check("attribute capped at 20", not s.spend_attr("luck"))
	s.skill_points = 5
	s._skills["blunt"] = 100
	check("skill capped at 100", not s.spend_skill("blunt"))

	# level cap
	s.reset()
	s.level = 30
	s.add_xp(100000)
	check("no levelling past 30", s.level == 30 and s.xp == 0)

	# kill XP
	s.reset()
	check("kill xp danger1 slow = 10", s.kill_xp("zombieSlow", 1) == 10, str(s.kill_xp("zombieSlow", 1)))
	check("kill xp fast has bonus 1.1", s.kill_xp("zombieFast", 1) == 11)
	check("kill xp danger 10 fat = round(55*1.2)=66", s.kill_xp("zombieFat", 10) == 66, str(s.kill_xp("zombieFat", 10)))
	s.level = 6
	check("anti-farming: level - danger > 4 gives 0", s.kill_xp("zombieSlow", 1) == 0)
	s.level = 5
	check("level - danger == 4 still pays", s.kill_xp("zombieSlow", 1) == 10)
	s.reset()
	ev.enemy_killed.emit("zombieSlow", 1, 0)
	check("enemy_killed event awards XP", s.xp == 10, str(s.xp))
	s.add_xp(50)
	s.apply_death_penalty()
	check("death halves XP", s.xp == 30)

	# regen formulas
	s.reset()
	check("health regen/tick base", is_equal_approx(s.health_regen_per_tick(), 55.0 / 200.0 * (5 + roundi(10 / 5.0)) / 2.0))
	s.from_dict({"attrs": {"endurance": 10}, "skills": {"fitness": 7}})
	check("stamina regen end10", s.stamina_regen() == maxf(0.1, roundi((10 + 18) / 20.0)), str(s.stamina_regen()))

	# backgrounds
	var pre: Dictionary = autoload("Data").table("pre")
	check("14 backgrounds", pre.size() == 14 and s.background_refs().size() == 14)
	var all_ok := true
	for ref in pre:
		all_ok = all_ok and s.set_background(ref)
		for a in s.ATTRIBUTES:
			all_ok = all_ok and s.attr(a) == int(pre[ref][a])
		for i in range(1, 5):
			all_ok = all_ok and s.skill(pre[ref]["skill%d" % i]) == 17
	check("every background applies attributes and +10 skills", all_ok)
	s.set_background("military")
	check("military: str 9, automatics 17", s.attr("strength") == 9 and s.skill("automatics") == 17)
	check("military: max health 20+64+10 = 94", s.max_health() == 94.0)
	check("military: adjusted automatics = 17+round(9*1.6-5)=17+9=26", s.adjusted_skill("automatics") == 26, str(s.adjusted_skill("automatics")))
	check("unknown background rejected", not s.set_background("nope") and s.background == "military")

	# free spend
	check("custom: 10 points ok", s.create_custom({"strength": 5, "luck": 5}, ["blunt", "sneak"]) and s.attr("strength") == 10 and s.skill("blunt") == 17)
	check("custom: 11 points rejected", not s.create_custom({"strength": 5, "luck": 6}, []))
	check("custom: attribute over 10 at start rejected", not s.create_custom({"strength": 6}, []))
	check("custom: 5 skills rejected", not s.create_custom({}, ["blunt", "blades", "sneak", "luck2", "smarts"]))
	check("custom: unknown skill rejected", not s.create_custom({}, ["nope"]))

	# serialisation and reset
	s.set_background("hunter")
	s.set_identity("Aoife", "female")
	s.add_xp(100)
	s.spend_attr("luck")
	var snap: Dictionary = s.to_dict()
	var json_snap: Dictionary = JSON.parse_string(JSON.stringify(snap))
	s.reset()
	check("reset restores defaults", s.level == 1 and s.xp == 0 and s.player_name == "" and s.attr("precision") == 5 and s.background == "")
	s.from_dict(json_snap)
	check("round trip via JSON", s.to_dict() == snap, "%s vs %s" % [s.to_dict(), snap])
	check("round trip fields", s.player_name == "Aoife" and s.level == 2 and s.attr("precision") == 10 and s.skill("longGuns") == 17)
	autoload("GameState").reset_run()
	check("reset_run resets Stats", s.level == 1 and s.attr("precision") == 5)

	# UI scenes load and work
	s.reset()
	var cc: Node = await load_scene("res://scenes/ui/character_create.tscn")
	check("character_create loads", cc != null)
	check("confirm without a choice fails", not cc.confirm())
	cc._ref = "farmer"
	cc._name_edit.text = "Seán"
	check("confirm with background applies", cc.confirm() and s.background == "farmer" and s.player_name == "Seán")
	cc.queue_free()
	s.attribute_points = 1
	s.skill_points = 1
	var lu: Node = await load_scene("res://scenes/ui/level_up.tscn")
	check("level_up loads", lu != null)
	lu.queue_free()
	var sh: Node = await load_scene("res://scenes/ui/skills_sheet.tscn")
	check("skills_sheet loads", sh != null)
	sh.queue_free()
	s.reset()
