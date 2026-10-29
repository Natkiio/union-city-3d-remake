class_name WorldData
extends RefCounted
## Pure lookups over the location tables. No nodes, no state: everything the
## level builder and the World autoload need to know about a section or room
## comes from here, so it can be tested headless.
##
## Sources (all through Data, so data/cork overrides apply):
##   world/l<N>          street -> building -> floor -> room records (sec. 12)
##   world/layout/l<N>   room width, floor marker and named markers, extracted
##                       from the SWF room symbols by tools/extract_layout.py
##   world/map.json      world map position of each section
##   sections            names and map connections
##
## A room id is the original's symbol name, "l16_s3_b1_f1_r1": section 16,
## street 3, building 1 (0 = the street itself), floor 1, room 1. Positions in
## the data are in Flash pixels; the remake uses 100 px = 1 unit (as zombies).

const PX_PER_UNIT := 100.0
## moveEdgeBuffer: where the player lands when entering from a room's edge.
const EDGE_BUFFER_PX := 50.0
const FALLBACK_STREET_WIDTH_PX := 3000.0
const FALLBACK_ROOM_WIDTH_PX := 600.0
## round(manhattan map distance / 200) hours of travel (travelTo -> sleepWait).
const TRAVEL_PX_PER_HOUR := 200.0
const SECTION_COUNT := 16

## Marker prefixes that move the player somewhere.
const LINK_KINDS := ["door", "entr", "exit", "sup", "sdwn", "drop", "strt", "area",
		"room", "uprm", "dnrm", "ltrm", "rtrm"]

static var _room_re: RegEx


## The Data autoload, looked up at run time so this class also compiles in
## headless test scripts (autoload names are not globals there).
static func _data() -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node("Data")


# --- ids --------------------------------------------------------------------

## "16", "l16", "section16" or 16 -> "16".
static func norm_section(id: Variant) -> String:
	var s := str(id)
	for prefix in ["section", "l"]:
		if s.begins_with(prefix):
			s = s.substr(prefix.length())
	return s


static func room_id(sec: Variant, street: int, building: int, floor_n: int, room: int) -> String:
	return "l%s_s%d_b%d_f%d_r%d" % [norm_section(sec), street, building, floor_n, room]


## "l16_s3_b1_f1_r2" -> {section:"16", street:3, building:1, floor:1, room:2}.
## Empty for a malformed id.
static func parse(id: String) -> Dictionary:
	if _room_re == null:
		_room_re = RegEx.create_from_string("^l(\\d+)_s(\\d+)_b(\\d+)_f(\\d+)_r(\\d+)$")
	var m := _room_re.search(id)
	if m == null:
		return {}
	return {"section": m.get_string(1), "street": int(m.get_string(2)), "building": int(m.get_string(3)),
			"floor": int(m.get_string(4)), "room": int(m.get_string(5))}


static func with_parts(id: String, changes: Dictionary) -> String:
	var p := parse(id)
	if p.is_empty():
		return ""
	p.merge(changes, true)
	return room_id(p.section, p.street, p.building, p.floor, p.room)


## Stable id of a container, "l16/s3/b1/f1/r1/cont1".
static func container_id(id: String, cont_key: String) -> String:
	var p := parse(id)
	return "l%s/s%d/b%d/f%d/r%d/%s" % [p.section, p.street, p.building, p.floor, p.room, cont_key]


## Save key of a door, the original's "<room id>_<marker name>" (questItem.door uses it).
static func door_id(id: String, marker_name: String) -> String:
	return "%s_%s" % [id, marker_name]


# --- tables -----------------------------------------------------------------

static var _wrapped: Dictionary = {}


## The section's table. Section 1 is defined in the original with its
## buildings at the top level and no street; it is read as street 1.
static func section(sec: Variant) -> Dictionary:
	var s := norm_section(sec)
	var d: Dictionary = _data().table("world/l" + s)
	if d.has("b0") and not d.has("s1"):
		if not _wrapped.has(s):
			var street := {}
			var top := {}
			for k in d:
				if k.begins_with("b") and k.substr(1).is_valid_int():
					street[k] = d[k]
				else:
					top[k] = d[k]
			top["s1"] = street
			_wrapped[s] = top
		return _wrapped[s]
	return d


