# survival  —  Done
Branch: feat/survival
Done: Clock (time, signals, 28 light presets), DayNight node, Survival (hunger/sleep/penalties/eat/sleep/wait), Items lookup, ItemUse (food/meds/books/clothing), Inventory.use_item + carry limit/overweight, weight bar UI, docs/survival.md
Doing: -
Blocked: Stats needs set_penalty(attr, n) [floor 1], add_skill_points(skill, n); player should expose perm_health and read Inventory.overweight for the movement penalty
Next: sleep healing in bed/safehouse (world/ui), street lights, brightness setting
Tests: tests/test_survival.gd  72 pass / 0 fail
