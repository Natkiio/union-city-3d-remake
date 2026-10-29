extends Node
## Autoload "Director" (stub). Zombie threat budget, spawn requests, rushes, breaks, droppers for the current location. Spec: section 5. Owner: zombie-director workstream.
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
