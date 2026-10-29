class_name ZombieState
extends RefCounted
## Per-room zombie memory, owned by Director (issue #25). For each room id it
## keeps the living zombies (kind, health, x) captured when the player left,
## and the kinds that died there. Director restores a fresh entry instead of
## rolling new room-entry spawns; entries expire with DirectorRules.repop_time.
## Saved through Director.to_dict/from_dict.

## room id -> {"t": game minute of last leave, "alive": [{kind, health, x}], "dead": [kind]}
var rooms: Dictionary = {}


func clear() -> void:
	rooms.clear()


func has_room(id: String) -> bool:
	return rooms.has(id)


func _entry(id: String) -> Dictionary:
	if not rooms.has(id):
		rooms[id] = {"t": 0.0, "alive": [], "dead": []}
	return rooms[id]


func record_death(id: String, kind: String) -> void:
	if id != "":
		_entry(id)["dead"].append(kind)


## Replace the living snapshot of a room from live zombies.
func capture(id: String, zombies: Array, minute: float) -> void:
	if id == "":
		return
	var e := _entry(id)
	var alive := []
	for z in zombies:
		if is_instance_valid(z) and z.is_inside_tree() and not z.is_dead():
			alive.append({"kind": z.enemy_ref, "health": z.health, "x": z.global_position.x})
	e["alive"] = alive
	e["t"] = minute


## True when the room has memory that is still within the repop window.
func is_fresh(id: String, minute: float, outdoors: bool) -> bool:
	return rooms.has(id) and minute - float(rooms[id]["t"]) <= DirectorRules.repop_time(outdoors)


func forget(id: String) -> void:
	rooms.erase(id)


func living(id: String) -> Array:
	return rooms[id]["alive"] if rooms.has(id) else []


func to_dict() -> Dictionary:
	return rooms.duplicate(true)


func from_dict(d: Dictionary) -> void:
	rooms = d.duplicate(true)
