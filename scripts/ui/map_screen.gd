class_name MapScreen
extends UIScreen
## Map and travel screen. Draws World.map_nodes(): an Array of Dictionaries
## {id, name, pos (Vector2 or [x, y]), danger, unlocked, connections: [ids]}.
## Click a node to select it, see the cost, press Travel. Travel goes through
## World.travel_to(id). Cost preview = round(manhattan distance / 200), in
## game hours (the original's sleepWait units; verify).

signal travelled(section_id: String)

const COST_DIVISOR := 200.0
const CANVAS_SIZE := Vector2(660, 400)
const NODE_RADIUS := 11.0

## Tests inject nodes here; empty means ask World.
var nodes_override: Array = []
var map_nodes: Array = []
var current_id: String = ""
var selected_id: String = ""
var canvas: Control
var info: Label
var travel_button: Button
var last_error: String = ""


func _init() -> void:
	screen_title = "Cork"
	panel_min = Vector2(700, 0)


## Fallback layout used by tests and until the world workstream lands.
static func mock_nodes() -> Array:
	return [
		{"id": "9", "name": "Bishopstown", "pos": Vector2(180, 300), "danger": 4, "unlocked": true, "connections": ["12", "8"]},
		{"id": "12", "name": "City Centre", "pos": Vector2(360, 220), "danger": 9, "unlocked": true, "connections": ["9", "11", "10", "5"]},
		{"id": "11", "name": "Shandon", "pos": Vector2(340, 90), "danger": 11, "unlocked": true, "connections": ["12"]},
		{"id": "10", "name": "Kent Station", "pos": Vector2(480, 180), "danger": 0, "unlocked": false, "connections": ["12", "6"]},
		{"id": "5", "name": "Páirc Uí Chaoimh", "pos": Vector2(520, 290), "danger": 10, "unlocked": true, "connections": ["12", "6"]},
		{"id": "6", "name": "Cobh", "pos": Vector2(600, 330), "danger": 16, "unlocked": false, "connections": ["5", "10"]},
		{"id": "8", "name": "Tramore Valley", "pos": Vector2(300, 340), "danger": 0, "unlocked": true, "connections": ["9"]},
	]


static func to_vec(p: Variant) -> Vector2:
	if p is Vector2:
		return p
	if p is Array and p.size() >= 2:
		return Vector2(float(p[0]), float(p[1]))
	return Vector2.ZERO


static func travel_cost(a: Vector2, b: Vector2) -> int:
	return int(round((absf(a.x - b.x) + absf(a.y - b.y)) / COST_DIVISOR))


func _world() -> Node:
	return get_tree().root.get_node_or_null("World")


func build() -> void:
	var w := _world()
	if not nodes_override.is_empty():
		map_nodes = nodes_override
	elif w != null and w.has_method("map_nodes") and not (w.map_nodes() as Array).is_empty():
		map_nodes = w.map_nodes()
	else:
		map_nodes = mock_nodes()
	if current_id == "" and w != null and "current" in w and w.current is Dictionary:
		current_id = str(w.current.get("section", ""))
	canvas = Control.new()
	canvas.custom_minimum_size = CANVAS_SIZE
	canvas.draw.connect(_draw_map)
	canvas.gui_input.connect(_canvas_input)
	canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	body.add_child(canvas)
	info = UITheme.label("Pick a place on the map.", UITheme.FS_BODY, UITheme.TEXT_DIM)
	body.add_child(info)
	var row := HBoxContainer.new()
	travel_button = UITheme.button("Travel", travel)
	travel_button.disabled = true
	row.add_child(travel_button)
	row.add_child(UITheme.button("Close", close))
	body.add_child(row)
	canvas.queue_redraw()


func node_by_id(id: String) -> Dictionary:
	for n in map_nodes:
		if str(n.get("id")) == id:
			return n
	return {}


func current_pos() -> Vector2:
	var c := node_by_id(current_id)
	return to_vec(c.get("pos")) if not c.is_empty() else Vector2.ZERO


func cost_to(id: String) -> int:
	var n := node_by_id(id)
	if n.is_empty() or current_id == "":
		return 0
	return travel_cost(current_pos(), to_vec(n.get("pos")))


func select(id: String) -> void:
	var n := node_by_id(id)
	if n.is_empty():
		return
	selected_id = id
	var unlocked: bool = bool(n.get("unlocked", true))
	var txt := "%s   danger %d" % [n.get("name", id), int(n.get("danger", 0))]
	if id == current_id:
		txt += "\nYou are here."
	elif not unlocked:
		txt += "\nNot open to you yet."
	else:
		var h := cost_to(id)
		txt += "\nTravel time: %d hour%s" % [h, "" if h == 1 else "s"]
	info.text = txt
	travel_button.disabled = (not unlocked) or id == current_id
	canvas.queue_redraw()


func travel() -> bool:
	if selected_id == "" or travel_button.disabled:
		return false
	var w := _world()
	if w == null or not w.has_method("travel_to"):
		last_error = "Travel is not available yet."
		info.text = last_error
		return false
	var id := selected_id
	w.travel_to(id)
	travelled.emit(id)
	close()
	return true


func _canvas_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var hit := node_at(event.position)
		if hit != "":
			select(hit)


func node_at(p: Vector2) -> String:
	for n in map_nodes:
		if to_vec(n.get("pos")).distance_to(p) <= NODE_RADIUS + 6.0:
			return str(n.get("id"))
	return ""


func _danger_color(d: int) -> Color:
	return UITheme.GOOD.lerp(UITheme.BAD, clampf(d / 20.0, 0.0, 1.0))


func _draw_map() -> void:
	var font := ThemeDB.fallback_font
	canvas.draw_rect(Rect2(Vector2.ZERO, canvas.size), Color(0.04, 0.045, 0.05), true)
	canvas.draw_rect(Rect2(Vector2.ZERO, canvas.size), UITheme.PANEL_EDGE, false, 1.0)
	for n in map_nodes:
		var a := to_vec(n.get("pos"))
		for c in n.get("connections", []):
			var o := node_by_id(str(c))
			if not o.is_empty() and str(n.get("id")) < str(o.get("id")):
				canvas.draw_line(a, to_vec(o.get("pos")), Color(0.3, 0.3, 0.3), 2.0)
	for n in map_nodes:
		var pos := to_vec(n.get("pos"))
		var id := str(n.get("id"))
		var unlocked: bool = bool(n.get("unlocked", true))
		var col := _danger_color(int(n.get("danger", 0))) if unlocked else Color(0.25, 0.25, 0.25)
		canvas.draw_circle(pos, NODE_RADIUS, col)
		if id == selected_id:
			canvas.draw_arc(pos, NODE_RADIUS + 5, 0, TAU, 28, Color.WHITE, 2.0)
		if id == current_id:
			canvas.draw_arc(pos, NODE_RADIUS + 5, 0, TAU, 28, UITheme.WARN, 2.0)
		var name_text := str(n.get("name", id))
		canvas.draw_string(font, pos + Vector2(-60, -NODE_RADIUS - 6), name_text, HORIZONTAL_ALIGNMENT_CENTER,
			120, UITheme.FS_SMALL, UITheme.TEXT if unlocked else UITheme.TEXT_DIM)
