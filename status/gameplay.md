# gameplay  —  Done
Branch: feat/gameplay
Done: kill XP paid once (was doubled), armor via zombie.armor_for incl. melee, grab/struggle on player + StrugglePrompt, run/crouch actions, overweight slowdown, heal_perm/rest/full_heal, level-up restore, hunger in stamina max, ranged damage floor, bullets on Z=0, balance baseline in docs/gameplay.md
Doing: -
Blocked: sleep/wait dialog must call player.rest(h) (ui); no Events "level-up confirmed" (restore happens on level_up)
Next: tuning pass using the [BALANCE] baseline
Tests: tests/test_gameplay.gd  73 pass / 0 fail
