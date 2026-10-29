# Port plan — Cork City

Rebuild *The Last Stand: Union City* in Godot as a Cork City, Ireland zombie survival game: same feel and rules, new setting and story, our own structure. Rules come from `docs/ORIGINAL_ANALYSIS.md` and the tables in `data/original/`. Local only, nothing is published.

## Decisions (from Robert)

- Target: **full skeleton plus one deep slice**. Every system exists and is data-driven; one Cork district with 2-3 buildings is playable end to end.
- Visuals: **Nathan's direction, rigged 3D models from Blender** (`blender_source/*.blend` exported to `assets/characters/*.glb` with Idle/Walk animations, wrapped in `scenes/characters/*.tscn`). The player and the basic zombie already use this. New characters follow the same pipeline; variants (zombie kinds, NPCs) tint and scale the base rigs until dedicated models exist. The earlier flat-cutout rig (`scripts/visual/`, `docs/cutout.md`) was built as an alternative and is **not used by the game**; it stays in the repo for reference and can be deleted.
- Code boundaries: restructure freely, work on `dev`, **nothing is pushed**.
- Setting: **real Cork map and a new story** in the original's shape (see `docs/CORK_BIBLE.md` once written).

## Architecture

Three layers. Keep them apart.

1. **Data** — `data/original/*.json` (extracted, never hand-edited) and `data/cork/*.json` (our overrides, same file names and keys, deep-merged on top by the `Data` autoload). Rules read tables, never hard-code numbers that exist in a table.
2. **Sim** — autoloads and plain classes in `scripts/core/` and one folder per system. No node paths, no UI. Testable headless without loading a level.
3. **Presentation** — scenes, rigs, UI, audio. Reads sim state, emits input.

### Autoloads (registered in `project.godot`, do not edit that file; ask the lead)

| Name | File | Role |
|---|---|---|
| `Data` | `scripts/core/data.gd` | table loader, Cork merge, template text |
| `Events` | `scripts/core/events.gd` | signal bus; add a signal when a second system needs it |
| `Stats` | `scripts/core/stats.gd` | attributes, skills, level, XP, derived stats |
| `Clock` | `scripts/core/clock.gd` | game time, lighting preset |
| `Survival` | `scripts/core/survival.gd` | hunger, sleep |
| `Director` | `scripts/core/director.gd` | zombie budget, spawns, rushes, breaks |
| `Quests` | `scripts/core/quests.gd` | quests, NPC state, triggers |
| `World` | `scripts/core/world.gd` | location, rooms, travel |
| `SaveGame` | `scripts/core/save_game.gd` | save and load |
| `Sfx` | `scripts/core/sfx.gd` | procedural placeholder sounds |
| `Inventory`, `GameState`, `LootState`, `TrunkUI`, `InventoryUI`, `HoverSystem`, `DeathScreen` | existing | unchanged unless the owner says |

### Stateful convention

A system with state that must survive scene changes, be reset on death and be saved joins group `"stateful"` in `_ready()` and implements `reset()`, `to_dict()` and `from_dict(d)`. `GameState.reset_run()` resets them all; `SaveGame` serialises them all. Never duplicate reset logic anywhere else.

### Talking between systems

- Prefer `Events` signals to direct calls. Cross-system calls go through the autoload API only (e.g. `Stats.adjusted_skill("pistols")`), never into another system's private fields.
- Combat entities share this interface: `take_damage(amount: float, zone: String = "chest", source: Node = null, knockback: float = 0.0)`, `apply_stagger(direction: float, distance: float)`. Zones: `head`, `chest`, `belly`, `legs`.
- The Z=0 lane rule holds (see `ROADMAP.md`): only zombies and the player share the lane.

### Visual rig contract (superseded; see Decisions)

This contract belonged to the cutout rig, which the game does not use. Characters are Blender models with an `AnimationPlayer` (Idle, Walk); gameplay only picks the animation from velocity and state, and never touches parts. Kept for reference:

`scripts/visual/cutout_rig.gd` on a Node3D: `apply_look(look: Dictionary)` (keys follow `npc.json`/`pre.json`: `skinColour`, `hair`, `hairColour`, `clothesTop`, `clothesBottom`, `clothesShoe`, `backpack`, `weapon`), `play(anim: String)` (`idle walk run punch shove aim hurt die`), `set_facing(dir: float)`, `set_aim(pitch: float)`. Gameplay code never touches rig parts.

