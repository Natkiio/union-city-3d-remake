extends CharacterBody3D
## Minimal zombie AI: shamble toward the player along X, bite on contact.

const SPEED: float = 2.2
const BITE_DAMAGE: float = 10.0
const BITE_COOLDOWN_TIME: float = 1.0
const MAX_HEALTH: float = 50.0

var health: float = MAX_HEALTH
var bite_cooldown: float = 0.0
var player: Node3D = null

@onready var bite_area: Area3D = $BiteArea

func _ready() -> void:
	player = get_tree().get_first_node_in_group("player")

func _physics_process(delta: float) -> void:
	if health <= 0.0:
		return
	if player == null:
		player = get_tree().get_first_node_in_group("player")
		return

	var dir: float = sign(player.global_position.x - global_position.x)
	velocity.x = dir * SPEED
	velocity.z = 0.0
	if not is_on_floor():
		velocity.y -= 20.0 * delta
	move_and_slide()

	bite_cooldown = max(0.0, bite_cooldown - delta)
	if bite_cooldown <= 0.0:
		for body in bite_area.get_overlapping_bodies():
			if body.is_in_group("player") and body.has_method("take_damage"):
				body.take_damage(BITE_DAMAGE)
				bite_cooldown = BITE_COOLDOWN_TIME


func take_damage(amount: float) -> void:
	health = max(0.0, health - amount)
	print("[Zombie] took %.1f damage, health now %.1f" % [amount, health])
	if health <= 0.0:
		print("[Zombie] down")
		queue_free()
