# Companions and human enemies (workstream notes)

Source functions read in the original: `setupSurvivor`, `survivorAIRoutine`, `companionDown`, `companionDeath`, `addCompanion`, `addPartner`, `removeCompanion`, `removePartner`, `compRangeCheck`, `giveWeapon`, `helpCompanion`, `setupAHuman`, `setupHuman`, `humanAIRoutine`, `triggerJebAndPaul`, the survivor branches of `applyDamageMelee` and `applyDamageProjectiles`. Marked **(verify)** = read from code or chosen by us, not confirmed in the running original.

## Findings from the original

**Companions (`survivorAIRoutine`)**
- Only one follower (`player.follower`) plus the partner. A second follower is refused with a dialog (`alreadyHaveCompanion`); the NPC stays. Joining turns the NPC's state to `"off"`.
- Stats: health and healthMax are **half the player's**; `downHealth = healthMax*4` (of the full player max). The partner has 999999999 health. Weapon: `npc.weapon`, kept in the save (`comp*Weapon`); the partner has none.
- States: `follow`, `chase`, `attack`, `shove`, `down`. Targets are alerted zombies and hostile (non-friendly) human enemies, never the player. Firearm: attack when the target is within 400 px (`survivorRange`), else keep following. Melee: chase until within 80 px (`survivorMeleeRange`), then swing. Chainsaw 100 px, flamethrower 150 px. A firearm holder shoves a target closer than 60 px.
- Attack cycle: wait 40 ticks, then fire per animation up to 50 ticks, then reset. Out of magazine: reload animation, no reserve is tracked (infinite ammo **(verify)**).
- Follow: waypoint = player x + 50 px * slot, refreshed every 35/3 ticks while the player moves; walks at `player.speed`, runs (x1.5) when the player runs or the gap is over 300 px (`catchUpDistance`); stops within random(50)+50*slot px. If more than 400 px from the player while attacking, walks back toward them (`stayCloseDistance`). Jumps obstacles.
- Damage: they deal the same formulas as the player (ranged `companionWeaponSkill` 30 for the miss roll, no player skill bonus, no crit; melee/knockback checks as the player). Zombies hit them with normal bite damage.
- Down/death: health <= 0 and not down -> `companionDown` (state `down`, "help me" shout). While down, each hit also reduces `downHealth`; at `downHealth <= 0` -> `companionDeath`: drops the held weapon, removes them, NPC state `"off"` for good. The follower being down also sets a HUD arrow.
- Revive (`startHelpCompanion` / `helpCompanion`, key G within 100 px): stands up with **full** health, state follow. No item needed.
- Weapon swap (`giveWeapon`, key G near a standing companion): swaps current weapons; the companion's old weapon goes to the inventory. Partner has no prompt.
- Map: a follower is respawned near the player in every new room (`checkCompanionSetup` / `setupSurvivor` places them at the player's start x +- random(40)).

**Human enemies (`setupAHuman`, `humanAIRoutine`)**
- Placed from the room's `enemy` / `enemyX` lists, unless the room's `_clr` (cleared) flag is saved. Health, weapon, `friendly`, `stationary`, `xpBonus` come from the NPC record; shots use skill 10 (`enemyWeaponSkill`) for the miss roll.
- No sight cone: every ten ticks each human picks the nearest living target among everything on screen it is hostile to (hostile humans: the player, companions and friendly humans; friendly humans: alerted zombies and hostile humans). Firearm: attack within 400 +- 40 px, else chase. Melee: chase to 80 px, then swing. `stationary` humans never chase. Friendly non-stationary humans follow the player when idle.
- Attack cycle: wait 30 ticks, burst of up to 50, 1% per tick to toggle crouch (crouching helps spread).
- Death: removed from the AI lists; kills by the player or a companion pay XP `round(baseXP * xpBonus)` (baseXP uses the area danger). **Nothing is dropped by humans in the original** and they never flee. Both are remake additions below.
- `triggerJebAndPaul` spawns `JebEnemy` and `PaulEnemy` from the pseudo-room `fakeRoom` (x 550 and 950 px).
- Room data: 12 human entries across sections 5, 6, 7, 11, 16. `army*`, `HERCsoldierHeavyFriendly`, `JaneWall`... are `friendly` or invulnerable (health 999999999) guards. `citizen1` (l16 street 3) has no NPC record: dead data, skipped.

## Remake rules

Files: `scripts/enemies/human_body.gd` (`HumanBody`, shared body), `human_enemy.gd` (`HumanEnemy`), `scripts/companions/companion.gd` (`Companion`), `actor_gun.gd` (`ActorGun`), `companion_menu.gd`, `scripts/core/companions.gd` (autoload), scenes under `scenes/companions/`. Tests: `tests/test_companions.gd`.

- **Body**: CharacterBody3D, capsule 0.4 x 1.8, child `Visual` holds an instance of `scenes/characters/male_basic.tscn` (Idle/Walk), tinted by clothes colour; a better model replaces what is inside `Visual`. Facing rotates `Visual` like the player model. Speed 6 (the original uses `player.speed`).
- **Shooting** (`ActorGun.fire`): resolved as a hitscan instead of a flying bullet. Spread uses the combat formula with raw skill 10 (enemy) / 30 (companion), crouch +25; the random angle is applied vertically from the muzzle to the target's chest, so a wide spread flies over or under. A round inside the body then rolls the miss check `random(1000) < 400 - round(skill*2)` (380 enemy, 340 companion; test measures 62.8% and 66.5% hits). Zone from hit height, damage = `weapon.damage * zoneMod` minus up to 20%, armor, no skill bonus, no crit. Knockback roll as bullets. Shotguns scatter pellets +-0.06 rad. Emits `Events.shot_fired` (alerts zombies). **(verify)** that the original uses the same skill for spread.
- **Melee** (`ActorGun.swing`): `round(damage + 5/3) + round(0.1*(skill-75))`, unarmed `round(1 + 5/5)`, 10% shave, armor, min 1. NPC strength 5, fitness 7 **(verify)**; the original reads the *player's* strength and skill for survivors.
- **Human enemy**: sight 8 units (on-screen), hears any shot within 10 units, then closes to 4 +- 0.4 units (firearm) or melee range. Remake additions **(verify)**: patrol within 2.5 units of its post, flee at 25% health (not stationary, not invulnerable; runs until 8 units away, fights if cornered), `friendly` guards shoot only alerted zombies and hostile humans.
- **Armor** implied by clothes **(verify)**: tops containing `army` or `police` multiply chest and belly damage by 0.5, `HERC` by 0.4. Default health when the record has none: `20 + 5^2 + 10*danger`.
- **Death**: `Events.enemy_killed(npc_id, danger, round((round(5*danger)+5) * xpBonus))` only when killed by the player or a companion and not friendly (`Stats` applies the level cut-off). Drops a `scenes/loot/container.tscn` with the weapon, `ammo<type>_<loaded + mag/2>` and maybe cash (`LootRules.roll_cash`), pre-filled and marked searched (no search XP). Kills are remembered per room in `Companions.killed` and the drop reappears when the room is rebuilt, so the human is not respawned.
- **Companion**: skill 30, collision layer 4 (the player's bullets and swings pass through; floor mask only), group `companion` and `zombie_targets`. Follow/attack/chase/hold/down as above. Interact (the `world_interactable` convention, `wants_interact()`): downed -> revive at full health; standing -> `CompanionMenu` (give weapon, heal with a meds item `round((bonus + firstAid/2)/100 * healthMax)`, hold/follow, dismiss). Partner: follows, never fights, cannot be hurt, no menu. Dismiss puts the NPC back at their post (`Quests.set_npc_on(npc, true)`); death turns them off for good.
- **Zombies target companions**: `zombie.gd` gained `_retarget()` (about 20 lines): every 0.5 s a zombie aims at the nearest of the player and group `zombie_targets` (not mid-grab). Grabs only happen on the player (`start_grab`). Downed companions leave the group.
- **Not reproduced**: companions give XP when they kill zombies (the zombie emits `enemy_killed` itself; the original gave none), the "help me" shout, the HUD arrow for a far companion, ammo for companions (unlimited).

## API

`Companions` autoload (group `stateful`): `add(npc_id, kind="follower") -> bool`, `remove(npc_id)` (dismiss), `active() -> Array`, `has(npc_id)`, `follower()`, `node_for(npc_id)`, `sync_quests()` (called on `Events.quest_changed` and `Quests.npc_changed`: brings `Quests.companions()` into the roster, once; dismissed or dead NPCs stay out), `note_enemy_killed(room, idx, x)`, `to_dict/from_dict/reset`. Signals `roster_changed`, `companion_died(npc_id)`. Roster entry: `{kind, health, weapon, mag, hold, down, down_health, room}`. A `Quests` story action `spawn` (Jeb and Paul) spawns the named humans at x 5.5 and 9.5.

## The hooks outside my files

1. `scripts/world/level_builder.gd`, in `build()` right after `_build_npcs(things, id, w)`: `_place_actors(level, id)`, plus the function `_place_actors` (looks up the `Companions` autoload by path and calls `populate_level(level, id)`). That places the room's human enemies and the active companions under `Level/Actors`. `Companions` also listens to `Events.location_entered` and stands the companions next to the player after `World` has positioned them.
2. `scripts/zombie.gd`: `var _retarget_t`, a `_retarget(delta)` call at the top of `_physics_process` (before the player null check) and the `_retarget` function.
3. `tests/test_world.gd`: the Z=0 lane detector also accepts `HumanBody` (armed humans share the lane like zombies).

## Follow-ups

Cutout/rig poses for down and shoot (the downed pose is a 90 degree roll for now), companion HUD arrow and health, a persistent per-room kill list for zombies, companion XP policy, giving ammo to companions, `Quests.companions()` still lists dead or dismissed companions (the roster tracks that itself).
