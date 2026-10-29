class_name ActorGun
extends RefCounted
## Weapon handling for AI humans (enemies, companions): magazine, reload, fire
## interval, and a hitscan shot that follows the combat rules of docs/combat.md
## (spread, miss roll, zone, armor, damage) with the non-player options. A
## shot is resolved straight away instead of flying as a bullet; the vertical
## spread decides whether it lands on the target's body and in which zone.
## No autoload names are used so it also compiles under `-s` tests.

const GUN_HEIGHT: float = 0.4   ## muzzle height above the shooter's centre
const CHEST_HEIGHT: float = 0.3 ## aim point above the target's centre
const PELLET_SCATTER_RAD: float = 0.06
const STRENGTH: float = 5.0     ## NPC attribute values for knockback and melee
const FITNESS: float = 7.0

var weapon: Weapon = null
var loaded: int = 0
var reserve: int = 0          ## spare rounds; -1 = unlimited (enemies)
var cooldown: float = 0.0
var reload_left: float = -1.0
var consecutive: int = 0
var _since_shot: float = 99.0


func _init(weapon_ref: String = "hands", loaded_rounds: int = -1, reserve_rounds: int = 0) -> void:
	set_weapon(weapon_ref, loaded_rounds, reserve_rounds)


func set_weapon(weapon_ref: String, loaded_rounds: int = -1, reserve_rounds: int = 0) -> void:
	weapon = Weapon.from_ref(weapon_ref)
	if weapon == null:
		weapon = Weapon.from_ref("hands")
	loaded = weapon.mag_size if loaded_rounds < 0 else mini(loaded_rounds, weapon.mag_size)
	reserve = reserve_rounds
	cooldown = 0.0
	reload_left = -1.0
	consecutive = 0


func is_firearm() -> bool:
	return weapon != null and weapon.weapon_class == "firearm"


func ref() -> String:
	return weapon.ref if weapon != null else "hands"


func tick(delta: float) -> void:
	cooldown = maxf(0.0, cooldown - delta)
	_since_shot += delta
	if _since_shot > 0.6:
		consecutive = 0
	if reload_left >= 0.0:
		reload_left -= delta
		if reload_left < 0.0:
			_finish_reload()


func reloading() -> bool:
	return reload_left >= 0.0


func needs_reload() -> bool:
	return is_firearm() and loaded <= 0


func can_fire() -> bool:
	return is_firearm() and loaded > 0 and cooldown <= 0.0 and reload_left < 0.0


## Starts a reload if there is anything to load. Returns true when started.
func start_reload() -> bool:
	if not is_firearm() or reloading() or loaded >= weapon.mag_size or reserve == 0:
		return false
	reload_left = weapon.reload_seconds()
	return true


func _finish_reload() -> void:
	reload_left = -1.0
	var room := weapon.mag_size - loaded
	var take := room if reserve < 0 else mini(room, reserve)
	loaded += take
	if reserve > 0:
		reserve -= take


## Fires one round (a pellet volley for shotguns) at `target` from `shooter`.
## `skill` is the NPC's weapon skill (10 enemy, 30 companion); it feeds the
## spread and the miss roll. Returns {fired, hits, damage, killed}.
func fire(shooter: Node3D, target: Node3D, skill: float, rng: RandomNumberGenerator,
		crouched: bool = false, moving: bool = false) -> Dictionary:
	var out := {"fired": false, "hits": 0, "damage": 0.0, "killed": false}
	if not can_fire():
		return out
	loaded -= 1
	cooldown = weapon.fire_interval()
	_since_shot = 0.0
	out["fired"] = true
	var spread_skill := CombatRules.spread_skill(skill, crouched, moving, false)
	var spread := CombatRules.spread_degrees(spread_skill, weapon.accuracy, consecutive)
	consecutive += 1
	var gun_y := shooter.global_position.y + GUN_HEIGHT
	var dx := absf(target.global_position.x - shooter.global_position.x)
	var chest_y := target.global_position.y + CHEST_HEIGHT
	var base_angle := atan2(chest_y - gun_y, maxf(dx, 0.05))
	var offset := CombatRules.spread_offset(rng, spread)
	var events := _events()
	if events != null:
		events.shot_fired.emit(weapon.ref, weapon.weapon_noise, shooter.global_position)
	for i in weapon.rounds_per_shot:
		var a := base_angle + offset
		if weapon.rounds_per_shot > 1:
			a += rng.randf_range(-PELLET_SCATTER_RAD, PELLET_SCATTER_RAD)
		var hit_y := gun_y + dx * tan(a)
		var ext := CombatActions.body_extent(target)
		if hit_y < ext.x or hit_y > ext.y:
			continue # flew over or under
		if CombatRules.roll_miss(rng, skill, crouched, weapon.never_misses()):
			continue
		var zone := CombatActions.zone_at(target, hit_y)
		var dmg := CombatRules.ranged_damage(rng, weapon.damage, zone, skill, false,
				CombatActions.armor_for(target, zone), weapon.has_piercing, false)
		var kb := 0.0
		if CombatRules.roll_knockback(rng, weapon.knockback):
			kb = CombatRules.px_to_units(CombatRules.stumble_px(dmg, STRENGTH, FITNESS))
		out["hits"] += 1
		out["damage"] += dmg
		if CombatActions.deal_damage(target, dmg, zone, shooter, kb):
			out["killed"] = true
			break
	return out


## One melee swing at `target` (weapon or fists). Skill 10 enemy, 30 companion.
## Armed: round(damage + str/3) + round(0.1 * (skill - 75)); unarmed
## round(1 + str/5); then the up-to-10% shave, armor and the minimum of 1.
## Returns the damage dealt (0 when the target had no take_damage).
func swing(shooter: Node3D, target: Node3D, skill: float, rng: RandomNumberGenerator) -> float:
	var base := CombatRules.melee_base(weapon.damage if weapon.ref != "hands" else -1.0, STRENGTH, skill)
	var zone := "chest"
	var dmg := CombatRules.melee_final(rng, base, false, CombatActions.armor_for(target, zone))
	var kb := 0.0
	if CombatRules.roll_knockback(rng, weapon.knockback):
		kb = CombatRules.px_to_units(CombatRules.stumble_px(dmg, STRENGTH, FITNESS))
	CombatActions.deal_damage(target, dmg, zone, shooter, kb)
	return dmg


static func _events() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("Events") if tree != null else null
