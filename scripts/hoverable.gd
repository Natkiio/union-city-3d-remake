extends Area3D
## Generic mouse-hover highlighter. Attach to a small Area3D placed
## over a visual mesh (door, trunk lid, etc). HoverSystem raycasts the
## mouse each frame and calls set_highlighted() on whatever it hits.
## While highlighted, the target mesh's material is swapped for a
## bright white emissive copy so it reads clearly under any lighting.

@export var target_mesh_path: NodePath
@export var highlight_color: Color = Color(1, 1, 1)
@export var highlight_energy: float = 1.8

var target_mesh: MeshInstance3D
var original_material: Material
var highlight_material: StandardMaterial3D
var is_highlighted: bool = false

func _ready() -> void:
	add_to_group("hoverable")
	target_mesh = get_node(target_mesh_path)
	original_material = target_mesh.get_surface_override_material(0)
	if original_material == null and target_mesh.mesh != null:
		original_material = target_mesh.mesh.surface_get_material(0)
	var base: StandardMaterial3D
	if original_material is StandardMaterial3D:
		base = original_material.duplicate()
	else:
		base = StandardMaterial3D.new()
	highlight_material = base
	highlight_material.albedo_color = highlight_color
	highlight_material.emission_enabled = true
	highlight_material.emission = highlight_color
	highlight_material.emission_energy_multiplier = highlight_energy

func set_highlighted(value: bool) -> void:
	if value == is_highlighted:
		return
	is_highlighted = value
	if value:
		target_mesh.set_surface_override_material(0, highlight_material)
	else:
		target_mesh.set_surface_override_material(0, original_material)
