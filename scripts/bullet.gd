extends Area3D
## Straight-line bullet fired by a firearm. Travels at a fixed velocity along the
## direction it was fired with (set by the shooter at spawn time, from
## the same mouse-aim data that drives the arm pose) until it hits
## something with take_damage(), or times out.

const SPEED: float = 30.0
const LIFETIME: float = 1.5

var direction: Vector3 = Vector3.RIGHT
var damage: float = 0.0
var _shooter: Node = null
var _age: float = 0.0

## damage comes from the firing weapon's Weapon.damage.
func setup(dir: Vector3, shooter: Node, bullet_damage: float) -> void:
	direction = dir
	_shooter = shooter
	damage = bullet_damage

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME:
		queue_free()
		return
	global_position += direction * SPEED * delta

func _on_body_entered(body: Node) -> void:
	if body == _shooter:
		return # never hit whoever fired it
	if body.has_method("take_damage"):
		body.take_damage(damage)
		queue_free()
