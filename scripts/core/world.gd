extends Node
## Autoload "World". Where the player is (section, street, building, floor,
## room), moving between rooms and sections, and building the current level
## into the run scene. Spec: docs/ORIGINAL_ANALYSIS.md sections 5, 9, 12;
## notes in docs/world.md. Owner: world workstream.
##
## API (docs/PORT_PLAN.md, Wave 2 contracts):
##   start_new_game()                 fresh run at the Cork start (section 16)
##   enter_location(section_id)       a section's start room (end=true: its endLoc)
##   enter_room(room_id, spawn_at)    any room; spawn_at = "" | marker | "left" | "right" | "x:<px>"
##   travel_to(section_id) -> bool    map travel: unlock check, time cost, enter
##   use_link(link)                   what a door/stair/exit trigger does
##   current: Dictionary              section, street, building, floor, room,
##                                    danger, width_px, outdoors, safehouse,
##                                    room_id, name
##   map_nodes() -> Array             data for the map screen
##
## The level itself is built by LevelBuilder into the run scene
## (scenes/main.tscn), which registers itself with attach_run_scene(). Without
## a run scene (menus, headless sim tests) World still tracks the location.
## Stateful systems join group "stateful" and implement reset(), to_dict(),
## from_dict(d); see docs/PORT_PLAN.md.

## The ui map screen listens to this; the area exits ("EXIT TO MAP") emit it.
signal map_requested()
## A safehouse bed was used; the ui sleep/wait dialog listens.
signal bed_used()
## The player walked into a story trigger zone (trig<N> marker of the art).
signal trigger_entered(trigger_id: String)
## After every level build, with `current`.
signal room_entered(info: Dictionary)
## A locked door or entrance refused to open (message for the HUD).
signal door_refused(door_id: String, reason: String)

const RUN_SCENE := "res://scenes/main.tscn"
const START_SECTION := "16"
const FADE_OUT_SECONDS := 0.18
const FADE_IN_SECONDS := 0.3

var current: Dictionary = {}
## Locks changed from their data default, door_id -> locked.
var door_locks: Dictionary = {}
## room_id -> game minute of the last visit (the Director keeps its own copy
## for repopulation; this one is for the map and saves).
var visited: Dictionary = {}
## Room transitions fade through black. Tests turn it off.
var fade_enabled: bool = true

var room_id: String = ""
var _spawn_at: String = ""
var _saved_player_x: float = -1.0
var _run: Node = null
var _level: Level = null
var _builder: LevelBuilder = null
var _busy: bool = false
var _fade_layer: CanvasLayer = null
var _fade_rect: ColorRect = null


func _ready() -> void:
	add_to_group("stateful")
	process_mode = Node.PROCESS_MODE_ALWAYS


# --- stateful ---------------------------------------------------------------

func reset() -> void:
	current = {}
	room_id = ""
	door_locks.clear()
	visited.clear()
	_spawn_at = ""
	_saved_player_x = -1.0
	_busy = false
	if _fade_rect != null:
		_fade_rect.modulate.a = 0.0


func to_dict() -> Dictionary:
	return {
		"room_id": room_id,
		"player_x_px": player_x_px(),
		"door_locks": door_locks.duplicate(),
		"visited": visited.duplicate(),
	}


## Restores the exact room and player x. Rebuilds at once when the run scene
## is up; otherwise the next run scene builds it (or call resume()).
func from_dict(d: Dictionary) -> void:
	door_locks = d.get("door_locks", {}).duplicate()
	visited = d.get("visited", {}).duplicate()
	var rid: String = str(d.get("room_id", ""))
	if not WorldData.has_room(rid):
		reset()
		return
	var x: float = float(d.get("player_x_px", -1.0))
	enter_room(rid, "x:%f" % x if x >= 0.0 else "")


## Opens the run scene if it is not already showing (after a load from a menu).
func resume() -> void:
	if _run == null and room_id != "":
		get_tree().change_scene_to_file(RUN_SCENE)


# --- run scene --------------------------------------------------------------

## Called by the run scene (scripts/world/run_scene.gd) when it enters the
## tree. Builds the current room, or starts a new game if there is none.
func attach_run_scene(run: Node) -> void:
	_run = run
	if room_id == "":
		_set_location(WorldData.start_room(START_SECTION), "")
	_build()


