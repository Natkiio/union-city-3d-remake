extends Node
## Autoload "SaveGame". Saves and loads the to_dict() of every node in group
## "stateful" (keyed by node name) plus registered providers, in slot files
## under user://saves/. Slot 0 is the autosave, 1..3 are manual slots.
## Format, providers and how to add a system: docs/persistence.md.
## Owner: persistence workstream.

signal saved(slot: int)
signal loaded(slot: int)
signal load_failed(slot: int, reason: String)

const AUTOSAVE_SLOT := 0
const MANUAL_SLOTS := 3
## Systems applied first, in this order. Anything stateful not listed is
## applied afterwards (alphabetical); World goes last so the room is rebuilt
## after the state it reads exists. Providers are applied after all systems.
const LOAD_ORDER: Array[String] = [
	"Stats", "Clock", "Survival", "Inventory", "LootState", "Quests", "Director", "World",
]
## Minimum real seconds between event-driven autosaves.
const AUTOSAVE_MIN_INTERVAL := 5.0

var save_dir: String = "user://saves"
var playtime := Playtime.new()
## Replaceable in tests to simulate a failing rename.
var fs_rename: Callable = func(from: String, to: String) -> int: return DirAccess.rename_absolute(from, to)
var autosave_enabled: bool = true

var _providers: Dictionary = {}  # name -> {"to": Callable, "from": Callable}
var _loading: bool = false
var _dead: bool = false
var _last_autosave_msec: int = -1000000
var _last_error: String = ""


func _ready() -> void:
	add_to_group("stateful")
	Events.location_entered.connect(_on_location_entered)
	Events.level_up.connect(_on_level_up)
	Events.player_died.connect(func(): _dead = true)
	Events.run_reset.connect(func(): _dead = false)
	Events.run_started.connect(func(): _dead = false)
	if "sleep_finished" in Survival or Survival.has_signal("sleep_finished"):
		Survival.connect("sleep_finished", notify_rest_finished)


func _process(delta: float) -> void:
	if not get_tree().paused and not _dead:
		playtime.tick(delta)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("quick_save"):
		quick_save()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("quick_load"):
		quick_load()
		get_viewport().set_input_as_handled()


# --- stateful (SaveGame only owns the playtime counter) ----------------------

func reset() -> void:
	playtime.reset()


## SaveGame is excluded from the systems it saves (the header carries the
## playtime), so these exist only to satisfy the stateful convention.
func to_dict() -> Dictionary:
	return {}


func from_dict(_d: Dictionary) -> void:
	pass


# --- providers ---------------------------------------------------------------

## Lets non-autoload state (the player node, the current room) take part.
## to_dict_fn() -> Dictionary (JSON-safe: no Vector3, use arrays);
## from_dict_fn(d: Dictionary). Call again with the same name to replace;
## unregister_provider() when the owner leaves the tree.
func register_provider(provider_name: String, to_dict_fn: Callable, from_dict_fn: Callable) -> void:
	_providers[provider_name] = {"to": to_dict_fn, "from": from_dict_fn}


func unregister_provider(provider_name: String) -> void:
	_providers.erase(provider_name)


func has_provider(provider_name: String) -> bool:
	return _providers.has(provider_name)


# --- paths and slot queries --------------------------------------------------

func slot_path(n: int) -> String:
	return "%s/slot_%d.json" % [save_dir, n]


static func valid_slot(n: int) -> bool:
	return n >= 0 and n <= MANUAL_SLOTS


func has_slot(n: int) -> bool:
	return valid_slot(n) and FileAccess.file_exists(slot_path(n))


## Header of a slot: name, level, location, clock_text, playtime_seconds,
## saved_unix. {} if the slot is empty, {"corrupt": true} if unreadable.
func slot_info(n: int) -> Dictionary:
	if not has_slot(n):
		return {}
	var parsed := SaveFormat.parse(_read_text(slot_path(n)))
	if not parsed["ok"]:
		return {"corrupt": true, "error": parsed["error"]}
	var h: Dictionary = parsed["data"].get("header", {})
	return {
		"name": str(h.get("name", "")), "level": int(h.get("level", 1)),
		"location": str(h.get("location", "")), "clock_text": str(h.get("clock_text", "")),
		"playtime_seconds": float(h.get("playtime_seconds", 0.0)),
		"saved_unix": int(h.get("saved_unix", 0)),
	}


func delete_slot(n: int) -> bool:
	if not has_slot(n):
		return false
	return DirAccess.remove_absolute(slot_path(n)) == OK


func last_error() -> String:
	return _last_error


# --- save --------------------------------------------------------------------

## Snapshot of the whole game (the dictionary written to disk).
func snapshot() -> Dictionary:
	var systems := {}
	for node in get_tree().get_nodes_in_group("stateful"):
		if node == self:
			continue
		systems[str(node.name)] = node.to_dict()
	var providers := {}
	for pname in _providers:
		var d: Variant = _providers[pname]["to"].call()
		if d is Dictionary:
			providers[pname] = d
	return {
		"version": SaveFormat.VERSION, "game": SaveFormat.GAME,
		"header": _make_header(), "systems": systems, "providers": providers,
	}


