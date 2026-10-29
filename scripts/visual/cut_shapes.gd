class_name CutShapes
extends RefCounted
## Polygon helpers and the flat "cutout" mesh builder.
## A part mesh has two surfaces: dark outlines behind, coloured fills in front.
## Colours are vertex colours, so every part shares one unshaded material.

const OUTLINE_COL := Color(0.055, 0.045, 0.05)
const OUTLINE_W := 0.011
const Z_STEP := 0.004

static var _mat: StandardMaterial3D


static func material() -> StandardMaterial3D:
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat.vertex_color_use_as_albedo = true
		_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _mat


static func ellipse(cx: float, cy: float, rx: float, ry: float, n: int = 14) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * i / n
		pts.append(Vector2(cx + cos(a) * rx, cy + sin(a) * ry))
	return pts


static func box(x0: float, y0: float, x1: float, y1: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)])


## Capsule hanging down from the origin: top radius w_top/2, bottom radius w_bot/2, length len.
static func capsule(length: float, w_top: float, w_bot: float, n: int = 5) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var r1 := w_top * 0.5
	var r2 := w_bot * 0.5
	for i in n + 1:
		var a := PI - PI * i / n
		pts.append(Vector2(cos(a) * r1, sin(a) * r1))
	for i in n + 1:
		var a2 := -PI * i / n
		pts.append(Vector2(cos(a2) * r2, -length + sin(a2) * r2))
	return pts


## Points on an ellipse arc around (cx, cy); angle 0 = +X, PI/2 = up.
static func arc(cx: float, cy: float, rx: float, ry: float, a0: float, a1: float, n: int = 8) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n + 1:
		var a := lerpf(a0, a1, float(i) / n)
		pts.append(Vector2(cx + cos(a) * rx, cy + sin(a) * ry))
	return pts


static func item(poly: PackedVector2Array, col: Color) -> Dictionary:
	return {"p": poly, "c": col}


static func shift(poly: PackedVector2Array, d: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for v in poly:
		out.append(v + d)
	return out


static func scaled(poly: PackedVector2Array, s: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for v in poly:
		out.append(v * s)
	return out


static func rotated(poly: PackedVector2Array, a: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for v in poly:
		out.append(v.rotated(a))
	return out


static func _tris(poly: PackedVector2Array) -> PackedInt32Array:
	var idx := Geometry2D.triangulate_polygon(poly)
	if idx.is_empty():
		for i in range(1, poly.size() - 1):
			idx.append_array(PackedInt32Array([0, i, i + 1]))
	return idx


## items: Array of {p: PackedVector2Array, c: Color}, drawn in order (later on top).
static func make_mesh(items: Array, outline_col: Color = OUTLINE_COL, ow: float = OUTLINE_W, z_step: float = Z_STEP) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var ov := PackedVector3Array()
	var oc := PackedColorArray()
	var oi := PackedInt32Array()
	var fv := PackedVector3Array()
	var fc := PackedColorArray()
	var fi := PackedInt32Array()
	var k := 0
	for it in items:
		var poly: PackedVector2Array = it["p"]
		if poly.size() < 3:
			continue
		if Geometry2D.is_polygon_clockwise(poly):
			poly = poly.duplicate()
			poly.reverse()
		var z := k * z_step
		k += 1
		# outline
		var grown: Array = Geometry2D.offset_polygon(poly, ow, Geometry2D.JOIN_ROUND)
		for g in grown:
			var gp: PackedVector2Array = g
			if Geometry2D.is_polygon_clockwise(gp):
				continue
			var base := ov.size()
			for v in gp:
				ov.append(Vector3(v.x, v.y, z - z_step * 0.5))
				oc.append(outline_col)
			for t in _tris(gp):
				oi.append(base + t)
		# fill
		var fb := fv.size()
		var col: Color = it["c"]
		for v in poly:
			fv.append(Vector3(v.x, v.y, z))
			fc.append(col)
		for t in _tris(poly):
			fi.append(fb + t)
	for s in [[ov, oc, oi], [fv, fc, fi]]:
		if s[0].is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = s[0]
		arrays[Mesh.ARRAY_COLOR] = s[1]
		arrays[Mesh.ARRAY_INDEX] = s[2]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, material())
	return mesh
