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
## Fallback for scripts that still read player.MAX_HEALTH (the HUD does). The
## real ceiling is `max_health`, from Stats.max_health().
const MAX_HEALTH: float = 55.0
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
## Crouch has no input action yet; read this key directly (Blocked: ask lead).
const CROUCH_KEY: Key = KEY_C
const RUN_KEY: Key = KEY_SHIFT

var health: float = MAX_HEALTH
## Ceiling that regen can restore health to; drops by damage/1.85 per hit.
var perm_health: float = MAX_HEALTH
var max_health: float = MAX_HEALTH
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
	health = max_health
	perm_health = max_health
	stamina = stamina_max
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
	var input_dir := 0.0
	if Input.is_action_pressed("move_left"):
		input_dir -= 1.0
	if Input.is_action_pressed("move_right"):
		input_dir += 1.0

	crouched = Input.is_key_pressed(CROUCH_KEY) and is_on_floor()
	running = Input.is_key_pressed(RUN_KEY) and input_dir != 0.0 and not crouched and stamina > 0.0
	var speed := SPEED
	if crouched:
		speed /= CROUCH_SPEED_DIV
	elif running:
		speed *= RUN_SPEED_MULT
		_run_cost_clock += delta
		while _run_cost_clock >= STAMINA_FRAME:
			_run_cost_clock -= STAMINA_FRAME
			_use_stamina(CombatRules.STAMINA_COST_RUN)
	velocity.x = input_dir * speed
	velocity.z = 0.0 # locked to the street plane, 2.5D style
	if Input.is_action_just_pressed("jump") and is_on_floor() and not crouched and stamina > 0.0:
		velocity.y = JUMP_VELOCITY
		_use_stamina(CombatRules.STAMINA_COST_JUMP)
	if not is_on_floor():
		velocity.y -= 20.0 * delta

	move_and_slide()
	_tick_vitals(delta)

	_update_aim()

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
	if abs(dx) > 0.05:
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
		bullet.global_position = attack_area_r.global_position
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
	_melee_strike(area.get_overlapping_bodies(), base, weapon.skill, false, weapon.knockback)


## Resolves a melee hit on each body: shave, crit, armor, damage, then stumble.
## Shoves always stagger; swings stagger on a crit or a knockback roll.
func _melee_strike(bodies: Array, base: float, skill_name: String, always_stagger: bool, weapon_knockback: float = 0.0) -> void:
	var adjusted := Stats.adjusted_skill(skill_name)
	for body in bodies:
		if body == self:
			continue # the hitbox sits on our own hand; never hit ourselves
		if not body.has_method("take_damage"):
			continue
		var crit := CombatRules.roll_crit(rng, Stats.attr("luck"), adjusted)
		var dmg := CombatRules.melee_final(rng, base, crit, CombatActions.armor_for(body, "chest"))
		var stagger := always_stagger or crit or CombatRules.roll_knockback(rng, weapon_knockback)
		var kb := 0.0
		if stagger:
			kb = CombatRules.px_to_units(CombatRules.stumble_px(dmg, Stats.attr("strength"), Stats.adjusted_skill("fitness")))
		CombatActions.deal_damage(body, dmg, "chest", self, kb)
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


# --- Vitals ---------------------------------------------------------------

## Re-reads the ceilings from Stats (level-ups, endurance changes). Keeps the
## current fractions of health/perm_health/stamina.
func refresh_vitals() -> void:
	max_health = Stats.max_health()
	stamina_max = CombatRules.stamina_max(Stats.level, Stats.attr("endurance"), 0.0, Stats.adjusted_skill("fitness"))
	health = minf(health, max_health)
	perm_health = minf(perm_health, max_health)
	stamina = minf(stamina, stamina_max)


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


func _die() -> void:
	is_dead = true
	print("[Player] died - showing death screen")
	Events.player_died.emit()
	GameState.reset_run()
	get_tree().paused = true
	call_deferred("_trigger_death_screen")

func _trigger_death_screen() -> void:
	DeathScreen.show_death()