func detach_run_scene(run: Node) -> void:
	if _run != run:
		return
	_saved_player_x = player_x_px()
	_run = null
	_level = null
	Director.attach(null, null)


func has_run_scene() -> bool:
	return _run != null and is_instance_valid(_run)


func level() -> Level:
	return _level


func player() -> Node3D:
	if has_run_scene() and _run.has_method("get_player"):
		return _run.get_player()
	return null


## Player x in Flash px within the current room, or -1 with no player.
func player_x_px() -> float:
	var p := player()
	if p == null or not p.is_inside_tree():
		return _saved_player_x
	return p.global_position.x * WorldData.PX_PER_UNIT


# --- the contract -----------------------------------------------------------

func start_new_game() -> void:
	reset()
	_set_location(WorldData.start_room(START_SECTION), "")
	if has_run_scene():
		_build()
	elif is_inside_tree():
		get_tree().change_scene_to_file.call_deferred(RUN_SCENE)


## Enters a section at its start (or, with at_end, its endLoc when it has one).
func enter_location(section_id: String, at_end: bool = false) -> bool:
	var sec := WorldData.norm_section(section_id)
	var target := WorldData.end_room(sec) if at_end else ""
	if target == "":
		target = WorldData.start_room(sec)
	if target == "":
		push_warning("World: section %s has no rooms" % sec)
		return false
	# goto(..., "start") lands at the left edge, "end" at the right.
	return enter_room(target, "right" if at_end else "left")


## Moves to any room. spawn_at: "" (left edge), a marker name in the target
## room ("exit1", "sup"...), "left"/"right" (edge buffer) or "x:<px>".
func enter_room(room_path: String, spawn_at: String = "") -> bool:
	if not WorldData.has_room(room_path):
		push_warning("World: unknown room %s" % room_path)
		return false
	_set_location(room_path, spawn_at)
	if has_run_scene():
		_build()
	else:
		_announce()
	return true


## Map travel (sec. 12): only to an unlocked section that is on the map; costs
## round(manhattan map distance / 200) hours, which Clock turns into hunger
## and sleep. Returns false when the trip is not allowed.
func travel_to(section_id: String) -> bool:
	var sec := WorldData.norm_section(section_id)
	if not WorldData.is_travelable(sec) or not is_section_unlocked(sec):
		return false
	var from: String = str(current.get("section", START_SECTION))
	var hours := WorldData.travel_hours(from, sec)
	if hours > 0:
		Clock.advance(hours * 60)
	return enter_location(sec)


func travel_hours_to(section_id: String) -> int:
	return WorldData.travel_hours(str(current.get("section", START_SECTION)), section_id)


func is_section_unlocked(section_id: String) -> bool:
	var q := get_node_or_null("/root/Quests")
	if q != null and q.has_method("is_section_unlocked"):
		return bool(q.is_section_unlocked(WorldData.norm_section(section_id)))
	return true


## One entry per section 1..16 for the map screen.
func map_nodes() -> Array:
	var out: Array = []
	for i in range(1, WorldData.SECTION_COUNT + 1):
		var sec := str(i)
		out.append({
			"id": sec,
			"name": WorldData.section_name(sec),
			"pos": WorldData.map_pos(sec),
			"danger": int(WorldData.section(sec).get("danger", 0)),
			"unlocked": is_section_unlocked(sec),
			"travelable": WorldData.is_travelable(sec),
			"connections": WorldData.connections(sec),
			"desc": str(Data.entry("sections", sec).get("desc", "")),
			"current": sec == str(current.get("section", "")),
		})
	return out


func is_safehouse() -> bool:
	return bool(current.get("safehouse", false))


# --- doors ------------------------------------------------------------------

func is_door_locked(link: Dictionary) -> bool:
	if not link.get("locked", false):
		return false
	return bool(door_locks.get(link.get("door_id", ""), true))


func unlock_door(door_id: String) -> void:
	door_locks[door_id] = false
	_refresh_prompts()


func lock_door(door_id: String) -> void:
	door_locks[door_id] = true
	_refresh_prompts()


