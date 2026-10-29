class_name Backdrop
extends RefCounted
## Flat parallax backdrop built from a parameter dictionary. Layers sit at fixed
## depths behind the Z=0 lane (sky -60, far -38, mid -20, near -7); with a
## perspective camera the depth gives the parallax for free.
##
## params (all optional): seed, width (default 160), center_x, sky_top, sky_bottom,
## orb ("sun"|"moon"|"none"), orb_x, far ("hills"|"skyline"|"none"), mid ("terraced"|"industrial"|"none"),
## features (Array: "shandon", "bridge", "cranes"), feature_x (Dictionary feature -> x),
## palette (Array[Color]) for terraced houses, near (Array of prop names), near_gap, haze (0..1).
## Presets: Backdrop.preset("cork_day"|"cork_dusk"|"docks_night").

const DEPTH := {"sky": -80.0, "far": -40.0, "mid": -20.0, "near": -7.0}
const PASTEL := [Color(0.72, 0.42, 0.45), Color(0.78, 0.68, 0.38), Color(0.4, 0.55, 0.62), Color(0.52, 0.62, 0.45),
	Color(0.7, 0.5, 0.33), Color(0.62, 0.5, 0.64), Color(0.7, 0.66, 0.58), Color(0.38, 0.46, 0.6)]


static func preset(name: String) -> Dictionary:
	match name:
		"cork_dusk":
			return {"seed": 7, "sky_top": Color(0.16, 0.14, 0.26), "sky_bottom": Color(0.78, 0.45, 0.32), "orb": "sun", "orb_x": -25.0,
				"far": "hills", "mid": "terraced", "features": ["shandon"], "feature_x": {"shandon": 6.0},
				"near": ["street_lamp", "bin", "car", "crate"], "haze": 0.5}
		"docks_night":
			return {"seed": 11, "sky_top": Color(0.03, 0.04, 0.09), "sky_bottom": Color(0.14, 0.17, 0.26), "orb": "moon", "orb_x": 20.0,
				"far": "skyline", "mid": "industrial", "features": ["cranes", "bridge"], "feature_x": {"cranes": -18.0, "bridge": 14.0},
				"near": ["street_lamp", "crate", "crate", "car"], "haze": 0.3}
	return {"seed": 3, "sky_top": Color(0.34, 0.42, 0.5), "sky_bottom": Color(0.74, 0.74, 0.68), "orb": "sun", "orb_x": 30.0,
		"far": "hills", "mid": "terraced", "features": ["shandon", "bridge"], "feature_x": {"shandon": 4.0, "bridge": 26.0},
		"near": ["street_lamp", "bin", "car", "crate", "street_lamp"], "haze": 0.55}


static func build(params: Dictionary = {}) -> Node3D:
	var p := preset("cork_day")
	for k in params:
		p[k] = params[k]
	var root := Node3D.new()
	root.name = "Backdrop"
	var rng := RandomNumberGenerator.new()
	rng.seed = int(p["seed"])
	var cx: float = p.get("center_x", 0.0)
	var w: float = p.get("width", 160.0)
	var x0 := cx - w * 0.5
	var x1 := cx + w * 0.5
	_layer(root, "sky", _sky(p, x0, x1), 0.0)
	var haze: Color = (p["sky_bottom"] as Color).lerp(p["sky_top"], 0.25)
	var far_items := _far(p, rng, x0, x1, haze)
	_layer(root, "far", far_items, float(p["haze"]) * 0.0, 0.18, 0.05)
	var mid_items := _mid(p, rng, x0, x1, haze)
	_layer(root, "mid", mid_items, 0.0, 0.05, 0.02)
	_layer(root, "near", _near(p, rng, x0, x1), 0.0, 0.01, 0.0)
	add_near_props(root, p)
	return root


static func _layer(root: Node3D, layer: String, items: Array, _unused: float = 0.0, step: float = 0.01, ow: float = 0.05) -> void:
	var n := Node3D.new()
	n.name = layer
	n.position.z = DEPTH[layer]
	if layer == "far":
		n.position.y = 3.5
	var mi := MeshInstance3D.new()
	if layer == "sky":
		mi.mesh = items[0]
	else:
		mi.mesh = CutShapes.make_mesh(items, Color(0.04, 0.04, 0.06), ow, step)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(mi)
	root.add_child(n)


