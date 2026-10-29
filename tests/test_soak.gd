extends "res://tests/test_base.gd"
## Soak: enters every room of all 16 sections in turn (World.enter_room, the
## Director on), steps 60 physics frames in each and checks that no script
## error is logged, the player stays inside the room and on the Z=0 lane, and
## (over 100 more room changes) that the node count does not keep growing.
## Physics ticks 8x as often as normal (each tick a shorter step) so the
## whole map fits in the suite; the player cannot die (is_dead blocks damage).

const FRAMES_PER_ROOM := 60
const LEAK_CHANGES := 100
## Allowed node-count growth across the leak loop (toasts, pooled sounds).
const LEAK_SLACK := 40
const SPEEDUP := 8.0


class ErrorCounter extends Logger:
	var errors: Array = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array) -> void:
		# Script errors and engine errors; warnings are not failures here.
		if error_type != ERROR_TYPE_WARNING:
			errors.append("%s:%d %s %s %s" % [file, line, function, code, rationale])

	func _log_message(_message: String, _error: bool) -> void:
		pass


var counter := ErrorCounter.new()


func run() -> void:
	OS.add_logger(counter)
	push_error("soak: logger self-test")
	check("the error counter sees logged errors", counter.errors.size() == 1)
	counter.errors.clear()
	var world := autoload("World")
	world.fade_enabled = false
	autoload("Quests").auto_play_cutscenes = false
	autoload("Director").enabled = true
	Engine.max_physics_steps_per_frame = int(SPEEDUP)
	Engine.physics_ticks_per_second = int(60 * SPEEDUP)
	var scn = await load_scene("res://scenes/main.tscn")
	await frames(3)
	var player: Node3D = scn.get_player()
	player.is_dead = true # god mode: zombies bite, nothing dies

	var rooms := 0
	var outside: Array = []
	var off_lane: Array = []
	var errors_before := counter.errors.size()
	for i in range(1, WorldData.SECTION_COUNT + 1):
		for rid in WorldData.rooms_of(str(i)):
			if not world.enter_room(rid):
				continue
			await frames(FRAMES_PER_ROOM)
			_close_screens()
			rooms += 1
			var w: float = world.level().width_units()
			var x: float = player.global_position.x
			if x < -0.05 or x > w + 0.05 or player.global_position.y < -0.5:
				outside.append("%s x=%.2f y=%.2f w=%.2f" % [rid, x, player.global_position.y, w])
			if absf(player.global_position.z) > 0.01:
				off_lane.append("%s z=%.3f" % [rid, player.global_position.z])
	print("soak: %d rooms entered" % rooms)
	check("entered every room of the 16 sections", rooms >= 280, str(rooms))
	check("no script errors while visiting every room", counter.errors.size() == errors_before,
			"\n".join(counter.errors.slice(errors_before, errors_before + 8)))
	check("the player stays inside every room", outside.is_empty(), ", ".join(outside.slice(0, 8)))
	check("the player stays on the lane", off_lane.is_empty(), ", ".join(off_lane.slice(0, 8)))

	# Leak check: the same handful of rooms over and over.
	var cycle := ["l16_s3_b0_f0_r1", "l16_s3_b1_f1_r1", "l16_s3_b2_f1_r2", "l12_s2_b1_f1_r2", "l11_s4_b3_f1_r1"]
	for k in cycle.size() * 2:
		world.enter_room(cycle[k % cycle.size()])
		await frames(4)
	world.enter_room(cycle[0]) # measure in the same room both times
	await frames(10)
	var base := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	for k in LEAK_CHANGES:
		world.enter_room(cycle[k % cycle.size()])
		await frames(4)
		_close_screens()
	world.enter_room(cycle[0])
	await frames(10)
	var after := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	print("soak: nodes %d -> %d over %d room changes" % [base, after, LEAK_CHANGES])
	check("node count does not grow over %d room changes" % LEAK_CHANGES, after - base <= LEAK_SLACK,
			"%d -> %d" % [base, after])
	check("no script errors in the leak loop", counter.errors.size() == errors_before,
			"\n".join(counter.errors.slice(errors_before, errors_before + 8)))
	Engine.physics_ticks_per_second = 60
	Engine.max_physics_steps_per_frame = 8
	OS.remove_logger(counter)


## Trigger zones can open captions, help or a level-up screen; nobody is
## there to close them.
func _close_screens() -> void:
	var ctl: UIController = get_first_node_in_group("ui_controller")
	if ctl != null:
		ctl.close_all()
	for n in get_nodes_in_group("run_overlay"):
		n.queue_free()
	paused = false
