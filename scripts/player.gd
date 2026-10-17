extends CharacterBody3D
## 2.5D side-scroller player controller.
## Movement is locked to the X axis to match the original flash game's
## left/right lane movement; Z stays fixed on the game's "street plane".
## Facing and attack direction are driven by the mouse, not movement —
## matching the original game, where you aim your fist/weapon with the
## cursor independently of which way you're walking.

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

@onready var model: Node3D = $Model
@onready var weapon_pivot: Node3D = $WeaponPivot
@onready var attack_area: Area3D = $WeaponPivot/AttackArea
@onready var anim_player: AnimationPlayer = model.find_child("AnimationPlayer", true, false)

func _ready() -> void:
	if GameState.has_pending_spawn:
		global_position.x = GameState.consume_spawn()
	model.rotation.y = -PI / 2.0 if facing_dir > 0.0 else PI / 2.0
	if anim_player:
		for anim_name in ["Idle", "Walk"]:
			if anim_player.has_animation(anim_name):
				anim_player.get_animation(anim_name).loop_mode = Animation.LOOP_PINGPONG
		anim_player.play("Idle")

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
## and orient the weapon pivot to point at it (left/right + up/down).
## Split out from _update_aim() so it can be tested directly without
## depending on screen/mouse plumbing.
func _apply_aim(aim_point: Vector3) -> void:
	var dx := aim_point.x - global_position.x
	if abs(dx) > 0.05:
		facing_dir = sign(dx)
	model.rotation.y = -PI / 2.0 if facing_dir > 0.0 else PI / 2.0

	var dy := aim_point.y - weapon_pivot.global_position.y
	var horiz: float = max(abs(dx), 0.2) # avoid a degenerate near-vertical aim
	var pitch: float = clamp(atan2(dy, horiz), -deg_to_rad(MAX_AIM_PITCH_DEG), deg_to_rad(MAX_AIM_PITCH_DEG))
	var aim_dir := Vector3(facing_dir * cos(pitch), sin(pitch), 0.0)
	weapon_pivot.look_at(weapon_pivot.global_position + aim_dir, Vector3.UP)


func _do_attack() -> void:
	attack_cooldown = ATTACK_COOLDOWN_TIME
	for body in attack_area.get_overlapping_bodies():
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
