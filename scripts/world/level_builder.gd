class_name LevelBuilder
extends RefCounted
## Builds a playable 2.5D Level for any room id straight from the data
## (WorldData): no per-section scenes. Streets get a road, facades with
## entrances, street-edge and map exits and a parallax backdrop; rooms get a
## side-view shell with doors, stairs, drops and room links. Containers and
## NPCs come from the room record.
##
## World layout rule (ROADMAP.md): the player and zombies own the Z=0 lane.
## The only solid bodies built here are the floor (under the lane) and the two
## end walls that bound the room; everything else is visual or an Area3D.

const CONTAINER_SCENE := "res://scenes/loot/container.tscn"
const NPC_SCENE := "res://scenes/story/npc.tscn"

const STREET_FACADE_Z := -4.0
const STREET_PROP_Z := -2.0
const INTERIOR_BACK_Z := -2.4
const INTERIOR_PROP_Z := -1.7
const NPC_Z := -1.1
## Interior floor-to-ceiling height in units.
const ROOM_HEIGHT := 3.4
## Trigger box for links: reaches from the visual back to just past the lane.
const TRIGGER_WIDTH := 1.2
const TRIGGER_FRONT_Z := 0.8
const HOVER_LAYER := 2

var dressing: SetDressing
## Where containers and NPCs come from: a path (used only if the file exists,
## the loot and story workstreams add them) or a PackedScene (tests).
var container_scene: Variant = CONTAINER_SCENE
var npc_scene: Variant = NPC_SCENE


func _init(kit: SetDressing = null) -> void:
	dressing = kit if kit != null else SetDressing.create()


static func px(v: float) -> float:
	return v / WorldData.PX_PER_UNIT


static func room_seed(id: String) -> int:
	var r := WorldData.room_def(id)
	if r.has("seed"):
		return int(r.seed) + id.hash() % 997
	var p := WorldData.parse(id)
	# setupRoom's fallback seed
	return int(p.section) * 1000 + p.street * 1000 + p.building * 100 + p.floor * 10 + p.room


## Builds the level for `id`. Returns null for an unknown room. The result is
## detached; the caller adds it to the tree.
func build(id: String) -> Level:
	if not WorldData.has_room(id):
		push_warning("LevelBuilder: unknown room %s" % id)
		return null
	var level := Level.new()
	level.name = "Level_" + id
	level.room_id = id
	level.width_px = WorldData.width_px(id)
	level.outdoors = WorldData.is_outdoors(id)
	level.safehouse = WorldData.is_safehouse(id)
	level.danger = WorldData.danger(id)
	var w := px(level.width_px)

	var dressing_root := Node3D.new()
	dressing_root.name = "Dressing"
	level.add_child(dressing_root)
	var actors := Node3D.new()
	actors.name = "Actors"
	level.add_child(actors)
	var links_root := Node3D.new()
	links_root.name = "Links"
	level.add_child(links_root)
	var things := Node3D.new()
	things.name = "Things"
	level.add_child(things)

	_build_collision(level, w)
	if level.outdoors:
		_build_street(level, dressing_root, id, w)
	else:
		_build_interior(level, dressing_root, id, w)
	_build_links(level, links_root, id, w)
	_build_containers(things, id, w, level.outdoors)
	_build_npcs(things, id, w)
	_build_extras(dressing_root, links_root, id, w, level)
	return level


# --- collision -----------------------------------------------------------------

func _build_collision(level: Level, w: float) -> void:
	var floor_body := StaticBody3D.new()
	floor_body.name = "Floor"
	floor_body.add_to_group("level_floor")
	var fs := CollisionShape3D.new()
	var fb := BoxShape3D.new()
	fb.size = Vector3(w + 4.0, 1.0, 9.0)
	fs.shape = fb
	fs.position = Vector3(w * 0.5, -0.5, -1.5)
	floor_body.add_child(fs)
	level.add_child(floor_body)
	for side in [0, 1]:
		var wall := StaticBody3D.new()
		wall.name = "BoundLeft" if side == 0 else "BoundRight"
		wall.add_to_group("level_bounds")
		var ws := CollisionShape3D.new()
		var wb := BoxShape3D.new()
		wb.size = Vector3(0.4, 8.0, 4.0)
		ws.shape = wb
		ws.position = Vector3(-0.2 if side == 0 else w + 0.2, 4.0, 0.0)
		wall.add_child(ws)
		level.add_child(wall)


