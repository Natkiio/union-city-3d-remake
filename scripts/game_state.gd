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
