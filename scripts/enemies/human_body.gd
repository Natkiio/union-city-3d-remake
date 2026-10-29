class_name HumanBody
extends CharacterBody3D
## Shared body of every armed human the AI drives: hostile humans (HumanEnemy)
## and survivors who join the player (Companion). Health, armor, the combat
## entity interface (take_damage / apply_stagger), gravity, the rigged model
## under a child named "Visual", animation, and the attack cycle of
## humanAIRoutine / survivorAIRoutine (docs/companions.md).
##
## Autoloads are reached through _sys() so the class compiles under `-s` tests.

signal died(body: HumanBody)

const MODEL_SCENE := "res://scenes/characters/male_basic.tscn"
const PX := 100.0
const MOVE_SPEED: float = 6.0          ## the original moves humans at player.speed
const HIT_FLASH_TIME: float = 0.1
const STAGGER_TIME: float = 0.25
const FOOT_OFFSET: float = -0.9
## humanAIRoutine: attack wait of 30 ticks, then up to 50 ticks of firing.
const ATTACK_WAIT: float = 1.0
const ATTACK_BURST: float = 1.67
const MELEE_INTERVAL: float = 0.8
const MELEE_RANGE_PX: float = 80.0     ## humanMeleeRange / survivorMeleeRange
const SHOVE_RANGE: float = 0.6         ## survivors shove at under 60 px
const CHAINSAW_RANGE_PX: float = 100.0
const FLAME_RANGE_PX: float = 150.0
const SHOT_RANGE_PX: float = 400.0     ## humanRange / survivorRange
const CROUCH_TOGGLE_CHANCE: int = 100  ## random(100) == 0 per burst tick

var npc_id: String = ""
var def: Dictionary = {}
var enemy_ref: String = ""
var danger_level: int = 1
var xp_bonus: float = 1.0
var skill: float = 10.0                ## enemyWeaponSkill 10, companionWeaponSkill 30
var max_health: float = 40.0
var health: float = 40.0
var armor: Dictionary = {}             ## zone -> multiplier
var gun: ActorGun = ActorGun.new("hands")
var state: String = "idle"
var facing: float = 1.0
var target: Node3D = null
var dead: bool = false
var crouched: bool = false
var rng := RandomNumberGenerator.new()

var _attack_clock: float = 0.0
var _burst_clock: float = 0.0
var _melee_cd: float = 0.0
var _stagger_t: float = 0.0
var _stagger_v: float = 0.0
var _flash_t: float = 0.0
var _meshes: Array[MeshInstance3D] = []
var _mat := StandardMaterial3D.new()
var _flash := StandardMaterial3D.new()
var _anim: AnimationPlayer = null
var visual: Node3D = null


static func _sys(sys_name: String) -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node(sys_name)


func _ready() -> void:
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash.albedo_color = Color.WHITE
	_build_visual()
	collision_mask = 1
	if rng.seed == 0:
		rng.randomize()


# --- look ----------------------------------------------------------------------------

func _build_visual() -> void:
	visual = get_node_or_null("Visual")
	if visual == null:
		visual = Node3D.new()
		visual.name = "Visual"
		add_child(visual)
	if visual.get_child_count() == 0 and ResourceLoader.exists(MODEL_SCENE):
		visual.add_child((load(MODEL_SCENE) as PackedScene).instantiate())
	visual.position.y = FOOT_OFFSET
	_meshes.clear()
	for m in visual.find_children("*", "MeshInstance3D", true, false):
		_meshes.append(m)
	_anim = visual.find_child("AnimationPlayer", true, false)
	if _anim != null:
		for n in ["Idle", "Walk"]:
			if _anim.has_animation(n):
				_anim.get_animation(n).loop_mode = Animation.LOOP_PINGPONG
		_play("Idle")
	_apply_tint()


## Colour from the NPC's top, so each person reads differently until real
## clothing exists. Overridable.
func look_color() -> Color:
	var top := str(def.get("clothesTop", ""))
	return Color.from_hsv(float(top.hash() % 360) / 360.0, 0.45, 0.65)


func _apply_tint() -> void:
	_mat.albedo_color = look_color()
	for m in _meshes:
		for i in m.mesh.get_surface_count():
			m.set_surface_override_material(i, _mat)


func _play(anim_name: String) -> void:
	if _anim != null and _anim.has_animation(anim_name) and _anim.current_animation != anim_name:
		_anim.play(anim_name)


func set_facing(dir: float) -> void:
	if dir == 0.0:
		return
	facing = signf(dir)
	if visual != null:
		visual.rotation.y = -PI / 2.0 if facing > 0.0 else PI / 2.0 # as the player model


# --- stats -------------------------------------------------------------------------

## Default health when the NPC record has none: the player formula
## 20 + endurance^2 + level * 10 with endurance 5 and level = danger **(verify)**.
static func default_health(danger: int) -> float:
	return float(20 + 25 + danger * 10)


## round((round(danger * 5) + 5) * xpBonus)
static func xp_for(danger: int, bonus: float) -> int:
	return roundi((roundi(danger * 5.0) + 5) * bonus)


func xp_value() -> int:
	return xp_for(danger_level, xp_bonus)


