# loot  —  Done (pending lead merge)
Branch: feat/loot
Done: LootRules (sec. 6 generation), container scene + search + persistence (LootState), container panel (TrunkUI reworked, car trunk intact), Locks + PickGame + lockpick UI, Shop + shop UI, cash as inventory item "Cash", docs/loot.md
Doing: -
Blocked: nothing hard. World must call Container.setup / Locks.try_open / ShopUI.open (see docs/loot.md Seams)
Next: zombie drops could use LootRules.roll_drop_categories; door locks need world hookup
Tests: tests/test_loot.gd  99 pass / 0 fail
