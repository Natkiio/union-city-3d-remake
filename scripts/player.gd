extends CharacterBody3D
## 2.5D side-scroller player controller.
## Movement is locked to the X axis to match the original flash game's
## left/right lane movement; Z stays fixed on the game's "street plane".
## Facing and aim are driven by the mouse, not movement — matching the
## original game, where you aim with the cursor independently of which
## way you're walking.
##
## Combat: the player holds a boxing guard (elbows bent, fists up) at
## all times, and both arms continuously track the mouse's vertical
## aim (not just the punching arm) so the whole stance visibly leans
## up/down with the cursor. Each attack throws a punch with whichever
## arm is due next, alternating left/right every click, straightening
## that arm toward the aim target and back to guard; the other arm
## stays bent in guard the whole time. No separate floating prop —
## this is the model's own rigged arms.

const SPEED: float = 6.0
const JUMP_VELOCITY: float = 8.0
## Movement speed factor while Inventory.overweight. The original subtracts a
## flat 50 from a base of 7.5 and clamps at 0 (so an overloaded character
## cannot walk or jump at all). We keep the player able to crawl so a run is
## never softlocked; set this to 0.0 for exact parity. Jumping stays disabled.
const OVERWEIGHT_SPEED_FACTOR: float = 0.25
const RUN_SPEED_MULT: float = 1.5
const CROUCH_SPEED_DIV: float = 2.0
const MAX_AIM_PITCH_DEG: float = 80.0

const GUARD_FOREARM_BEND_DEG: float = 110.0
const PUNCH_DURATION: float = 0.3

## Horizontal reach in front of the player; the hand hitbox is too pose-dependent.
const SHOVE_RANGE: float = 1.6
const SHOVE_COOLDOWN_TIME: float = 0.6
const HIT_STOP_FRAMES: int = 3

## Extra half-angle of scatter for shotgun pellets on top of the accuracy
## spread (our own tuning, verify against the original).
const PELLET_SCATTER_RAD: float = 0.06
## Seconds without firing before the consecutive-round spread penalty resets (verify).
const SPREAD_RESET_TIME: float = 0.6
## One stamina / regen tick is 5 original frames; run cost applies per frame.
const STAMINA_TICK: float = 5.0 / 30.0
const STAMINA_FRAME: float = 1.0 / 30.0

## Per-hour rest healing (sleepWait): max health fraction, and the stamina
## fraction restored. Plus a flat part from fitness and endurance, see rest().
const REST_HEALTH_FRACTION: float = 0.1
const REST_STAMINA_FRACTION: float = 0.2

## Current health, the ceiling regen can restore it to (drops by damage/1.85 per
## hit), and the absolute ceiling from Stats.max_health().
var health: float = 0.0
var perm_health: float = 0.0
var max_health: float = 0.0
var stamina: float = 0.0
var stamina_max: float = 0.0
var crouched: bool = false
var running: bool = false
var consecutive_rounds: int = 0
var rng := RandomNumberGenerator.new()
var is_dead: bool = false
var _regen_delay_ticks: int = 0
var _regen_clock: float = 0.0
var _stamina_delay_ticks: int = 0
var _stamina_clock: float = 0.0
var _run_cost_clock: float = 0.0
var _since_shot: float = 99.0
var attack_cooldown: float = 0.0
var shove_cooldown: float = 0.0
var _hit_stopping: bool = false
## Firearm state. Cleared whenever the equipped gun changes.
var reloading: bool = false
var reload_timer: float = 0.0
var burst_left: int = 0

## The zombie holding the player, or null. Set by start_grab / end_grab.
var grabbed_by: Node = null
var _struggle_prompt: StrugglePrompt = null

var facing_dir: float = 1.0
var aim_pitch: float = 0.0

var punch_side: String = "R" # which arm last punched / is currently punching
var is_punching: bool = false
var punch_timer: float = 0.0
var punch_did_hit: bool = false

