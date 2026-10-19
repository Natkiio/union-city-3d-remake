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
const ATTACK_DAMAGE: float = 25.0
const MAX_HEALTH: float = 100.0
const MAX_AIM_PITCH_DEG: float = 80.0

const GUARD_FOREARM_BEND_DEG: float = 110.0
const PUNCH_DURATION: float = 0.3

const PISTOL_COOLDOWN_TIME: float = 0.3

var health: float = MAX_HEALTH
var is_dead: bool = false
var attack_cooldown: float = 0.0
const ATTACK_COOLDOWN_TIME: float = 0.5

var facing_dir: float = 1.0
var aim_pitch: float = 0.0

var punch_side: String = "R" # which arm last punched / is currently punching
var is_punching: bool = false
var punch_timer: float = 0.0
var punch_did_hit: bool = false

## "fist" (default boxing guard) or "pistol". Switches with equip_fists
## / equip_pistol; pistol only equippable once the item is in Inventory.
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

	velocity.x = input_dir * SPEED
	velocity.z = 0.0 # locked to the street plane, 2.5D style
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY
	if not is_on_floor():
		velocity.y -= 20.0 * delta

	move_and_slide()

	_update_aim()

	if anim_player:
		var desired := "Walk" if input_dir != 0.0 else "Idle"
		if anim_player.current_animation != desired:
			anim_player.play(desired)

	attack_cooldown = max(0.0, attack_cooldown - delta)
	if Input.is_action_just_pressed("equip_fists"):
		equipped_weapon = "fist"
		print("[Player] equipped fists")
	if Input.is_action_just_pressed("equip_pistol") and Inventory.has_item("Pistol"):
		equipped_weapon = "pistol"
		print("[Player] equipped pistol")

	if Input.is_action_just_pressed("attack") and attack_cooldown <= 0.0:
		if equipped_weapon == "pistol":
			_fire_pistol()
		else:
			_start_punch()


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

	if equipped_weapon == "pistol":
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
	attack_cooldown = ATTACK_COOLDOWN_TIME
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


func _fire_pistol() -> void:
	if not Inventory.has_item("Pistol Ammo"):
		print("[Player] out of ammo")
		return
	attack_cooldown = PISTOL_COOLDOWN_TIME
	Inventory.remove_item("Pistol Ammo", 1)

	var bullet := BulletScene.instantiate()
	get_parent().add_child(bullet)
	bullet.global_position = attack_area_r.global_position
	bullet.setup(_aim_direction(), self)

	var ammo_left: int = Inventory.items.get("Pistol Ammo", {}).get("count", 0)
	print("[Player] fired pistol toward %s, ammo left: %d" % [bullet.direction, ammo_left])


func _apply_punch_damage() -> void:
	var area := attack_area_r if punch_side == "R" else attack_area_l
	for body in area.get_overlapping_bodies():
		if body == self:
			continue # the hitbox sits on our own hand; never hit ourselves
		if body.has_method("take_damage"):
			body.take_damage(ATTACK_DAMAGE)


func take_damage(amount: float) -> void:
	if is_dead:
		return
	health = max(0.0, health - amount)
	print("[Player] took %.1f damage, health now %.1f" % [amount, health])
	if health <= 0.0:
		_die()

func heal(amount: float) -> void:
	health = min(MAX_HEALTH, health + amount)
	print("[Player] healed %.1f, health now %.1f" % [amount, health])

func _die() -> void:
	is_dead = true
	print("[Player] died - showing death screen")
	Inventory.items.clear()
	Inventory.inventory_changed.emit()
	LootState.looted.clear()
	LootState.trunk_contents.clear()
	GameState.has_pending_spawn = false
	get_tree().paused = true
	call_deferred("_trigger_death_screen")

func _trigger_death_screen() -> void:
	DeathScreen.show_death()
