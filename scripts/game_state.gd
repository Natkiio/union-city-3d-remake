extends Node
## Tiny cross-scene autoload: remembers where to place the player
## after a scene transition (e.g. walking through a house door).

var has_pending_spawn: bool = false
var pending_spawn_x: float = 0.0

func request_spawn(x: float) -> void:
	has_pending_spawn = true
	pending_spawn_x = x

func consume_spawn() -> float:
	has_pending_spawn = false
	return pending_spawn_x