## "fist" (default boxing guard) or the Weapon ref of an equipped firearm,
## e.g. "glock". Switches with equip_fists / equip_gun; a firearm is only
## equippable once one is in Inventory.
var equipped_weapon: String = "fist"
const BulletScene := preload("res://scenes/weapons/bullet.tscn")

@onready var model: Node3D = $Model
@onready var attack_area_r: Area3D = $Model/MaleBasic_Armature/Skeleton3D/HandAttachment_R/AttackArea_R
@onready var attack_area_l: Area3D = $Model/MaleBasic_Armature/Skeleton3D/HandAttachment_L/AttackArea_L
@onready var anim_player: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
@onready var skeleton: Skeleton3D = model.find_child("Skeleton3D", true, false)
@onready var upper_arm_r_idx: int = skeleton.find_bone("UpperArm_R") if skeleton else -1
@onready var forearm_r_idx: int = skeleton.find_bone("Forearm_R") if skeleton else -1
@onready var upper_arm_l_idx: int = skeleton.find_bone("UpperArm_L") if skeleton else -1
@onready var forearm_l_idx: int = skeleton.find_bone("Forearm_L") if skeleton else -1

## Both UpperArm_L/R hang straight down at rest and need to be raised
## to a forward-ish pose, but they need OPPOSITE sign Z rotations to
## both end up pointing forward (their rest bone-roll isn't mirrored
## the way their position is) -- confirmed empirically at runtime, not
## assumed. The pitch (X) axis sign is the same for both sides, and
## the forearm bend (also X) is the same sign for both sides too.
func _upper_arm_pose(pitch_deg: float, is_left: bool) -> Quaternion:
	var raise_angle := PI / 2.0 if is_left else -PI / 2.0
	var raise_b := Basis(Vector3(0, 0, 1), raise_angle)
	var pitch_b := Basis(Vector3(1, 0, 0), deg_to_rad(pitch_deg))
	return (raise_b * pitch_b).get_rotation_quaternion()

func _forearm_pose(bend_deg: float) -> Quaternion:
	return Basis(Vector3(1, 0, 0), deg_to_rad(bend_deg)).get_rotation_quaternion()

func _ready() -> void:
	rng.randomize()
	refresh_vitals()
	full_heal()
	stamina = stamina_max
	Events.stats_changed.connect(refresh_vitals)
	Events.level_up.connect(_on_level_up)
	if GameState.has_pending_spawn:
		global_position.x = GameState.consume_spawn()
	model.rotation.y = -PI / 2.0 if facing_dir > 0.0 else PI / 2.0
	if anim_player:
		for anim_name in ["Idle", "Walk"]:
			if anim_player.has_animation(anim_name):
				anim_player.get_animation(anim_name).loop_mode = Animation.LOOP_PINGPONG
		anim_player.play("Idle")
	# AnimationPlayer also keyframes the arms (for the idle/walk swing);
	# it updates during the default idle-process pass. Run our own
	# guard/punch pose override AFTER that in the same frame, or the
	# animation would stomp it right back to the walk/idle pose.
	set_process_priority(100)

