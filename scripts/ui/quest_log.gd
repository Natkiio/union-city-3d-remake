class_name QuestLog
extends UIScreen
## Journal. Reads Quests.journal(): Array of {id, name, desc, state}. If the
## story workstream has not added it yet the log says so.

var entries: Array = []


func _init() -> void:
	screen_title = "Journal"
	panel_min = Vector2(560, 0)


func build() -> void:
	var q := get_tree().root.get_node_or_null("Quests")
	if entries.is_empty() and q != null and q.has_method("journal"):
		entries = q.journal()
	if entries.is_empty():
		body.add_child(UITheme.label("Nothing written down yet.", UITheme.FS_BODY, UITheme.TEXT_DIM))
	for e in entries:
		var done: bool = str(e.get("state", "")) in ["done", "complete", "completed"]
		body.add_child(UITheme.label(str(e.get("name", e.get("id", "?"))) + ("  (done)" if done else ""),
			UITheme.FS_BODY, UITheme.TEXT_DIM if done else UITheme.WARN))
		var d := UITheme.label(str(e.get("desc", "")), UITheme.FS_SMALL, UITheme.TEXT_DIM)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size.x = 520
		body.add_child(d)
	body.add_child(UITheme.button("Close", close))
