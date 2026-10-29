class_name PlayerProvider
extends RefCounted
## The "Player" save provider (docs/persistence.md, Providers). The player is a
## node of the run scene, not an autoload, so SaveGame asks this class for its
## state. Registered once by SaveGame._ready().
##
## Saved: health, perm_health, stamina, equipped weapon, position [x, y, z],
## facing. Hunger and sleep live in Survival, the room in World, the weapon
## slots and magazines in Inventory; zombies are not saved.
##
## Loading from a menu happens before the run scene exists, so from_dict keeps
## the data pending and the run scene applies it once its player is in the
## room (apply_pending, called from RunGlue).

const NAME := "Player"

static var _pending: Dictionary = {}


static func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


static func player() -> Node:
	var t := _tree()
	return t.get_first_node_in_group("player") if t != null else null


static func register(save_game: Node) -> void:
	save_game.register_provider(NAME, Callable(PlayerProvider, "to_dict"), Callable(PlayerProvider, "from_dict"))


static func to_dict() -> Dictionary:
	var p := player()
	if p == null:
		return {}
	var pos: Vector3 = p.global_position
	return {
		"health": float(p.health), "perm_health": float(p.perm_health),
		"stamina": float(p.stamina), "equipped_weapon": str(p.equipped_weapon),
		"position": [pos.x, pos.y, pos.z], "facing": float(p.get("facing_dir")),
	}


## Applies now when the player is up (World.from_dict has already rebuilt
## the room by then: providers run after every system), else keeps it.
static func from_dict(d: Dictionary) -> void:
	_pending = d.duplicate(true)
	var p := player()
	if p != null and p.is_inside_tree() and not p.is_queued_for_deletion():
		apply_pending(p)


static func has_pending() -> bool:
	return not _pending.is_empty()


static func clear_pending() -> void:
	_pending = {}


static func apply_pending(p: Node) -> void:
	if _pending.is_empty() or p == null:
		return
	var d := _pending
	_pending = {}
	if p.has_method("refresh_vitals"):
		p.refresh_vitals()
	p.perm_health = clampf(float(d.get("perm_health", p.max_health)), 0.0, p.max_health)
	p.health = clampf(float(d.get("health", p.perm_health)), 0.0, p.perm_health)
	p.stamina = clampf(float(d.get("stamina", p.stamina_max)), 0.0, p.stamina_max)
	var ref := str(d.get("equipped_weapon", "fist"))
	var gun := Weapon.from_ref(ref) if ref != "fist" else null
	var inventory: Node = _tree().root.get_node("Inventory")
	if gun == null or not inventory.has_item(gun.display_name):
		ref = "fist"
	if p.has_method("_set_equipped"):
		p._set_equipped(ref)
	else:
		p.equipped_weapon = ref
	var pos: Array = d.get("position", [])
	if pos.size() == 3:
		# x only: World places y on the floor, z is the lane.
		p.global_position.x = float(pos[0])
		if "velocity" in p:
			p.velocity = Vector3.ZERO
	if d.has("facing") and "facing_dir" in p:
		p.facing_dir = 1.0 if float(d.facing) >= 0.0 else -1.0