static func _sky(p: Dictionary, x0: float, x1: float) -> Array:
	var top: Color = p["sky_top"]
	var bot: Color = p["sky_bottom"]
	var ymin := -10.0
	var ymax := 60.0
	var v := PackedVector3Array([Vector3(x0, ymin, 0), Vector3(x1, ymin, 0), Vector3(x1, ymax, 0), Vector3(x0, ymax, 0),
		Vector3(x0, 8, 0), Vector3(x1, 8, 0)])
	var c := PackedColorArray([bot, bot, top, top, bot.lerp(top, 0.12), bot.lerp(top, 0.12)])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_COLOR] = c
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 5, 0, 5, 4, 4, 5, 2, 4, 2, 3])
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	m.surface_set_material(0, CutShapes.material())
	# orb + clouds as an extra surface via make_mesh
	var extra: Array = []
	var orb: String = p.get("orb", "none")
	var ox: float = p.get("orb_x", 0.0)
	if orb == "sun":
		extra.append(CutShapes.item(CutShapes.ellipse(ox, 16, 3.2, 3.2, 20), bot.lightened(0.35)))
	elif orb == "moon":
		extra.append(CutShapes.item(CutShapes.ellipse(ox, 22, 2.2, 2.2, 20), Color(0.8, 0.82, 0.78)))
		extra.append(CutShapes.item(CutShapes.ellipse(ox + 0.8, 22.4, 1.9, 1.9, 20), top.lerp(bot, 0.3)))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(p["seed"]) + 99
	var cloud_c := bot.lerp(top, 0.45).lightened(0.05)
	for i in 14:
		var cx := rng.randf_range(x0, x1)
		var cy := rng.randf_range(14.0, 34.0)
		var w := rng.randf_range(5.0, 12.0)
		extra.append(CutShapes.item(PackedVector2Array([Vector2(cx - w, cy), Vector2(cx - w * 0.6, cy + 0.9), Vector2(cx, cy + 1.2),
			Vector2(cx + w * 0.7, cy + 0.7), Vector2(cx + w, cy), Vector2(cx + w * 0.5, cy - 0.6), Vector2(cx - w * 0.5, cy - 0.5)]), cloud_c))
	var em := CutShapes.make_mesh(extra, Color(0, 0, 0, 0), 0.0001, 0.02)
	for s in em.get_surface_count():
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, em.surface_get_arrays(s))
		m.surface_set_material(m.get_surface_count() - 1, CutShapes.material())
	return [m]


static func _tint(base: Color, haze: Color, amount: float) -> Color:
	return base.lerp(haze, amount)