static func layout_table(sec: Variant) -> Dictionary:
	return _data().table("world/layout/l" + norm_section(sec))


static func _node(id: String, depth: int) -> Dictionary:
	var p := parse(id)
	if p.is_empty():
		return {}
	var keys := ["s%d" % p.street, "b%d" % p.building, "f%d" % p.floor, "r%d" % p.room]
	var cur: Variant = section(p.section)
	for i in depth:
		if not (cur is Dictionary) or not cur.has(keys[i]) or not (cur[keys[i]] is Dictionary):
			return {}
		cur = cur[keys[i]]
	return cur


static func street_def(id: String) -> Dictionary:
	return _node(id, 1)


static func building_def(id: String) -> Dictionary:
	return _node(id, 2)


static func room_def(id: String) -> Dictionary:
	return _node(id, 4)


static func has_room(id: String) -> bool:
	return not room_def(id).is_empty()


## Every room id of a section, in data order.
static func rooms_of(sec: Variant) -> Array[String]:
	var out: Array[String] = []
	var s := norm_section(sec)
	var d := section(s)
	for sk in d:
		if not (sk.begins_with("s") and sk.substr(1).is_valid_int() and d[sk] is Dictionary):
			continue
		for bk in d[sk]:
			if not (bk.begins_with("b") and bk.substr(1).is_valid_int() and d[sk][bk] is Dictionary):
				continue
			for fk in d[sk][bk]:
				if not (fk.begins_with("f") and fk.substr(1).is_valid_int() and d[sk][bk][fk] is Dictionary):
					continue
				for rk in d[sk][bk][fk]:
					if rk.begins_with("r") and rk.substr(1).is_valid_int() and d[sk][bk][fk][rk] is Dictionary:
						out.append(room_id(s, int(sk.substr(1)), int(bk.substr(1)), int(fk.substr(1)), int(rk.substr(1))))
	return out


## Where a section starts: its startLoc, else its first street room.
static func start_room(sec: Variant) -> String:
	var d := section(sec)
	var start: String = str(d.get("startLoc", ""))
	if start != "" and has_room(start):
		return start
	var first := room_id(sec, 1, 0, 0, 1)
	if has_room(first):
		return first
	var all := rooms_of(sec)
	return all[0] if not all.is_empty() else ""


static func end_room(sec: Variant) -> String:
	var e: String = str(section(sec).get("endLoc", ""))
	return e if has_room(e) else ""


# --- room properties --------------------------------------------------------

## The street itself (building 0) and rooms flagged "outside" are outdoors.
static func is_outdoors(id: String) -> bool:
	var r := room_def(id)
	if r.get("outside", false):
		return true
	var p := parse(id)
	return not p.is_empty() and p.building == 0 and float(r.get("lightReduction", 0)) == 0.0


## checkIfSafeHouse: the building or the room is flagged.
static func is_safehouse(id: String) -> bool:
	return bool(building_def(id).get("safeHouse", false)) or bool(room_def(id).get("safeHouse", false))


## setMaxThreat: section danger, overridden by the street's, then the
## building's. Sections without a value (story links) are 0.
static func danger(id: String) -> int:
	var p := parse(id)
	if p.is_empty():
		return 0
	var value: int = int(section(p.section).get("danger", 0))
	var st := street_def(id)
	if st.has("danger"):
		value = int(st.danger)
	var b := building_def(id)
	if b.has("danger"):
		value = int(b.danger)
	return value


static func light_reduction(id: String) -> float:
	return float(room_def(id).get("lightReduction", 0))


static func room_type(id: String) -> String:
	return str(room_def(id).get("type", "anywhere"))


## Display names (Cork-merged): street, building and room.
static func street_name(id: String) -> String:
	var s := street_def(id)
	var b0: Variant = s.get("b0", {})
	return str(b0.get("name", "")) if b0 is Dictionary else ""


static func building_name(id: String) -> String:
	return str(building_def(id).get("name", ""))