## Remake rule **(verify)**: clothing implies armor. Army tops and HERC suits
## halve damage to the chest and belly (HERC a little more); nothing else does.
static func armor_from_clothes(top: String) -> Dictionary:
	var t := top.to_lower()
	if t.contains("herc"):
		return {"chest": 0.4, "belly": 0.4}
	if t.contains("army") or t.contains("police"):
		return {"chest": 0.5, "belly": 0.5}
	return {}


func armor_for(zone: String) -> float:
	return armor.get(zone, 1.0)


func has_armor(zone: String) -> bool:
	return armor.has(zone)


func is_dead() -> bool:
	return dead


func equip(weapon_ref: String, loaded: int = -1, reserve: int = -1) -> void:
	gun.set_weapon(weapon_ref, loaded, reserve)


## Shooting range in units, with the original's random(80) - 40 px jitter.
func shot_range() -> float:
	return (SHOT_RANGE_PX + float(rng.randi() % 80) - 40.0) / PX


func melee_range() -> float:
	if gun.weapon.weapon_type == "chainsaw":
		return CHAINSAW_RANGE_PX / PX
	if gun.weapon.weapon_type == "flameThrower":
		return FLAME_RANGE_PX / PX
	return MELEE_RANGE_PX / PX


# --- combat entity interface ---------------------------------------------------------

func take_damage(amount: float, zone: String = "chest", source: Node = null, knockback: float = 0.0) -> void:
	if dead:
		return
	health = maxf(0.0, health - amount)
	_flash_t = HIT_FLASH_TIME
	for m in _meshes:
		m.material_override = _flash
	_on_hurt(amount, zone, source)
	if health <= 0.0:
		_on_zero_health(source)
		return
	if knockback > 0.0 and source is Node3D:
		apply_stagger(signf(global_position.x - (source as Node3D).global_position.x), knockback)


func _on_hurt(_amount: float, _zone: String, _source: Node) -> void:
	pass


func _on_zero_health(source: Node) -> void:
	_die(source)


func apply_stagger(direction: float, distance: float) -> void:
	if dead:
		return
	_stagger_t = STAGGER_TIME
	_stagger_v = signf(direction) * distance / STAGGER_TIME
	_melee_cd = maxf(_melee_cd, 0.4)


func _die(_killer: Node) -> void:
	dead = true
	state = "dead"
	died.emit(self)
	queue_free()


# --- attack cycle --------------------------------------------------------------------

## One frame of the attack loop on `target`: wait, then burst-fire (or swing),
## reloading when the magazine runs dry. Returns true if a shot or swing left.
func attack_tick(delta: float) -> bool:
	gun.tick(delta)
	_melee_cd = maxf(0.0, _melee_cd - delta)
	if target == null or not is_instance_valid(target):
		return false
	set_facing(target.global_position.x - global_position.x)
	_attack_clock += delta
	if _attack_clock < ATTACK_WAIT:
		return false
	_burst_clock += delta
	if _burst_clock > ATTACK_BURST:
		_burst_clock = 0.0
		_attack_clock = 0.0
		return false
	return attack_once()


## Fires or swings right now, ignoring the burst timing. Used by the cycle and
## by tests.
func attack_once() -> bool:
	if target == null or not is_instance_valid(target):
		return false
	var dist := absf(target.global_position.x - global_position.x)
	if gun.is_firearm():
		if gun.needs_reload():
			gun.start_reload()
			return false
		if rng.randi() % CROUCH_TOGGLE_CHANCE == 0 and rng.randi() % 2 == 0:
			crouched = not crouched
		if gun.can_fire():
			var r := gun.fire(self, target, skill, rng, crouched, absf(velocity.x) > 0.1)
			return r["fired"]
		return false
	# melee, chainsaw, flamethrower, fists
	if dist <= melee_range() + 0.8 and _melee_cd <= 0.0: # + capsule contact gap
		_melee_cd = MELEE_INTERVAL
		gun.swing(self, target, skill, rng)
		return true
	return false


# --- movement ------------------------------------------------------------------------

## Subclasses return the desired horizontal velocity for this frame.
func think(_delta: float) -> float:
	return 0.0


func _physics_process(delta: float) -> void:
	if dead:
		return
	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0:
			for m in _meshes:
				m.material_override = null
	var vx := think(delta)
	if _stagger_t > 0.0:
		_stagger_t -= delta
		vx = _stagger_v
	velocity.x = vx
	velocity.z = 0.0
	if not is_on_floor():
		velocity.y -= 20.0 * delta
	move_and_slide()
	global_position.z = 0.0
	if absf(vx) > 0.1:
		_play("Walk")
		if _stagger_t <= 0.0:
			set_facing(vx)
	else:
		_play("Idle")


## Nearest node in `nodes` that is alive, within `max_dist` on X.
func nearest_of(nodes: Array, max_dist: float) -> Node3D:
	var best: Node3D = null
	var best_d := max_dist
	for n in nodes:
		if not (n is Node3D) or not is_instance_valid(n) or n == self:
			continue
		if flag_dead(n):
			continue
		var d := absf((n as Node3D).global_position.x - global_position.x)
		if d < best_d:
			best_d = d
			best = n
	return best


## True when `n` is dead by method (`is_dead()`) or by flag (the player node's
## `is_dead` variable).
static func flag_dead(n: Object) -> bool:
	if n == null or not is_instance_valid(n):
		return true
	if n.has_method("is_dead"):
		return bool(n.call("is_dead"))
	var v = n.get("is_dead")
	return v is bool and v
