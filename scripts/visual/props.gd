class_name Props
extends RefCounted
## Small reusable flat props (street lamp, bin, car, crate, door, window).
## Each returns a Node3D whose origin is at ground level / bottom-centre, drawn
## side-on in the XY plane. Keep props off the Z=0 lane (recess them in Z).

const NAMES := ["street_lamp", "bin", "car", "crate", "door", "window"]
const CAR_COLOURS := [Color(0.42, 0.14, 0.13), Color(0.18, 0.28, 0.4), Color(0.55, 0.55, 0.5), Color(0.15, 0.15, 0.17), Color(0.5, 0.42, 0.18)]


static func make(prop: String, opts: Dictionary = {}) -> Node3D:
	var items: Array = []
	match prop:
		"street_lamp": items = _lamp()
		"bin": items = _bin(opts)
		"car": items = _car(opts)
		"crate": items = _crate()
		"door": items = _door(opts)
		"window": items = _window(opts)
		_:
			push_warning("Props: unknown prop %s" % prop)
	var n := Node3D.new()
	n.name = prop
	var mi := MeshInstance3D.new()
	mi.mesh = CutShapes.make_mesh(items, opts.get("outline", CutShapes.OUTLINE_COL), opts.get("ow", CutShapes.OUTLINE_W), opts.get("z_step", CutShapes.Z_STEP))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(mi)
	return n


static func _lamp() -> Array:
	var iron := Color(0.14, 0.15, 0.17)
	return [CutShapes.item(CutShapes.box(-0.2, 0.0, 0.2, 0.22), iron),
		CutShapes.item(CutShapes.box(-0.05, 0.0, 0.05, 4.4), iron),
		CutShapes.item(PackedVector2Array([Vector2(-0.05, 4.3), Vector2(0.05, 4.4), Vector2(0.9, 4.55), Vector2(0.9, 4.45)]), iron),
		CutShapes.item(PackedVector2Array([Vector2(0.65, 4.46), Vector2(1.15, 4.46), Vector2(1.05, 4.32), Vector2(0.75, 4.32)]), iron.lightened(0.1)),
		CutShapes.item(CutShapes.box(0.72, 4.27, 1.08, 4.33), Color(0.95, 0.85, 0.5))]


static func _bin(opts: Dictionary) -> Array:
	var c: Color = opts.get("colour", Color(0.2, 0.3, 0.25))
	return [CutShapes.item(PackedVector2Array([Vector2(-0.3, 0.0), Vector2(0.3, 0.0), Vector2(0.34, 0.85), Vector2(-0.34, 0.85)]), c),
		CutShapes.item(CutShapes.box(-0.38, 0.85, 0.38, 0.95), c.lightened(0.12)),
		CutShapes.item(CutShapes.box(-0.2, 0.2, 0.2, 0.28), c.darkened(0.25))]


static func _car(opts: Dictionary) -> Array:
	var c: Color = opts.get("colour", CAR_COLOURS[0])
	var glass := Color(0.45, 0.55, 0.6)
	var body := PackedVector2Array([Vector2(-2.1, 0.35), Vector2(-2.15, 0.9), Vector2(-1.5, 1.0), Vector2(-0.9, 1.5), Vector2(0.7, 1.52),
		Vector2(1.3, 1.0), Vector2(2.0, 0.95), Vector2(2.15, 0.6), Vector2(2.1, 0.35)])
	return [CutShapes.item(body, c),
		CutShapes.item(PackedVector2Array([Vector2(-0.8, 1.0), Vector2(-0.45, 1.42), Vector2(0.0, 1.42), Vector2(0.0, 1.0)]), glass),
		CutShapes.item(PackedVector2Array([Vector2(0.1, 1.0), Vector2(0.1, 1.42), Vector2(0.62, 1.42), Vector2(1.05, 1.0)]), glass),
		CutShapes.item(CutShapes.box(-2.1, 0.3, 2.1, 0.42), c.darkened(0.4)),
		CutShapes.item(CutShapes.ellipse(-1.2, 0.36, 0.36, 0.36, 12), Color(0.07, 0.07, 0.08)),
		CutShapes.item(CutShapes.ellipse(-1.2, 0.36, 0.16, 0.16, 8), Color(0.5, 0.5, 0.52)),
		CutShapes.item(CutShapes.ellipse(1.25, 0.36, 0.36, 0.36, 12), Color(0.07, 0.07, 0.08)),
		CutShapes.item(CutShapes.ellipse(1.25, 0.36, 0.16, 0.16, 8), Color(0.5, 0.5, 0.52)),
		CutShapes.item(CutShapes.box(1.95, 0.62, 2.12, 0.78), Color(0.85, 0.78, 0.5))]


static func _crate() -> Array:
	var w := Color(0.42, 0.3, 0.17)
	return [CutShapes.item(CutShapes.box(-0.45, 0.0, 0.45, 0.9), w),
		CutShapes.item(CutShapes.box(-0.45, 0.0, -0.36, 0.9), w.darkened(0.25)),
		CutShapes.item(CutShapes.box(0.36, 0.0, 0.45, 0.9), w.darkened(0.25)),
		CutShapes.item(CutShapes.box(-0.45, 0.4, 0.45, 0.5), w.darkened(0.25)),
		CutShapes.item(PackedVector2Array([Vector2(-0.4, 0.05), Vector2(-0.3, 0.05), Vector2(0.4, 0.85), Vector2(0.3, 0.85)]), w.darkened(0.15))]


static func _door(opts: Dictionary) -> Array:
	var c: Color = opts.get("colour", Color(0.4, 0.14, 0.12))
	return [CutShapes.item(CutShapes.box(-0.6, 0.0, 0.6, 2.25), c.darkened(0.45)),
		CutShapes.item(CutShapes.box(-0.5, 0.0, 0.5, 2.15), c),
		CutShapes.item(CutShapes.box(-0.36, 1.2, 0.36, 1.95), c.lightened(0.1)),
		CutShapes.item(CutShapes.box(-0.36, 0.2, 0.36, 1.0), c.lightened(0.1)),
		CutShapes.item(CutShapes.ellipse(0.38, 1.1, 0.05, 0.05, 6), Color(0.75, 0.65, 0.3))]


static func _window(opts: Dictionary) -> Array:
	var lit: bool = opts.get("lit", false)
	var glass := Color(0.9, 0.78, 0.42) if lit else Color(0.2, 0.25, 0.3)
	var frame := Color(0.82, 0.8, 0.74)
	return [CutShapes.item(CutShapes.box(-0.55, 0.0, 0.55, 1.3), frame),
		CutShapes.item(CutShapes.box(-0.47, 0.08, -0.03, 1.22), glass),
		CutShapes.item(CutShapes.box(0.03, 0.08, 0.47, 1.22), glass),
		CutShapes.item(CutShapes.box(-0.62, -0.08, 0.62, 0.0), frame.darkened(0.2))]
