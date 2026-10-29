class_name HumanEnemy
extends HumanBody
## An armed NPC placed by a room's `enemy` list (Jeb, Paul, looters, HERC
## soldiers, and the friendly guards that only shoot zombies). Follows
## humanAIRoutine: no sight cone, it simply targets what is within range
## (here: sight 8 units, or any shot heard within 10), closes to its weapon's
## range, stands and fires in bursts, or chases and swings. Remake additions
## **(verify)**: patrol while idle, crouch for cover, flee when badly hurt,
## drop weapon, ammo and cash on death.

const SCENE_PATH := "res://scenes/companions/human_enemy.tscn"
const CONTAINER_PATH := "res://scenes/loot/container.tscn"
const SIGHT_RANGE: float = 8.0
const HEARING_RANGE: float = 10.0
const RETARGET_TIME: float = 10.0 / 30.0
const WANDER_SPEED: float = 1.0
const PATROL_RADIUS: float = 2.5
const FLEE_HEALTH_FRACTION: float = 0.25
const FLEE_DISTANCE: float = 8.0
const FLEE_SPEED: float = 6.0
const INVULNERABLE_HEALTH: float = 1.0e6

var friendly: bool = false
var stationary: bool = false
var home_x: float = 0.0
var room_id: String = ""
var index: int = 0               ## position in the room's enemy list
var fleeing: bool = false
var flee_enabled: bool = true
var provoker: Node3D = null      ## whoever hurt us last

var _retarget_t: float = 0.0
var _range: float = 4.0
var _wander_t: float = 0.0
var _wander_dir: float = 0.0
var _carry_cash: String = ""


## Instantiates the scene for NPC record `ref` at local x (units) under `parent`.
static func spawn(parent: Node, ref: String, x: float, danger: int, p_room: String = "", p_index: int = 0) -> HumanEnemy:
	var e: HumanEnemy = (load(SCENE_PATH) as PackedScene).instantiate()
	e.configure(ref, danger)
	e.room_id = p_room
	e.index = p_index
	e.home_x = x
	e.position = Vector3(x, 1.0, 0.0)
	parent.add_child(e)
	return e


func configure(ref: String, danger: int) -> void:
	npc_id = ref
	enemy_ref = ref
	danger_level = danger
	def = _sys("Data").entry("npc", ref)
	friendly = def.get("friendly", false) == true
	stationary = def.get("stationary", false) == true
	xp_bonus = float(def.get("xpBonus", 1.0))
	skill = 10.0
	max_health = float(def.get("health", default_health(danger)))
	health = max_health
	armor = armor_from_clothes(str(def.get("clothesTop", "")))
	var wref := str(def.get("weapon", "none"))
	gun = ActorGun.new(wref if Weapon.from_ref(wref) != null else "hands", -1, -1)
	flee_enabled = not stationary and max_health < INVULNERABLE_HEALTH
	state = "idle"
	_range = shot_range()
	if is_node_ready():
		_apply_tint()


func _ready() -> void:
	super()
	add_to_group("human_enemy")
	if not friendly:
		add_to_group("hostile_human")
	collision_layer = 1
	_sys("Events").shot_fired.connect(_on_shot_fired)
	home_x = global_position.x if home_x == 0.0 else home_x


func _on_shot_fired(_ref: String, noise: float, pos: Vector3) -> void:
	if dead or target != null or noise <= 0.0 or friendly:
		return
	if absf(pos.x - global_position.x) <= HEARING_RANGE:
		var p := nearest_of(get_tree().get_nodes_in_group("player"), 1.0e9)
		if p != null:
			target = p # heard it: go and look
			_enter_combat()


func _on_hurt(_amount: float, _zone: String, source: Node) -> void:
	if source is Node3D and not friendly:
		provoker = source
		if target == null:
			target = source
			_enter_combat()


func _on_zero_health(source: Node) -> void:
	_die(source)


# --- AI ----------------------------------------------------------------------------------

func candidates() -> Array:
	if friendly:
		var out: Array = []
		for z in get_tree().get_nodes_in_group("zombie"):
			if z.get("alerted") == true:
				out.append(z)
		out.append_array(get_tree().get_nodes_in_group("hostile_human"))
		return out
	var cs: Array = get_tree().get_nodes_in_group("player")
	cs.append_array(get_tree().get_nodes_in_group("companion"))
	return cs


func _enter_combat() -> void:
	_range = shot_range()
	_attack_clock = 0.0
	_burst_clock = 0.0
	state = "chase"