# --- streets -------------------------------------------------------------------

func _build_street(level: Level, root: Node3D, id: String, w: float) -> void:
	var seed_value := room_seed(id)
	if WorldData.markers(id, "entr").is_empty():
		dressing.open_backdrop(root, w, seed_value)
	else:
		dressing.street_backdrop(root, w, seed_value)
	dressing.street_ground(root, w, STREET_FACADE_Z)
	var p := WorldData.parse(id)
	# Building fronts: one per entrance marker, filler between them.
	var fronts: Array = []
	for m in WorldData.markers(id, "entr"):
		var bn := int(str(m.name).substr(4))
		var bdef := WorldData.building_def(WorldData.with_parts(id, {"building": bn}))
		var floors := 0
		for k in bdef:
			if k.begins_with("f") and k.substr(1).is_valid_int():
				floors = maxi(floors, int(k.substr(1)))
		fronts.append({"x": px(m.x), "bn": bn, "floors": maxi(floors, 1 + bn % 2), "name": str(bdef.get("name", ""))})
	fronts.sort_custom(func(a, b): return a.x < b.x)
	var cursor := -12.0
	for i in fronts.size():
		var f: Dictionary = fronts[i]
		var half := 3.2
		var left: float = f.x - half
		var right: float = f.x + half
		if i > 0:
			left = maxf(left, (fronts[i - 1].x + f.x) * 0.5 + 0.1)
		if i < fronts.size() - 1:
			right = minf(right, (fronts[i + 1].x + f.x) * 0.5 - 0.1)
		dressing.filler(root, cursor, left, STREET_FACADE_Z + 0.3, seed_value + i * 31)
		var colour := _facade_colour(seed_value + f.bn * 7)
		dressing.facade(root, left, right, STREET_FACADE_Z, f.floors, colour, _short(f.name), seed_value + f.bn * 13, f.x)
		cursor = right
	if not fronts.is_empty():
		dressing.filler(root, cursor, w + 12.0, STREET_FACADE_Z + 0.3, seed_value + 999)
	var street := WorldData.street_name(id)
	if street != "":
		dressing.sign_board(root, Vector3(1.2, 2.6, STREET_PROP_Z - 0.4), street, Color(0.1, 0.3, 0.18), 36)
		dressing.sign_board(root, Vector3(maxf(w - 1.2, 1.2), 2.6, STREET_PROP_Z - 0.4), street, Color(0.1, 0.3, 0.18), 36)


func _facade_colour(seed_value: int) -> Color:
	var palette := [Color(0.62, 0.42, 0.32), Color(0.72, 0.66, 0.52), Color(0.45, 0.5, 0.56),
		Color(0.55, 0.6, 0.48), Color(0.7, 0.55, 0.45), Color(0.5, 0.42, 0.5), Color(0.78, 0.74, 0.66)]
	return palette[posmod(seed_value, palette.size())]


static func _short(text: String) -> String:
	return text if text.length() <= 26 else text.substr(0, 25) + "."


# --- interiors -----------------------------------------------------------------

