# persistence  -  Done
Branch: feat/persistence
Done: SaveGame autoload (slots 0-3, atomic write, versioned format + MIGRATIONS, staging load, LOAD_ORDER, providers, autosave rules, quick keys), save_slots picker scene, docs/persistence.md, round trip of all merged systems.
Doing: -
Blocked (owner fixes, none stop persistence):
 - director.gd reset() does not clear rush_start, break_start, break_length -> stale values after reset_run. Add to reset(): `rush_start = 0.0; break_start = 0.0; break_length = 0`.
 - Quests/World are still stubs (to_dict {}); round trip covers them once real. World must register a "Player" provider or restore the player itself.
 - Sfx.to_dict saves bus volumes: loading a save changes the user's volume (settings, not run state). Suggest dropping from to_dict or moving to settings file.
 - No rest-finished event: ui sleep/wait dialog should call SaveGame.notify_rest_finished() (or Survival adds signal sleep_finished).
Next: -
Tests: tests/test_persistence.gd  122 pass / 0 fail
