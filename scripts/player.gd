extends CharacterBody3D
## 2.5D side-scroller player controller.
## Movement is locked to the X axis to match the original flash game's
## left/right lane movement; Z stays fixed on the game's "street plane".
## Facing and aim are driven by the mouse, not movement — matching the
## original game, where you aim your fist/weapon with the cursor
## independently of which way you're walking. The actual right arm
## bone is posed to point at the aim target every frame (not a
## separate floating prop), so the model's own arm is the thing that
## visibly aims.

const SPEED: float = 6.0
const ATTACK_RANGE: float = 1.6
const ATTACK_DAMAGE: float = 25.0
const MAX_HEALTH: float = 100.0
const MAX_AIM_PITCH_DEG: float = 80.0

var health: float = MAX_HEALTH
var is_dead: bool = false
var attack_cooldown: float = 0.0
const ATTACK_COOLDOWN_TIME: float = 0.5

var facing_dir: float = 1.0
var aim_pitch: float = 0.0

@onready var model: Node3D = $Model
@onready var attack_area: Area3D = $Model/MaleBasic_Armature/Skeleton3D/HandAttachment/AttackArea
@onready var anim_player: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
@onready var skeleton: Skeleton3D = model.find_child("Skeleton3D", true, false)
@onready var upper_arm_r_idx: int = skeleton.find_bone("UpperArm_R") if skeleton else -1

## UpperArm_R's rest pose hangs straight down. This rotates it onto a
## forward "ready to punch" pose (local Z by -90 deg) then tilts that
## by the aim pitch (local X) -- empirically determined in Godot at
## runtime (with the body already yawed to face sideways), since bone
## axes don't map to world axes the same way they do in Blender's own
## Z-up space before import/yaw.
func _arm_pose_for_pitch(pitch: float) -> Quaternion:
	var raise_to_forward := Basis(Vector3(0, 0, 1), -PI / 2.0)
	var pitch_basis := Basis(Vector3(1, 0, 0), pitch)
	return (raise_to_forward * pitch_basis).get_rotation_quaternion()

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
	# it updates during the default idle-process pass. Run our own arm
	# aim override AFTER that in the same frame, or the animation would
	# stomp it right back to the walk/idle pose every tick.
	set_process_priority(100)

func _physics_process(delta: float) -> void:
	var input_dir := 0.0
	if Input.is_action_pressed("move_left"):
		input_dir -= 1.0
	if Input.is_action_pressed("move_right"):
		input_dir += 1.0

	velocity.x = input_dir * SPEED
	velocity.z = 0.0 # locked to the street plane, 2.5D style
	if not is_on_floor():
		velocity.y -= 20.0 * delta

	move_and_slide()

	_update_aim()

	if anim_player:
		var desired := "Walk" if input_dir != 0.0 else "Idle"
		if anim_player.current_animation != desired:
			anim_player.play(desired)

	attack_cooldown = max(0.0, attack_cooldown - delta)
	if Input.is_action_just_pressed("attack") and attack_cooldown <= 0.0:
		_do_attack()


func _process(_delta: float) -> void:
	if skeleton and upper_arm_r_idx >= 0:
		skeleton.set_bone_pose_rotation(upper_arm_r_idx, _arm_pose_for_pitch(aim_pitch))


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
## and store the pitch used to pose the arm. Split out from
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


func _do_attack() -> void:
	attack_cooldown = ATTACK_COOLDOWN_TIME
	for body in attack_area.get_overlapping_bodies():
		if body == self:
			continue # the hitbox sits on our own hand; never hit ourselves
		if body.has_method("take_damage"):
			body.take_damage(ATTACK_DAMAGE)
	print("[Player] attack swung")


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
	GameState.has_pending_spawn = false
	get_tree().paused = true
	call_deferred("_trigger_death_screen")

func _trigger_death_screen() -> void:
	DeathScreen.show_death()
