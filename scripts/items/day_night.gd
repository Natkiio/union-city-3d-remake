class_name DayNight
extends Node
## Drop-in day/night lighting. Add this node to a level scene; it tints a
## DirectionalLight3D and the ambient light from Clock's lightTime preset.
##
## Usage: add a DayNight node anywhere in the scene. Leave `sun` and
## `world_environment` empty to use the first DirectionalLight3D and
## WorldEnvironment found in the scene, or assign them. Set `light_reduction`
## (percent) for interiors, which dim the light. `base_sun_energy` and
## `base_ambient_energy` are the full-daylight values; night scales them by
## _clock().energy(). The preset changes in steps, so the node eases to it.

@export var sun: DirectionalLight3D
@export var world_environment: WorldEnvironment
@export_range(0.0, 100.0) var light_reduction: float = 0.0
@export var base_sun_energy: float = 1.0
@export var base_ambient_energy: float = 1.0
## Seconds to ease to a new preset. 0 snaps.
@export var ease_seconds: float = 3.0

var _color: Color = Color.WHITE
var _energy: float = 1.0


func _ready() -> void:
	if sun == null:
		sun = _first_of(get_tree().current_scene if get_tree().current_scene else get_parent(), "DirectionalLight3D")
	if world_environment == null:
		world_environment = _first_of(get_tree().current_scene if get_tree().current_scene else get_parent(), "WorldEnvironment")
	apply_now()


func _process(delta: float) -> void:
	var target_color: Color = _clock().light_color(light_reduction)
	var target_energy: float = _clock().energy(light_reduction)
	var t := 1.0 if ease_seconds <= 0.0 else clampf(delta / ease_seconds, 0.0, 1.0)
	_color = _color.lerp(target_color, t)
	_energy = lerpf(_energy, target_energy, t)
	_apply()


## Jumps straight to the current preset.
func apply_now() -> void:
	_color = _clock().light_color(light_reduction)
	_energy = _clock().energy(light_reduction)
	_apply()


func _apply() -> void:
	if sun != null:
		sun.light_color = _color
		sun.light_energy = base_sun_energy * _energy
	if world_environment != null and world_environment.environment != null:
		var env := world_environment.environment
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = _color
		env.ambient_light_energy = base_ambient_energy * _energy


func _clock() -> Node:
	return get_node("/root/Clock")


static func _first_of(node: Node, type_name: String) -> Node:
	if node == null:
		return null
	if node.is_class(type_name):
		return node
	for c in node.get_children():
		var found := _first_of(c, type_name)
		if found != null:
			return found
	return null
