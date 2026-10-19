extends CanvasLayer
## Tiny HUD: inventory count, weight, and last picked up item.
## Press "toggle_inventory" (I) for the full inventory screen.

const LOW_HEALTH_FRACTION: float = 0.3
const HEALTH_FILL_NORMAL := Color(0.2, 0.7, 0.3)
const HEALTH_FILL_LOW := Color(0.85, 0.15, 0.15)

@onready var label: Label = $Label
@onready var health_bar: ProgressBar = $HealthBar
@onready var health_label: Label = $HealthBar/HealthLabel
@onready var health_fill: StyleBoxFlat = health_bar.get_theme_stylebox("fill")

var player = null
var shown_health: float = -1.0
var shown_max_health: float = -1.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # keep the HP readout live while paused (death screen)
	Inventory.item_added.connect(_on_item_added)
	Inventory.inventory_changed.connect(_on_inventory_changed)
	_refresh("")

func _process(_delta: float) -> void:
	if not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	# Player has no max-health property yet, so read the script constant.
	var max_health: float = player.MAX_HEALTH
	if player.health == shown_health and max_health == shown_max_health:
		return
	shown_health = player.health
	shown_max_health = max_health
	_refresh_health()

func _on_item_added(item_name: String) -> void:
	_refresh(item_name)

func _on_inventory_changed() -> void:
	_refresh("")

func _refresh(last_item: String) -> void:
	var text := "Items: %d (%.1f lbs)  [I] Inventory" % [Inventory.item_count(), Inventory.total_weight()]
	if last_item != "":
		text += "\nPicked up: %s" % last_item
	label.text = text

func _refresh_health() -> void:
	health_bar.max_value = shown_max_health
	health_bar.value = shown_health
	health_label.text = "HP %d / %d" % [ceili(shown_health), shown_max_health]
	var low := shown_health < shown_max_health * LOW_HEALTH_FRACTION
	health_fill.bg_color = HEALTH_FILL_LOW if low else HEALTH_FILL_NORMAL
