extends Node3D
## A searchable container (bin, locker, fridge, ...) built from one `contN`
## entry of the world data. World calls setup(); Loot owns everything after.
##
## Layout: this node sits on the lane (Z=0). The visible body is recessed in Z
## and only the trigger Area3D reaches back to Z=0 (ROADMAP world layout rule).
##
## Flow: interact -> (locked? Locks.try_open) -> first time: "Searching..." for
## SEARCH_TIME seconds, then LootRules.generate, search XP, Events.container_searched
## -> container panel (TrunkUI). Contents and lock state persist in LootState.
## The panel talks to the same `items` / `take_item` / `take_all` interface as
## the car trunk.

const SEARCH_TIME := 0.8
const RECESS_Z := -1.4
const PROMPT_HEIGHT := 1.6

var container_id: String = ""
var def: Dictionary = {}
var room_type: String = "anywhere"
var danger: int = 1
var items: Array = []
var searched: bool = false
var title: String = "Container"
var rng := RandomNumberGenerator.new()

var player_in_range: Node3D = null
var search_left: float = -1.0
var reopen_cooldown: float = 0.0
var _lock_busy: bool = false
var _body: MeshInstance3D
var _label: Label3D
var _trigger: Area3D


## `def` is a `contN` entry: {desc, cnt, noJunk, locked, lockDiff, hasKey, ...}.
func setup(p_container_id: String, p_def: Dictionary, p_room_type: String, p_danger: int) -> void:
	container_id = p_container_id
	def = p_def
	room_type = p_room_type
	danger = p_danger
	title = str(def.get("desc", "Container"))
	rng.randomize()
	_restore()
	if is_inside_tree():
		_build()


func _ready() -> void:
	add_to_group("world_interactable")
	if container_id == "":
		return
	_build()


## True while the player stands at this container and interact would act on it
## (World checks this so a door trigger behind it does not steal the key).
func wants_interact() -> bool:
	return player_in_range != null and not TrunkUI.visible and reopen_cooldown <= 0.0 \
			and _is_nearest_in_range()


## Neighbouring containers can have overlapping triggers; only the one closest
## to the player reacts to the interact key.
func _is_nearest_in_range() -> bool:
	if player_in_range == null:
		return false
	var px: float = player_in_range.global_position.x
	var mine := absf(global_position.x - px)
	for other in get_tree().get_nodes_in_group("world_interactable"):
		if other == self or not other.has_method("_is_nearest_in_range") or other.player_in_range == null:
			continue
		var d := absf(other.global_position.x - px)
		if d < mine or (is_equal_approx(d, mine) and other.get_instance_id() < get_instance_id()):
			return false
	return true


func _restore() -> void:
	var rec := LootState.get_container(container_id)
	searched = rec.get("searched", false)
	items = []
	for e in rec.get("items", []):
		var entry: Dictionary = e.duplicate()
		entry["count"] = int(entry.get("count", 1))
		items.append(entry)


# --- Lock ---------------------------------------------------------------------

func lock_def() -> Dictionary:
	return {"id": container_id, "locked": def.get("locked", false), "lock_diff": def.get("lockDiff", "normal"),
		"can_force": not def.get("hasKey", false), "needs_key": false}


func is_locked() -> bool:
	var d := lock_def()
	return d["locked"] and not Locks.is_unlocked(d)


# --- Search -------------------------------------------------------------------

## Runs the first-search generation now (no delay): builds the contents once,
## saves them, grants search XP and announces it. Returns false if already done.
func search_now() -> bool:
	if searched:
		return false
	var player := {"searching": Stats.skill("searching"), "luck": Stats.attr("luck")}
	items = LootRules.generate(def, room_type, danger, player, rng)
	searched = true
	_save()
	Stats.add_xp(LootRules.search_xp(Stats.level, Stats.adjusted_skill("smarts")), "search")
	Events.container_searched.emit(container_id)
	return true


## Interaction entry point (also what the interact key calls).
func interact() -> void:
	if _lock_busy or search_left >= 0.0:
		return
	if is_locked():
		_lock_busy = true
		Locks.try_open(lock_def(), self, _on_lock_result)
		_refresh_prompt()
		return
	_begin_open()


func _on_lock_result(ok: bool) -> void:
	_lock_busy = false
	_refresh_prompt()
	if ok:
		_begin_open()


func _begin_open() -> void:
	if searched:
		_open_panel()
	else:
		search_left = SEARCH_TIME


func _open_panel() -> void:
	TrunkUI.open(self)


func suppress_interact(duration: float = 0.3) -> void:
	reopen_cooldown = duration


# --- Panel interface ----------------------------------------------------------

func take_item(index: int) -> Dictionary:
	var item: Dictionary = items.pop_at(index)
	_save()
	return item


func take_all() -> Array:
	var taken: Array = items.duplicate()
	items.clear()
	_save()
	return taken


func _save() -> void:
	LootState.set_container(container_id, {"searched": searched, "items": items})


# --- Node plumbing --------------------------------------------------------------

