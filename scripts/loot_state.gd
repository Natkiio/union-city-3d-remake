extends Node
## Tracks which lootable objects (crates, trunks) have already been
## emptied, keyed by their stable scene-tree path. Persists across
## scene reloads (change_scene_to_file) since this is an autoload,
## so a looted car trunk or crate does not respawn full after a trip
## through a door.

var looted: Dictionary = {}

func mark_looted(loot_id: String) -> void:
	looted[loot_id] = true

func is_looted(loot_id: String) -> bool:
	return looted.get(loot_id, false)