static func place_name(id: String) -> String:
	var p := parse(id)
	if p.is_empty():
		return ""
	if p.building == 0:
		return street_name(id)
	var b := building_name(id)
	return b if b != "" else street_name(id)


static func section_name(sec: Variant) -> String:
	var s := norm_section(sec)
	var rec: Dictionary = _data().entry("sections", s)
	return str(rec.get("name", section(s).get("name", "Section " + s)))


# --- layout -----------------------------------------------------------------

static func has_layout(id: String) -> bool:
	var p := parse(id)
	return not p.is_empty() and layout_table(p.section).has(id)


## {width, left, floor_y, markers:[{name, x, y, left, right, top, bottom, flip}]}
## in Flash px. Rooms without art (story-link sections, unused s0 rooms) get a
## synthesised layout so they still build.
static func layout(id: String) -> Dictionary:
	var p := parse(id)
	if p.is_empty():
		return {}
	var t := layout_table(p.section)
	if t.has(id) and t[id].has("width"):
		return t[id]
	return _synth_layout(id)


static func width_px(id: String) -> float:
	return float(layout(id).get("width", FALLBACK_ROOM_WIDTH_PX))


static func markers(id: String, prefix: String = "") -> Array:
	var out: Array = []
	for m in layout(id).get("markers", []):
		if prefix == "" or str(m.name).begins_with(prefix):
			out.append(m)
	return out


static func marker(id: String, marker_name: String) -> Dictionary:
	for m in layout(id).get("markers", []):
		if m.name == marker_name:
			return m
	return {}


## Street edges, building entrances spaced along the street and a map exit
## for rooms with no art.
static func _synth_layout(id: String) -> Dictionary:
	var p := parse(id)
	var outdoors: bool = p.building == 0
	var w: float = FALLBACK_STREET_WIDTH_PX if outdoors else FALLBACK_ROOM_WIDTH_PX
	var ms: Array = []
	var mk := func(n: String, x: float) -> Dictionary:
		return {"name": n, "x": x, "y": 300.0, "left": x - 25.0, "right": x + 25.0, "top": 150.0, "bottom": 300.0, "flip": false, "synth": true}
	if outdoors and p.floor == 0 and p.room == 1:
		# an unnamed street (the unused s0 rooms) is not a street anyone walks to
		var named := street_name(id) != ""
		if named and street_name(with_parts(id, {"street": p.street - 1})) != "":
			ms.append(mk.call("strt1", 18.0))
		if named and street_name(with_parts(id, {"street": p.street + 1})) != "":
			ms.append(mk.call("strt2", w - 18.0))
		var st := street_def(id)
		var n := 0
		for bk in st:
			if bk.begins_with("b") and bk != "b0" and st[bk] is Dictionary and st[bk].has("f1"):
				n += 1
				var bn := int(bk.substr(1))
				ms.append(mk.call("entr%d" % bn, 400.0 + bn * 380.0))
		ms.append(mk.call("area1", w - 60.0))
	elif not outdoors and p.floor >= 1 and p.room == 1:
		ms.append(mk.call("exit%d" % p.building, w * 0.5))
	ms.sort_custom(func(a, b): return a.x < b.x)
	return {"width": w, "left": 0.0, "floor_y": 300.0, "markers": ms, "synth": true}


# --- links ------------------------------------------------------------------

## Every way out of a room, resolved against the data. Each link:
##   {name, kind, x, left, right, target, spawn, door_id, locked, needs_key,
##    lock_diff, label}
## `target` is a room id, "" for a dead end (the original plays the locked
## sound), or "map" for an area exit. `spawn` says where the player lands in
## the target: {"marker": name} or {"edge": "left"/"right"}.
## Lock fields come from the room's lockedDoors/needsKey/lockDiff lists.
static func links(id: String) -> Array:
	var out: Array = []
	var p := parse(id)
	if p.is_empty():
		return out
	var w := width_px(id)
	var r := room_def(id)
	var locked_names: Array = r.get("lockedDoors", [])
	var needs_key: Array = r.get("needsKey", [])
	var lock_diffs: Array = r.get("lockDiff", [])
	for m in layout(id).get("markers", []):
		var link := _resolve(id, p, w, m)
		if link.is_empty():
			continue
		var li := locked_names.find(m.name)
		link["door_id"] = door_id(id, m.name)
		link["locked"] = li >= 0
		link["needs_key"] = li >= 0 and li < needs_key.size() and bool(needs_key[li])
		link["lock_diff"] = str(lock_diffs[li]) if li >= 0 and li < lock_diffs.size() else ""
		out.append(link)
	return out


