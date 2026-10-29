extends "res://tests/test_base.gd"
## Audio checks: procedural sounds build and are non-silent, play() runs
## headless (dummy driver), the pool reuses players, bus volume works, Events
## hooks route to the right sound, ambient loops are seamless.

func peak(stream: AudioStreamWAV) -> float:
	var data := stream.data
	var m := 0.0
	for i in range(0, data.size(), 2):
		m = maxf(m, absf(data.decode_s16(i) / 32767.0))
	return m


func run() -> void:
	var sfx = autoload("Sfx")
	var events = autoload("Events")

	# Every named sound builds, has length and is not silent.
	var all_built := true
	var all_loud := true
	var all_length := true
	var built := 0
	for name in SfxSynth.SOUND_NAMES:
		var variants := SfxSynth.GROAN_VARIANTS if name == "zombie_groan" else 1
		for v in variants:
			var stream: AudioStreamWAV = sfx.build(name, v)
			if stream == null:
				all_built = false
				print("missing %s variant %d" % [name, v])
				continue
			built += 1
			var frames := stream.data.size() / 2
			if frames < SfxSynth.MIX_RATE / 100:
				all_length = false
			if peak(stream) < 0.1:
				all_loud = false
				print("silent %s variant %d" % [name, v])
	check("every named sound builds", all_built, "n=%d" % built)
	check("every sound has non-zero length", all_length)
	check("every sound has non-silent samples", all_loud)
	check("zombie_groan has 3 variants", SfxSynth.GROAN_VARIANTS == 3)
	check("cache returns the same stream", sfx.build("pistol_shot") == sfx.build("pistol_shot"))
	check("unknown sound builds to null", sfx.build("nope") == null)
	check("play of unknown sound returns false", sfx.play("nope") == false)
	check("play sets last_played", sfx.play("ui_click") and sfx.last_played == "ui_click")

	# play() headless, with and without a position.
	var ok := true
	for name in SfxSynth.SOUND_NAMES:
		ok = sfx.play(name) and ok
		ok = sfx.play(name, Vector3(3, 1, 0)) and ok
	check("play() works for every sound, 2D and 3D", ok)
	await frames(3)
	sfx.stop_all()

	# Pool reuses players instead of growing.
	var before: int = sfx.pool_stats()["size"]
	for i in 60:
		sfx.play("pistol_shot")
		sfx.play("rifle_shot", Vector3(1, 0, 0))
	var after: int = sfx.pool_stats()["size"]
	check("pool size is fixed under load", before == after and before == sfx.POOL_SIZE * 2,
		"before=%d after=%d" % [before, after])
	check("pool playing count stays within pool", sfx.pool_stats()["playing"] <= after)
	sfx.stop_all()
	check("stop_all silences the pool", sfx.pool_stats()["playing"] == 0)

	# Bus volumes.
	check("buses exist", AudioServer.get_bus_index("Sfx") != -1
		and AudioServer.get_bus_index("Music") != -1
		and AudioServer.get_bus_index("Ambient") != -1
		and AudioServer.get_bus_index("Master") != -1)
	check("set_volume returns true for a known bus", sfx.set_volume("Sfx", 0.5))
	check("bus volume 0.5 reads back", absf(sfx.get_volume("Sfx") - 0.5) < 0.01,
		"got=%f" % sfx.get_volume("Sfx"))
	sfx.set_volume("Sfx", 0.0)
	check("bus volume 0 is silent", sfx.get_volume("Sfx") < 0.001)
	check("set_volume on unknown bus is false", sfx.set_volume("Nope", 1.0) == false)
	sfx.set_volume("Sfx", 1.0)

	# Events hooks.
	check("shot_fired is hooked", events.is_connected("shot_fired", sfx._on_shot_fired))
	events.shot_fired.emit("Shotgun Pump", 1.0, Vector3.ZERO)
	check("shot_fired shotgun -> shotgun_shot", sfx.last_played == "shotgun_shot", sfx.last_played)
	events.shot_fired.emit("smg_venom", 1.0, Vector3.ZERO)
	check("shot_fired smg -> smg_shot", sfx.last_played == "smg_shot", sfx.last_played)
	events.shot_fired.emit("pistols_glock", 1.0, Vector3(2, 0, 0))
	check("shot_fired pistol -> pistol_shot", sfx.last_played == "pistol_shot", sfx.last_played)
	check("gunshot_for rifle keyword", sfx.gunshot_for("longGuns_m16") == "rifle_shot")
	events.player_damaged.emit(4.0, null)
	check("player_damaged -> player_hurt", sfx.last_played == "player_hurt", sfx.last_played)
	events.player_died.emit()
	check("player_died -> player_death", sfx.last_played == "player_death", sfx.last_played)
	events.enemy_killed.emit("zombieSlow", 1, 10)
	check("enemy_killed -> zombie_death", sfx.last_played == "zombie_death", sfx.last_played)
	events.level_up.emit(2)
	check("level_up -> level_up", sfx.last_played == "level_up", sfx.last_played)
	events.item_used.emit("Bandages")
	check("item_used -> pickup", sfx.last_played == "pickup", sfx.last_played)
	events.container_searched.emit("cont1")
	check("container_searched -> pickup", sfx.last_played == "pickup", sfx.last_played)
	sfx.stop_all()

	# Ambient loops.
	check("start_ambient street", sfx.start_ambient("street", -10.0))
	check("ambient is playing", sfx.is_ambient_playing() and sfx.ambient_kind() == "street")
	check("start_ambient unknown kind is false", sfx.start_ambient("bogus") == false)
	sfx.start_ambient("night")
	check("ambient switches kind", sfx.ambient_kind() == "night")
	sfx.stop_ambient()
	check("stop_ambient stops", not sfx.is_ambient_playing())
	var all_seamless := true
	var all_ambient_loud := true
	for kind in SfxSynth.AMBIENT_KINDS:
		var s := SfxSynth.render_ambient(kind)
		var n := s.size()
		var max_step := 0.0
		var amp := 0.0
		for i in n - 1:
			max_step = maxf(max_step, absf(s[i + 1] - s[i]))
			amp = maxf(amp, absf(s[i]))
		var wrap_step := absf(s[0] - s[n - 1])
		if wrap_step > max_step * 1.01 + 1e-6:
			all_seamless = false
			print("loop click in %s: wrap=%f max=%f" % [kind, wrap_step, max_step])
		if amp < 0.1:
			all_ambient_loud = false
	check("ambient loops have no click at the loop point", all_seamless)
	check("ambient beds are audible", all_ambient_loud)

	# Stateful convention: volumes survive to_dict/from_dict, reset silences.
	sfx.set_volume("Ambient", 0.25)
	var snap: Dictionary = sfx.to_dict()
	sfx.set_volume("Ambient", 1.0)
	sfx.from_dict(snap)
	check("to_dict/from_dict restores bus volume", absf(sfx.get_volume("Ambient") - 0.25) < 0.01)
	sfx.play("pistol_shot")
	sfx.reset()
	check("reset stops every sound", sfx.pool_stats()["playing"] == 0 and not sfx.is_ambient_playing())
	check("Sfx is not in the stateful group (volumes are settings)", not sfx.is_in_group("stateful"))
