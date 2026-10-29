class_name Zombie
extends CharacterBody3D
## Zombie AI as a state machine (docs/ORIGINAL_ANALYSIS.md sec. 8, docs/zombies.md).
## States: idle, wander, rise, chase, attack, grab, stumble. Everything moves on
## X only (Z stays 0). `type_ref` picks the enemy record; `danger_level` sets
## health and damage. Use Zombie.spawn() or configure() to change kind.

signal died(zombie: Zombie)

const SCENE_PATH := "res://scenes/zombie/zombie.tscn"
const PX := ZombieType.PX_PER_UNIT

## Basic zombies limp: speed swings sinusoidally around the base speed (the
## average is unchanged) on a fixed, predictable beat.
const LIMP_AMPLITUDE: float = 0.6
const LIMP_PERIOD: float = 1.2

const BITE_COOLDOWN_TIME: float = 1.0
## Seconds between reaching bite range and the bite landing; a stagger cancels it.
const BITE_WINDUP_TIME: float = 0.4
const STAGGER_TIME: float = 0.25
const HIT_FLASH_TIME: float = 0.1

# Perception (px values from the original, converted with PX).
const SIGHT_RANGE_PX: float = 600.0
const SIGHT_MOD: float = 0.6 # lighting sightMod; 0.6 at every hour
const SENSE_RANGE_PX: float = 150.0
const GRAB_RANGE_PX: float = 65.0
const ATTACK_RANGE_MIN_PX: float = 45.0
const ATTACK_RANGE_VAR_PX: int = 30
const ALERT_RAND_RANGE: int = 500
const ALERT_BASE_CHANCE: int = 5
const ALERT_MELEE_HIT: int = 300
const ALERT_SIGHTED: int = 300
const ALERT_SENSED: int = 100
const ALERT_PER_NOISE: int = 15
const GRAB_CHANCE: int = 100 # of 1000, rolled each time an attack would start
## The original checks perception every frame at 30 fps.
const PERCEPTION_INTERVAL: float = 1.0 / 30.0
## Shots heard from this far (units): the original alerts everything on screen.
const HEARING_RANGE: float = 10.0
## Centre-to-centre gap when two capsules (radius 0.4) touch. Attack and grab
## ranges are edge distances in the original, so add this.
const BODY_CONTACT: float = 0.8
const WANDER_SPEED: float = 1.0
const RISE_TIME: float = 1.2
const RIOT_PAUSE_CHANCE: int = 300 # of 1000, rolled once per RIOT_CHECK_INTERVAL
const RIOT_CHECK_INTERVAL: float = 1.0 # (verify: original rolls per tick)
const RIOT_PAUSE_TIME: float = 3.0 # 90 ticks

@export var type_ref: String = "zombieSlow"
@export var danger_level: int = 1

var type: ZombieType
var enemy_ref: String = "zombieSlow"
var max_health: float = 12.0
var health: float = 12.0
var speed: float = ZombieType.BASE_CHASE_SPEED
var bite_damage: float = 7.0
var state: String = "wander"
var alerted: bool = false
var facing: float = 1.0
var move_time: float = 0.0
var bite_cooldown: float = 0.0
var player: Node3D = null
var stagger_timer: float = 0.0
var stagger_speed: float = 0.0
var windup_timer: float = -1.0
var flash_timer: float = 0.0
var struggle: Struggle = null
var carries_loot: bool = false # director "dropper": drops a backpack on death
var rng := RandomNumberGenerator.new()

var _prev_state: String = "wander"
var _rise_timer: float = 0.0
var _wander_timer: float = 0.0
var _wander_dir: float = 0.0
var _perceive_accum: float = 0.0
var _attack_reach: float = 1.2
var _pause_timer: float = 0.0
var _riot_timer: float = 0.0
var _dead: bool = false
var _retarget_t: float = 0.0

@onready var model: Node3D = $Model
@onready var mesh: MeshInstance3D = _find_by_class(model, "MeshInstance3D")
@onready var anim_player: AnimationPlayer = model.find_child("AnimationPlayer", true, false)

var _flash_material := StandardMaterial3D.new()
var _body_material := StandardMaterial3D.new()


## Autoload lookup by name. Bare autoload identifiers would not compile when a
## `-s` test script pulls this class in before the autoloads exist.
static func _sys(sys_name: String) -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node(sys_name)


## Instantiates a zombie of `ref` at danger `danger`, adds it under `parent`
## at local x (parent assumed at the origin) and returns it.
static func spawn(parent: Node, ref: String, danger: int, x: float) -> Zombie:
	var z: Zombie = (load(SCENE_PATH) as PackedScene).instantiate()
	z.type_ref = ref
	z.danger_level = danger
	z.position = Vector3(x, 1.0, 0.0) # before add_child: no frame at the origin
	parent.add_child(z)
	return z


