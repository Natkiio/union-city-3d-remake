extends Node
## Autoload "SaveGame" (stub). Collects to_dict() from every node in group 'stateful' and writes/reads the save file. Owner: persistence workstream.
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
