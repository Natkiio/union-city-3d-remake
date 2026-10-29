# Gameplay (workstream notes)

The seams between combat, zombies, stats, items and the player. Code: `scripts/player.gd`, `scripts/zombie.gd`, `scripts/combat/` (incl. `struggle_prompt.gd`). Tests: `tests/test_gameplay.gd`.

## What the seams do now
- **Kill XP**: a zombie announces its own death on `Events.enemy_killed(ref, danger, xp)`. `CombatActions.report_kill` skips targets that have a `died` signal; before, a kill by punch, shove or bullet paid the XP twice. Stats pays `round((round(danger*5)+5) * xpBonus)` (10 for zombieSlow at danger 1), nothing when `level - danger > 4`; level 1 needs 100 XP.
- **Armor**: `CombatActions.armor_for(target, zone)` asks `zombie.armor_for(zone)` / `has_armor(zone)`; a zone the kind defines at 1.0 (zombieArmy head) still goes through rounding and the minimum of 1; undefined zones are untouched. Bullets pass `piercing` (any value, 0 included). Melee ignores piercing and takes its zone from the height of the striking hand (shoves hit the chest); melee has no zone damage mod, only armor.
- **Ranged damage floor**: the player skill bonus `round(0.05*(skill-50))` is negative below 50 and, applied after armor's minimum of 1, healed the target (1 - 2 = -1). Damage now floors at 1 before the crit multiplier.
- **Grab**: `player.start_grab(zombie)` / `end_grab()` / `is_grabbed()`. While grabbed: no walking, running, crouching or jumping; facing locks onto the zombie; shooting and punching still work. A press of the `move_left` action calls `zombie.struggle_press("A")`, `move_right` calls `"D"`. The prompt (`StrugglePrompt`, CanvasLayer child of the player) reads the key names from the bindings, so an AZERTY layout shows "Mash Q / D". Bites are x0.5, an escape shoves the zombie back 1 unit, killing it or staggering it ends the grab. Zombies roll the 10% grab each time an attack starts; headless, an idle player is grabbed within seconds.
- **Vitals**: `max_health` and `stamina_max` follow Stats through `stats_changed` (clamping health, never raising it). On `Events.level_up` health, perm health and the new maximum are restored fully (the original does this when the level-up screen is confirmed, `confirmStats -> fullHealth`; the bus has no "confirmed" event, so level arrival stands in **(verify with ui)**). `heal(n)` restores both layers (meds and food), `heal_perm(n)` only the ceiling, `full_heal()`, `rest(hours)`.
- **Items**: `ItemUse` heals through `player.heal()` and then also adds the amount to `perm_health` itself, so meds raise the ceiling by twice the amount (health once). Harmless but unintended; owner: survival.
- **Rest** (`sleepWait`, per game hour): perm health `+= round(0.1*max) + round((fitness + endurance)/2)`, health set to the ceiling, stamina `+= round(0.2*staminaMax) + round(fitness + endurance)`. `fitness` is the raw skill, `endurance` the attribute with penalties. `Survival.sleep_hours` / `wait_hours` do not call it; the sleep/wait dialog should call `player.rest(h)` (Blocked/request below).
- **Hunger and stamina**: `stamina_max = round(level + endurance + hungerPenalty + adj fitness + 56)` exactly as in the original, where `endurance` already has the penalty subtracted and `hungerPenalty` is added back, so hunger leaves stamina max unchanged (a quirk of the original). The same quirk would apply to max health (`(endurance + hungerPenalty)^2`), but `Stats.max_health()` uses the penalised endurance, so hunger lowers max health here. Decide in the tuning pass.
- **Run and crouch** use the `run` and `crouch` actions.
- **Overweight**: the original subtracts a flat 50 from a 7.5 base and clamps at 0, so an overloaded character cannot walk, and `characterGravity` blocks jumping. Here `OVERWEIGHT_SPEED_FACTOR = 0.25` of the normal speed (0.0 for parity), jumping disabled. Running stays possible (it multiplies the reduced base).
- **Bullets** spawn on the Z=0 lane; the hand bone hangs about 0.28 off it.

## Balance baseline (level 1, all stats at base, zombieSlow at danger 1)
Printed by `tests/test_gameplay.gd` as `[BALANCE]` lines. The fight sim is pure rules (CombatRules, Weapon, ZombieType, Zombie's bite timing 0.4 s windup + 1.0 s cooldown): zombies start in contact, the player always hits the nearest at chest height at point blank, no stagger, no grabs, no regeneration, 600 seeded trials. Fire and swing intervals are our placeholders.

| | Result |
|---|---|
| Zombie / player | 12 HP, bite 7 / 55 HP |
| Unarmed | 2 damage per punch (crit 2%), 6 punches = 3.0 s |
| G17 (9 dmg, 38% miss at pistols skill 10) | 3.20 pulls by headshot, 3.53 by chest shot |
| Shotgun (3 pellets x 12, each can miss), close range | 1.35 shells |
| Unarmed vs 1 zombie | survives 100%, 41.5 HP left, 3.0 s |
| Unarmed vs 3 zombies | survives 0%, dies after 3.4 s having killed 1.08 |
| G17 vs 1 / 3 | 100% (49.9 HP left) / 94% (21.8 HP left, 2.91 kills) |
| Shotgun vs 1 / 3 | 100% (52.9) / 100% (36.8) |

The original's tension holds unarmed (one zombie is fine, three are lethal) but a level-1 character with any gun beats three danger-1 zombies easily; ammo scarcity has to carry that, or the tuning pass should look at the miss rate and the 7-damage bite.

Director with a standing level-1 player, danger 3 (max 3 zombies, 3000 px outdoors), 120 game minutes:
- Idle: 3 zombies spawn at the start and fill the budget; no rush (needs a free slot), no break, none ever reaches the player (0 bites). Off-screen spawns wander at 1 u/s and only notice the player within 1.5 units (any facing) or 3.6 units (facing). Gunshots wake them within 10 units.
- With a defender who kills anything within 6 units: 5 spawned, 2 reached the defender, 1 rush, 1 break, +44 XP, no damage.
So encounters depend on the player making noise or walking; if the game should push zombies at the player, that is a director/AI tuning decision.

## Unconfirmed
- Level-up health restore timing (above), the exact meaning of `player.fitness` in `sleepWait` (raw skill assumed), overweight factor, melee zone from hand height, and the fire/swing intervals.