## What a WorldLink does when the player interacts with it.
func use_link(link: Dictionary) -> void:
	if _busy:
		return
	var kind: String = link.get("kind", "")
	if kind == "bed":
		bed_used.emit()
		return
	if is_door_locked(link) and not _try_unlock(link):
		return
	var target: String = link.get("target", "")
	if target == "":
		door_refused.emit(link.get("door_id", ""), "blocked")
		_sfx("dry_click")
		return
	if target == "map":
		_open_map()
		return
	var spawn: Dictionary = link.get("spawn", {})
	var spawn_at := ""
	if spawn.has("edge"):
		spawn_at = spawn.edge
	elif spawn.has("marker") and not WorldData.marker(target, spawn.marker).is_empty():
		spawn_at = spawn.marker
	elif spawn.has("x"):
		spawn_at = "x:%f" % float(spawn.x)
	else:
		spawn_at = "x:%f" % (WorldData.width_px(target) * 0.5)
	_sfx("door")
	_transition(func(): enter_room(target, spawn_at))


## Keys first (a questItem whose `door` is this door, consumed), then the
## loot workstream's Locks.try_open(def) if it exists, else: doors that need
## a key stay shut, others open (no lockpicking yet).
func _try_unlock(link: Dictionary) -> bool:
	var door_id: String = link.get("door_id", "")
	var key := _held_key_for(door_id)
	if key != "":
		Inventory.remove_item(key)
		unlock_door(door_id)
		return true
	var def := {"id": "door:" + door_id, "door_id": door_id, "name": link.get("name", ""),
			"room_id": room_id, "locked": true,
			"needs_key": link.get("needs_key", false), "lock_diff": link.get("lock_diff", "normal")}
	var locks: Variant = _locks()
	if locks != null:
		# Result: 0 opened, 1 minigame started (the callback unlocks later), 2 denied.
		var on_done := func(ok: bool) -> void:
			if ok:
				unlock_door(door_id)
			else:
				door_refused.emit(door_id, "needs key" if def.needs_key else "locked")
				_sfx("dry_click")
		var result: int = locks.call("try_open", def, self, on_done)
		return result == 0
	if link.get("needs_key", false):
		door_refused.emit(door_id, "needs key")
		_sfx("dry_click")
		return false
	unlock_door(door_id)
	return true


## Inventory name of a held key item for this door, or "".
func _held_key_for(door_id: String) -> String:
	for ref in Data.table("questItem"):
		var rec: Dictionary = Data.entry("questItem", ref)
		if str(rec.get("door", "")) != door_id:
			continue
		for n in [ref, str(rec.get("name", ""))]:
			if n != "" and Inventory.has_item(n):
				return n
	return ""


## The loot workstream's lock handler: an autoload "Locks" or a global class
## "Locks" with try_open(def). Null until it lands.
func _locks() -> Variant:
	var node := get_node_or_null("/root/Locks")
	if node != null and node.has_method("try_open"):
		return node
	for c in ProjectSettings.get_global_class_list():
		if c.get("class", "") == "Locks":
			var script: Script = load(c.path)
			for m in script.get_script_method_list():
				if m.name == "try_open":
					return script
	return null


func _open_map() -> void:
	if not map_requested.get_connections().is_empty():
		map_requested.emit()
		return
	# No map screen yet (ui workstream): go to the first open neighbour.
	for sec in WorldData.connections(current.get("section", START_SECTION)):
		if WorldData.is_travelable(sec) and is_section_unlocked(sec):
			print("[World] no map screen; travelling to section %s" % sec)
			_transition(func(): travel_to(sec))
			return


# --- building -----------------------------------------------------------------

func _set_location(rid: String, spawn_at: String) -> void:
	room_id = rid
	_spawn_at = spawn_at
	var p := WorldData.parse(rid)
	current = {
		"room_id": rid,
		"section": p.section, "street": p.street, "building": p.building,
		"floor": p.floor, "room": p.room,
		"danger": WorldData.danger(rid),
		"width_px": WorldData.width_px(rid),
		"outdoors": WorldData.is_outdoors(rid),
		"safehouse": WorldData.is_safehouse(rid),
		"name": WorldData.place_name(rid),
		"section_name": WorldData.section_name(p.section),
		"light_reduction": WorldData.light_reduction(rid),
	}