## Workstreams

Each runs on its own branch `feat/<name>` in its own worktree (made by the lead from `dev`), owns the files listed, and merges into `dev` only through the lead. Anything not listed is read-only for you; if you need a change there, write it in your status file under Blocked.

### Wave 1

| Name | Owns | Delivers |
|---|---|---|
| `progression` | `scripts/core/stats.gd`, `scripts/progression/`, `scenes/ui/character_create*`, `scenes/ui/level_up*`, `scenes/ui/skills*` | attributes, skills, adjusted skill, derived stats, XP and levels (sec. 1-2), 14 backgrounds from `pre.json`, character creation, level-up and skills screens |
| `combat` | `scripts/player.gd`, `scripts/weapon.gd`, `scripts/bullet.gd`, `scripts/combat/`, `scenes/player/`, `scenes/weapons/` | sec. 3 rules: ranged spread, miss, crit, zones, armor, damage, knockback; melee formulas; stamina use; noise events; all weapon types fire/reload correctly; kill XP via `Events.enemy_killed` |
| `zombies` | `scripts/zombie.gd`, `scripts/zombie_type.gd`, `scripts/enemies/`, `scripts/core/director.gd`, `scenes/zombie/` | sec. 5 and 8: AI states, sight and sense, alert rolls, grab and struggle, all 22 enemy types, director budget, rushes, breaks, droppers |
| `survival` | `scripts/core/clock.gd`, `scripts/core/survival.gd`, `scripts/items/`, `scripts/inventory.gd`, `scripts/inventory_ui.gd`, `scenes/ui/inventory_ui.tscn` | sec. 4, 7, 9: time, day/night lighting from `lightTime*`, hunger and sleep, `Items` lookup over all item tables, using food/meds/books, weight limit from `Stats.carry_weight()` |
| `cutout` | `scripts/visual/`, `scenes/chars/`, `assets/` (generated) | the cutout rig contract above, 14+ zombie looks, demo scene, parallax backdrop pieces |
| `cork` | `data/cork/`, `docs/CORK_BIBLE.md` | map of the 16 sections onto Cork places, names, danger, new story and NPCs, same keys as the originals |
| `audio` | `scripts/core/sfx.gd`, `scripts/audio/` | procedural sounds and a hook list |

### Wave 2 (started after wave 1 merges)

`world` (level builder from `world/l*.json` plus Cork overrides, rooms, doors, stairs, safehouses, scrolling streets), `loot` (container generation, searching, lockpicking, shops), `story` (NPCs, dialogue box, quests, triggers, cutscenes), `ui` (main menu, map and travel screen, pause, settings, shop), `persistence` (save and load), `integrate-visuals` (rig into player and zombies), `companions`.

### Wave 3

Integration, balance pass against the doc's numbers, end-to-end playthrough test, Cork content pass, cleanup, docs.

## Rules for every workstream

- Read first: `CLAUDE.md`, `docs/PORT_PLAN.md`, the sections of `docs/ORIGINAL_ANALYSIS.md` for your area. Use the decompiled source at `reference/scripts/scripts/frame_4/DoAction.as` (git-ignored; the path is relative to the main checkout, absolute: `/Users/robertobrien/code/games/union-city-3d-remake/reference/...`) when the doc is unclear, and record what you learn in your own doc `docs/<name>.md` (short; mark unconfirmed items **(verify)**).
- Rules are reimplemented from the spec, never copied: no pasted original code, no original art or audio.
- Tests: add `tests/test_<name>.gd` (extends `tests/test_base.gd`). `tools/run_tests.sh` must pass before every commit, for the whole project, not only your file.
- Do not edit `project.godot`, `tests/test_base.gd`, `tools/run_tests.sh` or `scripts/core/events.gd` beyond adding signals at the end of a section. Need an autoload or input action? Put it in your status file under Blocked and keep going with a local workaround.
- Commits: small, on your branch. **Never** add a `Co-Authored-By` trailer, a "Generated with" line, or any mention of Claude or AI tooling. Never push or merge.
- Status: keep `/Users/robertobrien/code/games/union-city-3d-remake/status/<name>.md` current per `status/README.md`. Terse.
- Seeing your work: tests prove logic; for visuals you may run the game windowed for a few seconds with a script that saves `get_viewport().get_texture().get_image()` to a PNG in the scratchpad and quits, then read the PNG. Always quit automatically.
- Keep scope to your row. Better a complete small thing than a sprawling half-thing. List follow-ups in your final report instead of building them.

