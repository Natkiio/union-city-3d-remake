extends "res://tests/test_base.gd"
## Every room: containers never overlap each other (per row), stay inside the
## room and keep clear of door/stair/drop links.

func run() -> void:
	var rooms := 0
	var nudged := 0
	var second_row := 0
	var squeezed := 0
	var bad: Array = []
	var builder := LevelBuilder.new()
	for s in range(1, 17):
		for id in WorldData.rooms_of(s):
			var conts := WorldData.containers(id)
			if conts.is_empty():
				continue
			rooms += 1
			var w := LevelBuilder.px(WorldData.width_px(id))
			var lay := LevelBuilder.layout_containers(id, w)
			var moved := false
			var boxes: Array = []
			for i in conts.size():
				var h: float = lay[i].half
				if lay[i].scale < 1.0:
					squeezed += 1
				var x: float = lay[i].x
				if absf(x - LevelBuilder.px(conts[i].x)) > 0.01:
					moved = true
				if lay[i].row == 1:
					second_row += 1
				if x - h < 0.0 or x + h > w:
					bad.append("%s %s outside room" % [id, conts[i].key])
				for l in WorldData.links(id):
					var lx := clampf(LevelBuilder.px(l.x), 0.3, maxf(w - 0.3, 0.3))
					var lh := LevelBuilder.link_half_width(str(l.kind))
					if x + h > lx - lh and x - h < lx + lh:
						bad.append("%s %s hits link %s" % [id, conts[i].key, l.name])
				if WorldData.is_safehouse(id):
					for m in WorldData.markers(id, "abed"):
						var bx := clampf(LevelBuilder.px(m.x), 1.0, maxf(w - 1.0, 1.0))
						if x + h > bx - 1.0 and x - h < bx + 1.0:
							bad.append("%s %s blocks the bed" % [id, conts[i].key])
						break
				for n in WorldData.npcs(id):
					var nx := clampf(LevelBuilder.px(n.x), 0.4, maxf(w - 0.4, 0.4))
					if x + h > nx - LevelBuilder.NPC_CLEARANCE and x - h < nx + LevelBuilder.NPC_CLEARANCE:
						bad.append("%s %s blocks NPC %s" % [id, conts[i].key, n.npc_id])
				for j in boxes.size():
					var b: Array = boxes[j]
					if b[2] == lay[i].row and x + h + LevelBuilder.CONTAINER_GAP * 0.99 > b[0] and x - h - LevelBuilder.CONTAINER_GAP * 0.99 < b[1]:
						bad.append("%s %s overlaps %s" % [id, conts[i].key, b[3]])
				boxes.append([x - h, x + h, lay[i].row, conts[i].key])
			if moved:
				nudged += 1
	print("rooms with containers: %d, nudged: %d, second-row containers: %d, squeezed: %d" % [rooms, nudged, second_row, squeezed])
	for b in bad.slice(0, 20):
		print("  ", b)
	check("no container clashes in any room (%d rooms, %d nudged, %d on a second row, %d squeezed)" % [rooms, nudged, second_row, squeezed], bad.is_empty(), str(bad.size()))
	# One built level: node positions follow the layout and carry the container ids.
	var id2 := "l11_s3_b1_f1_r3"
	var level := builder.build(id2)
	root.add_child(level)
	await frames(2)
	var xs: Array = []
	for c in level.get_node("Things").get_children():
		if c.has_meta("container_id"):
			xs.append(c.position.x)
	check("built level has all containers", xs.size() == WorldData.containers(id2).size())
	level.queue_free()
