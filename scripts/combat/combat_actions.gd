class_name CombatActions
extends RefCounted
## Scene-facing glue shared by the player and bullets: calls take_damage with
## the contract signature (falling back for old one-argument targets), works
## out the hit zone from a world position, and reports kills.

const DEFAULT_BODY_HEIGHT: float = 1.8


## take_damage(amount, zone, source, knockback) is the contract. Targets that
## still have the old take_damage(amount) are called that way. Returns true if
## this call killed the target (it had health above 0 before and none after,
## or was freed).
static func deal_damage(target: Node, amount: float, zone: String = "chest", source: Node = null, knockback: float = 0.0) -> bool:
	if target == null or not target.has_method("take_damage"):
		return false
	var before: float = target.get("health") if "health" in target else 1.0
	if _arg_count(target, "take_damage") >= 4:
		target.take_damage(amount, zone, source, knockback)
	else:
		target.take_damage(amount)
		# Old-style targets do not stagger themselves; push them from here.
		if knockback > 0.0 and is_instance_valid(target) and target.has_method("apply_stagger") \
				and target is Node3D and source is Node3D:
			var dir := signf(target.global_position.x - source.global_position.x)
			target.apply_stagger(dir if dir != 0.0 else 1.0, knockback)
	var killed := false
	if before > 0.0:
		killed = not is_instance_valid(target) or ("health" in target and float(target.get("health")) <= 0.0)
	if killed:
		report_kill(target)
	return killed


## Emits Events.enemy_killed when the target exposes enemy_ref, danger_level
## and xp_value(); otherwise does nothing (the zombies workstream adds them).
static func report_kill(target: Node) -> void:
	if not ("enemy_ref" in target and "danger_level" in target and target.has_method("xp_value")):
		return
	# Looked up by path so this script also compiles in -s test runs, where
	# autoload names are not yet registered when the test script loads.
	var events: Node = (Engine.get_main_loop() as SceneTree).root.get_node("Events")
	events.enemy_killed.emit(target.get("enemy_ref"), int(target.get("danger_level")), int(target.xp_value()))


static func _arg_count(obj: Object, method: String) -> int:
	for m in obj.get_method_list():
		if m["name"] == method:
			return (m["args"] as Array).size()
	return 0


## [bottom_y, top_y] of a body in world space, from its first collision shape
## (capsule or box) or a default 1.8 tall body centred on its origin.
static func body_extent(body: Node3D) -> Vector2:
	for child in body.get_children():
		if child is CollisionShape3D and child.shape != null:
			var h := DEFAULT_BODY_HEIGHT
			if child.shape is CapsuleShape3D:
				h = child.shape.height
			elif child.shape is BoxShape3D:
				h = child.shape.size.y
			var centre: float = child.global_position.y
			return Vector2(centre - h / 2.0, centre + h / 2.0)
	return Vector2(body.global_position.y - DEFAULT_BODY_HEIGHT / 2.0, body.global_position.y + DEFAULT_BODY_HEIGHT / 2.0)


## Zone struck by a hit at world height `hit_y` on `body`.
static func zone_at(body: Node3D, hit_y: float) -> String:
	var ext := body_extent(body)
	var span := maxf(ext.y - ext.x, 0.001)
	return CombatRules.zone_from_height(clampf((hit_y - ext.x) / span, 0.0, 1.0))


## Armor multiplier a target has for a zone, or -1 when it has none. Targets
## expose armor as a Dictionary `armor` (zone -> multiplier).
static func armor_for(target: Node, zone: String) -> float:
	if "armor" in target and target.get("armor") is Dictionary:
		return float((target.get("armor") as Dictionary).get(zone, -1.0))
	return -1.0
