extends Area3D
## Straight-line round fired by a firearm. Flies along `direction` until it
## reaches a solid body or times out. On an enemy it rolls the miss check, works
## out the hit zone from its height against the body, and applies damage per
## docs/combat.md. Any other solid body (wall, prop) stops it.

const SPEED: float = 30.0
const LIFETIME: float = 1.5

var direction: Vector3 = Vector3.RIGHT
var damage: float = 0.0
## Per-shot context set by the shooter. Keys (all optional): adjusted_skill,
## luck, strength, fitness, crouched, piercing, knockback, never_miss,
## is_player, rng.
var ctx: Dictionary = {}
var _shooter: Node = null
var _age: float = 0.0
var _done: bool = false
var _ignored: Array[Node] = []


## `bullet_damage` is the weapon's base damage; the rest rides in `context`.
func setup(dir: Vector3, shooter: Node, bullet_damage: float, context: Dictionary = {}) -> void:
	direction = dir
	_shooter = shooter
	damage = bullet_damage
	ctx = context


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME:
		_finish()
		return
	global_position += direction * ctx.get("speed", SPEED) * delta


func _on_body_entered(body: Node) -> void:
	if body == _shooter or body in _ignored:
		return
	if not body.has_method("take_damage"):
		_finish() # wall, prop, anything solid
		return
	var rng: RandomNumberGenerator = ctx.get("rng", null)
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var is_player: bool = ctx.get("is_player", true)
	var skill: float = ctx.get("adjusted_skill", 7.0)
	if CombatRules.roll_miss(rng, skill, ctx.get("crouched", false), ctx.get("never_miss", false)):
		_ignored.append(body) # whiffed: the round flies on past
		return
	var zone := CombatActions.zone_at(body, global_position.y) if body is Node3D else "chest"
	var crit: bool = is_player and CombatRules.roll_crit(rng, ctx.get("luck", 5.0), skill)
	var dmg := CombatRules.ranged_damage(rng, damage, zone, skill, crit,
			CombatActions.armor_for(body, zone), ctx.get("piercing", false), is_player)
	var kb_hit: bool = crit or (is_player and CombatRules.roll_knockback(rng, ctx.get("knockback", 0.0)))
	var kb_dist := 0.0
	if kb_hit:
		kb_dist = CombatRules.px_to_units(CombatRules.stumble_px(dmg, ctx.get("strength", 5.0), ctx.get("fitness", 7.0)))
	CombatActions.deal_damage(body, dmg, zone, _shooter, kb_dist)
	_finish()


## Ends the round; explosives burst first (splash_damage within splash_size px
## of the impact, flat damage with no falloff -- verify).
func _finish() -> void:
	if _done:
		return
	_done = true
	var splash: float = ctx.get("splash_damage", 0.0)
	if splash > 0.0 and get_parent() != null:
		var radius := CombatRules.px_to_units(ctx.get("splash_size", 0.0))
		for node in get_parent().get_children():
			if node is Node3D and node != _shooter and node != self and node.has_method("take_damage") \
					and node.global_position.distance_to(global_position) <= radius:
				CombatActions.deal_damage(node, splash, "chest", _shooter, 0.0)
	queue_free()
