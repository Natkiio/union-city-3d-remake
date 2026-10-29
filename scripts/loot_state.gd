extends Node
## Tracks which lootable objects (crates, trunks) have already been
## emptied, keyed by their stable scene-tree path, plus the exact
## remaining contents of multi-item containers (trunks) so a PARTIAL
## take (grabbing one item, not all) also survives a scene reload --
## previously only "fully emptied" was remembered, so taking a single
## item from the trunk and then changing scenes (e.g. through a door)
## would respawn the trunk with that item back in it. Persists across
## scene reloads (change_scene_to_file) since this is an autoload.

var looted: Dictionary = {}
var trunk_contents: Dictionary = {}
## Searched containers by container id: {"searched": bool, "items": Array}.
## `items` is the exact remaining contents after any partial takes.
var containers: Dictionary = {}
## Lock state by lock id (container id, or "<room path>_<door>"):
## {"unlocked": bool, "broken": bool}.
var locks: Dictionary = {}

func _ready() -> void:
	add_to_group("stateful")

func reset() -> void:
	looted.clear()
	trunk_contents.clear()
	containers.clear()
	locks.clear()

func to_dict() -> Dictionary:
	return {"looted": looted.duplicate(true), "trunk_contents": trunk_contents.duplicate(true),
		"containers": containers.duplicate(true), "locks": locks.duplicate(true)}

func from_dict(d: Dictionary) -> void:
	looted = d.get("looted", {}).duplicate(true)
	trunk_contents = d.get("trunk_contents", {}).duplicate(true)
	containers = d.get("containers", {}).duplicate(true)
	locks = d.get("locks", {}).duplicate(true)

func mark_looted(loot_id: String) -> void:
	looted[loot_id] = true

func is_looted(loot_id: String) -> bool:
	return looted.get(loot_id, false)

## Call whenever a trunk's items change (take_item/take_all) so the
## exact remaining contents are remembered, not just "is it empty".
func save_trunk_contents(trunk_id: String, items: Array) -> void:
	trunk_contents[trunk_id] = items.duplicate(true)

func has_saved_trunk_contents(trunk_id: String) -> bool:
	return trunk_contents.has(trunk_id)

func get_saved_trunk_contents(trunk_id: String) -> Array:
	return trunk_contents.get(trunk_id, []).duplicate(true)

## Searched-container record, or {} if it has never been searched.
func get_container(container_id: String) -> Dictionary:
	return containers.get(container_id, {}).duplicate(true)

func has_container(container_id: String) -> bool:
	return containers.has(container_id)

func set_container(container_id: String, record: Dictionary) -> void:
	containers[container_id] = record.duplicate(true)

func get_lock(lock_id: String) -> Dictionary:
	return locks.get(lock_id, {}).duplicate()

func set_lock(lock_id: String, state: Dictionary) -> void:
	locks[lock_id] = state.duplicate()