static func _far(p: Dictionary, rng: RandomNumberGenerator, x0: float, x1: float, haze: Color) -> Array:
	var items: Array = []
	var kind: String = p.get("far", "hills")
	var col := _tint(Color(0.2, 0.22, 0.26), haze, 0.55)
	var feat: Array = p.get("features", [])
	var fx: Dictionary = p.get("feature_x", {})
	if kind == "hills":
		var pts := PackedVector2Array([Vector2(x0, -6)])
		var x := x0
		while x <= x1:
			pts.append(Vector2(x, 7.0 + 5.0 * sin(x * 0.045 + 1.0) + 3.0 * sin(x * 0.11) + rng.randf() * 0.6))
			x += 4.0
		pts.append(Vector2(x1, -6))
		items.append(CutShapes.item(pts, col))
		# distant ridge of houses on the hills
		var hx := x0
		while hx < x1:
			var hw := rng.randf_range(1.6, 2.8)
			var base := 7.0 + 5.0 * sin(hx * 0.045 + 1.0) + 3.0 * sin(hx * 0.11) - 0.3
			var hh := rng.randf_range(1.6, 3.2)
			items.append(CutShapes.item(PackedVector2Array([Vector2(hx, base), Vector2(hx + hw, base), Vector2(hx + hw, base + hh), Vector2(hx + hw * 0.5, base + hh + 0.9), Vector2(hx, base + hh)]), _tint(col, haze, 0.18).lerp(PASTEL[rng.randi() % PASTEL.size()], 0.14)))
			hx += hw + rng.randf_range(0.2, 1.4)
	elif kind == "skyline":
		var sx := x0
		while sx < x1:
			var bw := rng.randf_range(3.0, 7.0)
			var bh := rng.randf_range(6.0, 20.0)
			items.append(CutShapes.item(CutShapes.box(sx, -6, sx + bw, bh), _tint(col, haze, rng.randf_range(0.0, 0.2))))
			for r in int(bh / 3.0):
				if rng.randf() < 0.35:
					var wx := sx + rng.randf_range(0.5, bw - 1.2)
					items.append(CutShapes.item(CutShapes.box(wx, 2.0 + r * 2.8, wx + 0.7, 2.7 + r * 2.8), Color(0.85, 0.72, 0.4).lerp(haze, 0.3)))
			sx += bw + rng.randf_range(0.0, 1.0)
	if feat.has("shandon"):
		items.append_array(_shandon(fx.get("shandon", 0.0), col))
	if feat.has("cranes"):
		var cxx: float = fx.get("cranes", 0.0)
		for i in 3:
			items.append_array(_crane(cxx + i * 11.0, 17.0 - i * 2.0, _tint(Color(0.45, 0.2, 0.14), haze, 0.4)))
	return items


static func _shandon(x: float, col: Color) -> Array:
	var k := 0.6
	# stone tower with tiered, octagonal-style "pepper pot" top and a fish weathervane
	var stone := col.lightened(0.08)
	var roof := col.darkened(0.15)
	var it: Array = []
	it.append(CutShapes.item(CutShapes.box(x - 3.0, -6, x + 3.0, 6), stone))               # nave
	it.append(CutShapes.item(PackedVector2Array([Vector2(x - 3.4, 6), Vector2(x, 9.5), Vector2(x + 3.4, 6)]), roof))
	it.append(CutShapes.item(CutShapes.box(x + 3.0, -6, x + 6.4, 15), stone))               # tower
	it.append(CutShapes.item(CutShapes.box(x + 3.3, 15, x + 6.1, 19), stone.lightened(0.05)))   # belfry
	it.append(CutShapes.item(CutShapes.box(x + 3.7, 15.6, x + 4.5, 18.2), Color(0.08, 0.08, 0.1)))
	it.append(CutShapes.item(CutShapes.box(x + 5.0, 15.6, x + 5.8, 18.2), Color(0.08, 0.08, 0.1)))
	it.append(CutShapes.item(CutShapes.box(x + 3.6, 19, x + 5.8, 21.6), stone))             # drum
	it.append(CutShapes.item(CutShapes.ellipse(x + 4.7, 12.6, 0.7, 0.7, 10), Color(0.85, 0.82, 0.7)))   # clock
	it.append(CutShapes.item(PackedVector2Array([Vector2(x + 3.5, 21.6), Vector2(x + 4.7, 25.5), Vector2(x + 5.9, 21.6)]), roof))
	it.append(CutShapes.item(PackedVector2Array([Vector2(x + 4.6, 25.5), Vector2(x + 4.8, 25.5), Vector2(x + 4.74, 27.4), Vector2(x + 4.66, 27.4)]), roof))
	it.append(CutShapes.item(PackedVector2Array([Vector2(x + 4.1, 27.3), Vector2(x + 5.0, 27.7), Vector2(x + 5.4, 27.3), Vector2(x + 5.0, 27.0)]), Color(0.78, 0.65, 0.25)))
	for i in it.size():
		var q: PackedVector2Array = it[i]["p"]
		for j in q.size():
			q[j] = Vector2(q[j].x, q[j].y * k if q[j].y > 0 else q[j].y)
		it[i]["p"] = q
	return it