## Wave 2 contracts

Wave 1 is merged into `dev` (progression, combat, zombies, survival, cork, audio; cutout pending). Wave 2 workstreams build against these interfaces so they can run in parallel. Read the real code of the merged systems before relying on them.

| Name | Owns | Role |
|---|---|---|
| `world` | `scripts/core/world.gd`, `scripts/world/`, `scenes/world/`, `scenes/main.tscn`, `scripts/camera_rig.gd`, `scripts/door_trigger.gd`, `scenes/house/`, `scenes/car/`, `scenes/building/` | builds playable levels from `data/original/world/l*.json` merged with Cork, scrolling streets, buildings, floors, rooms, doors, stairs, safehouses; owns the run scene `scenes/main.tscn` (player, HUD, camera, level container) |
| `loot` | `scripts/loot/`, `scenes/loot/`, `scripts/interactable.gd`, `scripts/car_trunk.gd`, `scripts/trunk_ui.gd`, `scenes/ui/trunk_ui.tscn`, `scripts/loot_state.gd` | containers, searching rules (sec. 6), loot rarity lists, locks and lockpicking (sec. 10), keys, shops (`shopSet*`), cash |
| `story` | `scripts/core/quests.gd`, `scripts/story/`, `scenes/story/` | quests (all 39), NPC state machines, dialogue box, triggers (`trig.json`), cutscenes (`cutScene*.json`), unlocks, companions' data hooks |
| `ui` | `scripts/main_menu.gd`, `scripts/hud.gd`, `scripts/death_screen.gd`, `scripts/ui/`, `scenes/ui/` (except inventory, trunk and the progression screens) | main menu to character creation to game flow, HUD (health, stamina, hunger, sleep, XP, clock, weapon and ammo), pause, settings, map and travel screen, sleep/wait dialog, death screen, level-up popup wiring |
| `persistence` | `scripts/core/save_game.gd`, `scripts/persistence/`, `scenes/ui/save_slots*` | save and load of every stateful system, slots, autosave, versioned format, corruption handling |
| `gameplay` | `scripts/player.gd`, `scripts/zombie.gd`, `scripts/combat/`, `scripts/enemies/` | glue between combat, zombies, stats and items: grab and struggle on the player, armor, kill XP end to end, overweight slowdown, run and crouch actions, perm health with items and sleep, balance pass |

Agreed seams (implement your side; code against the other side's signature and guard with `has_method` until it lands):

- **World API**: `World.start_new_game()`, `World.enter_location(section_id: String)`, `World.enter_room(room_path: String, spawn_at: String)`, `World.travel_to(section_id: String)`, `World.current: Dictionary` with keys `section, street, building, floor, room, danger, width_px, outdoors, safehouse`. It calls `Director.begin_area(...)` and `Director.attach(...)`, emits `Events.location_entered`, and spawns the player and camera. `to_dict`/`from_dict` restore the exact room.
- **Containers**: `scripts/loot/container.gd` with `setup(container_id: String, def: Dictionary, room_type: String, danger: int)` and `scenes/loot/container.tscn`. `def` is one `contN` entry from the room data. World instantiates one per entry; Loot owns everything after that. Interaction goes through the existing interact action.
- **NPCs**: `scenes/story/npc.tscn` and `scripts/story/npc.gd` with `setup(npc_id: String)`; World instantiates NPCs from the room's NPC list. Dialogue opens through `Quests`/story code only.
- **Game flow**: ui owns `main menu -> character creation -> World.start_new_game()` and `death -> main menu`. Load goes through `SaveGame.load_slot(n)` then `World.from_dict`.
- **Save API**: `SaveGame.save_slot(n: int) -> bool`, `load_slot(n: int) -> bool`, `has_slot(n)`, `slot_info(n) -> Dictionary` (name, level, location, clock, playtime), `autosave()`. Saves `to_dict()` of every node in group `stateful`, keyed by autoload name, plus a version number.
- **Safehouse sleep and wait**: `Survival.sleep_hours` / `wait_hours` exist; the ui dialog calls them and `World` knows which rooms are safehouses.
- Input actions already added: `run`, `crouch`, `pause`, `open_map`, `open_skills`, `quick_save`, `quick_load`, `sleep_wait` (plus the earlier ones). Need another? Put it in your status under Blocked.