func _physics_process(delta: float) -> void:
	var grabbed := is_grabbed()
	var input_dir := 0.0
	if not grabbed:
		if Input.is_action_pressed("move_left"):
			input_dir -= 1.0
		if Input.is_action_pressed("move_right"):
			input_dir += 1.0
	else:
		_struggle_input()

	crouched = Input.is_action_pressed("crouch") and is_on_floor() and not grabbed
	running = Input.is_action_pressed("run") and input_dir != 0.0 and not crouched and stamina > 0.0
	var speed := SPEED
	if crouched:
		speed /= CROUCH_SPEED_DIV
	elif running:
		speed *= RUN_SPEED_MULT
		_run_cost_clock += delta
		while _run_cost_clock >= STAMINA_FRAME:
			_run_cost_clock -= STAMINA_FRAME
			_use_stamina(CombatRules.STAMINA_COST_RUN)
	if Inventory.overweight:
		speed *= OVERWEIGHT_SPEED_FACTOR
	velocity.x = input_dir * speed
	velocity.z = 0.0 # locked to the street plane, 2.5D style
	if Input.is_action_just_pressed("jump") and is_on_floor() and not crouched and not grabbed \
			and not Inventory.overweight and stamina > 0.0:
		velocity.y = JUMP_VELOCITY
		_use_stamina(CombatRules.STAMINA_COST_JUMP)
	if not is_on_floor():
		velocity.y -= 20.0 * delta

	move_and_slide()
	_tick_vitals(delta)

	_update_aim()
	_update_held_item()

	if anim_player:
		var desired := "Walk" if input_dir != 0.0 else "Idle"
		if anim_player.current_animation != desired:
			anim_player.play(desired)

	attack_cooldown = max(0.0, attack_cooldown - delta)
	shove_cooldown = max(0.0, shove_cooldown - delta)
	if Input.is_action_just_pressed("shove") and shove_cooldown <= 0.0 and stamina > 0.0:
		_shove()
	if Input.is_action_just_pressed("equip_fists"):
		_set_equipped("fist")
		print("[Player] equipped fists")
	if Input.is_action_just_pressed("equip_gun"):
		var gun := _first_firearm_in_inventory()
		if gun != null:
			_set_equipped(gun.ref)
			print("[Player] equipped %s" % gun.display_name)

	_since_shot += delta
	if _since_shot > SPREAD_RESET_TIME:
		consecutive_rounds = 0
	var gun := Weapon.from_ref(equipped_weapon)
	if gun == null or not gun.is_firearm():
		if Input.is_action_just_pressed("attack") and attack_cooldown <= 0.0:
			_start_punch()
	else:
		_update_firearm(delta)


func _process(delta: float) -> void:
	if not skeleton:
		return

	var extension := 0.0
	if is_punching:
		punch_timer += delta
		var t := punch_timer / PUNCH_DURATION
		if t >= 1.0:
			is_punching = false
		else:
			# Triangular curve: 0 -> 1 (fully extended) -> 0, so the
			# punch snaps out toward the aim target and back to guard.
			extension = 1.0 - abs(t - 0.5) * 2.0
			if not punch_did_hit and t >= 0.45:
				_apply_punch_damage()
				punch_did_hit = true

	# Both arms continuously track the mouse's vertical aim (the upper
	# arm pitch), so the whole guard visibly leans toward the cursor;
	# only the forearm bend (elbow tuck) differs between guard and a
	# punch in progress.
	var pitch_deg := rad_to_deg(aim_pitch)
	var right_bend := GUARD_FOREARM_BEND_DEG
	var left_bend := GUARD_FOREARM_BEND_DEG

	if _equipped_firearm() != null:
		# Arm held straight out toward the aim point, not tucked into
		# a guard -- this is what makes it visibly "aim with the gun".
		right_bend = 0.0
	elif is_punching and punch_side == "R":
		right_bend = lerp(GUARD_FOREARM_BEND_DEG, 0.0, extension)
	elif is_punching and punch_side == "L":
		left_bend = lerp(GUARD_FOREARM_BEND_DEG, 0.0, extension)

	if upper_arm_r_idx >= 0:
		skeleton.set_bone_pose_rotation(upper_arm_r_idx, _upper_arm_pose(pitch_deg, false))
	if forearm_r_idx >= 0:
		skeleton.set_bone_pose_rotation(forearm_r_idx, _forearm_pose(right_bend))
	if upper_arm_l_idx >= 0:
		skeleton.set_bone_pose_rotation(upper_arm_l_idx, _upper_arm_pose(pitch_deg, true))
	if forearm_l_idx >= 0:
		skeleton.set_bone_pose_rotation(forearm_l_idx, _forearm_pose(left_bend))


