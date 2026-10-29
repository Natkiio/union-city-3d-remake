class_name Playtime
extends RefCounted
## Real seconds spent in the current run. SaveGame ticks it while the tree is
## not paused and writes it into the save header.

var seconds: float = 0.0


func tick(delta: float) -> void:
	seconds += maxf(delta, 0.0)


func reset() -> void:
	seconds = 0.0


## "1h 05m" / "12m 03s" for slot pickers.
static func format(total_seconds: float) -> String:
	var s := int(total_seconds)
	var h := s / 3600
	var m := (s % 3600) / 60
	if h > 0:
		return "%dh %02dm" % [h, m]
	return "%dm %02ds" % [m, s % 60]
