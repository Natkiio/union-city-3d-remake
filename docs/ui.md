# UI workstream

Code-built Controls, one theme (`scripts/ui/theme.gd`: colours, font sizes, panel styles). No art assets, no autoloads added.

## Files

- `scripts/ui/theme.gd` (`UITheme`), `settings.gd` (`Settings`), `game_flow.gd` (`GameFlow`), `screen.gd` (`UIScreen` base).
- Screens: `pause_menu.gd`, `settings_screen.gd`, `slot_list.gd`, `map_screen.gd`, `sleep_dialog.gd`, `quest_log.gd`.
- `scripts/ui/ui_controller.gd` (`UIController`): overlay stack, pauses the tree, maps actions `pause`, `open_map`, `sleep_wait`, `open_skills` and `Events.level_up`. The HUD adds one to itself, so any scene with the HUD has them.
- `scripts/main_menu.gd`, `scripts/hud.gd`, `scripts/death_screen.gd`; scenes `main_menu.tscn`, `hud.tscn` are now just a node plus script.

## Game flow

Main menu: New Game -> `GameFlow.new_game(host)` (`GameState.reset_run()`, character creation as a child, on `confirmed` -> `GameFlow.start_world`) -> `World.start_new_game()` if it exists, else `change_scene_to_file(res://scenes/main.tscn)`. Continue opens `SlotList`; load = `SaveGame.load_slot(n)` then `World.enter_loaded_game()` if it exists, else the main scene (**the world workstream should say what loading needs**). Death screen -> `GameFlow.to_main_menu`. Pause menu: resume, save, load, journal, settings, quit to menu. `GameFlow.scene_changer`, `quitter`, `world_override`, `save_override` are test hooks.

## Seams used (all guarded)

`World.current` (keys `section`, `danger`, `safehouse`), `World.map_nodes()` (`id, name, pos, danger, unlocked, connections`), `World.travel_to(id)`, `World.start_new_game()`; `SaveGame.has_slot/slot_info/load_slot/save_slot`; `Quests.journal()` (Array of `{id, name, desc, state}`); `Data.entry("sections", id).name` for the place name.

## Decisions

- Travel cost preview = `round(manhattan(pos) / 200)` hours (the doc's travel-time rule; unit **(verify)**). The screen only previews; World applies the time.
- Rest dialog only opens when `World.current.safehouse`; elsewhere a toast says so.
- Settings (`user://settings.cfg`): `volume_Master/Sfx/Music/Ambient`, `brightness` (stored only, nothing applies it yet), `head_shots_only` (stored only; combat/zombies must read `Settings.get_value("head_shots_only")`), `mode` (`survivor`/`runngun`, applied to `Survival.set_mode` by `Settings.apply`).
- Death summary is snapshotted on `Events.player_died` because the player resets the run before `show_death()`. Kills are counted from `Events.enemy_killed`.
- HUD never writes game state. Toasts: pickups, XP, level.

## Tests and screenshots

`tests/test_ui.gd` (headless). `tests/capture_ui.gd` is not a test: `godot --path . -s tests/capture_ui.gd -- <dir>` runs windowed, writes `ui_menu.png`, `ui_hud.png`, `ui_map.png` and quits.
