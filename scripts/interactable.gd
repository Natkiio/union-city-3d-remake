extends Area3D
## Scavenge pickup: walk up, press "interact" to loot while in range.
## Uses its stable scene path as a loot id so it stays looted across
## scene reloads instead of respawning full.

@export var item_name: String = "Canned Food"
@export var item_weight: float = 1.0

var player_in_range: Node3D = null
var loot_id: String = ""

func _ready() -> void:
	loot_id = str(get_path())
	if LootState.is_looted(loot_id):
		queue_free()
		return
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
		Inventory.add_item(item_name, item_weight)
		LootState.mark_looted(loot_id)
		queue_free()
