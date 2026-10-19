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