func _update_aim() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var mouse_pos := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse_pos)
	var ray_dir := camera.project_ray_normal(mouse_pos)
	# The whole game lives on a fixed-depth plane (Z is locked); intersect
	# the mouse ray with that plane to get a world-space aim point.
	var plane := Plane(Vector3(0, 0, 1), global_position.z)
	var hit = plane.intersects_ray(ray_origin, ray_dir)
	if hit == null:
		return
	_apply_aim(hit)


## Given a world-space aim point, face the body toward it (left/right)
## and store the pitch used to pose the punching arm. Split out from
## _update_aim() so it can be tested directly without depending on
## screen/mouse plumbing.
func _apply_aim(aim_point: Vector3) -> void:
	var dx := aim_point.x - global_position.x
	if is_grabbed():
		facing_dir = signf(grabbed_by.global_position.x - global_position.x) if grabbed_by.global_position.x != global_position.x else facing_dir
	elif abs(dx) > 0.05:
		facing_dir = sign(dx)
	model.rotation.y = -PI / 2.0 if facing_dir > 0.0 else PI / 2.0

	var shoulder_height := global_position.y + 0.4
	var dy := aim_point.y - shoulder_height
	var horiz: float = max(abs(dx), 0.2) # avoid a degenerate near-vertical aim
	aim_pitch = clamp(atan2(dy, horiz), -deg_to_rad(MAX_AIM_PITCH_DEG), deg_to_rad(MAX_AIM_PITCH_DEG))


## Starts a punch with whichever arm is due next (always the opposite
## of the last one thrown), so clicks alternate left/right every time.
func _start_punch() -> void:
	attack_cooldown = _melee_weapon().melee_interval()
	punch_side = "L" if punch_side == "R" else "R"
	is_punching = true
	punch_timer = 0.0
	punch_did_hit = false
	print("[Player] threw a %s punch" % punch_side)


## Direction vector pointing at the current aim target, reconstructed
## from the same facing_dir/aim_pitch the mouse-aim system already
## maintains every frame -- so a bullet always flies exactly where the
## arm is pointing (and where the cursor currently is).
func _aim_direction() -> Vector3:
	return Vector3(cos(aim_pitch) * facing_dir, sin(aim_pitch), 0.0).normalized()


## The equipped weapon as a simple flat silhouette at the right hand, pointing
## along the aim. The imported model has no weapon mesh of its own.
var _held_pivot: Node3D = null
var _held_ref: String = ""

func _update_held_item() -> void:
	var weapon := Weapon.from_ref(equipped_weapon) if equipped_weapon != "fist" else null
	if weapon == null or weapon.ref == "hands":
		if _held_pivot != null:
			_held_pivot.visible = false
		return
	if _held_pivot == null:
		_held_pivot = Node3D.new()
		_held_pivot.name = "HeldItem"
		_held_pivot.top_level = true
		add_child(_held_pivot)
	if _held_ref != weapon.ref:
		_held_ref = weapon.ref
		for c in _held_pivot.get_children():
			c.queue_free()
		_build_held_shape(weapon)
	_held_pivot.visible = true
	var hand := get_node_or_null("Model/MaleBasic_Armature/Skeleton3D/HandAttachment_R") as Node3D
	var origin := hand.global_position if hand != null else global_position + Vector3(0.0, 0.2, 0.0)
	var d := _aim_direction()
	_held_pivot.global_position = Vector3(origin.x, origin.y, 0.0)
	_held_pivot.rotation = Vector3(0.0, 0.0, atan2(d.y, d.x))
	_held_pivot.scale = Vector3(1.0, 1.0 if d.x >= 0.0 else -1.0, 1.0) # keep the grip down when facing left


