extends Node
## Autoload "Quests" (stub). Quest and NPC state, triggers, rewards, unlocks. Spec: section 11. Owner: story workstream.
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
