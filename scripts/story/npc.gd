class_name StoryNPC
extends Area3D
## A survivor or soldier the player can talk to. Root is an Area3D: the box
## sits recessed in Z (ROADMAP world layout rule) and reaches back to Z=0 so
## the player's body can enter it without colliding. Layer 2 is the hover pick
## layer used by HoverSystem; the mask watches the player on layer 1.
##
## setup(npc_id) reads npc.json (merged with Cork). The child "Visual" is a
## plain coloured silhouette that the cutout rig will replace.

signal talked(npc_id: String)

const RECESS_Z := -1.5

var npc_id: String = ""
var def: Dictionary = {}
var pose: String = "idle"
var facing: float = 1.0
var hovered: bool = false
var player_in_range: Node3D = null
var enemy_flag: bool = false
var friendly: bool = true
## "" | "follower" | "partner": companion data only, no AI here.
var companion_kind: String = ""

@onready var visual: Node3D = $Visual
var _body: MeshInstance3D
var _head: MeshInstance3D
var _label: Label3D
var _mat: StandardMaterial3D
var _base_color := Color(0.5, 0.5, 0.55)
var _t: float = 0.0


## World calls this right after instantiating (before or after add_child).
func setup(id: String) -> void:
	npc_id = id
	def = _sys("Quests").npc_def(id)
	name = "NPC_" + id
	enemy_flag = _sys("Quests").npc_is_enemy(id)
	friendly = _sys("Quests").npc_is_friendly(id)
	companion_kind = str(_sys("Quests").companions().get(id, ""))
	if is_inside_tree():
		_apply()


func _ready() -> void:
	add_to_group("hoverable")
	add_to_group("npc")
	add_to_group("world_interactable")
	collision_layer = 2
	collision_mask = 1
	position.z = RECESS_Z
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_sys("Quests").npc_changed.connect(_on_npc_changed)
	if npc_id != "":
		_apply()


func _apply() -> void:
	if _body == null:
		_build_visual()
	var ctx := StoryNames.context()
	_label.text = _sys("Data").text(def.get("fullName", def.get("name", npc_id)), ctx).strip_edges()
	_base_color = _color_for(str(def.get("clothesTop", "")))
	_mat.albedo_color = _base_color
	_refresh_active()


func _build_visual() -> void:
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_color = _base_color
	_body = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.6, 1.3, 0.08)
	_body.mesh = box
	_body.position.y = 0.65
	_body.material_override = _mat
	visual.add_child(_body)
	_head = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.2
	sphere.height = 0.4
	_head.mesh = sphere
	_head.position.y = 1.5
	var head_mat := StandardMaterial3D.new()
	head_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	head_mat.albedo_color = _skin_color(str(def.get("skinColour", "White")))
	_head.material_override = head_mat
	visual.add_child(_head)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.pixel_size = 0.006
	_label.position.y = 2.0
	_label.visible = false
	add_child(_label)


func _refresh_active() -> void:
	var on = _sys("Quests").npc_active(npc_id)
	visible = on
	monitoring = on
	monitorable = on
	if not on:
		player_in_range = null


func _on_npc_changed(id: String) -> void:
	if id == npc_id and is_inside_tree():
		_refresh_active()


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		player_in_range = body


func _on_body_exited(body: Node3D) -> void:
	if body == player_in_range:
		player_in_range = null


func _process(delta: float) -> void:
	_t += delta
	if visual != null:
		visual.scale.y = 1.0 + sin(_t * 1.6) * 0.012 # idle breathing
		visual.scale.x = facing
	if player_in_range != null and visible and Input.is_action_just_pressed("interact") \
			and not get_tree().paused:
		interact()


## True while the player is in range and could talk (World checks this so a
## door trigger behind the NPC does not steal the key).
func wants_interact() -> bool:
	return player_in_range != null and visible and not get_tree().paused


## Opens the dialogue. Returns the box (null if the NPC has nothing to say).
func interact() -> DialogueBox:
	var box := Dialogue.open(get_tree(), npc_id)
	if box != null:
		talked.emit(npc_id)
	return box


func set_facing(dir: float) -> void:
	facing = -1.0 if dir < 0.0 else 1.0


## Called by HoverSystem.
func set_highlighted(value: bool) -> void:
	hovered = value
	if _mat == null:
		return
	_mat.albedo_color = Color.WHITE if value else _base_color
	_label.visible = value


func _color_for(clothes: String) -> Color:
	var h := clothes.hash()
	return Color.from_hsv(float(h % 360) / 360.0, 0.35, 0.6)


func _skin_color(skin: String) -> Color:
	match skin:
		"Black":
			return Color(0.35, 0.24, 0.17)
		"Brown", "Tan":
			return Color(0.62, 0.45, 0.32)
	return Color(0.9, 0.74, 0.62)

static func _sys(system: String) -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node(system)