func save_slot(n: int) -> bool:
	_last_error = ""
	if not valid_slot(n):
		_last_error = "bad slot %d" % n
		return false
	var text := JSON.stringify(snapshot(), "\t")
	if not SaveFormat.parse(text)["ok"]:
		_last_error = "snapshot does not serialise"
		push_warning("SaveGame: " + _last_error)
		return false
	if DirAccess.make_dir_recursive_absolute(save_dir) != OK:
		_last_error = "cannot create %s" % save_dir
		push_warning("SaveGame: " + _last_error)
		return false
	var final := slot_path(n)
	var tmp := final + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		_last_error = "cannot open %s" % tmp
		push_warning("SaveGame: " + _last_error)
		return false
	f.store_string(text)
	f.flush()
	f.close()
	# Read it back before it replaces a good save.
	if _read_text(tmp) != text:
		DirAccess.remove_absolute(tmp)
		_last_error = "write verification failed"
		return false
	if fs_rename.call(tmp, final) != OK:
		DirAccess.remove_absolute(tmp)
		_last_error = "rename failed"
		push_warning("SaveGame: " + _last_error)
		return false
	saved.emit(n)
	return true


func quick_save() -> bool:
	return save_slot(1)


func quick_load() -> bool:
	return load_slot(1)


func _make_header() -> Dictionary:
	return {
		"name": Stats.player_name, "level": Stats.level,
		"location": _location_text(), "clock_text": _clock_text(),
		"playtime_seconds": snappedf(playtime.seconds, 0.1),
		"saved_unix": int(Time.get_unix_time_from_system()),
	}


func _clock_text() -> String:
	return "Day %d %s" % [Clock.day(), Clock.time_text()]


func _location_text() -> String:
	if not ("current" in World) or not (World.current is Dictionary):
		return ""
	var parts: Array[String] = []
	for k in ["section", "street", "building", "room"]:
		var v := str(World.current.get(k, ""))
		if v != "" and v != "null":
			parts.append(v)
	return " / ".join(parts)


# --- load --------------------------------------------------------------------

## Loads a slot. Parses and validates the whole file first; the running game is
## only touched once that succeeds. Returns false (and emits load_failed) on a
## missing, corrupt, truncated or too-new file.
func load_slot(n: int) -> bool:
	_last_error = ""
	if not has_slot(n):
		return _load_fail(n, "slot %d is empty" % n)
	var parsed := SaveFormat.parse(_read_text(slot_path(n)))
	if not parsed["ok"]:
		return _load_fail(n, parsed["error"])
	apply(parsed["data"])
	loaded.emit(n)
	return true


func _load_fail(n: int, reason: String) -> bool:
	_last_error = reason
	push_warning("SaveGame: cannot load slot %d: %s" % [n, reason])
	load_failed.emit(n, reason)
	return false


## Applies already-validated save data: reset_run, then each system in order.
func apply(data: Dictionary) -> void:
	_loading = true
	GameState.reset_run()
	var systems: Dictionary = data["systems"]
	var nodes := {}
	for node in get_tree().get_nodes_in_group("stateful"):
		if node != self:
			nodes[str(node.name)] = node
	for sname in systems:
		if not nodes.has(sname):
			push_warning("SaveGame: ignoring unknown system '%s'" % sname)
	for sname in _ordered_names(nodes.keys()):
		# A missing system keeps the reset() state reset_run just gave it.
		if systems.has(sname):
			nodes[sname].from_dict(systems[sname])
	var provs: Dictionary = data.get("providers", {})
	for pname in provs:
		if _providers.has(pname):
			_providers[pname]["from"].call(provs[pname])
		else:
			push_warning("SaveGame: no provider '%s' registered, skipping" % pname)
	playtime.seconds = float(data.get("header", {}).get("playtime_seconds", 0.0))
	_dead = false
	_loading = false


func _ordered_names(names: Array) -> Array:
	var out: Array = []
	for n in LOAD_ORDER:
		if names.has(n):
			out.append(n)
	var rest: Array = []
	for n in names:
		if not LOAD_ORDER.has(n):
			rest.append(n)
	rest.sort()
	return out + rest


func _read_text(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	return f.get_as_text()


# --- autosave ----------------------------------------------------------------

func is_loading() -> bool:
	return _loading


## Why an autosave would be refused right now, or "" if it is fine.
func autosave_blocked_reason() -> String:
	if not autosave_enabled:
		return "disabled"
	if _loading:
		return "loading"
	if _dead:
		return "dead"
	if get_tree().paused:
		return "paused"
	if Director.rush_active:
		return "rush"
	if get_tree().get_first_node_in_group("player") == null:
		return "no_run"
	return ""


## Saves slot 0 unless blocked. `force` skips the debounce, not the blockers.
func autosave(force: bool = true) -> bool:
	if autosave_blocked_reason() != "":
		return false
	var now := Time.get_ticks_msec()
	if not force and now - _last_autosave_msec < int(AUTOSAVE_MIN_INTERVAL * 1000.0):
		return false
	if save_slot(AUTOSAVE_SLOT):
		_last_autosave_msec = now
		return true
	return false


## Call when sleeping or waiting has finished (the rest dialog, or
## Survival.sleep_finished if it ever exists).
func notify_rest_finished() -> void:
	autosave(true)


func _on_location_entered(_id: String) -> void:
	autosave(false)


func _on_level_up(_lvl: int) -> void:
	autosave(true)