func _build_held_shape(weapon: Weapon) -> void:
	var dark := _held_material(Color(0.04, 0.04, 0.05))
	var steel := _held_material(Color(0.14, 0.15, 0.18)) # gunmetal, so it reads against the light model
	if weapon.is_firearm():
		var long_gun := not weapon.weapon_type.begins_with("pistol")
		var barrel_len := 0.85 if long_gun else 0.38
		_held_box(Vector3(barrel_len, 0.11, 0.08), Vector3(barrel_len * 0.5, 0.0, 0.0), steel)
		_held_box(Vector3(0.09, 0.2, 0.07), Vector3(0.06, -0.14, 0.0), dark)
		if long_gun:
			_held_box(Vector3(0.3, 0.12, 0.07), Vector3(-0.1, -0.03, 0.0), dark) # stock
	else:
		var length := 0.9 if weapon.weapon_type == "twoHand" else 0.5
		_held_box(Vector3(length, 0.07, 0.07), Vector3(length * 0.5 - 0.1, 0.0, 0.0), steel)
		_held_box(Vector3(0.18, 0.09, 0.08), Vector3(0.0, 0.0, 0.0), dark)


func _held_box(size: Vector3, pos: Vector3, mat: Material) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	box.material = mat
	mesh.mesh = box
	mesh.position = pos
	_held_pivot.add_child(mesh)


func _held_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


## Switching weapons drops any reload or burst in progress.
func _set_equipped(weapon_ref: String) -> void:
	if weapon_ref != equipped_weapon:
		reloading = false
		burst_left = 0
	equipped_weapon = weapon_ref


## First firearm found in Inventory, or null. Inventory keys firearms by
## their original display name, so each key is looked up in the weapon table.
func _first_firearm_in_inventory() -> Weapon:
	for item_name in Inventory.items:
		var weapon := Weapon.find_by_name(item_name)
		if weapon != null and weapon.is_firearm():
			return weapon
	return null


## Firearm loop: reload key, trigger (hold for auto, click otherwise),
## burst rounds, and the fire-rate cooldown. Rounds come from the loaded
## magazine; reserve ammo is only touched by reloading.
func _update_firearm(delta: float) -> void:
	var gun := Weapon.from_ref(equipped_weapon)
	if gun == null:
		return
	if Input.is_action_just_pressed("reload"):
		_start_reload(gun)
	if reloading:
		_tick_reload(delta, gun)

	var pulled := Input.is_action_pressed("attack") if gun.is_auto() else Input.is_action_just_pressed("attack")
	if pulled and burst_left == 0 and attack_cooldown <= 0.0:
		if reloading:
			# Only a pump action can be interrupted, the way the original's pump
			# raise works. Any other reload blocks the trigger.
			if not (gun.reloads_per_round() and _loaded_rounds(gun) > 0):
				return
			reloading = false
		if _loaded_rounds(gun) <= 0:
			print("[Player] %s is empty" % gun.display_name)
			_start_reload(gun)
			return
		burst_left = maxi(gun.burst_size, 1)

	if burst_left > 0 and attack_cooldown <= 0.0:
		if _loaded_rounds(gun) <= 0:
			burst_left = 0
			return
		_fire_round(gun)
		burst_left -= 1


func _fire_round(gun: Weapon) -> void:
	var loaded := _loaded_rounds(gun) - 1
	Inventory.set_magazine(gun.display_name, loaded)
	attack_cooldown = gun.fire_interval()
	_since_shot = 0.0

	var moving := absf(velocity.x) > 0.1
	var raw := CombatRules.spread_skill(Stats.skill(gun.skill), crouched, moving, not is_on_floor())
	var spread := CombatRules.spread_degrees(raw, gun.accuracy, consecutive_rounds)
	consecutive_rounds += 1
	var ctx := {
		"adjusted_skill": Stats.adjusted_skill(gun.skill),
		"luck": Stats.attr("luck"),
		"strength": Stats.attr("strength"),
		"fitness": Stats.adjusted_skill("fitness"),
		"crouched": crouched,
		"piercing": gun.has_piercing,
		"knockback": gun.knockback,
		"never_miss": gun.never_misses(),
		"is_player": true,
		"speed": gun.bullet_speed(),
		"splash_damage": gun.splash_damage,
		"splash_size": gun.splash_size,
		"rng": rng,
	}
	var aim := _aim_direction().rotated(Vector3.BACK, CombatRules.spread_offset(rng, spread))
	for i in gun.rounds_per_shot:
		var dir := aim
		if gun.rounds_per_shot > 1:
			# Pellets from one shell scatter; the shell is still one round.
			dir = aim.rotated(Vector3.BACK, rng.randf_range(-PELLET_SCATTER_RAD, PELLET_SCATTER_RAD))
		var bullet := BulletScene.instantiate()
		get_parent().add_child(bullet)
		# The hand hangs a little off the street plane; rounds fly on the Z=0 lane.
		bullet.global_position = Vector3(attack_area_r.global_position.x, attack_area_r.global_position.y, global_position.z)
		bullet.setup(dir, self, gun.damage, ctx)
	Events.shot_fired.emit(gun.ref, gun.weapon_noise, attack_area_r.global_position)
	print("[Player] fired %s, %d/%d loaded, %d in reserve" % [gun.display_name, loaded, gun.mag_size, _reserve(gun)])


