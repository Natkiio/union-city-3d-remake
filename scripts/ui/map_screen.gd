class_name MapScreen
extends UIScreen
## Map and travel screen. Draws World.map_nodes(): an Array of Dictionaries
## {id, name, pos (Vector2 or [x, y]), danger, unlocked, connections: [ids]}.
## Click a node to select it, see the cost, press Travel. Travel goes through
## World.travel_to(id). Cost preview = round(manhattan distance / 200), in
## game hours (the original's sleepWait units; verify).

signal travelled(section_id: String)

const COST_DIVISOR := 200.0
const CANVAS_SIZE := Vector2(900, 560)
const PAD := Vector2(90, 60)
const LABEL_FS := 14
const NODE_RADIUS := 11.0

## Tests inject nodes here; empty means ask World.
var nodes_override: Array = []
var map_nodes: Array = []
var current_id: String = ""
var selected_id: String = ""
var canvas: Control
var info: Label
var travel_button: Button
## "Arrive at the far end": only for sections with an endLoc (World.enter_location(id, true)).
var end_check: CheckBox
var last_error: String = ""


func _init() -> void:
	screen_title = "Cork"
	panel_min = Vector2(940, 0)


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
	return GameFlow.world(get_tree())


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
	end_check = CheckBox.new()
	end_check.text = "Arrive at the far end"
	end_check.visible = false
	body.add_child(end_check)
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
	if n.has("hours"):
		return int(n.get("hours"))
	return travel_cost(current_pos(), to_vec(n.get("pos")))


func select(id: String) -> void:
	var n := node_by_id(id)
	if n.is_empty():
		return
	selected_id = id
	var unlocked: bool = bool(n.get("unlocked", true))
	var reachable: bool = bool(n.get("travelable", true))
	var txt := "%s   danger %d" % [n.get("name", id), int(n.get("danger", 0))]
	if id == current_id:
		txt += "   (YOU ARE HERE)"
	var h := cost_to(id)
	if id == current_id:
		txt += "\nYou are here."
	elif not unlocked:
		txt += "\nNot open to you yet."
	elif not reachable:
		txt += "\nThere is no way there from the map."
	else:
		txt += "\nTravel time: %d hour%s" % [h, "" if h == 1 else "s"]
	var desc := str(n.get("desc", ""))
	if desc != "":
		txt += "\n" + desc
	info.text = txt
	travel_button.disabled = (not unlocked) or (not reachable) or id == current_id
	travel_button.text = "Travel" if travel_button.disabled else "Travel (%d h)" % h
	end_check.visible = not travel_button.disabled and bool(n.get("has_end", false))
	if not end_check.visible:
		end_check.button_pressed = false
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
	if end_check != null and end_check.visible and end_check.button_pressed:
		w.travel_to(id, true)
	else:
		w.travel_to(id)
	travelled.emit(id)
	close()
	return true


func _canvas_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var hit := node_at(event.position)
		if hit != "":
			select(hit)


## Fits the raw node positions into the canvas: uniform scale, centred, with
## padding for labels. Returns the screen position of a raw position.
func layout_bounds() -> Rect2:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for n in map_nodes:
		var p := to_vec(n.get("pos"))
		lo = lo.min(p)
		hi = hi.max(p)
	if lo.x == INF:
		return Rect2(Vector2.ZERO, Vector2.ONE)
	return Rect2(lo, hi - lo)


func to_screen(p: Vector2) -> Vector2:
	var b := layout_bounds()
	var avail := CANVAS_SIZE - PAD * 2.0
	var sc := minf(avail.x / maxf(b.size.x, 1.0), avail.y / maxf(b.size.y, 1.0))
	var off := PAD + (avail - b.size * sc) * 0.5
	return off + (p - b.position) * sc


func node_screen_pos(n: Dictionary) -> Vector2:
	return to_screen(to_vec(n.get("pos")))


func _label_lines(n: Dictionary) -> Array:
	var id := str(n.get("id"))
	var lines: Array = [str(n.get("name", id))]
	if id == current_id:
		lines.append("YOU ARE HERE")
	elif not bool(n.get("unlocked", true)):
		lines.append("locked")
	return lines


## Screen-space rectangle of the label block (below the dot) for overlap tests.
func label_rect(n: Dictionary) -> Rect2:
	var font := ThemeDB.fallback_font
	var lines := _label_lines(n)
	var w := 0.0
	for l in lines:
		w = maxf(w, font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FS).x)
	var h := lines.size() * (LABEL_FS + 3.0)
	var p := node_screen_pos(n)
	return Rect2(p + Vector2(-w * 0.5, NODE_RADIUS + 5.0), Vector2(w, h))


func node_at(p: Vector2) -> String:
	var best := ""
	var best_d := NODE_RADIUS + 8.0
	for n in map_nodes:
		var d := node_screen_pos(n).distance_to(p)
		if d <= best_d:
			best_d = d
			best = str(n.get("id"))
	return best


func _danger_color(d: int) -> Color:
	return UITheme.GOOD.lerp(UITheme.BAD, clampf(d / 20.0, 0.0, 1.0))


func _draw_map() -> void:
	var font := ThemeDB.fallback_font
	canvas.draw_rect(Rect2(Vector2.ZERO, canvas.size), Color(0.04, 0.045, 0.05), true)
	canvas.draw_rect(Rect2(Vector2.ZERO, canvas.size), UITheme.PANEL_EDGE, false, 1.0)
	for n in map_nodes:
		var a := node_screen_pos(n)
		for c in n.get("connections", []):
			var o := node_by_id(str(c))
			if o.is_empty():
				continue
			var open := bool(n.get("unlocked", true)) and bool(o.get("unlocked", true))
			canvas.draw_line(a, node_screen_pos(o), Color(0.42, 0.42, 0.40) if open else Color(0.2, 0.2, 0.2), 2.0 if open else 1.0)
	for n in map_nodes:
		var pos := node_screen_pos(n)
		var id := str(n.get("id"))
		var unlocked: bool = bool(n.get("unlocked", true))
		var col := _danger_color(int(n.get("danger", 0))) if unlocked else Color(0.25, 0.25, 0.25)
		canvas.draw_circle(pos, NODE_RADIUS, col)
		if id == selected_id:
			canvas.draw_arc(pos, NODE_RADIUS + 5, 0, TAU, 28, Color.WHITE, 2.0)
		if id == current_id:
			canvas.draw_arc(pos, NODE_RADIUS + 5, 0, TAU, 28, Color(0.3, 0.8, 1.0), 3.0)
		var r := label_rect(n)
		var lines := _label_lines(n)
		for i in lines.size():
			var c: Color = UITheme.TEXT if unlocked else UITheme.TEXT_DIM
			if i == 1:
				c = Color(0.3, 0.8, 1.0) if id == current_id else UITheme.TEXT_DIM
			canvas.draw_string(font, Vector2(r.position.x, r.position.y + LABEL_FS + i * (LABEL_FS + 3.0) - 3.0),
				lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FS, c)