## Recursively find the first descendant of `root` whose Godot class
## matches `class_name_str` (used instead of find_child-by-name since
## imported glTF meshes keep their Blender object names, e.g.
## "ZombieBasic_Mesh", not a generic "MeshInstance3D").
static func _find_by_class(root: Node, class_name_str: String) -> Node:
	for child in root.get_children():
		if child.get_class() == class_name_str:
			return child
		var found := _find_by_class(child, class_name_str)
		if found != null:
			return found
	return null

func _ready() -> void:
	_flash_material.albedo_color = Color.WHITE
	_flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_body_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	configure(type_ref, danger_level)
	player = get_tree().get_first_node_in_group("player")
	_sys("Events").shot_fired.connect(_on_shot_fired)
	if anim_player:
		for anim_name in ["Idle", "Walk"]:
			if anim_player.has_animation(anim_name):
				anim_player.get_animation(anim_name).loop_mode = Animation.LOOP_PINGPONG
		anim_player.play("Idle")


## (Re)builds stats, look and starting state for an enemy kind and danger.
func configure(ref: String, danger: int) -> void:
	var t := ZombieType.from_ref(ref)
	if t == null:
		push_warning("Zombie: unknown type %s, using zombieSlow" % ref)
		ref = "zombieSlow"
		t = ZombieType.from_ref(ref)
	type = t
	type_ref = ref
	enemy_ref = ref
	danger_level = danger
	max_health = float(t.health_for(danger))
	health = max_health
	bite_damage = t.damage_for(danger)
	speed = t.chase_speed_units()
	alerted = false
	_dead = false
	state = "idle" if (t.start_state == "idle" or t.start_pos != "") else "wander"
	_roll_attack_reach()
	_wander_timer = rng.randf_range(0.5, 2.0)
	if is_node_ready():
		_apply_look()


func _apply_look() -> void:
	# The rigged model is a near-white placeholder: tint it per kind (surface
	# overrides, so the hit flash still takes over while it lasts) and size it.
	_body_material.albedo_color = EnemyLook.color_for(type_ref)
	for i in mesh.mesh.get_surface_count():
		mesh.set_surface_override_material(i, _body_material)
	var s := EnemyLook.scale_for(type_ref)
	model.scale = s
	model.position.y = -0.9 * s.y # keep the feet on the ground


## round((round(danger * 5) + 5) * xpBonus)
func xp_value() -> int:
	return type.xp_for(danger_level)


## Damage multiplier the combat code applies for a hit on `zone` (1.0 if the
## kind has no armor there). Piercing weapons ignore it.
func armor_for(zone: String) -> float:
	return type.armor.get(zone, 1.0) if type != null else 1.0


## True if the kind defines armor for `zone` (even at 1.0).
func has_armor(zone: String) -> bool:
	return type != null and type.armor.has(zone)


func is_dead() -> bool:
	return _dead


func attack_reach() -> float:
	return _attack_reach


func _roll_attack_reach() -> void:
	var px: float = type.attack_range_px if type != null and type.attack_range_px > 0.0 \
			else float(rng.randi() % ATTACK_RANGE_VAR_PX) + ATTACK_RANGE_MIN_PX
	_attack_reach = BODY_CONTACT + px / PX


func _physics_process(delta: float) -> void:
	if _dead:
		return
	_retarget(delta)
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")
		if player == null:
			return

	if flash_timer > 0.0:
		flash_timer -= delta
		if flash_timer <= 0.0:
			mesh.material_override = null

	move_time += delta
	bite_cooldown = maxf(0.0, bite_cooldown - delta)
	var dx: float = player.global_position.x - global_position.x
	var vx := 0.0

	match state:
		"idle":
			_perceive_tick(delta, dx)
		"wander":
			_perceive_tick(delta, dx)
			vx = _wander(delta)
		"rise":
			_rise_timer -= delta
			if _rise_timer <= 0.0:
				_become_alerted()
		"chase":
			vx = _chase(delta, dx)
		"attack":
			_face(dx)
			_attack(delta, dx)
		"grab":
			_face(dx)
			_grabbing(delta)
		"stumble":
			stagger_timer -= delta
			vx = stagger_speed
			windup_timer = -1.0
			if stagger_timer <= 0.0:
				state = _prev_state if _prev_state != "attack" else "chase"

	velocity.x = vx
	velocity.z = 0.0
	if not is_on_floor():
		velocity.y -= 20.0 * delta
	move_and_slide()
	global_position.z = 0.0

	# Face the way the zombie is facing; walk while it moves, idle otherwise.
	model.rotation.y = -PI / 2.0 if facing > 0.0 else PI / 2.0
	if anim_player:
		var desired := "Walk" if absf(velocity.x) > 0.01 else "Idle"
		if anim_player.current_animation != desired:
			anim_player.play(desired)

