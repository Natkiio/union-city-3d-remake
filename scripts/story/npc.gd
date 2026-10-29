class_name StoryNPC
extends Area3D
## A survivor or soldier the player can talk to. Root is an Area3D: the box
## sits recessed in Z (ROADMAP world layout rule) and reaches back to Z=0 so
## the player's body can enter it without colliding. Layer 2 is the hover pick
## layer used by HoverSystem; the mask watches the player on layer 1.
##
## setup(npc_id) reads npc.json (merged with Cork). The child "Visual" holds
## "Model", an instance of the shared male_basic rig dressed by CharacterLook
## from the NPC record. Its feet are on the NPC origin, the head top is at
## head_top_y() (a quest marker belongs about 0.4 above that), and the name
## label floats there too.

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
const TURN_RANGE := 6.0 ## faces the player when closer than this (metres)
const LABEL_GAP := 0.3

var model: Node3D
var _label: Label3D
var _anim: AnimationPlayer
var _built: bool = false


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
	if not _built:
		_build_visual()
	var ctx := StoryNames.context()
	_label.text = _sys("Data").text(def.get("fullName", def.get("name", npc_id)), ctx).strip_edges()
	_label.modulate = Color(1.0, 0.45, 0.4) if enemy_flag else Color.WHITE
	CharacterLook.apply(model, def)
	_label.position.y = head_top_y() + LABEL_GAP
	_refresh_active()


## Height of the head top above the NPC origin (feet), hair and hats included.
func head_top_y() -> float:
	if model == null:
		return 1.8
	return CharacterLook.top_y(model) * model.scale.y


func _build_visual() -> void:
	_built = true
	model = visual.get_node("Model") as Node3D
	_anim = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _anim != null and _anim.has_animation("Idle"):
		_anim.get_animation("Idle").loop_mode = Animation.LOOP_PINGPONG
		_anim.play("Idle")
		_anim.seek(randf() * _anim.current_animation_length, true) # crowds do not sync
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.pixel_size = 0.006
	_label.position.y = 2.1
	_label.visible = false
	add_child(_label)
	_turn()


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


func _process(_delta: float) -> void:
	if player_in_range != null and visible and Input.is_action_just_pressed("interact") \
			and _sys("World").is_interact_target(self) \
			and not get_tree().paused:
		interact()
	if _built and visible:
		var p := _player_near()
		if p != null:
			facing = signf(p.global_position.x - global_position.x) if p.global_position.x != global_position.x else facing
		_turn()


func _player_near() -> Node3D:
	if player_in_range != null:
		return player_in_range
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p != null and absf(p.global_position.x - global_position.x) < TURN_RANGE:
		return p
	return null


func _turn() -> void:
	# Same convention as the player: -PI/2 faces +X.
	model.rotation.y = -PI / 2.0 if facing > 0.0 else PI / 2.0


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
	if model == null:
		return
	CharacterLook.set_highlight(model, value)
	_label.visible = value


static func _sys(system: String) -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node(system)
