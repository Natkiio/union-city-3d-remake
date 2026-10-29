# Zombies and director (workstream notes)

Rules: `docs/ORIGINAL_ANALYSIS.md` sec. 3, 5, 8. This file lists how the remake maps them and what is unconfirmed.

## Files
- `scripts/zombie.gd` (`Zombie`): state machine `idle, wander, rise, chase, attack, grab, stumble`. `Zombie.spawn(parent, ref, danger, x)` or `configure(ref, danger)`. Child `Visual` (MeshInstance3D) is swappable; if it has `set_facing(dir)` it is called.
- `scripts/zombie_type.gd` (`ZombieType`): enemy record, formulas (`health_for`, `damage_for`, `xp_for`), `pool_for(danger)`, `chase_speed_units()`, `PX_PER_UNIT = 100`.
- `scripts/enemies/struggle.gd` (`Struggle`), `director_rules.gd` (`DirectorRules`, pure), `enemy_look.gd` (placeholder colours).
- `scripts/core/director.gd`: autoload `Director`.

## Contracts
- Combat entity: `take_damage(amount, zone, source, knockback_percent)`, `apply_stagger(dir, distance_units)`. Armor is NOT applied inside the zombie: combat multiplies by `zombie.armor_for(zone)` (unless piercing).
- Kill: emits `Events.enemy_killed(enemy_ref, danger_level, xp)`; zombie also has `died(zombie)`, `enemy_ref`, `danger_level`, `xp_value()`.
- Grab: the zombie calls `player.start_grab(zombie)` (only if the player has it; otherwise zombies never grab, to avoid an unwinnable grab) and `player.end_grab()` on release. The player feeds A/D presses with `zombie.struggle_press(side)`. Presses needed = clamp(round(level*2 - strength*2), 3, 8); bites at x0.5; escape shoves the zombie back 1 unit; killing it ends the grab. Only one zombie grabs at a time.
- Damage to the player: calls `take_damage(amount, "chest", zombie)` if the player's method takes more than one argument, else `take_damage(amount)`.
- Director: `begin_area(danger, width_px, outdoors, safehouse, id="")`, `attach(spawn_root, player)`, `set_bounds(min_x, max_x)`, `tick()`, `spawn_zombie(ref)`. Clock: reads `Clock.game_minutes` if it exists, else an internal counter (1 game minute = 50/30 s).

## Conversions and choices
- 100 px = 1 unit. Sight 600 x 0.6 = 3.6 units, sense 1.5, grab 0.65, attack range random(30)+45 px or `attackRange`. Attack and grab ranges are edge distances, so the capsule contact gap (0.8) is added.
- Chase speed = 2.2 x chaseSpeed / 1.5 units/s, capped at 7 (player runs at 6; sprinters 10-15 would be 15-24).
- Danger default 1: a basic zombie has 12 HP and bites for 7 (was 50 HP / 10). Combat tuning must expect this.
- Perception runs at 30 Hz. "Seen" in the original always alerts; here a zombie is alerted by `sensed` (within 1.5) or `sighted` (facing, within 3.6) rolls, which succeed 21% / 61% per tick, so effectively within a few frames. **(verify)** the original also rolls the base 5/500 chance without any event; not reproduced.
- Gunshots (`Events.shot_fired`) alert every zombie within 10 units (the original uses "on screen"): chance = 5 + noise*15 of 500.
- A hit (melee or shot) rolls +300; a hit that kills just kills.
- Grab roll (10%) happens once each time an attack starts, not every frame. **(verify)**
- Wander: random walk at 1 u/s with pauses; remake-specific. Riser: lies idle, rises 1.2 s after alert. Crawl and dog are stagger-immune. Riot shield pauses 3 s with 30% rolled once a second **(verify)**.
- Director tick: 1 s real. Ambient spawn every 4th tick when under maxZombies (outdoors only). `numZombiesSinceBreak` counts spawns. Droppers set `carries_loot` on the next spawned zombie (loot drop itself belongs to the loot workstream).
- The rush health test uses current health (original has permHealth) and always assumes enough ammo. **(verify)**; ammo awaits the combat workstream.
- Not built: burning, zombie miss roll (`zomMissChance`), zombie sounds, rooftop spawn animation, `zombieSurvivor` (story only, no level so never in a pool).
