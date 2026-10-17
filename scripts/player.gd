extends CharacterBody3D
## 2.5D side-scroller player controller.
## Movement is locked to the X axis to match the original flash game's
## left/right lane movement; Z stays fixed on the game's "street plane".

const SPEED: float = 6.0
const ATTACK_RANGE: float = 1.6
const ATTACK_DAMAGE: float = 25.0
const MAX_HEALTH: float = 100.0

var health: float = MAX_HEALTH
var is_dead: bool = false
var attack_cooldown: float = 0.0
const ATTACK_COOLDOWN_TIME: float = 0.5

var facing_dir: float = 1.0

@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var attack_area: Area3D = $AttackArea

func _ready() -> void:
	if GameState.has_pending_spawn:
		global_position.x = GameState.consume_spawn()

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

	if input_dir != 0.0:
		facing_dir = sign(input_dir)
		mesh.rotation.y = 0.0 if input_dir > 0.0 else PI
		attack_area.position.x = 0.9 * facing_dir

	attack_cooldown = max(0.0, attack_cooldown - delta)
	if Input.is_action_just_pressed("attack") and attack_cooldown <= 0.0:
		_do_attack()


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