func _build_interior(level: Level, root: Node3D, id: String, w: float) -> void:
	var seed_value := room_seed(id)
	var wall := dressing.room_colour(WorldData.room_type(id), seed_value)
	dressing.interior_shell(root, w, ROOM_HEIGHT, INTERIOR_BACK_Z, wall, seed_value)
	var title := WorldData.place_name(id)
	var rname := str(WorldData.room_def(id).get("name", ""))
	if rname != "" and rname != "Outside" and rname.to_upper() != title.to_upper():
		title = "%s - %s" % [title, rname] if title != "" else rname
	if level.safehouse:
		title = "SAFEHOUSE: " + title if title != "" else "SAFEHOUSE"
	if title != "":
		dressing.label(root, Vector3(w * 0.5, ROOM_HEIGHT - 0.3, INTERIOR_BACK_Z + 0.05), _short(title.to_upper()), 30,
				Color(0.6, 1.0, 0.65) if level.safehouse else Color(0.95, 0.92, 0.8))


# --- links -----------------------------------------------------------------------

func _build_links(level: Level, root: Node3D, id: String, w: float) -> void:
	var visual_z := STREET_FACADE_Z + 0.06 if level.outdoors else INTERIOR_BACK_Z + 0.03
	for link in WorldData.links(id):
		var x := clampf(px(link.x), 0.3, maxf(w - 0.3, 0.3))
		var z := visual_z
		var kind: String = link.kind
		if kind in ["strt", "area", "ltrm", "rtrm"]:
			z = STREET_PROP_Z
		if kind == "entr" and link.target == "":
			dressing.boarded(level.get_node("Dressing"), x, z)
			continue
		var text := ""
		match kind:
			"room":
				text = str(link.name).substr(4)
			"uprm":
				text = "PATH UP"
			"dnrm":
				text = "PATH DOWN"
			"exit":
				text = "EXIT"
			"area":
				text = ""
		var mesh := dressing.link_visual(level.get_node("Dressing"), kind, x, z, text, link.locked)
		add_link(root, link, x, z, mesh)


## Adds the WorldLink trigger (and hover area) for a resolved link at x.
func add_link(root: Node3D, link: Dictionary, x: float, visual_z: float, mesh: MeshInstance3D) -> WorldLink:
	var area := WorldLink.new()
	area.name = "Link_" + str(link.name)
	area.link = link
	area.collision_layer = 0
	area.collision_mask = 1
	var depth := TRIGGER_FRONT_Z - visual_z
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(TRIGGER_WIDTH, 2.4, depth)
	cs.shape = box
	cs.position = Vector3(0, 1.2, visual_z + depth * 0.5)
	area.add_child(cs)
	area.position = Vector3(x, 0, 0)
	var prompt := Label3D.new()
	prompt.name = "Prompt"
	prompt.font_size = 36
	prompt.pixel_size = 0.006
	prompt.outline_size = 10
	prompt.modulate = Color(1, 0.95, 0.6)
	prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	prompt.no_depth_test = true
	prompt.position = Vector3(0, 2.4, 0.2)
	area.add_child(prompt)
	area.prompt = prompt
	root.add_child(area)
	prompt.text = area.prompt_text()
	if mesh != null:
		_add_hover(area, mesh, visual_z)
	return area


func _add_hover(area: WorldLink, mesh: MeshInstance3D, visual_z: float) -> void:
	var hover := Area3D.new()
	hover.name = "Hover"
	hover.collision_layer = HOVER_LAYER
	hover.collision_mask = 0
	hover.monitoring = false
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var size := Vector2(1.0, 2.0)
	if mesh.mesh is QuadMesh:
		size = (mesh.mesh as QuadMesh).size
	box.size = Vector3(size.x, size.y, 0.2)
	cs.shape = box
	cs.position = Vector3(mesh.position.x - area.position.x, mesh.position.y, visual_z + 0.1)
	hover.add_child(cs)
	hover.set_script(load("res://scripts/hoverable.gd"))
	area.add_child(hover)
	hover.set("target_mesh_path", hover.get_path_to(mesh))


# --- containers and people ----------------------------------------------------------

static func _scene(source: Variant) -> PackedScene:
	if source is PackedScene:
		return source
	if source is String and source != "" and ResourceLoader.exists(source):
		return load(source)
	return null