static func _resolve(id: String, p: Dictionary, w: float, m: Dictionary) -> Dictionary:
	var name: String = m.name
	var kind := ""
	for k in LINK_KINDS:
		if name.begins_with(k):
			kind = k
			break
	if kind == "":
		return {}
	var num_s := name.substr(kind.length())
	var num := int(num_s) if num_s.is_valid_int() else 0
	var target := ""
	var spawn := {}
	var label := "OPEN"
	match kind:
		"door":
			# openDoor: player right of the door -> room - 1, else room + 1.
			# Doors sit at the room ends, so the side is the door's own.
			var left_side: bool = m.x < w * 0.5
			target = with_parts(id, {"room": p.room + (-1 if left_side else 1)})
			spawn = {"edge": "right" if left_side else "left"}
		"entr":
			target = with_parts(id, {"building": num, "floor": 1, "room": 1})
			spawn = {"marker": "exit%d" % num}
			label = "ENTER"
		"exit":
			target = with_parts(id, {"building": 0, "floor": 0, "room": 1})
			spawn = {"marker": "entr%d" % p.building}
			label = "EXIT"
		"sup":
			target = with_parts(id, {"floor": p.floor + 1})
			spawn = {"marker": "sdwn"}
			label = "UPSTAIRS"
		"sdwn":
			target = with_parts(id, {"floor": p.floor - 1})
			spawn = {"marker": "sup"}
			label = "DOWNSTAIRS"
		"drop":
			target = with_parts(id, {"floor": p.floor - 1})
			spawn = {"marker": "drop", "x": m.x}
			label = "DROP DOWN"
		"strt":
			# moveStreet: the next street only exists if it has a name.
			var go_left: bool = m.x < w * 0.5
			var next := with_parts(id, {"street": p.street + (-1 if go_left else 1), "building": 0, "floor": 0, "room": 1})
			target = next if street_name(next) != "" else ""
			spawn = {"edge": "right" if go_left else "left"}
			label = "NEXT AREA"
		"area":
			target = "map"
			label = "EXIT TO MAP"
		"room":
			target = with_parts(id, {"room": num})
			spawn = {"marker": "room%d" % p.room}
			label = "ENTER"
		"uprm":
			target = with_parts(id, {"room": num})
			spawn = {"marker": "dnrm%d" % p.room}
			label = "ENTER"
		"dnrm":
			target = with_parts(id, {"room": num})
			spawn = {"marker": "uprm%d" % p.room}
			label = "ENTER"
		"ltrm":
			target = with_parts(id, {"room": p.room - 1})
			spawn = {"edge": "right"}
			label = "NEXT AREA"
		"rtrm":
			target = with_parts(id, {"room": p.room + 1})
			spawn = {"edge": "left"}
			label = "NEXT AREA"
	if target != "map" and target != "" and not has_room(target):
		target = ""
	return {"name": name, "kind": kind, "x": float(m.x), "left": float(m.left), "right": float(m.right),
			"target": target, "spawn": spawn, "label": label}


## Player x (px) on arriving in `target` by `spawn`, clamped inside the room.
## A missing marker falls back to the given x, then the room centre.
static func spawn_x_px(target: String, spawn: Dictionary) -> float:
	var w := width_px(target)
	var x := w * 0.5
	if spawn.has("edge"):
		x = EDGE_BUFFER_PX if spawn.edge == "left" else w - EDGE_BUFFER_PX
	elif spawn.has("marker") and not marker(target, spawn.marker).is_empty():
		x = float(marker(target, spawn.marker).x)
	elif spawn.has("x"):
		x = float(spawn.x)
	return clampf(x, EDGE_BUFFER_PX, maxf(w - EDGE_BUFFER_PX, EDGE_BUFFER_PX))


