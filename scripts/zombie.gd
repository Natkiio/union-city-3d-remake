extends CharacterBody3D
## Minimal zombie AI: shamble toward the player along X, bite on contact.
## Baseline stats below are the basic zombie; `type_ref` picks a ZombieType
## from the original's enemy table that scales them and sets how it moves.

## Basic zombies limp: speed swings sinusoidally around SPEED (the average is
## unchanged) on a fixed, predictable beat.
const LIMP_AMPLITUDE: float = 0.6
const LIMP_PERIOD: float = 1.2

const SPEED: float = 2.2
const BITE_DAMAGE: float = 10.0
const BITE_COOLDOWN_TIME: float = 1.0
const MAX_HEALTH: float = 50.0
## Seconds between reaching bite range and the bite landing; a stagger cancels it.
const BITE_WINDUP_TIME: float = 0.4
const STAGGER_TIME: float = 0.25
const HIT_FLASH_TIME: float = 0.1

@export var type_ref: String = "zombieSlow"

var type: ZombieType
var max_health: float = MAX_HEALTH
var speed: float = SPEED
var bite_damage: float = BITE_DAMAGE
var health: float = MAX_HEALTH
var move_time: float = 0.0
var bite_cooldown: float = 0.0
var player: Node3D = null
var stagger_timer: float = 0.0
var stagger_speed: float = 0.0
var windup_timer: float = -1.0
var flash_timer: float = 0.0

@onready var bite_area: Area3D = $BiteArea
@onready var model: Node3D = $Model
@onready var mesh: MeshInstance3D = _find_by_class(model, "MeshInstance3D")
@onready var anim_player: AnimationPlayer = model.find_child("AnimationPlayer", true, false)

var _flash_material := StandardMaterial3D.new()

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
	type = ZombieType.from_ref(type_ref)
	if type != null:
		max_health = MAX_HEALTH * type.health_scale
		speed = SPEED * type.speed_scale
		bite_damage = BITE_DAMAGE * type.damage_scale
		health = max_health
	_flash_material.albedo_color = Color.WHITE
	_flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	player = get_tree().get_first_node_in_group("player")
	if anim_player:
		for anim_name in ["Idle", "Walk"]:
			if anim_player.has_animation(anim_name):
				anim_player.get_animation(anim_name).loop_mode = Animation.LOOP_PINGPONG
		anim_player.play("Idle")

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
	move_time += delta
	velocity.x = dir * speed * _movement_mult()
	if stagger_timer > 0.0:
		stagger_timer -= delta
		velocity.x = stagger_speed
	velocity.z = 0.0
	if not is_on_floor():
		velocity.y -= 20.0 * delta
	move_and_slide()

	# Same left/right facing convention as the player: -PI/2 points the
	# model's front toward world +X, +PI/2 toward world -X (confirmed
	# empirically for this rig/export pipeline via test_facing.gd at
	# the time, and reused here since it's the same build conventions).
	if abs(velocity.x) > 0.01:
		model.rotation.y = -PI / 2.0 if velocity.x > 0.0 else PI / 2.0
	if anim_player:
		var desired := "Walk" if abs(velocity.x) > 0.01 else "Idle"
		if anim_player.current_animation != desired:
			anim_player.play(desired)

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
					body.take_damage(bite_damage)
					bite_cooldown = BITE_COOLDOWN_TIME
					windup_timer = -1.0
				else:
					windup_timer -= delta
		if not in_range:
			windup_timer = -1.0


## Speed multiplier for this kind's movement style at the current moment.
func _movement_mult() -> float:
	match type.movement if type != null else "steady":
		"limp":
			return 1.0 + LIMP_AMPLITUDE * sin(TAU * move_time / LIMP_PERIOD)
		_:
			return 1.0


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