func _start_reload(gun: Weapon) -> void:
	if reloading or _loaded_rounds(gun) >= gun.mag_size or _reserve(gun) <= 0:
		return
	reloading = true
	reload_timer = gun.reload_seconds()
	burst_left = 0
	print("[Player] reloading %s" % gun.display_name)


## Full reloads finish in one go. Pump actions add one shell per reload
## cycle until the magazine is full or the reserve runs out.
func _tick_reload(delta: float, gun: Weapon) -> void:
	reload_timer -= delta
	if reload_timer > 0.0:
		return
	var room := gun.mag_size - _loaded_rounds(gun)
	var take := mini(1 if gun.reloads_per_round() else room, mini(room, _reserve(gun)))
	if take > 0:
		Inventory.remove_item(gun.ammo_item_name(), take)
		Inventory.set_magazine(gun.display_name, _loaded_rounds(gun) + take)
	var done := take == 0 or not gun.reloads_per_round() or _loaded_rounds(gun) >= gun.mag_size or _reserve(gun) <= 0
	if done:
		reloading = false
		print("[Player] reloaded %s, %d/%d loaded" % [gun.display_name, _loaded_rounds(gun), gun.mag_size])
	else:
		reload_timer = gun.reload_seconds()


func _loaded_rounds(gun: Weapon) -> int:
	return Inventory.get_magazine(gun.display_name, gun.mag_size)


func _reserve(gun: Weapon) -> int:
	return Inventory.items.get(gun.ammo_item_name(), {}).get("count", 0)


## Short-range push with no weapon needed. Always staggers.
func _shove() -> void:
	shove_cooldown = SHOVE_COOLDOWN_TIME
	_use_stamina(CombatRules.STAMINA_COST_SHOVE)
	print("[Player] shoved")
	var targets: Array[Node3D] = []
	for node in get_parent().get_children():
		var dx: float = node.global_position.x - global_position.x if node is Node3D else INF
		if node != self and node.has_method("apply_stagger") and dx * facing_dir > 0.0 and absf(dx) <= SHOVE_RANGE:
			targets.append(node)
	_melee_strike(targets, CombatRules.shove_base(Stats.attr("strength")), "blunt", true)


func _apply_punch_damage() -> void:
	var area := attack_area_r if punch_side == "R" else attack_area_l
	var weapon := _melee_weapon()
	var base := CombatRules.melee_base(weapon.damage if weapon.damage > 0.0 else -1.0,
			Stats.attr("strength"), Stats.adjusted_skill(weapon.skill))
	_melee_strike(area.get_overlapping_bodies(), base, weapon.skill, false, weapon.knockback, area.global_position.y)


