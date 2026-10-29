extends Node
## Autoload "Companions": who travels with the player, plus the hook that puts
## human enemies and companions into a built level. Spec and rules:
## docs/companions.md. Stateful: group "stateful", reset(), to_dict(), from_dict(d).
##
## Roster entry (npc id -> Dictionary): kind ("follower" | "partner"), health,
## weapon (ref), mag (loaded rounds), hold, down, down_health, room.
## One follower at a time (the original refuses a second, alreadyHaveCompanion),
## one partner.

signal roster_changed()
signal companion_died(npc_id: String)

const PARTNER := "Partner"
const FOLLOW_OFFSET: float = 0.8

var roster: Dictionary = {}
## NPCs that left or died: Quests still lists them as companions, so a
## quest sync must not bring them back.
var dismissed: Dictionary = {}
## Human enemies already killed: room id -> {index (string) -> x in units}.
var killed: Dictionary = {}

var _nodes: Dictionary = {}   # npc id -> Companion node in the current level


func _ready() -> void:
	add_to_group("stateful")
	call_deferred("_connect_signals")


func _connect_signals() -> void:
	Events.location_entered.connect(_on_location_entered)
	Events.quest_changed.connect(func(_id, _s): sync_quests())
	var q := get_node_or_null("/root/Quests")
	if q != null:
		q.npc_changed.connect(func(_id): sync_quests())
		q.story_action.connect(_on_story_action)


# --- roster API ---------------------------------------------------------------------

func active() -> Array:
	return roster.keys()


func has(npc_id: String) -> bool:
	return roster.has(npc_id)


func follower() -> String:
	for k in roster:
		if roster[k].kind == "follower":
			return k
	return ""


func node_for(npc_id: String) -> Companion:
	var n = _nodes.get(npc_id)
	return n if n != null and is_instance_valid(n) else null


## Adds a survivor to the party. Returns false if there is already a follower
## (or the partner is already here) or the NPC is unknown.
func add(npc_id: String, kind: String = "follower") -> bool:
	if roster.has(npc_id):
		return false
	if kind == "follower" and follower() != "":
		return false
	var d: Dictionary = Data.entry("npc", npc_id)
	if d.is_empty():
		return false
	var w := "hands" if kind == "partner" else str(d.get("weapon", "none"))
	roster[npc_id] = {"kind": kind, "health": -1.0, "weapon": w, "mag": -1, "hold": false,
			"down": false, "down_health": -1.0, "room": ""}
	dismissed.erase(npc_id)
	var q := get_node_or_null("/root/Quests")
	if q != null:
		q.set_npc_on(npc_id, false) # they leave their post in the world
	roster_changed.emit()
	_spawn_one(npc_id)
	return true


## Removes a companion from the party and puts the NPC back where they stood
## (`dismiss`). Returns false if they were not in the party.
func remove(npc_id: String, back_to_post: bool = true) -> bool:
	if not roster.has(npc_id):
		return false
	roster.erase(npc_id)
	dismissed[npc_id] = true
	var n := node_for(npc_id)
	_nodes.erase(npc_id)
	if n != null:
		n.dead = true # stop _exit_tree from re-syncing
		n.queue_free()
	var q := get_node_or_null("/root/Quests")
	if q != null and back_to_post:
		q.set_npc_on(npc_id, true)
	roster_changed.emit()
	return true


func on_companion_died(npc_id: String) -> void:
	if not roster.has(npc_id):
		return
	roster.erase(npc_id)
	dismissed[npc_id] = true
	_nodes.erase(npc_id)
	var q := get_node_or_null("/root/Quests")
	if q != null:
		q.set_npc_on(npc_id, false) # companionDeath: the NPC is gone for good
	companion_died.emit(npc_id)
	roster_changed.emit()


## Copies a live companion's state into the roster.
func sync_from(c: Companion) -> void:
	if not roster.has(c.npc_id):
		return
	var e: Dictionary = roster[c.npc_id]
	e["health"] = c.health
	e["weapon"] = c.gun.weapon.ref
	e["mag"] = c.gun.loaded
	e["hold"] = c.hold
	e["down"] = c.down
	e["down_health"] = c.down_health
	e["room"] = str(World.current.get("room_id", ""))


## Brings Quests' follower/partner rewards into the roster.
func sync_quests() -> void:
	var q := get_node_or_null("/root/Quests")
	if q == null:
		return
	var c: Dictionary = q.companions()
	for npc in c:
		if not roster.has(npc) and not dismissed.has(npc):
			add(str(npc), str(c[npc]))


# --- level hook ---------------------------------------------------------------------

