class_name PickGame
extends RefCounted
## Pure lockpick minigame logic (ORIGINAL_ANALYSIS section 10), no nodes.
##
## Pins sit at a height between PIN_TOP (-90) and PIN_BOTTOM (-25). Holding the
## push key raises the current pin, releasing lets it fall. Pressing lock tests
## whether the pin is inside its sweet spot [center - half, center + half]. A hit
## moves to the next pin (the last one opens the lock); a miss drops the
## previous pin and the current one and steps back one pin (two on a very hard
## lock past pin 2). Rise speed and fall speed are our own tuning (the original
## animates tweens) **(verify)**.

const PIN_TOP := -90.0
const PIN_BOTTOM := -25.0
const RANGE_TOP := -85.0
const RANGE_BOTTOM := -35.0
const PUSH_SPEED := 150.0
const FALL_SPEED := 50.0

enum Outcome { NONE, HIT, MISS, COMPLETE }

var diff: String = "normal"
var half_width: float = 10.0
var centers: Array = []   # sweet spot centre per pin
var heights: Array = []   # current pin heights
var current: int = 0
var complete: bool = false
var misses: int = 0


## Builds a lock: pin count and sweet spot width follow the difficulty and the
## player's adjusted security skill; centres are random, nudged by luck.
static func create(adjusted_security: int, luck: int, lock_diff: String, rng: RandomNumberGenerator) -> PickGame:
	var g := PickGame.new()
	g.diff = lock_diff
	g.half_width = Locks.half_width(adjusted_security, lock_diff)
	var k := Locks.diff_k(lock_diff)
	var span := int(absf(RANGE_TOP - RANGE_BOTTOM))
	for i in Locks.pin_count(lock_diff):
		var c := RANGE_BOTTOM - (LootRules.rnd(rng, span) + 15.0 / k + LootRules.rnd(rng, luck))
		g.centers.append(clampf(c, RANGE_TOP, RANGE_BOTTOM))
		g.heights.append(PIN_BOTTOM)
	return g


func pin_count() -> int:
	return centers.size()


func in_spot(pin: int, y: float) -> bool:
	return y >= centers[pin] - half_width and y <= centers[pin] + half_width


## Advances the current pin: up while `push_held`, down otherwise. Other pins
## settle at the bottom.
func tick(dt: float, push_held: bool) -> void:
	if complete:
		return
	var y: float = heights[current]
	if push_held:
		y = maxf(PIN_TOP, y - PUSH_SPEED * dt)
	else:
		y = minf(PIN_BOTTOM, y + FALL_SPEED * dt)
	heights[current] = y


func lock_pin() -> int:
	if complete:
		return Outcome.NONE
	if in_spot(current, heights[current]):
		if current >= centers.size() - 1:
			complete = true
			return Outcome.COMPLETE
		current += 1
		return Outcome.HIT
	misses += 1
	if current > 0:
		heights[current - 1] = PIN_BOTTOM
		heights[current] = PIN_BOTTOM
		if diff == "very hard" and current > 1:
			heights[current - 2] = PIN_BOTTOM
			current -= 1
		current -= 1
	return Outcome.MISS
