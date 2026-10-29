# Loot workstream

Containers, searching, locks, shops, cash. Spec: `ORIGINAL_ANALYSIS.md` sections 6, 7, 10.

## Pieces

- `scripts/loot/loot_rules.gd` (`LootRules`): pure statics, seedable `RandomNumberGenerator`. `generate(def, room_type, danger, {searching, luck}, rng)` returns resolved entries `{ref, name, weight (per unit), count, kind, lucky?}`. Order as the original: fixed `cnt`, junk, lucky, cash (rooms of type `anywhere`), shuffle. `noJunk` skips junk, lucky and cash. `search_xp(level, adjusted_smarts)`, `drop_rates()`, `roll_drop_categories()` (for zombie drops, nothing calls it yet).
- `scripts/loot/container.gd` + `scenes/loot/container.tscn`: `setup(container_id, def, room_type, danger)`, `interact()`, `search_now()`, panel interface `items` / `take_item(i)` / `take_all()` / `title`. Body recessed at Z -1.4, trigger Area3D reaches Z=0, hover through `hoverable.gd`.
- `scripts/loot/locks.gd` (`Locks`), `pick_game.gd` (`PickGame`, pure), `lock_ui.gd` + `scenes/loot/lockpick.tscn` (minigame UI).
- `scripts/loot/shop.gd` (`Shop`), `shop_ui.gd` + `scenes/ui/shop.tscn`.
- `scripts/trunk_ui.gd` / `scenes/ui/trunk_ui.tscn`: the autoload `TrunkUI` is now the general container panel (title, scrolling list, per-stack weight, "Carrying x / limit", rows flagged "(over limit)"). Taking is never blocked; overweight is the player's slowdown, as in the original.
- `scripts/loot_state.gd`: adds `containers` (`id -> {searched, items}`) and `locks` (`id -> {unlocked, broken}`) to the saved dict. Old `looted` / `trunk_contents` unchanged.

Static classes reach autoloads with `LootRules.auto("Stats")` etc. so they also compile in `-s` test runs. The node scripts (container, lock_ui, shop_ui) have no `class_name` for the same reason.

## Rules as implemented

- Junk: `random(100) <= 50` (so 51%), then `round(random(6) - searching/10)` items, min 0, from `<roomType>Junk`. `searching` is the raw skill.
- Junk lists: junk items by `location`, plus clothing by `location` (default "bedroom"). Room types in the data: anywhere, office, basement, kitchen, bathroom.
- Lucky: `random(1000) <= round(75 + luck*5 + searching*2)`, then `random(2)+1` items of rarity `round(random(danger)+1) + random(luck/4)`, cap 30. `rarityN` = weapon, clothing, food, meds, books with `|rarity - N| <= 5` (`rarityLevelCap`). Items with no rarity (6 clothing rows) are skipped.
- Cash: `random(100) <= 33`, index `getRandRange(1, ceil(min(round(danger*3.3 + luck), 1001) / 1.5))`.
- Search XP: `5 + level + ceil(adjustedSkill(smarts)/30)`, `Stats.add_xp(.., "search")`, then `Events.container_searched(id)`.
- Locks: required skill 15/30/45/60/75; attempt allowed when `adjusted security >= required - 25`; pins 1/2/2/3/3; half width `min(10, adj/5*k)`, k = 1.65/1.4/1.15/0.85/0.625; force `min(95, round((adj+luck)*k))`, roll `random(100)+1 <= chance`, failure sets `broken` for good; keys are questItems whose `door` equals the lock's `door_id` (or id), consumed on use; security XP `25 + level + ceil(smarts/30)`. Containers with `hasKey` cannot be forced.
- Pin sweet spot centre: `-35 - (random(50) + 15/k + random(luck))`, clamped to [-85, -35]. A miss drops the previous and current pin and steps back one (two on a very hard lock past pin 2).
- Shop: `discountCost = ceil(cost * (100 - smarts/2)/100)` with the **raw** Smarts skill (the original reads `player.smarts`).

## Decisions and deviations

- **Cash** is the inventory item `Cash` (weight 0, count = dollars). No change to `inventory.gd`. `Shop.cash()/add_cash()/spend_cash()`.
- **Weapon mods are out of scope.** Refs such as `tireIron_damaged` resolve to the base item and the entry carries `mod`; no stat change.
- **Selling** is new (the original has no sell screen): half the base shop price, only for items some shop set sells, whole boxes for ammo.
- Only `shopSet1` and `shopSet2` exist in the extracted data (rooms reference those).
- Ammo ref `ammo<type>_<n>` becomes `Weapon.ammo_name_for(type)` x n ("9mm Ammo", "5.56 Ammo").
- Pin rise (150/s) and fall (50/s) speeds and "glow when in the sweet spot" are our tuning **(verify)**; the original animates tweens and shakes the pin.
- The skill gate for opening a lock reads `Stats.adjusted_skill("security")`.

## Seams

- World: one `container.tscn` per `contN`, `setup("<room path>_<contN>", def, room.type, danger)`. For doors, call `Locks.try_open({id, door_id, locked, lock_diff, needs_key, can_force: false}, host, callback)`; it answers `OPENED` / `STARTED` / `DENIED` and always calls `callback(ok)`; `Locks.last_denied_reason` holds the prompt text.
- Shop: `World` instantiates `scenes/ui/shop.tscn` and calls `open(room.shopSet)`.
- Persistence: nothing to do, LootState is in group `stateful`.
