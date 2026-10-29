class_name Companion
extends HumanBody
## A survivor travelling with the player (Hank, Kelly, the partner), following
## survivorAIRoutine: follow the player (running to catch up), shoot or swing at
## alerted zombies and hostile humans in range, shove what gets too close, go
## down at 0 health (the player revives them), die only when hit further while
## down. Skill 30. The partner never fights and cannot be hurt.
##
## Companions sit on collision layer 4, so the player's bullets and melee pass
## through them, and join group "zombie_targets" so zombies can pick them.

const SCENE_PATH := "res://scenes/companions/companion.tscn"
const SURVIVOR_RANGE: float = 4.0          ## 400 px
const STAY_CLOSE: float = 4.0              ## 400 px: farther than this while fighting, walk back
const CATCH_UP: float = 3.0                ## 300 px: beyond this, run
const RUN_MULT: float = 1.5                ## runSpeedMod
const TELEPORT_DISTANCE: float = 14.0
const INTERACT_RANGE: float = 1.0          ## compInteractRange 100 px
const TARGET_RANGE: float = 8.0
const RETARGET_TIME: float = 10.0 / 30.0
const HELP_SOUND_CHANCE: int = 30

var kind: String = "follower"              ## "follower" | "partner"
var index: int = 0                         ## slot among companions (offsets the follow point)
var down: bool = false
var down_health: float = 0.0
var hold: bool = false                     ## hold position command
var player: Node3D = null

var _retarget_t: float = 0.0
var _follow_goal: float = 0.0
var _goal_t: float = 0.0
var _range: float = SURVIVOR_RANGE


## Builds the companion for `npc` (kind from Quests) under `parent` at x.
static func spawn(parent: Node, npc: String, p_kind: String, x: float, data: Dictionary = {}) -> Companion:
	var c: Companion = (load(SCENE_PATH) as PackedScene).instantiate()
	c.configure(npc, p_kind, data)
	c.position = Vector3(x, 1.0, 0.0)
	parent.add_child(c)
	return c


## `data` is a roster entry (health, weapon, mag, hold, down, down_health); missing
## keys give the NPC's defaults.
func configure(npc: String, p_kind: String, data: Dictionary = {}) -> void:
	npc_id = npc
	enemy_ref = npc
	kind = p_kind
	def = _sys("Data").entry("npc", npc)
	skill = 30.0
	var player_max: float = _sys("Stats").max_health()
	max_health = 999999999.0 if kind == "partner" else float(roundi(player_max / 2.0))
	health = float(data.get("health", -1.0))
	if kind == "partner" or health < 0.0:
		health = max_health
	var wref := str(data.get("weapon", def.get("weapon", "none")))
	if kind == "partner" or Weapon.from_ref(wref) == null:
		wref = "hands"
	gun = ActorGun.new(wref, int(data.get("mag", -1)), -1)
	hold = bool(data.get("hold", false))
	down = bool(data.get("down", false))
	down_health = float(data.get("down_health", -1.0))
	if down_health < 0.0:
		down_health = roundf(player_max * 4.0) # downHealth = healthMax * 4
	state = "down" if down else "follow"
	if is_node_ready():
		_apply_tint()


func _ready() -> void:
	super()
	add_to_group("companion")
	add_to_group("world_interactable")
	collision_layer = 4
	_set_targetable(not down)
	player = get_tree().get_first_node_in_group("player")


func _exit_tree() -> void:
	var c := get_node_or_null("/root/Companions")
	if c != null and not dead:
		c.sync_from(self)


func _set_targetable(on: bool) -> void:
	if on:
		add_to_group("zombie_targets")
	else:
		remove_from_group("zombie_targets")


func is_partner() -> bool:
	return kind == "partner"


# --- interaction --------------------------------------------------------------------

func player_near() -> bool:
	return player != null and is_instance_valid(player) \
			and absf(player.global_position.x - global_position.x) <= INTERACT_RANGE


func wants_interact() -> bool:
	return not is_partner() and not dead and player_near()


func _process(_delta: float) -> void:
	if wants_interact() and not get_tree().paused and Input.is_action_just_pressed("interact"):
		interact()


## Down: helpCompanion (stand them up at full health). Otherwise open the menu.
func interact() -> void:
	if down:
		revive()
		return
	var menu := get_node_or_null("/root/CompanionMenu")
	if menu == null:
		menu = (load("res://scripts/companions/companion_menu.gd") as GDScript).new()
		menu.name = "CompanionMenu"
		get_tree().root.add_child(menu)
	menu.open(self)


## helpCompanion: back up at full health, follow state.
func revive() -> void:
	if not down or dead:
		return
	down = false
	health = max_health
	state = "follow"
	_set_targetable(true)
	_attack_clock = 0.0
	_burst_clock = 0.0
	_play("Idle")
	if visual != null:
		visual.rotation.z = 0.0
	_push()


## Heals with a meds item from the player's inventory: round((bonus +
## adjustedSkill(firstAid) / 2) / 100 * healthMax). Returns the amount healed.
func heal_with(item_name: String) -> float:
	if dead or down or health >= max_health or is_partner():
		return 0.0
	var inv := _sys("Inventory")
	if not inv.has_item(item_name):
		return 0.0
	var info := Items.find(item_name)
	if info.is_empty() or info["kind"] != "meds" or str(info["rec"].get("type", "health")) != "health":
		return 0.0
	var bonus := float(info["rec"].get("bonus", 0))
	var amount := roundf((bonus + float(_sys("Stats").adjusted_skill("firstAid")) / 2.0) / 100.0 * max_health)
	inv.remove_item(item_name, 1)
	var before := health
	health = minf(max_health, health + amount)
	_push()
	return health - before