static func _crane(x: float, h: float, c: Color) -> Array:
	var it: Array = []
	it.append(CutShapes.item(CutShapes.box(x - 0.25, -6, x + 0.25, h), c))
	it.append(CutShapes.item(CutShapes.box(x - 0.9, -6, x - 0.55, h * 0.45), c))
	it.append(CutShapes.item(CutShapes.box(x - 4.0, h - 0.4, x + 9.0, h + 0.2), c))                 # jib
	it.append(CutShapes.item(CutShapes.box(x - 4.0, h - 1.8, x - 2.4, h - 0.4), c.darkened(0.2)))   # counterweight
	it.append(CutShapes.item(PackedVector2Array([Vector2(x - 0.25, h), Vector2(x, h + 2.4), Vector2(x + 0.25, h)]), c))
	it.append(CutShapes.item(CutShapes.box(x + 7.8, h * 0.45, x + 7.9, h - 0.4), c.darkened(0.3)))  # cable
	it.append(CutShapes.item(CutShapes.box(x + 7.4, h * 0.45 - 0.7, x + 8.3, h * 0.45), c.darkened(0.3)))
	return it


static func _mid(p: Dictionary, rng: RandomNumberGenerator, x0: float, x1: float, haze: Color) -> Array:
	var items: Array = []
	var kind: String = p.get("mid", "terraced")
	var feat: Array = p.get("features", [])
	var fx: Dictionary = p.get("feature_x", {})
	var bridge_x: float = fx.get("bridge", 1e9) if feat.has("bridge") else 1e9
	var bridge_w := 18.0
	var palette: Array = p.get("palette", PASTEL)
	var gap_lo := bridge_x - bridge_w * 0.5
	var gap_hi := bridge_x + bridge_w * 0.5
	var x := x0
	var night := (p["sky_top"] as Color).get_luminance() < 0.1
	while x < x1:
		if x > gap_lo - 3.0 and x < gap_hi:
			x = gap_hi
			continue
		if kind == "terraced":
			var hw := rng.randf_range(3.2, 4.8)
			var floors := 2 + (1 if rng.randf() < 0.12 else 0)
			var hh := floors * 2.9 + rng.randf_range(0.0, 0.8)
			var c: Color = palette[rng.randi() % palette.size()]
			c = _tint(c.darkened(0.15), haze, 0.15)
			if night:
				c = c.darkened(0.55)
			var pitched := rng.randf() < 0.75
			var roof_c := Color(0.17, 0.18, 0.21)
			items.append(CutShapes.item(CutShapes.box(x, 0, x + hw, hh), c))
			if pitched:
				items.append(CutShapes.item(PackedVector2Array([Vector2(x - 0.1, hh), Vector2(x + hw * 0.5, hh + 1.6), Vector2(x + hw + 0.1, hh)]), roof_c))
			else:
				items.append(CutShapes.item(CutShapes.box(x - 0.1, hh, x + hw + 0.1, hh + 0.35), roof_c.lightened(0.05)))
			if rng.randf() < 0.6:
				items.append(CutShapes.item(CutShapes.box(x + hw * 0.7, hh, x + hw * 0.7 + 0.45, hh + 1.7), c.darkened(0.3)))
			for f in floors:
				for col_i in 2:
					var wx := x + 0.5 + col_i * (hw - 1.6) / 1.0
					var wy := 1.0 + f * 2.8 + (1.2 if f == 0 else 0.0)
					if f == 0 and col_i == 0:
						items.append(CutShapes.item(CutShapes.box(x + 0.5, 0, x + 1.5, 2.1), c.darkened(0.45)))
						continue
					var lit := night and rng.randf() < 0.5
					items.append(CutShapes.item(CutShapes.box(wx - 0.05, wy - 0.05, wx + 1.0, wy + 1.35), c.lightened(0.35)))
					items.append(CutShapes.item(CutShapes.box(wx + 0.05, wy + 0.05, wx + 0.9, wy + 1.25), Color(0.9, 0.76, 0.4) if lit else Color(0.14, 0.17, 0.22)))
			x += hw
		else:
			var iw := rng.randf_range(6.0, 12.0)
			var ih := rng.randf_range(4.0, 9.0)
			var ic := _tint(Color(0.26, 0.26, 0.28), haze, 0.2).lightened(rng.randf_range(-0.05, 0.1))
			if night:
				ic = ic.darkened(0.4)
			items.append(CutShapes.item(CutShapes.box(x, 0, x + iw, ih), ic))
			items.append(CutShapes.item(CutShapes.box(x - 0.2, ih, x + iw + 0.2, ih + 0.4), ic.darkened(0.3)))
			if rng.randf() < 0.5:
				items.append(CutShapes.item(CutShapes.box(x + iw * 0.2, ih + 0.4, x + iw * 0.2 + 0.7, ih + 3.5), ic.darkened(0.2)))
			for k in int(iw / 1.8):
				items.append(CutShapes.item(CutShapes.box(x + 0.6 + k * 1.8, ih - 2.2, x + 1.7 + k * 1.8, ih - 1.2), Color(0.88, 0.74, 0.4) if night and rng.randf() < 0.4 else ic.darkened(0.45)))
			items.append(CutShapes.item(CutShapes.box(x + iw * 0.5 - 1.2, 0, x + iw * 0.5 + 1.2, 2.8), ic.darkened(0.5)))
			x += iw + rng.randf_range(0.0, 1.5)
	if feat.has("bridge"):
		items.append_array(_bridge(gap_lo, gap_hi, night))
	return items


