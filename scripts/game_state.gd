extends Node
## Tiny cross-scene autoload: remembers where to place the player
## after a scene transition (e.g. walking through a house door).

var has_pending_spawn: bool = false
var pending_spawn_x: float = 0.0

## Which weapon is equipped persists across scene reloads (entering/
## exiting a building, etc.) -- "fist" or a Weapon ref string, e.g.
## "glock". The player previously defaulted back to "fist" on every
## scene reload since equipped_weapon lived only on the per-scene
## player node; this is the single source of truth now (issues #29/#39).
var equipped_weapon: String = "fist"

func request_spawn(x: float) -> void:
	has_pending_spawn = true
	pending_spawn_x = x

func consume_spawn() -> float:
	has_pending_spawn = false
	return pending_spawn_x


## Wipes every stateful system (inventory, loot, stats, quests...) for a new
## run or after death. Systems join group "stateful" and implement reset().
func reset_run() -> void:
	has_pending_spawn = false
	equipped_weapon = "fist"
	for node in get_tree().get_nodes_in_group("stateful"):
		node.reset()
	_close_run_overlays()
	Events.run_reset.emit()


## Screens that belong to a run and live under the root (dialogue, cutscene,
## lockpick, shop) go with it; the autoload panels are closed.
func _close_run_overlays() -> void:
	for node in get_tree().get_nodes_in_group("run_overlay"):
		node.queue_free()
	var trunk := get_node_or_null("/root/TrunkUI")
	if trunk != null and trunk.visible and trunk.has_method("close"):
		trunk.close()
	var inv_ui := get_node_or_null("/root/InventoryUI")
	if inv_ui != null and inv_ui.visible and inv_ui.has_method("_close"):
		inv_ui._close()
