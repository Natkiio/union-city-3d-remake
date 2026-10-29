class_name SelectionUX
extends Node3D
## Selection feedback for one built level. Exactly one thing is "active": the
## World's interact target. It gets a coloured frame hugging its body, a bobbing
## chevron and ONE prompt above it ("[E] Search Cupboard", "[E] Leave to Main
## Street"), colour by kind: containers amber, exits/doors green, people blue,
## stairs grey, locked red. Everything else nearby shows nothing. A target under
## the mouse but out of reach gets a dim "too far" tag. A small copy of the
## prompt sits at the bottom of the screen so it is readable even when the world
## label is off-screen. Targets supply `select_info()` ->
## {kind, text, bounds (global AABB), in_range}.

const COLORS := {
	"container": Color(1.0, 0.72, 0.22),
	"empty": Color(0.7, 0.62, 0.45),
	"exit": Color(0.45, 0.95, 0.5),
	"stairs": Color(0.8, 0.83, 0.88),
	"person": Color(0.5, 0.75, 1.0),
	"bed": Color(0.78, 0.66, 1.0),
	"shop": Color(1.0, 0.55, 0.8),
	"locked": Color(1.0, 0.38, 0.33),
	"blocked": Color(0.6, 0.6, 0.6),
}
const FRAME_MARGIN := 0.08
const FRAME_THICK := 0.04

## The active target and its info (read by tests and the HUD hint).
var active: Node3D = null
var info: Dictionary = {}
var far_target: Node3D = null

var prompt: WorldText
var far_label: WorldText
var _frame: Array[MeshInstance3D] = []
var _frame_mat: StandardMaterial3D
var _chevron: MeshInstance3D
var _chev_mat: StandardMaterial3D
var _hint_layer: CanvasLayer
var _hint: Label
var _t := 0.0


func _ready() -> void:
	name = "SelectionUX"
	add_to_group("selection_ux")
	process_mode = Node.PROCESS_MODE_ALWAYS
	_frame_mat = _unshaded_mat()
	for i in 4:
		var m := MeshInstance3D.new()
		m.mesh = BoxMesh.new()
		m.material_override = _frame_mat
		m.visible = false
		add_child(m)
		_frame.append(m)
	_chev_mat = _unshaded_mat()
	_chevron = MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.15
	cone.bottom_radius = 0.0
	cone.height = 0.22
	cone.radial_segments = 4
	_chevron.mesh = cone
	_chevron.material_override = _chev_mat
	_chevron.visible = false
	add_child(_chevron)
	prompt = WorldText.make("", WorldText.Kind.PROMPT)
	prompt.name = "ActivePrompt"
	prompt.width = 340.0
	prompt.visible = false
	add_child(prompt)
	far_label = WorldText.make("", WorldText.Kind.PROMPT, Color(0.75, 0.75, 0.75, 0.7))
	far_label.name = "FarPrompt"
	far_label.visible = false
	add_child(far_label)
	_hint_layer = CanvasLayer.new()
	_hint_layer.layer = 4
	add_child(_hint_layer)
	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 18)
	_hint.add_theme_color_override("font_outline_color", WorldText.OUTLINE)
	_hint.add_theme_constant_override("outline_size", 6)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.anchor_left = 0.25
	_hint.anchor_right = 0.75
	_hint.offset_left = 0.0
	_hint.offset_right = 0.0
	_hint.offset_top = -64.0
	_hint.offset_bottom = -30.0
	_hint.visible = false
	_hint_layer.add_child(_hint)


static func _unshaded_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = true
	m.render_priority = 5
	return m


static func color_for(kind: String) -> Color:
	return COLORS.get(kind, Color.WHITE)


func _process(delta: float) -> void:
	_t += delta
	var world: Node = get_node_or_null("/root/World")
	var target: Node3D = null
	if world != null and not get_tree().paused:
		target = world.interact_target()
	if target != active:
		active = target
	info = {}
	if active != null and is_instance_valid(active) and active.has_method("select_info"):
		info = active.select_info()
	else:
		active = null
	_show_active()
	_show_far(world)


func _show_active() -> void:
	var on := not info.is_empty()
	for m in _frame:
		m.visible = on
	_chevron.visible = on
	prompt.visible = on
	_hint.visible = on
	if not on:
		return
	var col := color_for(str(info.kind))
	var b: AABB = info.bounds
	var pulse := 0.65 + 0.35 * sin(_t * 6.0)
	_frame_mat.albedo_color = Color(col, pulse)
	_chev_mat.albedo_color = col
	var x0 := b.position.x - FRAME_MARGIN
	var x1 := b.end.x + FRAME_MARGIN
	var y0 := maxf(b.position.y - FRAME_MARGIN, 0.0)
	var y1 := b.end.y + FRAME_MARGIN
	var z := b.end.z + 0.05
	_set_bar(0, Vector3((x0 + x1) * 0.5, y0, z), Vector3(x1 - x0, FRAME_THICK, FRAME_THICK))
	_set_bar(1, Vector3((x0 + x1) * 0.5, y1, z), Vector3(x1 - x0, FRAME_THICK, FRAME_THICK))
	_set_bar(2, Vector3(x0, (y0 + y1) * 0.5, z), Vector3(FRAME_THICK, y1 - y0, FRAME_THICK))
	_set_bar(3, Vector3(x1, (y0 + y1) * 0.5, z), Vector3(FRAME_THICK, y1 - y0, FRAME_THICK))
	var cx := (x0 + x1) * 0.5
	if info.kind == "person":
		y1 += 0.45 # clear of the quest marker above the head
	_chevron.global_position = Vector3(cx, y1 + 0.2 + 0.05 * sin(_t * 5.0), z)
	var text := str(info.text)
	if prompt.text != text:
		prompt.text = text
	prompt.modulate = col
	prompt.global_position = Vector3(cx, y1 + 0.55 + (0.28 if text.contains("\n") else 0.0), z)
	_hint.text = text.replace("\n", " ")
	_hint.add_theme_color_override("font_color", col)


func _set_bar(i: int, pos: Vector3, size: Vector3) -> void:
	var m := _frame[i]
	m.global_position = pos
	(m.mesh as BoxMesh).size = size


## A hovered target the player cannot reach yet gets a dim tag instead.
func _show_far(world: Node) -> void:
	far_target = null
	far_label.visible = false
	if world == null or get_tree().paused or not world.mouse_recent():
		return
	var h: Node3D = world.hovered_target()
	if h == null or h == active:
		return
	var fi: Dictionary = h.select_info()
	if fi.get("in_range", false):
		return
	far_target = h
	var b: AABB = fi.bounds
	var t := str(fi.text).replace("[E] ", "").split("\n")[0]
	far_label.text = "%s - too far" % t
	far_label.global_position = Vector3(b.get_center().x, b.end.y + 0.4, b.end.z + 0.05)
	far_label.visible = true
