# zombies  -  Done (first pass)
Branch: feat/zombies (worktree uc-worktrees/zombies), 3 commits, not pushed
Done: Zombie state machine (idle/wander/rise/chase/attack/grab/stumble), 22 types via one scene, alert rolls, shot alerts, Struggle class, DirectorRules + Director autoload (budget, pools, ambient, room entry, rushes, breaks, droppers), docs/zombies.md
Doing: -
Blocked: player.start_grab/end_grab and struggle key input (combat); Clock.game_minutes (survival); something must call Director.attach/begin_area (world)
Next: integrate with real player, main.tscn spawn via Director, ammo check in rush formula
Tests: tests/test_zombies.gd  73 pass / 0 fail
