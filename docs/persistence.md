# Persistence

`SaveGame` (autoload, `scripts/core/save_game.gd`) saves and loads the whole run. Pure format code lives in `scripts/persistence/save_format.gd`; the playtime counter in `scripts/persistence/playtime.gd`; the slot picker in `scenes/ui/save_slots.tscn`.

## Slots and files

- Slot 0 is the autosave, slots 1-3 are manual. `user://saves/slot_N.json`, pretty-printed JSON.
- Written atomically: `slot_N.json.tmp` is written, read back and compared, then renamed over the slot. A failed write or rename leaves the old save alone and returns false.
- Quick keys (`quick_save`, `quick_load`, handled in `_unhandled_input`) use slot 1.

## Format

```json
{
  "version": 1, "game": "cork",
  "header": {"name": "", "level": 7, "location": "", "clock_text": "Day 2 12:00", "playtime_seconds": 3725.0, "saved_unix": 0},
  "systems":   {"Stats": {...}, "Clock": {...}},
  "providers": {"Player": {...}}
}
```

`systems` holds `to_dict()` of every node in group `stateful`, keyed by node (autoload) name; `SaveGame` itself is left out. JSON has one number type, so on load whole floats are turned back into ints (`SaveFormat.normalize`). Do not put Vector3, Color or objects in a `to_dict()`; use arrays and strings.

## API

`save_slot(n) -> bool`, `load_slot(n) -> bool`, `has_slot(n)`, `slot_info(n)` (`name, level, location, clock_text, playtime_seconds, saved_unix`; `{}` if empty, `{corrupt: true}` if unreadable), `delete_slot(n)`, `autosave(force = true)`, `quick_save()`, `quick_load()`, `last_error()`. Signals: `saved(slot)`, `loaded(slot)`, `load_failed(slot, reason)`.

## Loading

1. The file is read, parsed, version-checked, migrated and shape-checked (`SaveFormat.parse`) with the running game untouched. Any problem (empty, truncated, garbage, wrong game, newer version, no migration path, `systems` not objects) returns false and emits `load_failed`.
2. `GameState.reset_run()`.
3. `from_dict` per system in `SaveGame.LOAD_ORDER` (Stats, Clock, Survival, Inventory, LootState, Quests, Director, World); unlisted systems follow alphabetically. A system missing from the file keeps its `reset()` state. A system in the file but not in the game is ignored with a warning.
4. Providers, then the playtime counter.

Migrations: `SaveFormat.MIGRATIONS` maps `old_version -> Callable(data) -> data at old_version + 1`. Bump `SaveFormat.VERSION` and add an entry when the format changes incompatibly. Version 0 is the worked example (top-level `player` moves into `header.name`).

## Providers (state that is not an autoload)

```gdscript
SaveGame.register_provider("Player", to_dict_callable, from_dict_callable)
SaveGame.unregister_provider("Player")   # when the node leaves the tree
```

`to_dict_callable() -> Dictionary` is called at save time; `from_dict_callable(d)` after all systems are restored (so the player can be placed in the room `World` just rebuilt). Suggested player keys: `health`, `perm_health`, `equipped_weapon`, `position` as `[x, y, z]`.

## Autosave

Slot 0 is written on `Events.location_entered` (debounced to one per 5 s), `Events.level_up`, and `SaveGame.notify_rest_finished()` (the sleep/wait dialog calls it; it also connects to `Survival.sleep_finished` if that signal ever exists). Refused while loading, dead (`player_died` until `run_reset`/`run_started`), paused, or `Director.rush_active`. `autosave_enabled = false` turns it off (tests).

## Adding a stateful system

1. In `_ready()`: `add_to_group("stateful")`.
2. Implement `reset()` (back to a new-game state), `to_dict()` (JSON-safe, only what cannot be rebuilt), `from_dict(d)` (tolerate missing keys with `d.get(key, default)`).
3. If it must be restored before/after another system, add its node name to `SaveGame.LOAD_ORDER`.
4. Add a case to the rich state in `tests/test_persistence.gd`; the round trip compares every system's `to_dict()` automatically.
