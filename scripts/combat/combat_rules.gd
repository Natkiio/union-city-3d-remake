class_name CombatRules
extends RefCounted
## Pure combat formulas from docs/ORIGINAL_ANALYSIS.md section 3 (see also
## docs/combat.md). No nodes, no autoloads: every random roll takes a
## RandomNumberGenerator so tests are deterministic. Skill arguments are
## already-resolved numbers (callers pass Stats.adjusted_skill(...)).
## Values mirror data/original/constants.json; tests/test_combat.gd checks
## that they still match.

const ZONES: Array[String] = ["head", "chest", "belly", "legs"]
const ZONE_MOD := {"head": 1.2, "chest": 1.0, "belly": 0.8, "legs": 0.6}
const CRIT_DAMAGE: float = 3.0
const CRIT_LUCK_DIV: float = 7.0
const CRIT_SKILL_DIV: float = 11.0
const SKILL_DAMAGE_MOD: float = 0.05
const SKILL_DAMAGE_BASE: float = 50.0
const MELEE_SKILL_MOD: float = 0.1
const MELEE_SKILL_BASE: float = 75.0
## missChance. Assigned twice in the original (50 then 400); 400 wins (verify).
const MISS_CHANCE: int = 400
const MISS_RANGE: int = 1000
const MISS_CROUCH_MULT: float = 1.5
const PERM_HEALTH_DIV: float = 1.85
const STRUGGLE_DAMAGE_MOD: float = 0.5
const SPREAD_SKILL_CROUCH: float = 25.0
const SPREAD_SKILL_MOVING: float = -20.0
const SPREAD_SKILL_JUMPING: float = -50.0
const SPREAD_ROUND_DIV: float = 7.0
const MIN_STUMBLE_PX: float = 30.0
## Conversion between the original's pixels and our world units.
const PX_PER_UNIT: float = 100.0
const SHOVE_BASE: float = 0.5
## Head is the upper 20% of the body height, legs the lower 30%; chest and
## belly split the rest evenly (chest above belly).
const HEAD_FRACTION: float = 0.20
const LEGS_FRACTION: float = 0.30
const CHEST_BELLY_SPLIT: float = 0.5 # fraction of the span between head and legs


static func zone_mod(zone: String) -> float:
	return ZONE_MOD.get(zone, 1.0)


## Zone from a hit height: 0 = feet, 1 = top of head.
static func zone_from_height(rel: float) -> String:
	if rel >= 1.0 - HEAD_FRACTION:
		return "head"
	if rel < LEGS_FRACTION:
		return "legs"
	var span := (1.0 - HEAD_FRACTION) - LEGS_FRACTION
	return "chest" if rel >= (1.0 - HEAD_FRACTION) - span * CHEST_BELLY_SPLIT else "belly"


# --- Ranged ---------------------------------------------------------------

## Raw skill used for spread: +25 crouched, -20 moving, -50 jumping.
static func spread_skill(raw_skill: float, crouched: bool, moving: bool, jumping: bool) -> float:
	var s := raw_skill
	if crouched:
		s += SPREAD_SKILL_CROUCH
	if moving:
		s += SPREAD_SKILL_MOVING
	if jumping:
		s += SPREAD_SKILL_JUMPING
	return s


## Half-angle of the cone in degrees. Higher weapon accuracy = worse.
static func spread_degrees(spread_skill_value: float, weapon_accuracy: float, consecutive_rounds: int) -> float:
	return maxf(0.0, (100.0 - spread_skill_value) / 25.0 * weapon_accuracy + consecutive_rounds / SPREAD_ROUND_DIV)


## Random aim offset in radians, uniform within +-spread.
static func spread_offset(rng: RandomNumberGenerator, spread_deg: float) -> float:
	return deg_to_rad(rng.randf_range(-spread_deg, spread_deg))


## Miss when random(1000) < threshold. Crouching multiplies the skill term.
static func miss_threshold(adjusted_skill: float, crouched: bool) -> int:
	var skill_term := roundi(adjusted_skill * 2.0 * (MISS_CROUCH_MULT if crouched else 1.0))
	return MISS_CHANCE - skill_term


