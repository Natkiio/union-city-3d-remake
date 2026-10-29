# Integration

How the workstreams fit together at run time, the startup, load and death sequences, the fixes made where the seams were wrong, and what is still missing. Tests: `tests/test_integration.gd` (each seam on real nodes), `tests/test_playthrough.gd` (the whole game, about 40 s headless), `tests/test_soak.gd` (all 299 rooms, about 35 s).

## The pieces

```
                         Data (tables + Cork overrides)
                                    |
   Stats  Clock  Survival  Inventory  LootState  Quests  Director  Companions   <- stateful autoloads
     ^      ^       ^          ^          ^        ^  |      ^                     (reset / to_dict / from_dict)
     |      |       |          |          |        |  | story_action, npc_changed
     +------+-------+---- Events bus -----+--------+  v
                                    |            RunGlue (scenes/main.tscn "Glue")
   SaveGame --- providers: Player (PlayerProvider)   |  map_requested -> MapScreen
     |  slots 0..3, autosave                         |  bed_used      -> SleepDialog -> player.rest, Survival, autosave
     v                                               |  trigger_entered -> Quests.fire_trigger("trig<N>")
   World (autoload) --- LevelBuilder --- Level       |  story_action  -> speech bubble, World.unlock_door,
     | room id, links, doors, travel       |         |                   Director.start_ending_rush, EndingScreen,
     | interact_target(): one target       +- Container (loot)  -> TrunkUI, Locks
     |   per E press                       +- StoryNPC (story)  -> Dialogue -> Quests
     |                                     +- WorldLink (door, stair, exit, bed, shop counter -> ShopUI)
     v                                     +- Zombies (Director spawns under Level/Actors)
   run scene: Player, CameraRig, HUD (UIController: pause, map, rest, skills, level-up), DayNight
```

- **One owner per decision.** World decides what an interact press acts on (`World.interact_target()`: the nearest in-range link, container or NPC, ties to the container or NPC). Containers and NPCs still handle their own key but ask `World.is_interact_target(self)` first.
- **RunGlue** (`scripts/world/run_glue.gd`, created by `run_scene.gd`) is the only place that connects World and Quests signals to screens. Nothing else knows about another system's screens.
- **Quest markers**: `!` over an NPC whose current state offers a quest not yet taken, `?` when that quest's requirement is met. They refresh on `quest_changed`, `npc_changed`, inventory changes and room entry.
- **Story actions** (`Quests.story_action`): `speech` shows a bubble over the speaker (an NPC in the room, else the player), `unlockDoor` opens the World door, `startEndingRush` starts an endless Director rush, `showEnding` opens `EndingScreen`, `cash` / `showHelp` / `alert` / `companion` show HUD messages, `spawn` asks `Companions.spawn_enemy(id, x)` if it exists. `setupAnNPCDirect`, `animateCharacter`, `fixJack` change no state and are not presented.
- **Cash** is the inventory item `Cash` everywhere: container loot, shops and quest rewards (`Quests.cash` reads and writes that stack).
- **Shops**: a room with `shopSet` gets a SHOP counter link at its first `shop<N>` marker; it opens `scenes/ui/shop.tscn`, which is freed on close.
- **Settings**: brightness becomes `Environment.adjustment_brightness` (0.6 to 1.4, 0.5 is neutral) through `Settings.apply` and the `brightness_target` group; `head_shots_only` is read in `CombatActions.deal_damage` (any non-head hit on a zombie does 1).
- **Logging**: `DebugLog.say(tag, text)` prints `[Tag] text` only with `-- --debug-log` (or `DebugLog.enabled = true`).

## Sequences

**New game.** Main menu, New Game: `GameFlow.new_game` calls `GameState.reset_run()` and opens character creation. Confirm: `World.start_new_game()` resets World, sets the section 16 start room, calls `Quests.begin_story()` (trig1: quest 900 and cutscene 10), emits `Events.run_started` and opens `scenes/main.tscn` through `GameFlow.change_scene`. The run scene creates RunGlue, then `World.attach_run_scene` builds the room (Director attach, `begin_area`, `location_entered`, which autosaves).

