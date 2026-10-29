extends "res://tests/test_base.gd"
## Map screen layout: distinct positions, everything inside the canvas, no
## overlapping labels, hit-testing through the same transform.

func run() -> void:
	var w: Node = autoload("World")
	var nodes: Array = w.map_nodes()
	check("16 sections on the map", nodes.size() == 16, str(nodes.size()))
	var seen := {}
	var distinct := true
	for n in nodes:
		if n.pos == null:
			distinct = false
			continue
		var key := str(n.pos)
		if seen.has(key):
			distinct = false
		seen[key] = true
	check("every section has a distinct map position", distinct)

	var m := MapScreen.new()
	m.nodes_override = nodes
	m.current_id = "16"
	root.add_child(m)
	await frames(3)
	var canvas_rect := Rect2(Vector2.ZERO, MapScreen.CANVAS_SIZE)
	var inside := true
	var overlap := ""
	var rects := {}
	for n in m.map_nodes:
		var p: Vector2 = m.node_screen_pos(n)
		var lr: Rect2 = m.label_rect(n)
		if not canvas_rect.encloses(lr) or not canvas_rect.grow(-MapScreen.NODE_RADIUS).has_point(p):
			inside = false
		rects[str(n.id)] = lr
	check("every node and label fits inside the canvas", inside)
	var ids: Array = rects.keys()
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			if (rects[ids[i]] as Rect2).intersects(rects[ids[j]]):
				overlap += "%s/%s " % [ids[i], ids[j]]
		# labels must not sit on another node's dot either
		for n in m.map_nodes:
			if str(n.id) != ids[i] and (rects[ids[i]] as Rect2).grow(MapScreen.NODE_RADIUS).has_point(m.node_screen_pos(n)):
				overlap += "label%s-dot%s " % [ids[i], n.id]
	check("no two labels overlap, none covers a dot", overlap == "", overlap)
	var spread := m.layout_bounds()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for n in m.map_nodes:
		lo = lo.min(m.node_screen_pos(n))
		hi = hi.max(m.node_screen_pos(n))
	check("nodes spread across most of the canvas", (hi.x - lo.x) > MapScreen.CANVAS_SIZE.x * 0.6 and (hi.y - lo.y) > MapScreen.CANVAS_SIZE.y * 0.6, str(hi - lo))
	check("layout bounds not degenerate", spread.size.x > 1.0 and spread.size.y > 1.0)

	var hit_ok := true
	for n in m.map_nodes:
		if m.node_at(m.node_screen_pos(n)) != str(n.id):
			hit_ok = false
		if m.node_at(m.node_screen_pos(n) + Vector2(5, -4)) != str(n.id):
			hit_ok = false
	check("node_at returns the node drawn at each spot", hit_ok)
	check("node_at on empty canvas returns nothing", m.node_at(Vector2(2, 2)) == "")

	# travel hours come from the original's manhattan rule (World), not the display layout
	check("cost to Bishopstown from Ballincollig is 2 h", m.cost_to("9") == 2, str(m.cost_to("9")))
	m.select("9")
	check("info shows name, danger and time", m.info.text.contains("Bishopstown") and m.info.text.contains("danger") and (m.info.text.contains("Travel time") or m.info.text.contains("Not open")))
	m.queue_free()
	await frames(2)