static func _bridge(a: float, b: float, night: bool) -> Array:
	var it: Array = []
	var water := Color(0.14, 0.26, 0.3) if not night else Color(0.05, 0.09, 0.14)
	var stone := Color(0.4, 0.38, 0.34) if not night else Color(0.14, 0.14, 0.17)
	it.append(CutShapes.item(CutShapes.box(a - 6.0, -6, b + 6.0, -0.2), water))
	for i in 7:
		var sx := a + (b - a) * (i / 6.0)
		it.append(CutShapes.item(CutShapes.box(sx - 2.0, -0.55, sx + 2.0, -0.4), water.lightened(0.18)))
	# deck + arches
	var deck_y := 2.6
	it.append(CutShapes.item(CutShapes.box(a - 1.0, 0.0, b + 1.0, deck_y), stone))
	it.append(CutShapes.item(CutShapes.box(a - 1.0, deck_y, b + 1.0, deck_y + 0.7), stone.lightened(0.08)))
	var n := 3
	var span := (b - a) / n
	for k in n:
		var cx := a + span * (k + 0.5)
		var arch := PackedVector2Array()
		for i in 11:
			var ang := PI * i / 10.0
			arch.append(Vector2(cx + cos(ang) * span * 0.4, sin(ang) * 2.1))
		it.append(CutShapes.item(arch, water))
	return it


static func _near(p: Dictionary, rng: RandomNumberGenerator, x0: float, x1: float) -> Array:
	# the near layer is a mesh of kerb/pavement plus individually spawned props placed by the caller;
	# here only the pavement strip and a low wall are baked.
	var night := (p["sky_top"] as Color).get_luminance() < 0.1
	var pave := Color(0.3, 0.3, 0.32)
	var items: Array = [CutShapes.item(CutShapes.box(x0, -0.2, x1, 0.12), pave.darkened(0.3 if night else 0.0)),
		CutShapes.item(CutShapes.box(x0, 0.12, x1, 0.2), pave.lightened(0.1).darkened(0.3 if night else 0.0))]
	return items


## Spawns the near props (lamps, bins, cars, crates) as separate nodes under `root`. Call once after build().
static func add_near_props(root: Node3D, p: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(p.get("seed", 3)) + 5
	var list: Array = p.get("near", [])
	if list.is_empty():
		return
	var w: float = p.get("width", 160.0)
	var x := float(p.get("center_x", 0.0)) - w * 0.5 + 4.0
	var near: Node3D = root.get_node("near")
	var i := 0
	while x < float(p.get("center_x", 0.0)) + w * 0.5 - 4.0:
		var name: String = list[i % list.size()]
		var opts := {"ow": 0.012, "z_step": 0.004}
		if name == "car":
			opts["colour"] = Props.CAR_COLOURS[rng.randi() % Props.CAR_COLOURS.size()]
		var pr := Props.make(name, opts)
		pr.position = Vector3(x, 0.12, 0.0)
		near.add_child(pr)
		x += rng.randf_range(7.0, 14.0)
		i += 1
