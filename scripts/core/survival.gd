extends Node
## Autoload "Survival" (stub). Hunger and sleep meters, penalties, eating, sleeping and waiting. Spec: section 4. Owner: survival workstream.
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
