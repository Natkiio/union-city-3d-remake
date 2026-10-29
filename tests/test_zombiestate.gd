extends "res://tests/test_base.gd"
## Zombie memory across room changes (issue #25).

var d: Node
var player: Node3D
var level: Node3D


func enter(id: String, outdoors: bool = false) -> int:
	if level != null:
		level.queue_free()
	level = Node3D.new()
	root.add_child(level)
	d.remember_area()
	d.attach(level, player)
	d.set_bounds(-50.0, 50.0)
	var n: int = d.begin_area(10, 3000.0, outdoors, false, id)
	await frames(2)
	return n


func zs() -> Array:
	return d.zombies.filter(func(z): return is_instance_valid(z) and not z.is_dead())


func run() -> void:
	d = autoload("Director")
	d.reset()
	d.enabled = true # begin_area restores only for an enabled Director
	d.rng.seed = 3
	autoload("Stats").level = 1
	player = Node3D.new()
	root.add_child(player)
	player.add_to_group("player")

	# First visit rolls spawns by the entry rule; top up to 3, wound one, kill one.
	await enter("room_a")
	while zs().size() < 3:
		if d.spawn_zombie("zombieSlow", true) == null:
			break
	var list := zs()
	check("at least three zombies", list.size() >= 3, str(list.size()))
	var victim: Zombie = list[0]
	var hurt: Zombie = list[1]
	hurt.health = 5.0
	var before := list.size()
	var victim_kind: String = victim.enemy_ref
	victim.take_damage(9999.0, "head")
	await frames(2)
	check("kill recorded as dead kind", d.zombie_state.rooms["room_a"]["dead"] == [victim_kind])

	# Leave and come back soon: same population, no new rolls.
	await enter("room_b")
	check("leaving captured the living", d.zombie_state.living("room_a").size() == before - 1)
	var saved_xs: Array = d.zombie_state.living("room_a").map(func(r): return float(r["x"]))
	d.advance_minutes(10.0)
	var n := await enter("room_a")
	var back := zs()
	check("revisit restores survivors only", n == before - 1 and back.size() == before - 1, "n=%d size=%d" % [n, back.size()])
	var hs := back.map(func(z): return z.health)
	check("wounded zombie keeps its health", 5.0 in hs, str(hs))
	var near := 0
	for z in back:
		for sx in saved_xs:
			if absf(z.global_position.x - sx) < 0.5:
				near += 1
				break
	check("zombies return at their saved x", near == back.size() and saved_xs.size() == back.size(), str(saved_xs))
	var thr := 0.0
	for z in back:
		thr += z.type.threat
	check("restored zombies count toward threat", d.current_threat() == thr and thr > 0.0, str(d.current_threat()))
	var live_now := back.size()

	# Save/load roundtrip.
	var snap: Dictionary = d.to_dict()
	var json: Dictionary = JSON.parse_string(JSON.stringify(snap))
	d.reset()
	check("reset clears zombie memory", d.zombie_state.rooms.is_empty())
	d.from_dict(json)
	check("roundtrip keeps room_a living", d.zombie_state.living("room_a").size() == live_now)
	await enter("room_b")
	n = await enter("room_a")
	check("loaded save restores same population", n == live_now and zs().size() == live_now, "n=%d" % n)

	# Kill everything, leave, return within repop: stays dead.
	for z in zs():
		z.take_damage(9999.0, "head")
	await frames(2)
	await enter("room_b")
	n = await enter("room_a")
	check("cleared room stays empty", n == 0 and zs().size() == 0)

	# After repopTime (90 min indoors) it repopulates by the entry rule.
	await enter("room_b")
	d.advance_minutes(DirectorRules.repop_time(false) + 5.0)
	d.rng.seed = 4
	var repop := 0
	for attempt in 8:
		await enter("room_b")
		d.advance_minutes(DirectorRules.repop_time(false) + 5.0)
		repop = await enter("room_a")
		if repop > 0:
			break
	check("room repopulates after repopTime", repop > 0, str(repop))
	check("repop forgot the old dead list", not d.zombie_state.rooms.has("room_a") or d.zombie_state.rooms["room_a"]["dead"].is_empty())
	d.reset()