**Save.** `SaveGame.save_slot(n)`: every `stateful` node's `to_dict()` plus providers (`Player`: health, perm health, stamina, equipped weapon, position, facing). Zombies are not saved. From the pause menu (slots 1-3), quick save (slot 1), autosave (slot 0: room entry, level up, after resting).

**Load.** `SaveGame.load_slot(n)`: parse and validate, `GameState.reset_run()` (also frees dialogue, cutscene, lockpick and shop screens and closes the panels), then `from_dict` in `LOAD_ORDER` with World always last; World rebuilds the room without counting it as a new visit. Then providers: in the run, the player is restored at once; from a menu `PlayerProvider` keeps it pending, `World.enter_loaded_game()` opens the run scene, and RunGlue applies it after the first build. Pause menu Load, quick load and Continue all go this way.

**Death.** `player._die`: `Events.player_died` (the death screen snapshots its summary), `GameState.reset_run()`, pause, death screen. When it has faded: `GameFlow.to_main_menu` resets the run again, stops sounds, sets `Engine.time_scale` back to 1 and loads the menu. Quit to menu from the pause menu does the same, so the menu never sees an old run.

## Fixes made at the seams

| Where | Bug | Fix |
|---|---|---|
| `scripts/core/quests.gd` `_num` | JSON numbers are floats; `str(16.0)` read as 160, so no kill quest with a location filter (Fred's 500) ever counted | numbers converted directly |
| `scripts/player.gd` | punches only hit a zombie in body contact (0.8), but zombies attack and grab from 1.25-1.55 units, so an unarmed player could not hit back | swings also hit targets in front within 1.6 (the shove's reach) |
| `scripts/player.gd` `_shove` | searched only the player's siblings; zombies live under `Level/Actors` | also searches the `zombie` group |
| containers, NPCs, World | one E press could search a container, open a dialogue and use a link at the same time | `World.interact_target()` |
| `scripts/ui/ui_controller.gd` | restored the pause state from when its first screen opened, so the level-up screen after a dialogue left the game frozen | stays paused only while another pauser is still showing |
| `scripts/core/world.gd` `from_dict` | re-entering the room on load overwrote the saved visit times | kept |
| `scripts/core/director.gd` | a disabled Director still spawned room-entry zombies; `ending_rush` was not saved | fixed; `start_ending_rush()` |
| `scripts/core/save_game.gd` | unlisted systems (Companions) loaded after World | World always last |
| `scripts/ui/slot_list.gd`, `game_flow.gd` | slots 0-2 were shown as "Slot 1-3", so saving to "Slot 1" wrote the autosave slot | autosave row (load only) plus manual slots 1-3 |
| `scripts/ui/game_flow.gd` | `World.enter_loaded_game` did not exist, so a load from the menu changed scene by hand; quit to menu kept the run | added; reset on the way to the menu |
| `scripts/core/world.gd` | a picked lock did not let the player through | walks on after the minigame |
| `scripts/loot/container.gd` | loot RNG ignored `seed()` | seeded from the global RNG |

## Known gaps

- Human enemies (Jeb and Paul's ambush, `enemy`/`enemyX` placements, `npc.enemy`) wait for the companions workstream's spawner; the `spawn` action is a no-op until `Companions.spawn_enemy` exists.
- Cutscene `setupAnNPCDirect` / `animateCharacter` and `fixJack` are not presented; cutscenes show their speech as captions only.
- Quest 500 is reached by Fred (`StoryExtras.PLACEMENTS`), but its `unlocksDoor` names an entrance that is not locked in the data.
- The way out of section 16 in the story (quest 004, Ed's bolt cutters, after 001 and 003) works, but the playthrough test skips the two talk quests and hands over the cutters.
- Zombies are not saved, so a load re-rolls room-entry spawns.
- The death screen does not offer the original's "deathSame / deathOutside" respawn.
