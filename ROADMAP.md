# Union City 3D — Roadmap & Design Doc

A 2.5D remake of *The Last Stand: Union City* (the 2011 Flash survival game) in Godot 4, built with 3D art blocked out in primitives and art direction from Blender.

This doc exists so anyone picking up the project — including a version of us six months from now — can see what's built, why it's built that way, what's missing, and what to work on next.

## Reference: the original game

Flash side-scroller, released 2011 on Armor Games / Newgrounds. You play a resident of a fictional city during a zombie outbreak, trying to reach your spouse. Core loop: walk between city zones, scavenge buildings for supplies, fight zombies (melee + ranged), manage an inventory with weight limits, level up stats and skills, survive a day/night cycle, meet other survivors who give quests.

We are **not** rebuilding all of that at once. The plan below scopes it into playable slices.

## Current state (what's actually built and verified)

Every item below has been exercised with a headless Godot run (`--headless`, scripted input, real engine state checked afterward), not just written and assumed correct.

### Core movement & combat
- **Player** (`scripts/player.gd`): 2.5D side-scroll controller. Movement locked to the X axis (Z is fixed at 0, the "street plane"), gravity, melee attack with a hitbox that flips to match facing direction.
- **Zombie** (`scripts/zombie.gd`): chases the player along X, bites on contact, has health, dies and is removed when killed.
- **Camera** (`scripts/camera_rig.gd`): follows the player's X position only, orthographic in the house interior (flat 2D-style framing), tight perspective on the street.

### World objects
- **Loot crates** (`scripts/interactable.gd` + `scenes/building/loot_crate.tscn`): walk up, press E, item goes to inventory. Each has a configurable weight.
- **Car trunk** (`scripts/car_trunk.gd` + `scenes/car/car.tscn`): walk to the rear, press E, opens a paper-style menu (`scripts/trunk_ui.gd`). Can take items individually (`[1-9]`) or all at once (`[A]`).
- **House** (`scenes/house/house_exterior.tscn`, `house_interior.tscn`): press E at the door to transition to a separate interior scene via `door_trigger.gd`; exit door brings you back to the street at the right spot.

