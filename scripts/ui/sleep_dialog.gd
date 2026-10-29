class_name SleepDialog
extends UIScreen
## Sleep / wait dialog. Offered only where World.current.safehouse is true.
## Sleep: Survival.sleep_hours(h). Wait: Survival.wait_hours(h). Both also
## heal the player per hour (player.rest, the original's sleepWait) and ask
## SaveGame for an autosave afterwards.

signal rested(kind: String, hours: int)

const MAX_HOURS := 12

var hours: int = 6
var hours_label: Label


static func available(tree: SceneTree) -> bool:
	var w := GameFlow.world(tree)
	if w == null or not ("current" in w) or not (w.current is Dictionary):
		return false
	return bool(w.current.get("safehouse", false))


func _init() -> void:
	screen_title = "Rest"
	panel_min = Vector2(340, 0)


func build() -> void:
	var row := HBoxContainer.new()
	row.add_child(UITheme.button("-", func(): set_hours(hours - 1)))
	row.get_child(0).custom_minimum_size = Vector2(44, 40)
	hours_label = UITheme.label("", UITheme.FS_HEAD)
	hours_label.custom_minimum_size.x = 140
	hours_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(hours_label)
	row.add_child(UITheme.button("+", func(): set_hours(hours + 1)))
	row.get_child(2).custom_minimum_size = Vector2(44, 40)
	body.add_child(row)
	body.add_child(UITheme.button("Sleep", func(): do_rest("sleep")))
	body.add_child(UITheme.button("Wait", func(): do_rest("wait")))
	body.add_child(UITheme.button("Cancel", close))
	set_hours(hours)


func set_hours(h: int) -> void:
	hours = clampi(h, 1, MAX_HOURS)
	hours_label.text = "%d hour%s" % [hours, "" if hours == 1 else "s"]


func do_rest(kind: String) -> void:
	var s := get_tree().root.get_node_or_null("Survival")
	if s == null:
		return
	if kind == "sleep":
		s.sleep_hours(hours)
	else:
		s.wait_hours(hours)
	var p := get_tree().get_first_node_in_group("player")
	if p != null and p.has_method("rest"):
		p.rest(hours)
	rested.emit(kind, hours)
	var sg := GameFlow.save_api()
	if sg != null and sg.has_method("notify_rest_finished"):
		# After the dialog has closed and unpaused, or the autosave is refused.
		sg.call_deferred("notify_rest_finished")
	close()