## Called by LevelBuilder.build once the level exists: places the room's human
## enemies (skipping the ones already killed, whose drops come back) and the
## active companions near the player.
func populate_level(level: Node3D, room_id: String) -> void:
	_nodes.clear()
	var danger := maxi(1, int(level.get("danger") if "danger" in level else 1))
	var root: Node3D = level.get_node("Actors") if level.has_node("Actors") else level
	var gone: Dictionary = killed.get(room_id, {})
	var list := WorldData.enemies(room_id)
	for i in list.size():
		var e: Dictionary = list[i]
		var x := clampf(float(e.x) / WorldData.PX_PER_UNIT, 0.5, maxf(WorldData.width_px(room_id) / WorldData.PX_PER_UNIT - 0.5, 0.5))
		if gone.has(str(i)):
			_restore_drop(root, room_id, i, float(gone[str(i)]), danger)
			continue
		if Data.entry("npc", str(e.ref)).is_empty():
			continue # dead data (citizen1 has no record)
		HumanEnemy.spawn(root, str(e.ref), x, danger, room_id, i)
	for npc in roster:
		_spawn_one(npc, root)


func _spawn_one(npc_id: String, root: Node3D = null) -> void:
	if node_for(npc_id) != null:
		return
	if root == null:
		var lv = World.level() if World.has_method("level") else null
		if lv == null or not is_instance_valid(lv):
			return
		root = lv.spawn_root()
	var e: Dictionary = roster[npc_id]
	var p := get_tree().get_first_node_in_group("player") as Node3D
	var index := roster.keys().find(npc_id)
	var x := (p.global_position.x if p != null else 1.0) - FOLLOW_OFFSET * (index + 1)
	_nodes[npc_id] = Companion.spawn(root, npc_id, str(e.kind), maxf(x, 0.3), e)
	_nodes[npc_id].index = index


func _restore_drop(root: Node3D, room_id: String, i: int, x: float, danger: int) -> void:
	var rec: Dictionary = LootState.get_container("drop_%s_%d" % [room_id, i])
	if rec.get("items", []).is_empty():
		return
	HumanEnemy.make_drop(root, "drop_%s_%d" % [room_id, i], "Fallen", [], x, danger)


func note_enemy_killed(room_id: String, idx: int, x: float) -> void:
	if not killed.has(room_id):
		killed[room_id] = {}
	killed[room_id][str(idx)] = x


## New room: companions (rebuilt with the level) stand next to the player.
func _on_location_entered(_room: String) -> void:
	var p := get_tree().get_first_node_in_group("player") as Node3D
	var i := 0
	for npc in roster:
		_spawn_one(npc)
		var n := node_for(npc)
		if n != null and p != null:
			n.global_position = Vector3(p.global_position.x - FOLLOW_OFFSET * (i + 1), p.global_position.y, 0.0)
			n.velocity = Vector3.ZERO
			n.player = p
		i += 1


## The Jeb and Paul ambush: spawn the named hostile NPCs near the fakeRoom
## positions of the original (x 550 and 950 px).
func _on_story_action(action: String, args: Array) -> void:
	if action != "spawn":
		return
	var lv: Level = World.level()
	if lv == null:
		return
	var xs := [5.5, 9.5]
	for i in args.size():
		var x := clampf(xs[i % xs.size()], 0.5, lv.width_units() - 0.5)
		HumanEnemy.spawn(lv.spawn_root(), str(args[i]), x, maxi(1, lv.danger))


# --- stateful -----------------------------------------------------------------------

func reset() -> void:
	roster.clear()
	dismissed.clear()
	killed.clear()
	_nodes.clear()


func to_dict() -> Dictionary:
	# live companions write back first
	for npc in _nodes.keys():
		var n := node_for(npc)
		if n != null:
			sync_from(n)
	return {"roster": roster.duplicate(true), "dismissed": dismissed.duplicate(), "killed": killed.duplicate(true)}


func from_dict(d: Dictionary) -> void:
	roster.clear()
	for npc in d.get("roster", {}):
		var e: Dictionary = d["roster"][npc]
		roster[str(npc)] = {"kind": str(e.get("kind", "follower")), "health": float(e.get("health", -1.0)),
				"weapon": str(e.get("weapon", "hands")), "mag": int(e.get("mag", -1)), "hold": bool(e.get("hold", false)),
				"down": bool(e.get("down", false)), "down_health": float(e.get("down_health", -1.0)),
				"room": str(e.get("room", ""))}
	dismissed = {}
	for k in d.get("dismissed", {}):
		dismissed[str(k)] = true
	killed = {}
	for room in d.get("killed", {}):
		killed[str(room)] = {}
		for idx in d["killed"][room]:
			killed[str(room)][str(idx)] = float(d["killed"][room][idx])
	_nodes.clear()