### Systems
- **Inventory** (`scripts/inventory.gd`, autoload): stackable items, each tracked as `name -> {weight, count}`. `InventoryUI` (press `I`) shows everything carried with per-item and total weight, pauses the game like the trunk menu.
- **LootState** (`scripts/loot_state.gd`, autoload): tracks which lootables (crates, trunks) have been emptied, keyed by their stable scene-tree path. This is what makes looting *persistent* — without it, every scene reload (e.g. walking through a door) would respawn all loot.
- **GameState** (`scripts/game_state.gd`, autoload): hands off spawn position across scene transitions (so you land at the right spot when exiting a door instead of the scene's default spawn).

### World layout rule (important, keep following this)
The player can only move on the X axis — Z is always 0. **Only zombies should ever share that exact Z plane**, because they need to walk up and bite the player. Every other placed object (buildings, cars, props) must sit **recessed in Z**, with only its *trigger zone* (Area3D, not a solid body) reaching back to Z=0 so the player can interact without colliding. We hit this bug twice (the car, then the house) before landing on this rule — see commits `032b05b` and `613bb30`.

### Known technical debt / rough edges
- The zombie and all loot respawn fresh each time `main.tscn` reloads, **except** loot already tracked in `LootState`. The zombie itself has no persistent "is it dead" state — if you kill it, then go through a door and come back, it's alive again. This is probably fine for an endless street encounter but worth a deliberate decision once there's more than one zombie.
- No save/load. Closing the game loses everything (`LootState` and `Inventory` are in-memory autoloads only).
- All models are primitives (capsules, boxes, cylinders) — no real art yet.
- Only one street segment, one house, one car exist. The map doesn't scroll into new areas yet.
- The Godot editor has repeatedly nudged object Z-positions slightly when the project is opened/saved in the GUI (not from our scripted changes) — if something looks slightly off after a playtest session, check `git diff` on the `.tscn` files before assuming it's a new bug.

## Architecture notes for whoever works on this next

- **Autoloads** (`project.godot` `[autoload]` section): `Inventory`, `GameState`, `LootState`, `TrunkUI`, `InventoryUI`. These persist across `change_scene_to_file` calls — that's the mechanism that makes inventory and loot state survive going through doors.
- **Scene transitions** use `get_tree().change_scene_to_file()`, which fully reinstantiates the target scene from disk. Anything that needs to survive that must live in an autoload, not scene-local state.
- **Testing workflow**: never trust a code change without running it. Pattern used throughout: temporarily add a `TestHarness` autoload pointing at a throwaway `.gd` script that simulates input (`Input.parse_input_event`) and asserts on real engine state (positions, health, inventory contents) printed to stdout, run via `Godot.app/Contents/MacOS/Godot --headless scenes/main.tscn`, then delete the harness and remove it from `project.godot` before committing. Always run `--headless --import --quit` first to catch parse errors cheaply.
- **Pausing**: `TrunkUI` and `InventoryUI` both pause the game (`get_tree().paused = true`) while open, and use `process_mode = PROCESS_MODE_ALWAYS` on themselves so they keep responding to input while everything else freezes.

## Roadmap

### Phase 1 — Make the core loop actually fun (next up)
- [ ] Ranged weapon: a pistol or similar, limited ammo, pulled from inventory
- [ ] Multiple zombies / a horde spawner instead of one fixed zombie
- [ ] Player death screen + restart (currently health just hits 0 and does nothing visible)
- [ ] Zombie death should persist like loot does (same `LootState`-style pattern, or a dedicated `ZombieState`)
- [ ] Sound: footsteps, zombie growl, hit/death feedback — even placeholder beeps help playtesting

### Phase 2 — Expand the world
- [ ] Extend the street (currently a single 60-unit segment) or chain multiple street scenes together
- [ ] A second enterable building (different interior layout, different loot)
- [ ] Day/night cycle: lighting shift over time, zombies more aggressive at night (this was a signature mechanic of the original)
- [ ] Safehouse concept: a place to rest/save

### Phase 3 — RPG systems from the original
- [ ] Player stats (strength, intelligence, etc.) and skills (melee, ranged, lockpicking)
- [ ] Weight limit tied to strength (the trunk UI already shows weight — enforce a cap)
- [ ] Level-up system
- [ ] Weapon conditions/attachments

### Phase 4 — Narrative
- [ ] NPCs / survivors with simple dialogue
- [ ] Quest system (starting with a single fetch quest, like the original's "Heavy, Man" junk-collection quests)
- [ ] Main storyline beats (the spouse search from the original, or your own story)

### Phase 5 — Art pass
- [ ] Replace primitives with real models: start with the player and zombie (highest visibility), then environment pieces
- [ ] Textures/materials beyond flat colors
- [ ] UI art pass beyond the current functional paper-style panels

## Decisions log (why things are the way they are)

- **2.5D over full 3D**: matches the original's feel, and locking the player to one axis massively simplifies camera work and collision — we can iterate on gameplay faster.
- **Primitives before real models**: standard practice per our `3d-scene-design` workflow — block out composition and mechanics first, replace with real art once the loop is confirmed fun. Don't let art-polish block gameplay iteration.
- **Everything verified headless before being called done**: every feature in this repo has a commit message describing the actual headless test that proved it works, not just "should work." Keep doing this — we caught real bugs (attack hitbox facing, car/house blocking the lane, same-key re-trigger on menu close) specifically because of this discipline.

## Contributing (for Robert / anyone else on this)

1. Clone: `git clone https://github.com/Natkiio/union-city-3d-remake.git`
2. Open `project.godot` in Godot 4.7+.
3. Before committing a change to gameplay logic, write a throwaway test harness (see Architecture notes above), run it headless, and paste the real output into your commit message as proof. Delete the harness before committing.
4. Keep new world objects off the player's Z=0 lane (see World layout rule above) unless they're meant to chase the player.
5. `git pull` before starting work, `git push` when a feature is verified and committed.
