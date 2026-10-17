extends Node3D
## Fixed side-on camera that tracks the player's X position only,
## matching the original game's horizontally-scrolling view.

@export var target_path: NodePath
@export var offset: Vector3 = Vector3(0, 4.5, 9.0)
@export var follow_speed: float = 6.0

var target: Node3D = null

func _ready() -> void:
	if target_path != NodePath(""):
		target = get_node(target_path)
	else:
		target = get_tree().get_first_node_in_group("player")

func _process(delta: float) -> void:
	if target == null:
		target = get_tree().get_first_node_in_group("player")
		return
	var goal := Vector3(target.global_position.x, 0, 0) + offset
	global_position = global_position.lerp(goal, clamp(follow_speed * delta, 0.0, 1.0))
