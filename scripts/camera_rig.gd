extends Node3D
## Fixed side-on camera that tracks the player's X position only,
## matching the original game's horizontally-scrolling view.
## World sets limits per room so the view stops at the room's ends (the
## original's panEdgeBuffer); a room narrower than the view is centred.

@export var target_path: NodePath
@export var offset: Vector3 = Vector3(0, 4.5, 9.0)
@export var follow_speed: float = 6.0

var target: Node3D = null
var limit_min: float = -INF
var limit_max: float = INF


func _ready() -> void:
	if target_path != NodePath(""):
		target = get_node(target_path)
	else:
		target = get_tree().get_first_node_in_group("player")


func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		target = get_tree().get_first_node_in_group("player")
		return
	global_position = global_position.lerp(goal(), clamp(follow_speed * delta, 0.0, 1.0))


## Room ends in world x. Pass -INF/INF to remove.
func set_limits(min_x: float, max_x: float) -> void:
	limit_min = min_x
	limit_max = max_x


## Jump straight to the goal (after a room change).
func snap() -> void:
	if target == null or not is_instance_valid(target):
		target = get_tree().get_first_node_in_group("player")
	if target != null:
		global_position = goal()


## Half the visible width at the player's lane, from the camera's fov.
func view_half_width() -> float:
	var cam := get_node_or_null("Camera3D") as Camera3D
	var fov := 50.0 if cam == null else cam.fov
	var size := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(16, 9)
	var aspect := size.x / maxf(size.y, 1.0)
	return offset.z * tan(deg_to_rad(fov) * 0.5) * aspect


func goal() -> Vector3:
	var x := target.global_position.x if target != null else 0.0
	if is_finite(limit_min) and is_finite(limit_max):
		var half := view_half_width()
		if limit_max - limit_min <= half * 2.0:
			x = (limit_min + limit_max) * 0.5
		else:
			x = clampf(x, limit_min + half, limit_max - half)
	return Vector3(x, 0, 0) + offset
