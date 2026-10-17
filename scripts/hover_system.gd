extends Node
## Autoload: raycasts from the mouse cursor into the active 3D camera
## each frame and highlights whatever "hoverable" Area3D the cursor
## is currently over (see hoverable.gd). Automatically stops while
## the game is paused (trunk/inventory menus) since Node processing
## is paused along with everything else by default.

var current_hovered: Node = null

const HOVER_LAYER_MASK := 2

func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		_clear_hover()
		return
	var world := camera.get_world_3d()
	if world == null:
		_clear_hover()
		return

	var mouse_pos := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse_pos)
	var ray_dir := camera.project_ray_normal(mouse_pos)
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * 1000.0)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	query.collision_mask = HOVER_LAYER_MASK

	var result := world.direct_space_state.intersect_ray(query)
	var hit_node: Node = null
	if result.has("collider"):
		var collider = result["collider"]
		if collider is Node and collider.is_in_group("hoverable"):
			hit_node = collider

	if hit_node != current_hovered:
		_clear_hover()
		current_hovered = hit_node
		if current_hovered and current_hovered.has_method("set_highlighted"):
			current_hovered.set_highlighted(true)

func _clear_hover() -> void:
	if current_hovered and is_instance_valid(current_hovered) and current_hovered.has_method("set_highlighted"):
		current_hovered.set_highlighted(false)
	current_hovered = null
