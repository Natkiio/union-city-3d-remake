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
		if prompt != null:
			prompt.visible = true


func _on_body_exited(body: Node3D) -> void:
	if body == player_in_range:
		player_in_range = null
		if prompt != null:
			prompt.visible = false


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
