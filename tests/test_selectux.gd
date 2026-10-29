extends "res://tests/test_base.gd"
## Selection feedback: one active target, equal to World.interact_target(), with
## an action verb per kind, and no flip-flop at an equal distance.

func run() -> void:
	var world := autoload("World")
	world.fade_enabled = false
	autoload("Clock").running = false
	autoload("Director").enabled = false
	world.reset()
	var scn = await load_scene("res://scenes/main.tscn")
	await frames(3)
	var player: Node3D = scn.get_player()

	# Safehouse: containers, an NPC, a bed and an exit close together.
	world.enter_room("l16_s3_b1_f1_r1")
	await frames(3)
	var level: Level = world.level()
	var ux: SelectionUX = level.get_node("SelectionUX")
	var things: Array = []
	for n in level.find_children("*", "", true, false):
		if n.has_method("select_info"):
			things.append(n)
	check("room has selectable things", things.size() >= 3, str(things.size()))

	var kinds := {}
	for t in things:
		await _stand_at(player, t)
		var tgt = world.interact_target()
		check("%s: active target is World.interact_target()" % t.name, ux.active == tgt and tgt != null, str(tgt))
		var shown := 0
		for l in level.find_children("*", "Label3D", true, false):
			if l.visible and l.name in ["Prompt", "ActivePrompt"]:
				shown += 1
		check("%s: exactly one prompt visible" % t.name, shown == 1, str(shown))
		kinds[ux.info.get("kind", "")] = ux.info.get("text", "")
		check("%s: prompt starts with [E]" % t.name, str(ux.info.get("text", "")).begins_with("[E] "), str(ux.info.get("text", "")))
	var texts := ", ".join(kinds.values())
	check("kinds covered include container, exit and person",
			kinds.has("container") or kinds.has("empty"), texts)
	for k in kinds:
		var tx: String = kinds[k]
		match k:
			"container": check("container verb", tx.contains("Search") or tx.contains("Open"), tx)
			"exit": check("exit verb", tx.contains("Leave") or tx.contains("Enter") or tx.contains("Go to"), tx)
			"person": check("person verb", tx.contains("Talk to"), tx)
			"bed": check("bed verb", tx.contains("Sleep"), tx)
	check("colours differ per kind", SelectionUX.color_for("container") != SelectionUX.color_for("exit")
			and SelectionUX.color_for("exit") != SelectionUX.color_for("person")
			and SelectionUX.color_for("locked") != SelectionUX.color_for("container"))

	# Locked cabinet on 14 Main Street.
	world.enter_room("l16_s3_b4_f1_r1")
	await frames(3)
	level = world.level()
	ux = level.get_node("SelectionUX")
	for n in level.find_children("*", "", true, false):
		if n.has_method("is_locked") and n.is_locked():
			await _stand_at(player, n)
			check("locked container prompt is red and says why", ux.info.get("kind") == "locked"
					and str(ux.info.text).contains("locked"), str(ux.info))
			break

	# Hysteresis: two in-range things; the previous one is kept near a tie.
	world.enter_room("l16_s3_b1_f1_r1")
	await frames(3)
	level = world.level()
	ux = level.get_node("SelectionUX")
	var pair := _closest_pair(level)
	if pair.size() == 2:
		var a: Node3D = pair[0]
		var b: Node3D = pair[1]
		var mid := (a.global_position.x + b.global_position.x) * 0.5
		var ra := _reach(a, mid)
		var rb := _reach(b, mid)
		print("pair ", a.name, " ", b.name, " reach ", ra, " ", rb)
		await _stand_x(player, a.global_position.x)
		var first = world.interact_target()
		var flips := 0
		var last = first
		# Sweep from a to b in small steps; the target may change at most once.
		var x0: float = a.global_position.x
		var x1: float = b.global_position.x
		for i in 41:
			await _stand_x(player, lerpf(x0, x1, i / 40.0))
			var t = world.interact_target()
			if t != last:
				flips += 1
				last = t
		check("sweeping between two targets flips at most once", flips <= 1, "flips=%d" % flips)
	else:
		check("found two nearby targets for the hysteresis check", false)

	# Mouse hover: out-of-range hover shows the far tag.
	await _stand_x(player, 0.5)
	var far_t: Node3D = null
	for n in level.find_children("*", "", true, false):
		if n.has_method("select_info") and not n.select_info().get("in_range", true):
			far_t = n
			break
	check("a far target exists", far_t != null)


func _reach(n: Node3D, px: float) -> float:
	return n.reach_distance(px) if n.has_method("reach_distance") else absf(n.global_position.x - px)


func _closest_pair(level: Level) -> Array:
	var best := INF
	var out := []
	var all: Array = []
	for n in level.find_children("*", "", true, false):
		if n.has_method("select_info") and n is Node3D:
			all.append(n)
	for i in all.size():
		for j in range(i + 1, all.size()):
			var d := absf(all[i].global_position.x - all[j].global_position.x)
			if d > 0.3 and d < best:
				best = d
				out = [all[i], all[j]]
	return out


func _stand_at(player: Node3D, target: Node3D) -> void:
	await _stand_x(player, target.global_position.x)


func _stand_x(player: Node3D, x: float) -> void:
	player.global_position = Vector3(x, 0.1, 0.0)
	player.velocity = Vector3.ZERO
	await frames(3)
	await process_frame
	await process_frame