# --- people and things ------------------------------------------------------

## {key, def, x} for each contN of the room. x is the art marker's x in px,
## or spread evenly when the art has no marker for it.
static func containers(id: String) -> Array:
	var r := room_def(id)
	var keys: Array = []
	for k in r:
		if k.begins_with("cont") and k.substr(4).is_valid_int() and r[k] is Dictionary:
			keys.append(k)
	keys.sort_custom(func(a, b): return int(a.substr(4)) < int(b.substr(4)))
	var w := width_px(id)
	var out: Array = []
	# Things already standing somewhere: marked containers and every link.
	var taken: Array[float] = []
	for k in keys:
		var m := marker(id, k)
		if not m.is_empty():
			taken.append(float(m.x))
	for m in layout(id).get("markers", []):
		for kind in LINK_KINDS:
			if str(m.name).begins_with(kind):
				taken.append(float(m.x))
				break
	for k in keys:
		var m := marker(id, k)
		var x: float
		if not m.is_empty():
			x = float(m.x)
		else:
			x = _free_spot(w, taken)
			taken.append(x)
		out.append({"key": k, "def": r[k], "x": x, "id": container_id(id, k), "placed": not m.is_empty()})
	return out


## The x (px) inside the room farthest from everything in `taken`.
static func _free_spot(w: float, taken: Array[float]) -> float:
	var best := w * 0.5
	var best_d := -1.0
	var x := EDGE_BUFFER_PX
	while x <= w - EDGE_BUFFER_PX:
		var d := INF
		for t in taken:
			d = minf(d, absf(t - x))
		if d > best_d:
			best_d = d
			best = x
		x += 10.0
	return best


## {npc_id, x, pose, facing} for each entry in the room's NPCs list.
static func npcs(id: String) -> Array:
	var r := room_def(id)
	var ids: Array = r.get("NPCs", [])
	var xs: Array = r.get("NPC_x", [])
	var poses: Array = r.get("NPCPose", [])
	var facings: Array = r.get("NPCFacing", [])
	var out: Array = []
	for i in ids.size():
		out.append({"npc_id": str(ids[i]), "x": float(xs[i]) if i < xs.size() else width_px(id) * 0.5,
				"pose": str(poses[i]) if i < poses.size() else "idle",
				"facing": str(facings[i]) if i < facings.size() else "left"})
	return out


## Human enemies placed by the room ({ref, x}); the AI belongs to gameplay.
static func enemies(id: String) -> Array:
	var r := room_def(id)
	var refs: Array = r.get("enemy", [])
	var xs: Array = r.get("enemyX", [])
	var out: Array = []
	for i in refs.size():
		out.append({"ref": str(refs[i]), "x": float(xs[i]) if i < xs.size() else 0.0})
	return out


# --- map --------------------------------------------------------------------

static func map_pos(sec: Variant) -> Variant:
	var rec: Variant = _data().table("world/map").get(norm_section(sec))
	if rec is Dictionary:
		return Vector2(float(rec.x), float(rec.y))
	return null


static func connections(sec: Variant) -> Array[String]:
	var out: Array[String] = []
	for loc in _data().entry("sections", norm_section(sec)).get("locations", []):
		out.append(norm_section(loc))
	return out


## Hours of travel between two sections: round(manhattan / 200). 0 when
## either has no map position.
static func travel_hours(from_sec: Variant, to_sec: Variant) -> int:
	var a: Variant = map_pos(from_sec)
	var b: Variant = map_pos(to_sec)
	if a == null or b == null:
		return 0
	return roundi((absf(a.x - b.x) + absf(a.y - b.y)) / TRAVEL_PX_PER_HOUR)


## A section can be travelled to when it is on the map and has a start room.
static func is_travelable(sec: Variant) -> bool:
	return map_pos(sec) != null and start_room(sec) != "" and not layout_table(sec).is_empty()