## giveWeapon: swaps the inventory weapon `item_name` with the companion's
## current one (the old one goes to the inventory). Returns false if the player
## does not carry it or it is not a weapon.
func give_weapon(item_name: String) -> bool:
	if is_partner() or dead:
		return false
	var inv := _sys("Inventory")
	var w := Weapon.find_by_name(item_name)
	if w == null or not inv.has_item(item_name):
		return false
	var old := gun.weapon
	var old_loaded := gun.loaded
	var new_loaded: int = inv.get_magazine(item_name, w.mag_size)
	inv.remove_item(item_name, 1)
	if old != null and old.ref != "hands":
		inv.add_item(old.display_name, old.weight, 1)
		inv.set_magazine(old.display_name, old_loaded)
	var p := get_tree().get_first_node_in_group("player")
	if p != null and p.get("equipped_weapon") == w.ref and p.has_method("_set_equipped"):
		p.call("_set_equipped", "fist")
	gun.set_weapon(w.ref, new_loaded, -1)
	_push()
	return true


func set_hold(value: bool) -> void:
	hold = value
	if state in ["follow", "hold"]:
		state = "hold" if hold else "follow"
	_push()


# --- damage -------------------------------------------------------------------------

func take_damage(amount: float, zone: String = "chest", source: Node = null, knockback: float = 0.0) -> void:
	if is_partner() or dead:
		return
	if down:
		down_health -= amount
		_flash_t = HIT_FLASH_TIME
		if down_health <= 0.0:
			_die(source)
		return
	super(amount, zone, source, knockback)


func _on_zero_health(_source: Node) -> void:
	down = true
	state = "down"
	target = null
	_set_targetable(false)
	if visual != null:
		visual.rotation.z = PI / 2.0 # lying down until the rig has a down pose
	_play("Idle")
	_push()


func _die(_killer: Node) -> void:
	if dead:
		return
	dead = true
	state = "dead"
	_set_targetable(false)
	remove_from_group("companion")
	if gun.weapon.ref != "hands":
		HumanEnemy.make_drop(get_parent(), "drop_companion_%s_%d" % [npc_id, Time.get_ticks_msec()],
				"%s's weapon" % str(def.get("name", npc_id)), [gun.weapon.ref], global_position.x, 1)
	var c := get_node_or_null("/root/Companions")
	if c != null:
		c.on_companion_died(npc_id)
	died.emit(self)
	queue_free()


func _push() -> void:
	var c := get_node_or_null("/root/Companions")
	if c != null:
		c.sync_from(self)


# --- AI -----------------------------------------------------------------------------

func candidates() -> Array:
	var out: Array = []
	for z in get_tree().get_nodes_in_group("zombie"):
		if z.get("alerted") == true:
			out.append(z)
	for h in get_tree().get_nodes_in_group("hostile_human"):
		out.append(h)
	return out


func think(delta: float) -> float:
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")
		if player == null:
			return 0.0
	if down:
		return 0.0
	gun.tick(delta)
	if is_partner():
		return _follow(delta)
	_retarget_t -= delta
	if target != null and flag_dead(target):
		target = null
	if _retarget_t <= 0.0:
		_retarget_t = RETARGET_TIME
		target = nearest_of(candidates(), TARGET_RANGE)
		_range = SURVIVOR_RANGE
	if target == null:
		if state in ["attack", "chase"]:
			state = "hold" if hold else "follow"
		return _hold_or_follow(delta)
	var dx := target.global_position.x - global_position.x
	var dist := absf(dx)
	var want := _range if gun.is_firearm() else melee_range()
	state = "attack" if dist <= want else "chase"
	set_facing(dx)
	var vx := 0.0
	if state == "chase" and not hold:
		vx = signf(dx) * MOVE_SPEED
	elif state == "attack":
		if gun.is_firearm() and dist < SHOVE_RANGE:
			_shove(dx)
		else:
			attack_tick(delta)
		# stay with the player while shooting (stayCloseDistance)
		if not hold and absf(player.global_position.x - global_position.x) > STAY_CLOSE:
			vx = signf(player.global_position.x - global_position.x) * MOVE_SPEED
	return vx


func _shove(dx: float) -> void:
	if _melee_cd > 0.0 or target == null:
		return
	_melee_cd = MELEE_INTERVAL
	var dmg := CombatRules.melee_final(rng, CombatRules.shove_base(ActorGun.STRENGTH), false,
			CombatActions.armor_for(target, "chest"))
	CombatActions.deal_damage(target, dmg, "chest", self, 1.0)
	set_facing(dx)


func _hold_or_follow(delta: float) -> float:
	if hold:
		return 0.0
	return _follow(delta)


func _follow(delta: float) -> float:
	var px := player.global_position.x
	var gap := px - global_position.x
	if absf(gap) > TELEPORT_DISTANCE:
		global_position.x = px - signf(gap) * 1.0
		return 0.0
	_goal_t -= delta
	if _goal_t <= 0.0:
		_goal_t = 35.0 / 30.0 / 3.0 # wpSetCount
		_follow_goal = px - signf(gap) * (0.5 + 0.5 * index)
	var stop := (rng.randi() % 50 + index * 50) / PX
	var to_goal := _follow_goal - global_position.x
	if absf(to_goal) <= maxf(stop, 0.3):
		return 0.0
	var run: bool = absf(gap) > CATCH_UP or (player.get("running") == true)
	return signf(to_goal) * MOVE_SPEED * (RUN_MULT if run else 1.0)