## Companions register in group "zombie_targets". Every half second the zombie
## aims at the nearest living target (the player included); mid-grab it keeps
## its victim. (Added for the companions workstream.)
func _retarget(delta: float) -> void:
	_retarget_t -= delta
	if _retarget_t > 0.0 or state == "grab":
		return
	_retarget_t = 0.5
	var best: Node3D = get_tree().get_first_node_in_group("player")
	var best_d: float = absf(best.global_position.x - global_position.x) if best != null else INF
	for t in get_tree().get_nodes_in_group("zombie_targets"):
		if t is Node3D and is_instance_valid(t):
			var d: float = absf((t as Node3D).global_position.x - global_position.x)
			if d < best_d:
				best = t
				best_d = d
	if best != null:
		player = best


# --- perception -------------------------------------------------------------

func _perceive_tick(delta: float, dx: float) -> void:
	_perceive_accum += delta
	while _perceive_accum >= PERCEPTION_INTERVAL:
		_perceive_accum -= PERCEPTION_INTERVAL
		if alerted:
			return
		_perceive(dx)


func _perceive(dx: float) -> void:
	var dist := absf(dx)
	var sight := SIGHT_RANGE_PX * SIGHT_MOD / PX
	if dist <= SENSE_RANGE_PX / PX:
		alert_roll(ALERT_SENSED)
	if not alerted and dist <= sight and sign(dx) == facing:
		alert_roll(ALERT_SIGHTED)


## Rolls random(500) < alertChance + bonus. Returns true if the zombie was alerted.
func alert_roll(bonus: int, noise: float = 0.0) -> bool:
	if alerted or _dead or state in ["stumble", "attack", "rise", "grab"]:
		return false
	var chance := ALERT_BASE_CHANCE + bonus + int(noise * ALERT_PER_NOISE)
	if rng.randi() % ALERT_RAND_RANGE < chance:
		_alert()
		return true
	return false


func _alert() -> void:
	if type.start_pos == "deadBack" and state == "idle":
		state = "rise"
		_rise_timer = RISE_TIME
		return
	_become_alerted()


func _become_alerted() -> void:
	alerted = true
	state = "chase"


## Heard a shot (Events.shot_fired): everything within hearing range rolls.
func _on_shot_fired(_weapon_ref: String, noise: float, pos: Vector3) -> void:
	if absf(pos.x - global_position.x) <= HEARING_RANGE:
		alert_roll(0, noise)


# --- movement states --------------------------------------------------------

func _face(dx: float) -> void:
	if dx != 0.0:
		_set_facing(sign(dx))


func _set_facing(dir: float) -> void:
	if dir == 0.0:
		return
	facing = dir
	if mesh.has_method("set_facing"):
		mesh.call("set_facing", dir)


func _wander(delta: float) -> float:
	_wander_timer -= delta
	if _wander_timer <= 0.0:
		var r := rng.randi() % 3
		_wander_dir = 0.0 if r == 0 else (1.0 if r == 1 else -1.0)
		_wander_timer = rng.randf_range(1.5, 4.0)
	_set_facing(_wander_dir)
	return _wander_dir * WANDER_SPEED


func _movement_mult() -> float:
	match type.movement if type != null else "steady":
		"limp":
			return 1.0 + LIMP_AMPLITUDE * sin(TAU * move_time / LIMP_PERIOD)
		_:
			return 1.0


func _chase(delta: float, dx: float) -> float:
	_face(dx)
	if _check_riot_pause(delta):
		return 0.0
	if absf(dx) <= _attack_reach:
		if bite_cooldown <= 0.0:
			_begin_attack(dx)
		return 0.0
	return sign(dx) * speed * _movement_mult()


func _check_riot_pause(delta: float) -> bool:
	if type.ref != "zombieRiotShield":
		return false
	if _pause_timer > 0.0:
		_pause_timer -= delta
		return true
	_riot_timer += delta
	if _riot_timer >= RIOT_CHECK_INTERVAL:
		_riot_timer = 0.0
		if rng.randi() % 1000 < RIOT_PAUSE_CHANCE:
			_pause_timer = RIOT_PAUSE_TIME
	return false


