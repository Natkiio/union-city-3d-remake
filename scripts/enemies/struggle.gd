class_name Struggle
extends RefCounted
## The key-mash minigame when a zombie grabs the player. The player script
## feeds presses (A / D) via press(); the zombie owns the instance
## (zombie.struggle) and reads `damage_mod` for its bites.

signal escaped

const PRESSES_MIN: int = 3
const PRESSES_MAX: int = 8
## Bites land at half damage while grabbed.
const DAMAGE_MOD: float = 0.5
## Distance (world units) the zombie is shoved back on escape.
const SHOVE_DISTANCE: float = 1.0

var presses_needed: int = PRESSES_MAX
var presses: int = 0
var active: bool = false


## clamp(round(level * 2 - strength * 2), 3, 8)
static func presses_for(level: int, strength: int) -> int:
	return clampi(roundi(level * 2.0 - strength * 2.0), PRESSES_MIN, PRESSES_MAX)


func begin(level: int, strength: int) -> void:
	presses_needed = presses_for(level, strength)
	presses = 0
	active = true


## One key press. Returns true when this press frees the player.
func press(_side: String = "") -> bool:
	if not active:
		return false
	presses += 1
	if presses >= presses_needed:
		active = false
		escaped.emit()
		return true
	return false


func cancel() -> void:
	active = false


func damage_mod() -> float:
	return DAMAGE_MOD if active else 1.0