## Resolves a melee hit on each body: shave, crit, armor, damage, then stumble.
## Shoves always stagger; swings stagger on a crit or a knockback roll. The
## zone (for armor) comes from `hit_y`, the height of the striking hand; NAN
## (shoves) means the chest.
func _melee_strike(bodies: Array, base: float, skill_name: String, always_stagger: bool,
		weapon_knockback: float = 0.0, hit_y: float = NAN) -> void:
	var adjusted := Stats.adjusted_skill(skill_name)
	for body in bodies:
		if body == self:
			continue # the hitbox sits on our own hand; never hit ourselves
		if not body.has_method("take_damage"):
			continue
		var zone := "chest" if is_nan(hit_y) or not body is Node3D else CombatActions.zone_at(body, hit_y)
		var crit := CombatRules.roll_crit(rng, Stats.attr("luck"), adjusted)
		var dmg := CombatRules.melee_final(rng, base, crit, CombatActions.armor_for(body, zone))
		var stagger := always_stagger or crit or CombatRules.roll_knockback(rng, weapon_knockback)
		var kb := 0.0
		if stagger:
			kb = CombatRules.px_to_units(CombatRules.stumble_px(dmg, Stats.attr("strength"), Stats.adjusted_skill("fitness")))
		CombatActions.deal_damage(body, dmg, zone, self, kb)
		_hit_stop()


## Freezes the game for HIT_STOP_FRAMES rendered frames to sell the hit.
func _hit_stop() -> void:
	if _hit_stopping:
		return
	_hit_stopping = true
	Engine.time_scale = 0.0
	for i in HIT_STOP_FRAMES:
		await get_tree().process_frame
	Engine.time_scale = 1.0
	_hit_stopping = false


## The equipped firearm, or null when fists or a melee weapon are out.
func _equipped_firearm() -> Weapon:
	var gun := Weapon.from_ref(equipped_weapon)
	return gun if gun != null and gun.is_firearm() else null


## The weapon a swing uses: the equipped melee weapon, else bare hands.
func _melee_weapon() -> Weapon:
	var weapon := Weapon.from_ref(equipped_weapon)
	if weapon != null and not weapon.is_firearm():
		return weapon
	return Weapon.from_ref("hands")


# --- Grab and struggle ----------------------------------------------------

## Called by the zombie that grabs us. Movement and jumping lock, we face the
## zombie, and the A / D (move_left / move_right) presses feed its struggle.
func start_grab(zombie: Node) -> void:
	grabbed_by = zombie
	velocity.x = 0.0
	if zombie is Node3D and zombie.global_position.x != global_position.x:
		facing_dir = signf(zombie.global_position.x - global_position.x)
	if _struggle_prompt == null:
		_struggle_prompt = StrugglePrompt.new()
		add_child(_struggle_prompt)
	_struggle_prompt.setup(zombie)


## Called by the zombie when it lets go (escape, stagger, death). Idempotent.
func end_grab() -> void:
	grabbed_by = null
	if _struggle_prompt != null:
		_struggle_prompt.queue_free()
		_struggle_prompt = null


func is_grabbed() -> bool:
	return grabbed_by != null and is_instance_valid(grabbed_by)


## Routes the press of either move key into the grabbing zombie's struggle.
## "A" is whatever the move_left action is bound to (Q on AZERTY), "D" move_right.
func _struggle_input() -> void:
	if not grabbed_by.has_method("struggle_press"):
		return
	if Input.is_action_just_pressed("move_left"):
		grabbed_by.struggle_press("A")
	elif Input.is_action_just_pressed("move_right"):
		grabbed_by.struggle_press("D")


# --- Vitals ---------------------------------------------------------------

## Re-reads the ceilings from Stats (level-ups, endurance and hunger changes).
## Keeps current health, perm health and stamina, clamped to the new ceilings.
func refresh_vitals() -> void:
	max_health = Stats.max_health()
	var hunger_penalty: float = Survival.hunger_penalty()
	stamina_max = CombatRules.stamina_max(Stats.level, Stats.attr("endurance"), hunger_penalty, Stats.adjusted_skill("fitness"))
	health = minf(health, max_health)
	perm_health = minf(perm_health, max_health)
	stamina = minf(stamina, stamina_max)


