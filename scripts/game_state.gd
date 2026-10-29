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

## Player vitals survive scene reloads (room changes, travel) and saves. The
## player node writes them every physics frame; a fresh player reads them back
## instead of starting at full health (issue #30). has_vitals=false means a
## new run: the player starts full.
var has_vitals: bool = false
var vit_health: float = 0.0
var vit_perm_health: float = 0.0
var vit_stamina: float = 0.0


func _ready() -> void:
	add_to_group("stateful")


func store_vitals(h: float, perm: float, stam: float) -> void:
	has_vitals = true
	vit_health = h
	vit_perm_health = perm
	vit_stamina = stam


func reset() -> void:
	has_vitals = false


func to_dict() -> Dictionary:
	return {"has_vitals": has_vitals, "health": vit_health, "perm_health": vit_perm_health, "stamina": vit_stamina}


func from_dict(d: Dictionary) -> void:
	has_vitals = bool(d.get("has_vitals", false))
	vit_health = float(d.get("health", 0.0))
	vit_perm_health = float(d.get("perm_health", 0.0))
	vit_stamina = float(d.get("stamina", 0.0))
	for p in get_tree().get_nodes_in_group("player"):
		if p.has_method("restore_vitals"):
			p.restore_vitals()


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
	Events.run_reset.emit()
