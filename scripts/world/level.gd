class_name Level
extends Node3D
## One built room or street, made by LevelBuilder. Holds what World needs to
## run it: the room id, its width, and lookups for spawn points.

var room_id: String = ""
var width_px: float = 0.0
var outdoors: bool = false
var safehouse: bool = false
var danger: int = 0


func width_units() -> float:
	return width_px / WorldData.PX_PER_UNIT


func links() -> Array[WorldLink]:
	var out: Array[WorldLink] = []
	for n in find_children("*", "WorldLink", true, false):
		out.append(n)
	return out


func link_named(marker_name: String) -> WorldLink:
	for l in links():
		if l.link.get("name", "") == marker_name:
			return l
	return null


## Where zombies and dropped things go. Zombies spawn as children here and are
## freed with the level when the player leaves.
func spawn_root() -> Node3D:
	return get_node("Actors")