func _process(delta: float) -> void:
	reopen_cooldown = maxf(0.0, reopen_cooldown - delta)
	if search_left >= 0.0:
		if player_in_range == null:
			search_left = -1.0
			_refresh_prompt()
			return
		search_left -= delta
		_label.text = "Searching... %d%%" % clampi(int((1.0 - search_left / SEARCH_TIME) * 100.0), 0, 100)
		if search_left < 0.0:
			search_left = -1.0
			search_now()
			_open_panel()
			_refresh_prompt()
		return
	if player_in_range == null or TrunkUI.visible or reopen_cooldown > 0.0:
		return
	if Input.is_action_just_pressed("interact") and _is_nearest_in_range():
		interact()


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		player_in_range = body
		_refresh_prompt()


func _on_body_exited(body: Node3D) -> void:
	if body == player_in_range:
		player_in_range = null
		_refresh_prompt()


func _refresh_prompt() -> void:
	if _label == null:
		return
	_label.visible = player_in_range != null
	if search_left >= 0.0:
		return
	var text := "[E] %s" % title
	if is_locked():
		var d := lock_def()
		text = "%s [LOCKED - %s]" % [title, str(d["lock_diff"]).to_upper()]
	elif searched and items.is_empty():
		text = "%s (empty)" % title
	_label.text = text


## desc -> [size (w, h, d), colour]. Matched by keyword, first hit wins.
static func visual_for(desc: String) -> Dictionary:
	var d := desc.to_lower()
	var table := [
		[["fridge"], Vector3(0.9, 1.8, 0.8), Color(0.82, 0.84, 0.86)],
		[["locker", "gun", "weapons", "equipment", "rack", "cage"], Vector3(0.8, 1.9, 0.6), Color(0.38, 0.45, 0.4)],
		[["safe"], Vector3(0.8, 0.9, 0.7), Color(0.2, 0.2, 0.22)],
		[["bookshelf", "bookcase", "book shelf", "books", "shelf", "shelves"], Vector3(1.4, 1.9, 0.5), Color(0.5, 0.33, 0.2)],
		[["trash", "bin", "dumpster", "junk"], Vector3(1.0, 1.0, 0.8), Color(0.25, 0.4, 0.28)],
		[["filing"], Vector3(0.6, 1.4, 0.7), Color(0.55, 0.57, 0.6)],
		[["desk", "table", "counter", "register"], Vector3(1.4, 0.8, 0.7), Color(0.55, 0.4, 0.28)],
		[["cupboard", "cabinet", "closet", "drawer", "dresser", "sideboard", "bedside"], Vector3(1.0, 1.1, 0.6), Color(0.6, 0.45, 0.3)],
		[["box", "crate", "suitcase", "bag", "trunk", "footlocker", "chest", "container"], Vector3(0.9, 0.6, 0.6), Color(0.6, 0.5, 0.32)],
		[["corpse", "body"], Vector3(1.6, 0.25, 0.6), Color(0.45, 0.3, 0.3)],
	]
	for row in table:
		for kw in row[0]:
			if d.contains(kw):
				return {"size": row[1], "color": row[2]}
	return {"size": Vector3(1.0, 1.0, 0.6), "color": Color(0.5, 0.5, 0.5)}


func _build() -> void:
	if _body != null:
		return
	var vis := visual_for(title)
	var size: Vector3 = vis["size"]
	_body = MeshInstance3D.new()
	_body.name = "Body"
	var box := BoxMesh.new()
	box.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = vis["color"]
	box.material = mat
	_body.mesh = box
	_body.position = Vector3(0, size.y * 0.5, RECESS_Z)
	add_child(_body)

	# Trigger: the only part that reaches the Z=0 lane. Not a solid body.
	_trigger = Area3D.new()
	_trigger.name = "Trigger"
	var tshape := CollisionShape3D.new()
	tshape.name = "Shape"
	var tbox := BoxShape3D.new()
	tbox.size = Vector3(size.x + 0.6, 2.0, absf(RECESS_Z) + 1.0)
	tshape.shape = tbox
	_trigger.position = Vector3(0, 1.0, RECESS_Z * 0.5 + 0.0)
	_trigger.add_child(tshape)
	add_child(_trigger)
	_trigger.body_entered.connect(_on_body_entered)
	_trigger.body_exited.connect(_on_body_exited)

	# Hover highlight through the existing hover system (layer 2, no mask).
	var hover := Area3D.new()
	hover.name = "Hover"
	hover.collision_layer = 2
	hover.collision_mask = 0
	hover.set_script(load("res://scripts/hoverable.gd"))
	hover.set("target_mesh_path", NodePath("../Body"))
	var hshape := CollisionShape3D.new()
	var hbox := BoxShape3D.new()
	hbox.size = size
	hshape.shape = hbox
	hover.position = _body.position
	hover.add_child(hshape)
	add_child(hover)

	_label = Label3D.new()
	_label.name = "Prompt"
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.pixel_size = 0.01
	_label.position = Vector3(0, maxf(size.y, 1.0) + 0.5, 0.0)
	_label.visible = false
	add_child(_label)
	_refresh_prompt()
