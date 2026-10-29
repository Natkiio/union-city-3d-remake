# integrate  —  Done
Branch: feat/integrate (dev acf4ffc merged, 5 commits, not pushed)
Done: RunGlue (map/bed/triggers/all story actions/quest toasts + ! ? markers/brightness), PlayerProvider, World load-last, shops, Fred placed, cash = Cash item, head shots only, ending rush, slot list (autosave + 1-3), quick keys/Continue/pause load, overlays freed on reset, DebugLog; docs/integration.md
Bugs fixed: quest kill filter on float JSON, punch reach < zombie attack range, shove never found zombies, one E press acting on several things, UIController pause restore, load overwrote visit times, disabled Director still spawned, slot 1 was the autosave
Doing: -
Blocked: -
Next: human enemy spawner (Companions.spawn_enemy) for the Jeb/Paul "spawn" action; cutscene animate/setup actions
Tests: test_integration 58/0, test_playthrough 48/0 (~40 s), test_soak 7/0 (299 rooms); run_tests.sh 20 files all ok
