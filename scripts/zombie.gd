extends CharacterBody3D
## Minimal zombie AI: shamble toward the player along X, bite on contact.

const SPEED: float = 2.2
const BITE_DAMAGE: float = 10.0
const BITE_COOLDOWN_TIME: float = 1.0
const MAX_HEALTH: float = 50.0
## Seconds between reaching bite range and the bite landing; a stagger cancels it.
const BITE_WINDUP_TIME: float = 0.4
const STAGGER_TIME: float = 0.25
const HIT_FLASH_TIME: float = 0.1

var health: float = MAX_HEALTH
var bite_cooldown: float = 0.0
var player: Node3D = null
var stagger_timer: float = 0.0
var stagger_speed: float = 0.0
var windup_timer: float = -1.0
var flash_timer: float = 0.0

@onready var bite_area: Area3D = $BiteArea
@onready var mesh: MeshInstance3D = $MeshInstance3D

var _flash_material := StandardMaterial3D.new()

func _ready() -> void:
	_flash_material.albedo_color = Color.WHITE
	_flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	player = get_tree().get_first_node_in_group("player")

func _physics_process(delta: float) -> void:
	if health <= 0.0:
		return
	if player == null:
		player = get_tree().get_first_node_in_group("player")
		return

	if flash_timer > 0.0:
		flash_timer -= delta
		if flash_timer <= 0.0:
			mesh.material_override = null

	var dir: float = sign(player.global_position.x - global_position.x)
	velocity.x = dir * SPEED
	if stagger_timer > 0.0:
		stagger_timer -= delta
		velocity.x = stagger_speed
	velocity.z = 0.0
	if not is_on_floor():
		velocity.y -= 20.0 * delta
	move_and_slide()

	bite_cooldown = max(0.0, bite_cooldown - delta)
	if stagger_timer > 0.0:
		windup_timer = -1.0
		return
	if bite_cooldown <= 0.0:
		var in_range := false
		for body in bite_area.get_overlapping_bodies():
			if body.is_in_group("player") and body.has_method("take_damage"):
				in_range = true
				if windup_timer < 0.0:
					windup_timer = BITE_WINDUP_TIME
				elif windup_timer - delta <= 0.0:
					body.take_damage(BITE_DAMAGE)
					bite_cooldown = BITE_COOLDOWN_TIME
					windup_timer = -1.0
				else:
					windup_timer -= delta
		if not in_range:
			windup_timer = -1.0


## Pushes the zombie `distance` world units along X in `direction` (+1/-1)
## over STAGGER_TIME. It can't chase or bite meanwhile, and a bite
## windup in progress is cancelled.
func apply_stagger(direction: float, distance: float) -> void:
	stagger_timer = STAGGER_TIME
	stagger_speed = sign(direction) * distance / STAGGER_TIME
	windup_timer = -1.0


func take_damage(amount: float) -> void:
	health = max(0.0, health - amount)
	mesh.material_override = _flash_material
	flash_timer = HIT_FLASH_TIME
	print("[Zombie] took %.1f damage, health now %.1f" % [amount, health])
	if health <= 0.0:
		print("[Zombie] down")
		queue_free()
