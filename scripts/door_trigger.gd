extends Area3D
## Interactive door: walk up, press "interact" to switch scenes.
## Tells GameState where to place the player in the destination scene.

@export var target_scene: String = ""
@export var spawn_x: float = 0.0

var player_in_range: Node3D = null
var triggered: bool = false

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		player_in_range = body

func _on_body_exited(body: Node3D) -> void:
	if body == player_in_range:
		player_in_range = null

func _process(_delta: float) -> void:
	if triggered or target_scene == "" or player_in_range == null:
		return
	if Input.is_action_just_pressed("interact"):
		triggered = true
		GameState.request_spawn(spawn_x)
		print("[Door] interact pressed, switching to %s (spawn_x=%.1f)" % [target_scene, spawn_x])
		call_deferred("_do_scene_change")

func _do_scene_change() -> void:
	get_tree().change_scene_to_file(target_scene)