func _build_containers(root: Node3D, id: String, w: float, outdoors: bool) -> void:
	var scene := _scene(container_scene)
	var z := STREET_PROP_Z if outdoors else INTERIOR_PROP_Z
	var rtype := WorldData.room_type(id)
	var dz := WorldData.danger(id)
	var last_x := -INF
	var lift := 0.0
	for c in WorldData.containers(id):
		var x := clampf(px(c.x), 0.4, maxf(w - 0.4, 0.4))
		if scene != null:
			var node: Node3D = scene.instantiate()
			node.name = "Container_" + str(c.key)
			node.position = Vector3(x, 0, z)
			if node.has_method("setup"):
				node.setup(c.id, c.def, rtype, dz)
			node.set_meta("container_id", c.id)
			root.add_child(node)
		else:
			var marker := Node3D.new()
			marker.name = "Container_" + str(c.key)
			marker.position = Vector3(x, 0, z)
			marker.set_meta("container_id", c.id)
			marker.set_meta("placeholder", true)
			marker.add_to_group("world_container")
			root.add_child(marker)
			lift = 0.0 if absf(x - last_x) > 1.0 or lift >= 0.6 else lift + 0.3
			last_x = x
			dressing.container_prop(marker, 0.0, 0.0, str(c.def.get("desc", c.key)), lift)


func _build_npcs(root: Node3D, id: String, w: float) -> void:
	var scene := _scene(npc_scene)
	for n in WorldData.npcs(id):
		var x := clampf(px(n.x), 0.4, maxf(w - 0.4, 0.4))
		var facing := -1.0 if n.facing == "left" else 1.0
		if scene != null:
			var node: Node3D = scene.instantiate()
			node.name = "NPC_" + n.npc_id
			node.position = Vector3(x, 0, NPC_Z)
			if node.has_method("setup"):
				node.setup(n.npc_id)
			node.set_meta("npc_id", n.npc_id)
			root.add_child(node)
		else:
			var marker := Node3D.new()
			marker.name = "NPC_" + n.npc_id
			marker.position = Vector3(x, 0, NPC_Z)
			marker.set_meta("npc_id", n.npc_id)
			marker.set_meta("placeholder", true)
			marker.add_to_group("world_npc")
			root.add_child(marker)
			var display := str(WorldData._data().entry("npc", n.npc_id).get("name", n.npc_id))
			dressing.npc_marker(marker, 0.0, 0.0, display if display != "" else n.npc_id, facing)


## Beds (safehouses only, like the original), dead bodies and story triggers.
func _build_extras(root: Node3D, links_root: Node3D, id: String, w: float, level: Level) -> void:
	var z := STREET_PROP_Z if level.outdoors else INTERIOR_PROP_Z - 0.2
	if level.safehouse:
		for m in WorldData.markers(id, "abed"):
			var x := clampf(px(m.x), 1.0, maxf(w - 1.0, 1.0))
			var mesh := dressing.bed(root, x, z)
			add_link(links_root, {"name": m.name, "kind": "bed", "target": "", "label": "USE BED",
					"locked": false, "x": m.x}, x, z, mesh)
			break
	var bi := 0
	for m in WorldData.markers(id, "body"):
		dressing.dead_body(root, clampf(px(m.x), 0.5, w - 0.5), z + 0.3 + 0.05 * bi)
		bi += 1
	for m in WorldData.markers(id, "trig"):
		var t := Area3D.new()
		t.name = "Trigger_" + str(m.name)
		t.add_to_group("world_trigger")
		t.set_meta("trigger_id", str(m.name).substr(4))
		t.collision_layer = 0
		t.collision_mask = 1
		t.monitorable = false
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(maxf(px(float(m.right) - float(m.left)), 0.5), 3.0, 2.0)
		cs.shape = box
		cs.position = Vector3(0, 1.5, 0)
		t.add_child(cs)
		t.position = Vector3(px((float(m.left) + float(m.right)) * 0.5), 0, 0)
		links_root.add_child(t)
