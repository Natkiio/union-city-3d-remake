extends Node
## Autoload "Companions" (stub). Followers and the partner: who is with the
## player, their AI, giving them weapons, healing them. Owner: companions workstream.
## Stateful: group "stateful", reset(), to_dict(), from_dict(d).

func _ready() -> void:
	add_to_group("stateful")


func reset() -> void:
	pass


func to_dict() -> Dictionary:
	return {}


func from_dict(_d: Dictionary) -> void:
	pass