## Spawn x in px for the pending spawn spec.
func _spawn_x_px() -> float:
	var s := _spawn_at
	if s.begins_with("x:"):
		return WorldData.spawn_x_px(room_id, {"x": float(s.substr(2))})
	if s == "left" or s == "right" or s == "":
		return WorldData.spawn_x_px(room_id, {"edge": "left" if s != "right" else "right"})
	return WorldData.spawn_x_px(room_id, {"marker": s})


func _build() -> void:
	if _builder == null:
		_builder = LevelBuilder.new()
	var root: Node3D = _run.get_level_root()
	Director.remember_area()
	if _level != null and is_instance_valid(_level):
		_level.get_parent().remove_child(_level)
		_level.queue_free()
	for old in root.get_children():
		root.remove_child(old)
		old.queue_free()
	_level = _builder.build(room_id)
	root.add_child(_level)
	for t in _level.find_children("Trigger_*", "Area3D", true, false):
		t.body_entered.connect(_on_trigger_body.bind(str(t.get_meta("trigger_id", ""))))
	var x := WorldData.PX_PER_UNIT
	var p := player()
	var spawn_x := _spawn_x_px() / x
	if p != null:
		p.global_position = Vector3(spawn_x, 0.95, 0.0)
		if "velocity" in p:
			p.velocity = Vector3.ZERO
	_saved_player_x = spawn_x * x
	if _run.has_method("on_level_built"):
		_run.on_level_built(_level, current)
	if p != null:
		Director.attach(_level.spawn_root(), p)
		Director.set_bounds(0.0, _level.width_units())
	_announce()


## Director budget, room visit time and the signals, for every area change.
func _announce() -> void:
	Director.begin_area(int(current.danger), float(current.width_px), bool(current.outdoors),
			bool(current.safehouse), room_id)
	visited[room_id] = Director.now()
	Events.location_entered.emit(room_id)
	room_entered.emit(current)


func _on_trigger_body(body: Node3D, trigger_id: String) -> void:
	if body.is_in_group("player"):
		trigger_entered.emit(trigger_id)


# --- interaction and transitions ------------------------------------------------

func _process(_delta: float) -> void:
	if not has_run_scene() or _busy or get_tree().paused:
		return
	if Input.is_action_just_pressed("interact"):
		var link := nearest_link_in_range()
		var px: float = player().global_position.x
		var link_d: float = absf(link.global_position.x - px) if link != null else INF
		# Containers and NPCs handle the key themselves; when one is at least as
		# close as the door trigger overlapping it, the key is theirs.
		for node in get_tree().get_nodes_in_group("world_interactable"):
			if node.has_method("wants_interact") and node.wants_interact() \
					and absf(node.global_position.x - px) <= link_d:
				return
		if link != null:
			use_link(link.link)


## The in-range WorldLink nearest the player, or null.
func nearest_link_in_range() -> WorldLink:
	var p := player()
	if p == null or _level == null:
		return null
	var best: WorldLink = null
	var best_d := INF
	for l in _level.links():
		if not l.in_range():
			continue
		var d := absf(l.global_position.x - p.global_position.x)
		if d < best_d:
			best_d = d
			best = l
	return best


func _refresh_prompts() -> void:
	if _level == null or not is_instance_valid(_level):
		return
	for l in _level.links():
		if l.link.get("door_id", "") != "":
			l.link["locked"] = l.link.get("locked", false) and is_door_locked(l.link)
		l.refresh_prompt()


func _transition(action: Callable) -> void:
	if not fade_enabled or not has_run_scene():
		action.call()
		return
	_busy = true
	_ensure_fade()
	var t := create_tween()
	t.tween_property(_fade_rect, "modulate:a", 1.0, FADE_OUT_SECONDS)
	t.tween_callback(action)
	t.tween_property(_fade_rect, "modulate:a", 0.0, FADE_IN_SECONDS)
	t.tween_callback(func(): _busy = false)


func _ensure_fade() -> void:
	if _fade_layer != null:
		return
	_fade_layer = CanvasLayer.new()
	_fade_layer.layer = 90
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color.BLACK
	_fade_rect.modulate.a = 0.0
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_layer.add_child(_fade_rect)
	add_child(_fade_layer)


func _sfx(event_name: String) -> void:
	var s := get_node_or_null("/root/Sfx")
	if s != null and s.has_method("play"):
		s.play(event_name)
