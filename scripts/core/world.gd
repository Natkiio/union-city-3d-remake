extends Node
## Autoload "World" (stub). Current location, danger level, building/floor/room navigation, travel between sections. Spec: section 12. Owner: world workstream.
## Stateful systems join group "stateful" and implement reset(), to_dict(),
## from_dict(d); see docs/PORT_PLAN.md.

func _ready() -> void:
	add_to_group("stateful")


func reset() -> void:
	pass


func to_dict() -> Dictionary:
	return {}


func from_dict(_d: Dictionary) -> void:
	pass
