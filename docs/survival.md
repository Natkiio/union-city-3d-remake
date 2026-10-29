# Survival workstream

Time, lighting, hunger and sleep, the item lookup, item use and the weight limit. Spec: `ORIGINAL_ANALYSIS.md` sections 4, 7, 9.

## Clock (`scripts/core/clock.gd`)

- `game_minutes` starts at 1440; the clock face starts 12:00 (`minute_of_day() = (game_minutes - 1440 + 720) mod 1440`). `hour()`, `minute()`, `day()` (1-based), `time_text()`.
- `SECONDS_PER_GAME_MINUTE = 50 / 30` (~1.67 s). `_process` ticks `advance(1)`; frozen while `get_tree().paused` or `Clock.running = false` (cutscenes, tests).
- `advance(minutes)` emits `Events.minute_passed(game_minutes)` per minute and `Events.hour_changed(hour)` at each hour. Travel and sleep use it. `set_time(h, m)` jumps forward to the next such time.
- `lighting_preset(light_reduction = 0)` returns the `lightTimeN` row plus `id`. `ra/ga/ba` are percent multipliers (100 = unchanged; the original feeds them to a colour transform), reduced by `light_reduction` percent indoors. `light_color()` is the tint normalised to a max channel of 1; `energy()` is the brightest channel / 100 clamped 0.1..1.
- Preset by time (`PRESET_STARTS`, minute of day): 00:00 -> 1, 04:00 -> 2, 05:00 -> 3, 05:31 -> 4, 06:00 -> 5, 06:16 -> 6, 06:30 -> 7, 07:00 -> 8, 07:30 -> 9, 08:00 -> 10, 08:31 -> 11, 09:00 -> 12, 09:31 -> 13, 13:00 -> 14, 16:00 -> 15, 16:31 -> 16, 17:00 -> 17, 17:16 -> 18, 17:31 -> 19, 17:46 -> 20, 18:00 -> 21, 18:16 -> 22, 18:31 -> 23, 18:46 -> 24, 19:00 -> 25, 19:16 -> 26, 19:31 -> 27, 20:00 -> 28. The original's `setLighting` leaves a few one-minute gaps (exactly :15/:30 in some hours); we keep the earlier preset. **(verify)** Its 12:xx rule and the `18:31-18:45` branch (`M > 30 && M > 45`) look buggy, so 23 is a guess.
- Not done: the brightness setting, street lights.

### DayNight node (`scripts/items/day_night.gd`)

Add a `DayNight` node to a level scene. With `sun` / `world_environment` left empty it uses the first `DirectionalLight3D` / `WorldEnvironment` in the scene. It eases the light colour and energy (`base_sun_energy`, `base_ambient_energy` times `Clock.energy()`) and ambient colour to the current preset. `light_reduction` (percent) dims interiors. `apply_now()` snaps.

## Survival (`scripts/core/survival.gd`)

- `hunger`, `sleep`: 0-100, +0.15 per game minute each (via `Events.minute_passed`). `mode`: `"survivor"` or `"runngun"`; Run'n'Gun turns both off (no growth, no penalties). `reset()` keeps the mode.
- `penalty_for(v) = round((v - 70) / 3)` above 70. Hunger lowers strength and endurance, sleep lowers precision and intellect. Applied with `Stats.set_penalty(attr, n)` if Stats has it (guarded). The floor of 1 on the resulting attribute belongs in Stats. `hunger_state()` / `sleep_state()` are `round(v / 25)`.
- `eat(amount)`, `reduce_sleep(amount)` (drops `round(amount * 10)`), `sleep_hours(h)` (time +h, sleep -`round(h * 10)`, hunger +`round(h * 60) * 0.1`, as the original's `sleepWait`), `wait_hours(h)` (time only). Sleep does not heal here; the original also restores health and stamina per hour (follow-up for whoever owns the bed/safehouse).
- Death and exhaustion consequences: not done.

## Items (`scripts/items/`)

- `Items` (`class_name Items`): `find(name_or_ref)` -> `{kind, key, ref, name, weight, rec}` over weapon, clothing, food, meds, books, junk, questItem; `kind()`, `weight()`, `all(kind)`, `in_table(kind, key)`. On a shared name or ref the first table in that order wins. Three names repeat inside a table (Cigarettes, Riot Helmet, Cargo Pants - Camo): `find` returns the first, `in_table` reaches each by key. Ammo is not a table item: `kind("9mm Ammo") == "ammo"`, `find` is empty.
- `ItemUse` rules:
  - food: `round(bonus + adjustedSkill(survival)/5)`; Survivor lowers hunger, Run'n'Gun heals (and perm health).
  - meds `health`: `round(round(bonus + adjustedSkill(firstAid)/2) / 100 * Stats.max_health())`, refused if the player's `perm_health` is at max (or `health` if the player has no `perm_health`). Heals through `player.heal()`; sets `perm_health` too if the player exposes it.
  - meds `sleep` (No ZZZ): sleep -`round(bonus * 10)`. Refused unless Survivor and `sleep > 0` (the original tests `sleep < 100`, which looks like a bug).
  - books: `bonus + ceil(adjustedSkill(smarts)/33)` points to the skill named by the book's table key (the `specialWeapons` row has `ref` "specialWeapon"; use the key). Through `Stats.add_skill_points(skill, n)` if it exists, otherwise recorded in `Inventory.book_points` (capped so skill + points <= 100).
  - clothing: equips into `Inventory.equipped_clothing[slot]` (`wearLocation`); using worn clothing removes it. Bookkeeping only. Weapons equip through the inventory UI button, not Use.
- `Inventory.use_item(name) -> bool` applies, consumes (food, meds, books) and emits `Events.item_used`. `Inventory.is_usable` / `get_use_effect` are now data-driven; the old `USE_EFFECTS` table (Canned Food, Bandages) is gone. Existing loot named "Canned Food" is unknown to the tables, so it is no longer usable; rename it to a table item (e.g. "Canned Beans").
- `add_item(name, weight = 1.0, count)`: a default weight of exactly 1.0 for a known item is replaced by the table weight.

## Weight limit

`Inventory.carry_limit()` = `Stats.carry_weight()`; `Inventory.overweight` and `overweight_changed(bool)` update on add/remove, reset, load and `Events.stats_changed`. If something edits `Inventory.items` directly, call `Inventory.is_overweight()` for a live answer. The movement penalty belongs to the player. The inventory screen shows `Weight: x / limit lbs` with a bar that turns red (and says OVERLOADED) over the limit.