## Level-up: the original restores health and perm health to full when the
## level-up screen is confirmed (confirmStats -> fullHealth). The bus has no
## "confirmed" event, so we do it when the level arrives (verify with ui).
func _on_level_up(_new_level: int) -> void:
	refresh_vitals()
	full_heal()


func full_heal() -> void:
	health = max_health
	perm_health = max_health


func _use_stamina(base_cost: float) -> void:
	stamina = maxf(0.0, stamina - CombatRules.stamina_cost(base_cost, Stats.adjusted_skill("fitness")))
	_stamina_delay_ticks = CombatRules.STAMINA_REGEN_DELAY_TICKS


func _tick_vitals(delta: float) -> void:
	if is_dead:
		return
	_stamina_clock += delta
	_regen_clock += delta
	while _stamina_clock >= STAMINA_TICK:
		_stamina_clock -= STAMINA_TICK
		_stamina_delay_ticks -= 1
		if _stamina_delay_ticks < 0 and stamina < stamina_max:
			stamina = minf(stamina_max, stamina + CombatRules.stamina_regen(Stats.attr("endurance"), Stats.adjusted_skill("fitness")))
	while _regen_clock >= STAMINA_TICK:
		_regen_clock -= STAMINA_TICK
		_regen_delay_ticks -= 1
		if _regen_delay_ticks < 0 and health < perm_health:
			health = minf(perm_health, health + CombatRules.regen_per_tick(max_health, Stats.attr("endurance"), Stats.skill("survival")))


## Contract signature shared by every combat entity. Zone and knockback are
## accepted for parity; the player is not knocked back yet.
func take_damage(amount: float, _zone: String = "chest", source: Node = null, _knockback: float = 0.0) -> void:
	if is_dead:
		return
	health = maxf(0.0, health - amount)
	perm_health = maxf(0.0, perm_health - CombatRules.perm_health_loss(amount))
	_regen_delay_ticks = CombatRules.STAMINA_REGEN_DELAY_TICKS
	Events.player_damaged.emit(amount, source)
	print("[Player] took %.1f damage, health now %.1f (perm %.1f)" % [amount, health, perm_health])
	if health <= 0.0:
		_die()


## Healing restores both layers, as meds and food do in the original.
func heal(amount: float) -> void:
	perm_health = minf(max_health, perm_health + amount)
	health = minf(perm_health, health + amount)
	print("[Player] healed %.1f, health now %.1f" % [amount, health])


## Raises only the ceiling (first aid on old wounds); regen then fills health.
func heal_perm(amount: float) -> void:
	perm_health = minf(max_health, perm_health + amount)


## Resting or waiting `hours` game hours (sleepWait). Each hour: perm health
## and health both go up by round(0.1 * max health) + round((fitness +
## endurance) / 2) (health is set to the new ceiling), and stamina by
## round(0.2 * stamina max) + round(fitness + endurance). The original reads
## raw `player.fitness` (the skill) and the attribute; we do the same.
func rest(hours: int) -> void:
	var fitness := float(Stats.skill("fitness"))
	var endurance := float(Stats.attr("endurance"))
	for i in maxi(hours, 0):
		perm_health = minf(max_health, perm_health + roundf(max_health * REST_HEALTH_FRACTION) + roundf((fitness + endurance) / 2.0))
		health = perm_health
		stamina = minf(stamina_max, stamina + roundf(stamina_max * REST_STAMINA_FRACTION) + roundf(fitness + endurance))
	print("[Player] rested %d h: health %.1f/%.1f stamina %.1f/%.1f" % [hours, health, max_health, stamina, stamina_max])


func _die() -> void:
	end_grab()
	is_dead = true
	print("[Player] died - showing death screen")
	Events.player_died.emit()
	GameState.reset_run()
	get_tree().paused = true
	call_deferred("_trigger_death_screen")

func _trigger_death_screen() -> void:
	DeathScreen.show_death()
