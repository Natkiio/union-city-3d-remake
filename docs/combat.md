# Combat (workstream notes)

Spec: `docs/ORIGINAL_ANALYSIS.md` sections 3, 7, 8. Code: `scripts/combat/combat_rules.gd` (pure formulas, seeded-RNG testable), `scripts/combat/combat_actions.gd` (damage dispatch, zones, kill report), `scripts/player.gd`, `scripts/bullet.gd`, `scripts/weapon.gd`. Tests: `tests/test_combat.gd`.

## Contract
- Targets expose `take_damage(amount, zone="chest", source=null, knockback=0.0)` and `apply_stagger(direction, distance)`. `CombatActions.deal_damage` detects old one-argument targets and, for those, staggers them itself when knockback > 0.
- Optional target fields: `armor` (Dictionary zone -> multiplier), `enemy_ref`, `danger_level`, `xp_value()`. With the last three present a kill emits `Events.enemy_killed(ref, danger, xp)`.
- Every shot emits `Events.shot_fired(weapon_ref, weapon_noise, position)`.

## Ranged
spread = `(100 - S)/25 * accuracy + consecutive/7` degrees, `S` = raw skill +25 crouched, -20 moving, -50 airborne. Consecutive rounds reset after 0.6 s idle **(verify)**. Miss on hit: `random(1000) < 400 - round(adjusted*2)` (x1.5 skill term crouched); 400 is the last of two assignments in the source **(verify)**. A missed round flies on. Damage: `weapon.damage * zoneMod`, minus round(rand * 20%), armor `round(d*armor)` min 1 unless the weapon defines `piercing` (any value, 0 included, as in the original), then player-only `+round(0.05*(adjusted-50))`, crit x3. Crit `round(luck/7 + adjusted/11)%` (player only; crit also staggers). Knockback roll `random(100) < weapon.knockback`.
Zone from hit height on the body's collision shape: head top 20%, legs bottom 30%, chest above belly.
Shotgun pellets: each gets the spread plus +-0.06 rad extra scatter (our tuning **(verify)**). Explosives: flat `splashDamage` to everything within `splashSize` px of impact, no falloff **(verify)**.

## Melee
Armed `round(dmg + str/3) + round(0.1*(adjusted-75))`; unarmed `round(1 + str/5)` (uses the `hands` record: blunt, knockback 1); shove `0.5 + (str/3)/4`. Up to 10% shaved, crit x3, armor, min 1. Swings stagger on crit or knockback roll; shoves always. Stumble distance `30 + dmg + str + round(fitness/5)` px, `PX_PER_UNIT = 50` (player is ~1.8 units ~ 90 px). Unarmed crit uses blunt skill **(verify)**. Melee miss is not implemented.

## Weapons
Fire intervals per type and hold-to-fire types (venom by `fireMode`; smg, bullpup, lmg, chainsaw as placeholders) live in `weapon.gd` **(verify)**. One magazine round per trigger pull; reserve only touched by reload. Bursts use `roundsPerBurst`.

## Player vitals
Health ceiling `Stats.max_health()`. `perm_health` drops `round(dmg/1.85)` per hit; regen (every 5 frames after 15 ticks) only fills `health` up to it; `heal()` restores both. Stamina: max `round(level + endurance + fitness + 56)`, run costs 1 per frame while Shift is held and moving, jump 5 (needs stamina > 0), shove 1; each reduced by `cost/100 * fitness/10`; regen per 5-frame tick after a 15-tick delay. Crouch (C) halves speed and gives the accuracy bonus; both keys are read directly because no input action exists. Death emits `Events.player_died` and calls `GameState.reset_run()`.