static func roll_miss(rng: RandomNumberGenerator, adjusted_skill: float, crouched: bool = false, never_misses: bool = false) -> bool:
	if never_misses:
		return false
	return rng.randi() % MISS_RANGE < miss_threshold(adjusted_skill, crouched)


static func crit_chance(luck: float, adjusted_skill: float) -> int:
	return roundi(luck / CRIT_LUCK_DIV + adjusted_skill / CRIT_SKILL_DIV)


static func roll_crit(rng: RandomNumberGenerator, luck: float, adjusted_skill: float) -> bool:
	return rng.randi() % 100 < crit_chance(luck, adjusted_skill)


static func roll_knockback(rng: RandomNumberGenerator, weapon_knockback: float) -> bool:
	return rng.randi() % 100 < weapon_knockback


## One round's damage on a target. armor_mult < 0 means the target has no
## armor in that zone. skill_bonus applies only for the player (pass
## is_player = false for enemies). Crit multiplies last, as in the original.
static func ranged_damage(rng: RandomNumberGenerator, weapon_damage: float, zone: String, adjusted_skill: float,
		crit: bool, armor_mult: float = -1.0, piercing: bool = false, is_player: bool = true) -> float:
	var d := weapon_damage * zone_mod(zone)
	d -= roundf(rng.randf() * d / 5.0)
	if armor_mult >= 0.0 and not piercing:
		d = maxf(1.0, roundf(d * armor_mult))
	if is_player:
		d += roundf(SKILL_DAMAGE_MOD * (adjusted_skill - SKILL_DAMAGE_BASE))
		if crit:
			d *= CRIT_DAMAGE
	return d


# --- Melee ----------------------------------------------------------------

## Pre-roll melee damage. weapon_damage < 0 means unarmed.
static func melee_base(weapon_damage: float, strength: float, adjusted_skill: float) -> float:
	if weapon_damage < 0.0:
		return roundf(1.0 + strength / 5.0)
	return roundf(weapon_damage + strength / 3.0) + roundf(MELEE_SKILL_MOD * (adjusted_skill - MELEE_SKILL_BASE))


static func shove_base(strength: float) -> float:
	return SHOVE_BASE + (strength / 3.0) / 4.0


## Applies the up-to-10% shave, crit, armor and the minimum of 1.
static func melee_final(rng: RandomNumberGenerator, base: float, crit: bool, armor_mult: float = -1.0) -> float:
	var d := base - roundf(rng.randf() * base / 10.0)
	if crit:
		d *= CRIT_DAMAGE
	if armor_mult >= 0.0:
		d = roundf(d * armor_mult)
	return maxf(1.0, d)


## Stumble distance in original pixels: 30 + damage + strength + round(fitness/5).
static func stumble_px(damage: float, strength: float, adjusted_fitness: float) -> float:
	return MIN_STUMBLE_PX + damage + strength + roundf(adjusted_fitness / 5.0)


static func px_to_units(px: float) -> float:
	return px / PX_PER_UNIT


# --- Player health --------------------------------------------------------

## How much the permanent health ceiling drops for a hit.
static func perm_health_loss(damage: float) -> float:
	return roundf(damage / PERM_HEALTH_DIV)


## Per-tick regeneration of current health (doc section 1).
static func regen_per_tick(health_max: float, endurance: float, survival_skill: float) -> float:
	return health_max / 200.0 * (endurance + roundf(survival_skill / 5.0)) / 2.0


# --- Stamina --------------------------------------------------------------

const STAMINA_BASE: float = 56.0
const STAMINA_COST_RUN: float = 1.0
const STAMINA_COST_SHOVE: float = 1.0
const STAMINA_COST_JUMP: float = 5.0
const STAMINA_REGEN_DELAY_TICKS: int = 15


static func stamina_max(level: float, endurance: float, hunger_penalty: float, adjusted_fitness: float) -> float:
	return roundf(level + endurance + hunger_penalty + adjusted_fitness + STAMINA_BASE)


## cost reduced by cost/100 * fitness/10.
static func stamina_cost(base_cost: float, adjusted_fitness: float) -> float:
	return base_cost - base_cost / 100.0 * adjusted_fitness / 10.0


static func stamina_regen(endurance: float, adjusted_fitness: float) -> float:
	return maxf(0.1, roundf((endurance + adjusted_fitness) / 20.0))
