extends Node
## Autoload "Stats". Character sheet: attributes, skills, level, XP, derived
## stats. Spec: docs/ORIGINAL_ANALYSIS.md sections 1-2. Owner: progression.
##
## The functions below are the contract other systems code against. Until the
## progression workstream implements them they return the original's base values.

var level: int = 1


func _ready() -> void:
	add_to_group("stateful")


## Attribute value: strength, precision, intellect, endurance, luck. Base 5.
func attr(_attr_name: String) -> int:
	return 5


## Raw skill points (base 7), e.g. "pistols", "blunt", "searching".
func skill(_skill_name: String) -> int:
	return 7


## round(skill + attribute * 1.6 - 5). Use this for every skill check.
func adjusted_skill(_skill_name: String) -> int:
	return 7


func max_health() -> float:
	return 55.0


func carry_weight() -> float:
	return 50.0


func add_xp(_amount: int, _reason: String = "") -> void:
	pass


func reset() -> void:
	level = 1


func to_dict() -> Dictionary:
	return {"level": level}


func from_dict(d: Dictionary) -> void:
	level = d.get("level", 1)
