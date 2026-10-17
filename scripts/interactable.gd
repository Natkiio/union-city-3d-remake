extends Area3D
## Scavenge pickup: walk up, press "interact" to loot while in range.

@export var item_name: String = "Canned Food"
var player_in_range: Node3D = null

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
	if player_in_range and Input.is_action_just_pressed("interact"):
		Inventory.add_item(item_name)
		queue_free()
