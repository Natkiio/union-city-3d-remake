class_name SetDressing
extends RefCounted
## Placeholder visuals for levels: flat coloured panels with dark outlines,
## sign labels and parallax backdrop layers, in the "flat cutouts in 3D" style.
## Purely visual: nothing here has collision.
##
## This is the seam for the cutout workstream's backdrop/prop kit. The level
## builder only calls the public methods below. To replace the look, provide
## res://scripts/visual/world_kit.gd extending SetDressing and overriding any
## of them; SetDressing.create() picks it up automatically.

const KIT_PATH := "res://scripts/visual/world_kit.gd"
const OUTLINE := Color(0.08, 0.07, 0.07)
const OUTLINE_PX := 0.045

var rng := RandomNumberGenerator.new()
var _mats: Dictionary = {}


static func create() -> SetDressing:
	if ResourceLoader.exists(KIT_PATH):
		var kit: Variant = load(KIT_PATH).new()
		if kit is SetDressing:
			return kit
	return SetDressing.new()


# --- primitives ---------------------------------------------------------------

func material(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 1.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
	_mats[key] = m
	return m


## A flat quad facing the camera (+Z), centred at `center`, with an optional
## dark outline drawn just behind it. Returns the coloured quad.
func panel(parent: Node3D, center: Vector3, size: Vector2, color: Color, outline: bool = true, node_name: String = "") -> MeshInstance3D:
	if outline:
		var o := MeshInstance3D.new()
		var oq := QuadMesh.new()
		oq.size = size + Vector2(OUTLINE_PX, OUTLINE_PX) * 2.0
		o.mesh = oq
		o.material_override = material(OUTLINE)
		o.position = center + Vector3(0, 0, -0.004)
		o.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(o)
	var mi := MeshInstance3D.new()
	if node_name != "":
		mi.name = node_name
	var q := QuadMesh.new()
	q.size = size
	mi.mesh = q
	mi.material_override = material(color)
	mi.position = center
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## A box (floors, ceilings, slabs). Visual only.
func slab(parent: Node3D, center: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = material(color)
	mi.position = center
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func label(parent: Node3D, pos: Vector3, text: String, font_size: int = 48, color: Color = Color(0.95, 0.93, 0.85)) -> Label3D:
	var l := WorldText.make(text, WorldText.Kind.SIGN, color, font_size)
	l.position = pos
	parent.add_child(l)
	return l


## A sign board with text: a panel plus a label in front of it.
func sign_board(parent: Node3D, pos: Vector3, text: String, board: Color = Color(0.16, 0.22, 0.2), font_size: int = 40) -> void:
	var w := maxf(0.6, text.length() * font_size * 0.006 * 0.62 + 0.3)
	panel(parent, pos, Vector2(w, font_size * 0.006 * 1.6), board)
	label(parent, pos + Vector3(0, 0, 0.01), text, font_size)


# --- streets --------------------------------------------------------------------

## Sky, far skyline and near rooftops. Layers sit far back so the perspective
## camera gives them parallax for free. `seed_value` keeps it stable per room.
func street_backdrop(parent: Node3D, width: float, seed_value: int) -> void:
	rng.seed = seed_value
	var span := width + 60.0
	panel(parent, Vector3(width * 0.5, 12.0, -60.0), Vector2(span * 2.5, 50.0), Color(0.45, 0.55, 0.66), false, "Sky")
	_skyline(parent, -2.0 - 30.0, -45.0, width + 30.0, Color(0.36, 0.42, 0.5), 6.0, 16.0, 5.0, 9.0)
	_skyline(parent, -20.0, -22.0, width + 20.0, Color(0.27, 0.3, 0.36), 4.0, 9.0, 3.0, 6.0)


## Open country (roads out of town, woods): hills and tree lines instead of
## a skyline.
func open_backdrop(parent: Node3D, width: float, seed_value: int) -> void:
	rng.seed = seed_value
	var span := width + 60.0
	panel(parent, Vector3(width * 0.5, 12.0, -60.0), Vector2(span * 2.5, 50.0), Color(0.5, 0.6, 0.68), false, "Sky")
	var x := -30.0
	while x < width + 30.0:
		var w := rng.randf_range(14.0, 26.0)
		var h := rng.randf_range(4.0, 8.0)
		var hill := panel(parent, Vector3(x + w * 0.5, h * 0.3 - 1.0, -45.0), Vector2(w, h), Color(0.38, 0.47, 0.4), false)
		hill.rotation.z = rng.randf_range(-0.08, 0.08)
		x += w * 0.7
	_trees(parent, -20.0, width + 20.0, -16.0, Color(0.16, 0.27, 0.18), 3.0, 6.0)
	_trees(parent, -12.0, width + 12.0, -6.5, Color(0.12, 0.22, 0.13), 3.5, 7.0)


func _trees(parent: Node3D, x0: float, x1: float, z: float, color: Color, min_h: float, max_h: float) -> void:
	var x := x0
	while x < x1:
		var h := rng.randf_range(min_h, max_h)
		var w := h * rng.randf_range(0.35, 0.55)
		panel(parent, Vector3(x, h * 0.25, z - 0.01), Vector2(0.25, h * 0.5), Color(0.25, 0.18, 0.12), false)
		var crown := panel(parent, Vector3(x, h * 0.62, z), Vector2(w, h * 0.75), color, false)
		crown.rotation.z = PI / 4.0 if rng.randf() < 0.5 else 0.0
		x += rng.randf_range(1.2, 3.5)


func _skyline(parent: Node3D, x0: float, z: float, x1: float, color: Color, min_h: float, max_h: float, min_w: float, max_w: float) -> void:
	var x := x0
	while x < x1:
		var w := rng.randf_range(min_w, max_w)
		var h := rng.randf_range(min_h, max_h)
		panel(parent, Vector3(x + w * 0.5, h * 0.5 - 1.0, z), Vector2(w, h), color, false)
		# a chimney or spire now and then
		if rng.randf() < 0.25:
			panel(parent, Vector3(x + w * rng.randf_range(0.2, 0.8), h - 1.0 + 0.8, z + 0.01), Vector2(0.5, 1.6), color, false)
		x += w + rng.randf_range(-0.5, 0.8)


## Road, kerb and pavement strips from the camera out to the facades.
func street_ground(parent: Node3D, width: float, facade_z: float) -> void:
	var x := width * 0.5
	var span := width + 40.0
	slab(parent, Vector3(x, -0.25, 5.0), Vector3(span, 0.5, 12.0), Color(0.24, 0.24, 0.26))
	slab(parent, Vector3(x, -0.2, (facade_z - 1.0) * 0.5 - 0.5), Vector3(span, 0.5, absf(facade_z) + 0.0), Color(0.5, 0.49, 0.46))
	# kerb line and road markings
	panel(parent, Vector3(x, 0.03, -1.0), Vector2(span, 0.06), Color(0.75, 0.74, 0.7), false)
	var dash := 0.0
	while dash < width + 20.0:
		var d := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(1.2, 0.12)
		d.mesh = q
		d.material_override = material(Color(0.85, 0.8, 0.45))
		d.rotation.x = -PI / 2.0
		d.position = Vector3(dash - 10.0, 0.005, 1.4)
		parent.add_child(d)
		dash += 3.0


const FLOOR_H := 2.7


## One building front around a door at `door_x`. `floors` sets the height;
## the door itself is drawn by link_visual().
func facade(parent: Node3D, x0: float, x1: float, z: float, floors: int, color: Color, title: String, seed_value: int, door_x: float = NAN) -> void:
	rng.seed = seed_value
	var n_floors := maxi(floors, 1)
	var h := 0.8 + FLOOR_H * n_floors
	var w := x1 - x0
	var cx := (x0 + x1) * 0.5
	if is_nan(door_x):
		door_x = cx
	panel(parent, Vector3(cx, h * 0.5, z), Vector2(w, h), color)
	panel(parent, Vector3(cx, h + 0.15, z + 0.01), Vector2(w + 0.3, 0.3), color.darkened(0.45))
	var trim := color.lightened(0.35)
	for f in n_floors:
		var y := 1.55 + f * FLOOR_H
		var n := maxi(1, int(w / 2.0))
		for i in n:
			var wx := x0 + (i + 0.5) * w / n
			if f == 0 and absf(wx - door_x) < 1.1:
				continue # the door owns this bay
			var lit := rng.randf() < 0.3
			panel(parent, Vector3(wx, y, z + 0.02), Vector2(0.9, 1.15), Color(0.85, 0.75, 0.4) if lit else Color(0.12, 0.15, 0.2))
			panel(parent, Vector3(wx, y - 0.65, z + 0.03), Vector2(1.1, 0.1), trim, false)
	if title != "":
		sign_board(parent, Vector3(door_x, 2.85, z + 0.05), title, color.darkened(0.6), 30)


## A plain wall, fence or hedge between buildings.
func filler(parent: Node3D, x0: float, x1: float, z: float, seed_value: int) -> void:
	rng.seed = seed_value
	var kind := rng.randi() % 3
	var w := x1 - x0
	if w <= 0.05:
		return
	match kind:
		0:
			panel(parent, Vector3((x0 + x1) * 0.5, 0.9, z), Vector2(w, 1.8), Color(0.42, 0.4, 0.38))
		1:
			panel(parent, Vector3((x0 + x1) * 0.5, 0.7, z), Vector2(w, 1.4), Color(0.2, 0.33, 0.2))
		_:
			panel(parent, Vector3((x0 + x1) * 0.5, 1.6, z), Vector2(w, 3.2), Color(0.5, 0.36, 0.3))


# --- interiors ------------------------------------------------------------------

const ROOM_COLOURS := {
	"kitchen": Color(0.62, 0.66, 0.52), "office": Color(0.55, 0.58, 0.62),
	"bathroom": Color(0.6, 0.7, 0.72), "bedroom": Color(0.6, 0.52, 0.58),
	"basement": Color(0.4, 0.39, 0.37), "store": Color(0.58, 0.55, 0.45),
	"medical": Color(0.7, 0.74, 0.72), "military": Color(0.42, 0.46, 0.36),
}


func room_colour(room_type: String, seed_value: int) -> Color:
	rng.seed = seed_value
	var base: Color = ROOM_COLOURS.get(room_type, Color(0.6, 0.55, 0.47))
	return base.lightened(rng.randf_range(-0.08, 0.08))


## Back wall, skirting, ceiling slab and the dark mass of the building
## around the room. `height` is the floor-to-ceiling height.
func interior_shell(parent: Node3D, width: float, height: float, back_z: float, wall: Color, seed_value: int) -> void:
	rng.seed = seed_value
	panel(parent, Vector3(width * 0.5, height * 0.5, back_z), Vector2(width, height), wall, false, "BackWall")
	panel(parent, Vector3(width * 0.5, 0.12, back_z + 0.01), Vector2(width, 0.24), wall.darkened(0.4), false)
	# floor and ceiling slabs, cut at the camera
	slab(parent, Vector3(width * 0.5, -0.3, back_z * 0.5 + 0.9), Vector3(width + 0.6, 0.6, absf(back_z) + 1.8), Color(0.33, 0.26, 0.2))
	slab(parent, Vector3(width * 0.5, height + 0.3, back_z * 0.5 + 0.4), Vector3(width + 0.6, 0.6, absf(back_z) + 0.8), Color(0.18, 0.17, 0.17))
	# building mass either side of the room
	var mass := Color(0.1, 0.1, 0.12)
	panel(parent, Vector3(-6.0, height * 0.5, back_z + 1.6), Vector2(12.0, height + 8.0), mass, false)
	panel(parent, Vector3(width + 6.0, height * 0.5, back_z + 1.6), Vector2(12.0, height + 8.0), mass, false)
	# a window or picture now and then
	var x := rng.randf_range(0.8, 2.0)
	while x < width - 1.0:
		if rng.randf() < 0.5:
			panel(parent, Vector3(x, 1.8, back_z + 0.02), Vector2(1.0, 0.9), Color(0.12, 0.14, 0.2))
		else:
			panel(parent, Vector3(x, 1.7, back_z + 0.02), Vector2(0.6, 0.45), wall.darkened(0.3))
		x += rng.randf_range(1.8, 3.2)


# --- links and props --------------------------------------------------------------

const LINK_COLOURS := {
	"door": Color(0.45, 0.3, 0.18), "room": Color(0.5, 0.34, 0.2), "entr": Color(0.3, 0.18, 0.12),
	"exit": Color(0.22, 0.36, 0.3), "sup": Color(0.55, 0.5, 0.42), "sdwn": Color(0.4, 0.36, 0.3),
	"drop": Color(0.08, 0.08, 0.08), "strt": Color(0.75, 0.62, 0.2), "area": Color(0.2, 0.45, 0.6),
	"uprm": Color(0.3, 0.42, 0.25), "dnrm": Color(0.3, 0.42, 0.25), "ltrm": Color(0.75, 0.62, 0.2),
	"rtrm": Color(0.75, 0.62, 0.2),
}


## The visual for a door, stair, exit or edge. Returns the mesh to highlight
## on hover.
func link_visual(parent: Node3D, kind: String, x: float, z: float, text: String, locked: bool) -> MeshInstance3D:
	var c: Color = LINK_COLOURS.get(kind, Color(0.45, 0.3, 0.18))
	var mesh: MeshInstance3D
	match kind:
		"sup", "sdwn":
			# a flight of steps climbing (up) or dropping (down) along the wall
			var dir := 1.0 if kind == "sup" else -1.0
			for i in 6:
				var sy := 0.25 + i * 0.4 if kind == "sup" else 2.25 - i * 0.4
				panel(parent, Vector3(x - 0.75 + i * 0.3, sy, z + 0.01 * i), Vector2(0.34, 0.12), c.darkened(0.3), false)
			mesh = panel(parent, Vector3(x, 1.2, z - 0.01), Vector2(1.6, 2.4), c)
			label(parent, Vector3(x, 2.65, z + 0.08), ("UP" if dir > 0 else "DOWN"), 36)
		"drop":
			mesh = panel(parent, Vector3(x, 0.4, z), Vector2(1.4, 0.8), c)
			label(parent, Vector3(x, 1.1, z + 0.08), "DROP", 32)
		"strt", "ltrm", "rtrm", "area":
			mesh = panel(parent, Vector3(x, 1.6, z), Vector2(0.9, 0.9), c)
			panel(parent, Vector3(x, 0.6, z - 0.02), Vector2(0.12, 1.4), Color(0.3, 0.3, 0.3), false)
			label(parent, Vector3(x, 1.6, z + 0.04), "MAP" if kind == "area" else ">>", 40)
		_:
			mesh = panel(parent, Vector3(x, 1.05, z), Vector2(1.0, 2.1), c)
			panel(parent, Vector3(x + 0.33, 1.0, z + 0.01), Vector2(0.09, 0.09), Color(0.85, 0.75, 0.4), false)
			if kind == "entr":
				panel(parent, Vector3(x, 2.25, z + 0.01), Vector2(1.3, 0.2), c.darkened(0.5), false)
	if locked:
		panel(parent, Vector3(x, 1.25, z + 0.03), Vector2(0.3, 0.3), Color(0.7, 0.15, 0.1))
	if text != "":
		label(parent, Vector3(x, 2.85, z + 0.06), text, 28)
	return mesh


## A boarded-up door or window (an entrance with nothing behind it).
func boarded(parent: Node3D, x: float, z: float) -> void:
	panel(parent, Vector3(x, 1.05, z), Vector2(1.0, 2.1), Color(0.15, 0.12, 0.1))
	for i in 3:
		var b := panel(parent, Vector3(x, 0.5 + i * 0.6, z + 0.02), Vector2(1.2, 0.18), Color(0.55, 0.42, 0.25))
		b.rotation.z = 0.25 if i % 2 == 0 else -0.2


## Placeholder furniture for a container the loot workstream has not built yet.
func container_prop(parent: Node3D, x: float, z: float, desc: String, label_lift: float = 0.0) -> MeshInstance3D:
	var c := Color(0.45, 0.36, 0.26)
	var lower := desc.to_lower()
	var size := Vector2(0.9, 0.9)
	if lower.contains("fridge") or lower.contains("closet") or lower.contains("locker") or lower.contains("bookshelf"):
		size = Vector2(0.8, 1.8)
		c = Color(0.82, 0.82, 0.8) if lower.contains("fridge") else Color(0.4, 0.3, 0.22)
	elif lower.contains("trunk") or lower.contains("car"):
		size = Vector2(2.2, 1.0)
		c = Color(0.5, 0.15, 0.12)
	elif lower.contains("bin") or lower.contains("trash") or lower.contains("dumpster"):
		c = Color(0.2, 0.32, 0.22)
	var mesh := panel(parent, Vector3(x, size.y * 0.5, z), size, c)
	label(parent, Vector3(x, size.y + 0.2 + label_lift, z + 0.05), desc, 24)
	return mesh


## Placeholder person marker for an NPC the story workstream has not built yet.
func npc_marker(parent: Node3D, x: float, z: float, text: String, facing: float) -> void:
	panel(parent, Vector3(x, 0.8, z), Vector2(0.55, 1.6), Color(0.25, 0.4, 0.65))
	panel(parent, Vector3(x, 1.8, z + 0.01), Vector2(0.42, 0.42), Color(0.85, 0.7, 0.55))
	panel(parent, Vector3(x + 0.12 * facing, 1.82, z + 0.02), Vector2(0.08, 0.08), OUTLINE, false)
	label(parent, Vector3(x, 2.3, z + 0.05), text, 26, Color(0.7, 0.9, 1.0))


func dead_body(parent: Node3D, x: float, z: float) -> void:
	var b := panel(parent, Vector3(x, 0.15, z), Vector2(1.7, 0.3), Color(0.3, 0.28, 0.3))
	b.rotation.z = 0.04
	panel(parent, Vector3(x - 0.3, 0.02, z - 0.01), Vector2(1.2, 0.06), Color(0.35, 0.05, 0.05), false)


func bed(parent: Node3D, x: float, z: float) -> MeshInstance3D:
	panel(parent, Vector3(x - 0.85, 0.55, z - 0.01), Vector2(0.15, 0.8), Color(0.3, 0.2, 0.15), false)
	return panel(parent, Vector3(x, 0.35, z), Vector2(1.9, 0.5), Color(0.75, 0.75, 0.82))