func _player_grabbable() -> bool:
	if not player.has_method("start_grab") or player.get("is_dead") == true:
		return false
	if player.has_method("is_on_floor") and not player.is_on_floor():
		return false
	for z in get_tree().get_nodes_in_group("grabbing_zombie"):
		if z != self:
			return false
	return true


func _begin_attack(dx: float) -> void:
	if not type.no_grab and absf(dx) <= BODY_CONTACT + GRAB_RANGE_PX / PX \
			and rng.randi() % 1000 < GRAB_CHANCE and _player_grabbable():
		_begin_grab()
		return
	state = "attack"
	windup_timer = BITE_WINDUP_TIME


func _attack(delta: float, dx: float) -> void:
	if absf(dx) > _attack_reach:
		windup_timer = -1.0
		state = "chase"
		return
	windup_timer -= delta
	if windup_timer <= 0.0:
		_bite(1.0)
		_roll_attack_reach()
		state = "chase"


func _bite(mult: float) -> void:
	bite_cooldown = BITE_COOLDOWN_TIME
	windup_timer = -1.0
	if player.has_method("take_damage"):
		_damage_player(bite_damage * mult)


func _damage_player(amount: float) -> void:
	player.take_damage(amount, "chest", self)


# --- grab and struggle ------------------------------------------------------

func _begin_grab() -> void:
	state = "grab"
	windup_timer = BITE_WINDUP_TIME
	struggle = Struggle.new()
	var stats := _sys("Stats")
	struggle.begin(stats.level, stats.attr("strength"))
	struggle.escaped.connect(_on_struggle_escaped)
	add_to_group("grabbing_zombie")
	player.start_grab(self)


func _grabbing(delta: float) -> void:
	if player.get("is_dead") == true:
		_end_grab()
		return
	windup_timer -= delta
	if bite_cooldown <= 0.0 and windup_timer <= 0.0:
		_bite(Struggle.DAMAGE_MOD)
		windup_timer = BITE_WINDUP_TIME


## The player script feeds key presses here while grabbed.
func struggle_press(side: String = "") -> void:
	if struggle != null:
		struggle.press(side)


func is_grabbing() -> bool:
	return state == "grab"


func _on_struggle_escaped() -> void:
	var dir: float = -facing
	_end_grab()
	apply_stagger(dir, Struggle.SHOVE_DISTANCE)
	bite_cooldown = BITE_COOLDOWN_TIME


func _end_grab() -> void:
	if struggle != null:
		struggle.cancel()
		struggle = null
	remove_from_group("grabbing_zombie")
	if player != null and is_instance_valid(player) and player.has_method("end_grab"):
		player.end_grab()
	if state == "grab":
		state = "chase"


# --- damage -----------------------------------------------------------------

## Pushes the zombie `distance` world units along X in `direction` (+1/-1)
## over STAGGER_TIME. It can't chase or bite meanwhile, and a bite windup in
## progress is cancelled. Crawlers and dogs are immune.
func apply_stagger(direction: float, distance: float) -> void:
	if _dead or (type != null and type.ref in ["zombieCrawl", "zombieDog"]):
		return
	if state == "grab":
		_end_grab()
	if state != "stumble":
		_prev_state = state
	state = "stumble"
	stagger_timer = STAGGER_TIME
	stagger_speed = sign(direction) * distance / STAGGER_TIME
	windup_timer = -1.0


## `knockback` is the weapon's knockback percent: random(100) < knockback
## staggers (distance 30 + damage + strength + fitness/5 px).
func take_damage(amount: float, zone: String = "chest", source: Node = null, knockback: float = 0.0) -> void:
	if _dead:
		return
	health = maxf(0.0, health - amount)
	mesh.material_override = _flash_material
	flash_timer = HIT_FLASH_TIME
	print("[Zombie] took %.1f damage (%s), health now %.1f" % [amount, zone, health])
	if health <= 0.0:
		_die()
		return
	alert_roll(ALERT_MELEE_HIT)
	if knockback > 0.0 and rng.randi() % 100 < knockback:
		var stats := _sys("Stats")
		var px: float = 30.0 + amount + stats.attr("strength") + roundf(stats.adjusted_skill("fitness") / 5.0)
		var dir: float = 1.0
		if source is Node3D:
			dir = sign(global_position.x - (source as Node3D).global_position.x)
		apply_stagger(dir, px / PX)


func _die() -> void:
	_dead = true
	print("[Zombie] down")
	_end_grab()
	_sys("Events").enemy_killed.emit(enemy_ref, danger_level, xp_value())
	died.emit(self)
	queue_free()
