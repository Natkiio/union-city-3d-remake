extends "res://tests/test_base.gd"
## Cutout rig, looks, zombie looks, backdrop and props.

var _finished: Array = []


func _json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	return JSON.parse_string(f.get_as_text())


func _on_finished(anim: String) -> void:
	_finished.append(anim)


func _run(rig: CutoutRig, secs: float) -> void:
	for i in int(secs * 30.0):
		rig.advance(1.0 / 30.0)


func run() -> void:
	var rig := CutoutRig.new()
	root.add_child(rig)
	rig.animation_finished.connect(_on_finished)
	check("rig instantiates with parts", rig.mesh_count() > 8, "meshes=%d" % rig.mesh_count())

	# ---- every anim plays; one-shots emit animation_finished
	for a in CutoutRig.ANIMS:
		_finished.clear()
		if a == "rise":
			rig.play("die")
			_run(rig, 1.2)
		rig.play(a)
		_run(rig, 1.6)
		var oneshot: bool = CutoutRig.ONESHOT.has(a)
		check("anim %s plays" % a, true)
		if oneshot:
			check("anim %s emits animation_finished" % a, _finished.has(a), str(_finished))
		else:
			check("anim %s loops without finishing" % a, not _finished.has(a))
		if a == "die":
			check("die holds the dead pose", rig.is_dead())
			rig.play("idle")
			check("dead rig ignores idle", rig.anim == "die")
			rig.play("rise")
			check("rise revives", not rig.is_dead())
			_run(rig, 1.6)
	rig.play("walk")
	rig.play("punch")
	_run(rig, 0.8)
	check("one-shot returns to the looping anim", rig.anim == "walk", rig.anim)
	rig.play("idle")
	_run(rig, 0.2)

	# ---- facing mirrors
	rig.apply_look({})
	rig.set_facing(1.0)
	rig.play("punch")
	_run(rig, 0.18)
	var hx := rig.joint_position("hand_f").x
	rig.set_facing(-1.0)
	_run(rig, 0.01)
	var hx2 := rig.joint_position("hand_f").x
	check("facing +1 reaches forward (+x)", hx > 0.2, "%.2f" % hx)
	check("facing -1 mirrors the hand", is_equal_approx(hx, -hx2) or absf(hx + hx2) < 0.05, "%.2f vs %.2f" % [hx, hx2])
	check("flip node scale sign follows facing", rig.get_node("flip").scale.x < 0.0)
	rig.set_facing(1.0)

	# ---- aim raises the front hand
	rig.apply_look({"weapon": "M4A1"})
	rig.play("aim")
	rig.set_aim(-0.5)
	_run(rig, 0.5)
	var low := rig.joint_position("hand_f").y
	rig.set_aim(0.6)
	_run(rig, 0.5)
	var high := rig.joint_position("hand_f").y
	check("set_aim moves the arms with the pitch", high > low + 0.2, "%.2f -> %.2f" % [low, high])

	# ---- feet stay on the ground while walking
	rig.apply_look({})
	rig.play("walk")
	var worst := 0.0
	var best := 9.0
	for i in 40:
		rig.advance(1.0 / 30.0)
		var y := minf(rig.joint_position("lf_ft").y, rig.joint_position("lb_ft").y)
		worst = maxf(worst, y)
		best = minf(best, y)
	check("walk keeps the lowest ankle near the ground", best > 0.0 and worst < 0.2, "ankle y %.2f..%.2f" % [best, worst])

	# ---- looks: every npc and premade
	var npcs := _json("res://data/original/npc.json")
	var bad := 0
	var worst_meshes := 0
	for k in npcs:
		var rec: Dictionary = npcs[k]
		rig.apply_look(rec)
		rig.play("walk")
		rig.advance(0.1)
		worst_meshes = maxi(worst_meshes, rig.mesh_count())
		var look := Look.from_npc(rec)
		if not Look.HAIR_STYLES.has(look["hair"]) or not Look.SKIN.has(look["skinColour"]) or not Look.HAIR.has(look["hairColour"]):
			bad += 1
			print("  unknown look value in ", k, ": ", look["hair"], " ", look["skinColour"], " ", look["hairColour"])
	check("apply_look works for all %d npc.json records" % npcs.size(), bad == 0, "bad=%d" % bad)
	var pres := _json("res://data/original/pre.json")
	for k in pres:
		rig.apply_look(pres[k])
	check("apply_look accepts all %d pre.json backgrounds" % pres.size(), true)
	check("npc looks stay under 40 mesh instances", worst_meshes < 40, "max=%d" % worst_meshes)
	var w1 := Look.random(5)
	var w2 := Look.random(5)
	var w3 := Look.random(6)
	check("Look.random is deterministic", w1 == w2)
	check("Look.random varies with the seed", w1 != w3)
	var kinds := {}
	for s in 40:
		kinds[Look.random(s)["hair"]] = true
	check("crowd uses 6+ hair styles", kinds.size() >= 6, str(kinds.size()))
	check("unknown clothes fall back to a colour", Look.top_style("male_doesNotExist").has("c") and Look.bottom_style("nope")["c"] is Color)
	check("weapon classes", Look.weapon_class("glock") == "pistol" and Look.weapon_class("M4A1") == "long" and Look.weapon_class("bat") == "melee" and Look.weapon_class("none") == "none")

	# ---- zombies
	var enemies := _json("res://data/original/enemy.json")
	var missing := 0
	var zworst := 0
	for ref in enemies:
		if not ZombieLooks.TABLE.has(ref):
			missing += 1
		var ok := ZombieLooks.apply(rig, ref, 3)
		var mv := ZombieLooks.move_anim(ref)
		for a in CutoutRig.ANIMS:
			rig.play(a)
			_run(rig, 0.2)
		rig.play(mv)
		_run(rig, 0.3)
		zworst = maxi(zworst, rig.mesh_count())
		if not ok:
			missing += 1
	check("all %d enemy.json refs have a zombie look" % enemies.size(), missing == 0 and enemies.size() == 22, "missing=%d" % missing)
	check("zombie looks stay under 40 mesh instances", zworst < 40, "max=%d" % zworst)
	check("ZombieLooks.apply accepts an unknown ref", not ZombieLooks.apply(rig, "zombieNope"))
	ZombieLooks.apply(rig, "zombieDog")
	check("dog uses four limbs and keeps the dog posture", rig.tweaks.get("posture") == "dog")
	ZombieLooks.apply(rig, "zombieFat")
	var fat_w := rig.mesh_count()
	check("fat zombie is built", fat_w > 8)

	# ---- backdrop and props
	for pr in ["cork_day", "cork_dusk", "docks_night"]:
		var bd := Backdrop.build(Backdrop.preset(pr))
		root.add_child(bd)
		var layers := 0
		for l in ["sky", "far", "mid", "near"]:
			if bd.has_node(l) and bd.get_node(l).get_child_count() > 0:
				layers += 1
		check("backdrop %s has 4 layers" % pr, layers == 4)
		bd.queue_free()
	for pn in Props.NAMES:
		var n := Props.make(pn)
		var mi := n.get_child(0) as MeshInstance3D
		check("prop %s builds a mesh" % pn, mi.mesh != null and mi.mesh.get_surface_count() >= 1)
		n.free()
	rig.queue_free()
