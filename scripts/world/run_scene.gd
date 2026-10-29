extends Node3D
## Root of the run scene (scenes/main.tscn): sun, environment, day/night,
## the LevelRoot that World fills, the player, camera rig and HUD. On ready it
## registers with World, which builds the current room into LevelRoot.

@onready var level_root: Node3D = $LevelRoot
@onready var player: Node3D = $Player
@onready var camera_rig: Node3D = $CameraRig
@onready var day_night: Node = $DayNight
@onready var banner: Label = $Banner/Label

## Camera offsets: the street pulls back to show facades and skyline, rooms
## come in closer (the rooms are 4-12 units wide).
const STREET_CAMERA := Vector3(0, 2.6, 9.5)
const ROOM_CAMERA := Vector3(0, 2.0, 7.0)

var _banner_tween: Tween


func _ready() -> void:
	World.attach_run_scene(self)


func _exit_tree() -> void:
	World.detach_run_scene(self)


func get_level_root() -> Node3D:
	return level_root


func get_player() -> Node3D:
	return player


## World calls this after building a level: camera limits, lighting, banner.
func on_level_built(level: Level, info: Dictionary) -> void:
	camera_rig.offset = STREET_CAMERA if info.get("outdoors", false) else ROOM_CAMERA
	if camera_rig.has_method("set_limits"):
		camera_rig.set_limits(0.0, level.width_units())
		camera_rig.snap()
	if day_night != null:
		day_night.light_reduction = float(info.get("light_reduction", 0.0))
		day_night.apply_now()
	var sfx := get_node_or_null("/root/Sfx")
	if sfx != null and sfx.has_method("start_ambient"):
		sfx.start_ambient("street" if info.get("outdoors", false) else "interior", -14.0)
	_show_banner(info)


func _show_banner(info: Dictionary) -> void:
	var text := str(info.get("name", ""))
	var section_name := str(info.get("section_name", "")).to_upper()
	if info.get("outdoors", false) and section_name != text.to_upper():
		text = "%s\n%s" % [section_name, text]
	if info.get("safehouse", false):
		text += "\nSAFEHOUSE"
	banner.text = text
	banner.modulate.a = 1.0
	if _banner_tween != null:
		_banner_tween.kill()
	_banner_tween = create_tween()
	_banner_tween.tween_interval(2.5)
	_banner_tween.tween_property(banner, "modulate:a", 0.0, 1.0)