func think(delta: float) -> float:
	_retarget_t -= delta
	if target != null and flag_dead(target):
		target = null
		if state != "idle":
			state = "idle"
	if _retarget_t <= 0.0:
		_retarget_t = RETARGET_TIME
		var best := nearest_of(candidates(), SIGHT_RANGE)
		if best != null and (target == null or absf(best.global_position.x - global_position.x) \
				< absf(target.global_position.x - global_position.x) - 0.5):
			if target == null:
				_enter_combat()
			target = best
	gun.tick(delta)
	if target == null:
		return _patrol(delta)
	_check_flee()
	var dx := target.global_position.x - global_position.x
	var dist := absf(dx)
	set_facing(dx)
	if state == "flee":
		return _flee(dx, dist)
	if stationary:
		state = "attack" if dist <= maxf(_range, melee_range()) + 0.8 else "idle"
		if state == "attack":
			attack_tick(delta)
		return 0.0
	var want := _range if gun.is_firearm() else melee_range()
	if state == "attack" and dist > want + 0.2:
		state = "chase"
	if state == "chase" and dist <= want:
		state = "attack"
	if state == "attack":
		attack_tick(delta)
		return 0.0
	return signf(dx) * MOVE_SPEED


func _check_flee() -> void:
	if not flee_enabled or state == "flee" or fleeing:
		return
	if health <= max_health * FLEE_HEALTH_FRACTION:
		fleeing = true
		state = "flee"


func _flee(dx: float, dist: float) -> float:
	if dist >= FLEE_DISTANCE:
		state = "idle" # far enough: catch breath, stay hidden
		fleeing = true
		return 0.0
	if is_on_wall():
		state = "attack" # cornered: fight
		flee_enabled = false
		fleeing = false
		return 0.0
	return -signf(dx) * FLEE_SPEED


func _patrol(delta: float) -> float:
	if stationary or fleeing:
		return 0.0
	_wander_t -= delta
	if _wander_t <= 0.0:
		var r := rng.randi() % 3
		_wander_dir = 0.0 if r == 0 else (1.0 if r == 1 else -1.0)
		_wander_t = rng.randf_range(1.5, 4.0)
	if absf(global_position.x - home_x) > PATROL_RADIUS:
		_wander_dir = signf(home_x - global_position.x)
	return _wander_dir * WANDER_SPEED


# --- death and drops ---------------------------------------------------------------------

func _die(killer: Node) -> void:
	if dead:
		return
	dead = true
	state = "dead"
	var rewarded := killer != null and (killer.is_in_group("player") or killer.is_in_group("companion"))
	if rewarded and not friendly:
		_sys("Events").enemy_killed.emit(enemy_ref, danger_level, xp_value())
	var at := global_position
	var parent := get_parent()
	_drop_loot(parent, at)
	var comp := _sys("Companions")
	if comp != null and room_id != "":
		comp.note_enemy_killed(room_id, index, at.x)
	died.emit(self)
	queue_free()


## Weapon, the rounds left plus half a magazine, and maybe cash, in a
## searchable container on the spot (the loot workstream's Container, filled
## and marked searched so no search XP or junk is rolled).
func _drop_loot(parent: Node, at: Vector3) -> Node:
	var refs: Array = []
	if gun.weapon.ref != "hands" and gun.weapon.ref != "none":
		refs.append(gun.weapon.ref)
		if gun.is_firearm():
			var n := gun.loaded + maxi(1, gun.weapon.mag_size / 2)
			refs.append("ammo%s_%d" % [gun.weapon.ammo_type, n])
	var cash := LootRules.roll_cash(danger_level, 5, rng)
	if cash != "":
		refs.append(cash)
	return make_drop(parent, "drop_%s_%d" % [room_id if room_id != "" else "x", index], "Fallen " + str(def.get("name", npc_id)),
			refs, at.x, danger_level)


static func make_drop(parent: Node, drop_id: String, title: String, refs: Array, x: float, danger: int) -> Node:
	if parent == null or not ResourceLoader.exists(CONTAINER_PATH):
		return null
	var c: Node3D = (load(CONTAINER_PATH) as PackedScene).instantiate()
	c.position = Vector3(x, 0.0, 0.0)
	c.setup(drop_id, {"desc": title, "cnt": refs, "noJunk": true}, "anywhere", danger)
	if not c.searched:
		var items: Array = []
		for r in refs:
			var e := LootRules.resolve(str(r))
			if not e.is_empty():
				items.append(e)
		c.items = items
		c.searched = true
		c.call("_save")
	parent.add_child.call_deferred(c)
	return c
