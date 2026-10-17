extends Area3D
## Car trunk: walk up to the rear, press "interact" to open the trunk
## inventory. Items live here until taken into the player's Inventory.

@export var items: Array[Dictionary] = []

var player_in_range: Node3D = null
var reopen_cooldown: float = 0.0

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	if items.is_empty():
		items = [
			{"name": "Spare Tire", "weight": 8.0},
			{"name": "Tool Kit", "weight": 3.5},
			{"name": "Road Flares", "weight": 1.0},
		]

func suppress_interact(duration: float = 0.3) -> void:
	reopen_cooldown = duration

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		player_in_range = body

func _on_body_exited(body: Node3D) -> void:
	if body == player_in_range:
		player_in_range = null

func _process(delta: float) -> void:
	reopen_cooldown = max(0.0, reopen_cooldown - delta)
	if player_in_range == null or TrunkUI.visible or reopen_cooldown > 0.0:
		return
	if Input.is_action_just_pressed("interact"):
		TrunkUI.open(self)

func take_all() -> Array:
	var taken: Array = items.duplicate()
	items.clear()
	return taken

func take_item(index: int) -> Dictionary:
	return items.pop_at(index)
