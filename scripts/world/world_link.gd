class_name WorldLink
extends Area3D
## Trigger for a door, stair, building entrance/exit, street edge, room link,
## map exit or bed. The visual sits recessed in Z; this Area3D reaches back to
## the player's Z=0 lane (it has no solid body). World decides what happens
## when the player presses interact inside it: see World.use_link().

## Resolved link from WorldData.links() (plus "kind": "bed" for beds and "shop" for shop counters).
var link: Dictionary = {}
var player_in_range: Node3D = null
var prompt: Label3D = null
## Door, bed or counter mesh: the highlight frame hugs it.
var visual: MeshInstance3D = null


func _ready() -> void:
	add_to_group("world_link")
	monitorable = false
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	if prompt != null:
		prompt.visible = false


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		player_in_range = body


func _on_body_exited(body: Node3D) -> void:
	if body == player_in_range:
		player_in_range = null


func in_range() -> bool:
	return player_in_range != null and is_instance_valid(player_in_range)


## Prompt text in the original's style: "[E] OPEN", "[E] LOCKED"...
func prompt_text() -> String:
	if not link.get("kind", "") in ["bed", "shop"] and link.get("target", "") == "":
		return "[E] BLOCKED"
	if link.get("locked", false):
		return "[E] LOCKED"
	return "[E] " + str(link.get("label", "OPEN"))


func refresh_prompt() -> void:
	if prompt != null:
		prompt.text = prompt_text()


## Selection feedback (see SelectionUX): action + destination, kind colour.
func select_info() -> Dictionary:
	var kind := str(link.get("kind", ""))
	var target := str(link.get("target", ""))
	var text := "Open"
	var cat := "exit"
	var dest := _dest_name(target)
	match kind:
		"bed":
			text = "Sleep"
			cat = "bed"
		"shop":
			text = "Shop"
			cat = "shop"
		"sup":
			text = "Go upstairs"
			cat = "stairs"
		"sdwn":
			text = "Go downstairs"
			cat = "stairs"
		"drop":
			text = "Drop down"
			cat = "stairs"
		"entr":
			text = "Enter " + dest if dest != "" else "Enter"
		"exit":
			text = "Leave to " + dest if dest != "" else "Leave"
		"area":
			text = "Open the map"
		"strt", "ltrm", "rtrm":
			text = "Go to " + dest if dest != "" else "Next area"
		_:
			var leaving := dest != "" and int(WorldData.parse(target).get("building", 1)) == 0
			text = ("Leave to " if leaving else "Go to ") + dest if dest != "" else "Open door"
	if kind not in ["bed", "shop"] and target == "":
		text = "Blocked"
		cat = "blocked"
	elif link.get("locked", false):
		cat = "locked"
		text += "\n(locked: needs %s)" % ("key" if link.get("needs_key", false) else "lockpick")
	return {"kind": cat, "text": ("[E] " if cat != "blocked" else "") + text, "bounds": _select_bounds(),
			"in_range": in_range()}


func _select_bounds() -> AABB:
	if visual != null and is_instance_valid(visual) and visual.mesh != null:
		var b := visual.global_transform * visual.get_aabb()
		if b.size.x > 0.05 and b.size.y > 0.05:
			return b
	return AABB(Vector3(global_position.x - 0.5, 0.0, global_position.z - 0.1), Vector3(1.0, 2.2, 0.2))


## Short display name of the room a link leads to.
static func _dest_name(target: String) -> String:
	if target == "" or target == "map":
		return ""
	var p := WorldData.parse(target)
	if p.is_empty():
		return ""
	var out := WorldData.street_name(target) if int(p.building) == 0 else WorldData.building_name(target)
	if int(p.building) != 0:
		var rname := str(WorldData.room_def(target).get("name", ""))
		if rname != "" and rname != "Outside" and rname.to_upper() != out.to_upper():
			out = "%s - %s" % [out, rname] if out != "" else rname
	out = out.capitalize() if out == out.to_upper() else out
	return out if out.length() <= 30 else out.substr(0, 29) + "."
