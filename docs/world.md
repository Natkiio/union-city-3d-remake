# World (workstream notes)

Rules: `docs/ORIGINAL_ANALYSIS.md` sec. 5, 9, 12. Source functions read: `setupRoom`, `changeRooms`, `openDoor`, `openRoom`, `openEntranceDoor`, `openExitDoor`, `stairsUp/Down`, `dropFloor`, `moveStreet`, `checkIfDoorLocked`, `attemptUnlockDoor`, `checkIfSafeHouse`, `setMaxThreat`, `travelTo`, `goto`, `setupMapLocations`, `buttonSetup_locations`.

## Where room geometry comes from

The location tables (`world/l*.json`) say what is in each room but not where. Widths, doors, stairs and container spots are named instances inside each room's movieclip in the SWF (symbol `l16_s3_b1_f1_r1`). `tools/extract_layout.py` reads an FFDec XML dump and writes, per section, `data/original/world/layout/l<N>.json`: `{room_id: {width, left, top, height, floor_y, markers: [{name, x, y, left, right, top, bottom, flip}]}}` in Flash px, plus `data/original/world/map.json` (map position of each section). Numbers and names only. Regenerate, never hand-edit:

```
java -Xmx6g -jar ~/tools/ffdec/FFDec.app/Contents/Resources/ffdec-cli.jar -swf2xml reference/union_city.swf /tmp/uc.xml
python3 -I tools/extract_layout.py /tmp/uc.xml data/original/world
```

285 of the 292 rooms have art. The rest (story-link sections 2, 3, 4, 8, 10 and the unused `s0` rooms of 14 and 15) get a synthesised layout (3000 px street or 600 px room). Section 1 is defined in the original with its buildings at the top level and no street; `WorldData.section()` reads it as street 1.

## Files

- `scripts/world/world_data.gd` (`WorldData`): pure lookups. Room ids, tables, danger (section, then street, then building, like `setMaxThreat`), outdoors, safehouse (`checkIfSafeHouse`), layout, `links(room_id)`, spawn x, containers, NPCs, human enemies, map positions, travel hours.
- `scripts/world/level_builder.gd` (`LevelBuilder`): builds a `Level` for any room id. No per-section scenes.
- `scripts/world/level.gd` (`Level`), `scripts/world/world_link.gd` (`WorldLink`: the trigger for a door, stair, exit, edge, map exit or bed).
- `scripts/world/set_dressing.gd` (`SetDressing`): all visuals (flat outlined panels, signs, parallax backdrops). The cutout workstream replaces it by adding `scripts/visual/world_kit.gd` that extends `SetDressing`; `SetDressing.create()` picks it up.
- `scripts/core/world.gd` (`World` autoload), `scripts/world/run_scene.gd` (root of `scenes/main.tscn`), `scripts/camera_rig.gd`.
- `tests/test_world.gd`, `tests/capture_level.gd` (screenshots, not a test).

## Markers and links

| Marker | Goes to | Lands at |
|---|---|---|
| `door<N>` | same floor, room -1 if the door is in the left half, else +1 (`openDoor` uses the player's side; doors sit at the ends) | the other room's far edge, 50 px in |
| `entr<N>` (street) | building N, floor 1, room 1 | `exit<N>` there |
| `exit<N>` | the street (`b0 f0 r1`) | `entr<N>` there |
| `sup` / `sdwn` | same room number, floor +1 / -1 | `sdwn` / `sup` there |
| `drop` | same room, floor -1 (one-way) | `drop` there, else the same x |
| `strt<N>` | street -1 (left half) / +1, only if that street has a name | far edge |
| `area<N>` | the map (`World.map_requested`) | |
| `room<N>` | room N on the same floor | `room<previous>` there |
| `uprm<N>` / `dnrm<N>` | room N (the woods paths) | `dnrm<prev>` / `uprm<prev>` |
| `ltrm` / `rtrm` | room -1 / +1 | far edge |
| `abed<N>` | bed, safehouses only (`World.bed_used`) | |
| `cont<N>`, `body<N>`, `trig<N>` | container spot, dead body, story trigger zone (`World.trigger_entered(id)`) | |

A target that does not exist is a dead end (the original plays the locked sound): 47 of them, almost all boarded-up entrances. One-way in the data: the drop in `l13_s2_b1_f2_r0`, three woods paths in `l15_s3`, and `l9_s2_b5_f2_r1`'s stairs down (its lower room has no stairs up). Their missing landing marker falls back to the room centre. Not built: `shop<N>` slots (loot), `note<N>` (story), `bloc<N>` climbable blocks, `noSpawn` zones (the Director has no API for them), `l*` light markers.

## Scale and layout

- 100 px = 1 unit, as the zombies. A street is about 30 units, rooms 4 to 36.
- The floor's top is y = 0. Player and zombies walk the Z = 0 lane. Solid bodies: the floor (under the lane) and two end walls (`level_bounds`) at x = 0 and x = width. Everything else is visual or an `Area3D`.
- Street: facades at z = -4 (one per `entr` marker, floors from the building data), props and street signs at z = -2, skyline layers at -22 and -45 (city) or hills and tree lines (streets with no entrances), sky at -60. Perspective gives the parallax.
- Room: back wall at z = -2.4, ceiling at 3.4, furniture at -1.7, NPCs at -1.1.
- Camera (run scene): street offset (0, 2.6, 9.5), rooms (0, 2.0, 7.0), fov 38. It clamps to the room ends and centres rooms narrower than the view.
- Triggers: a 1.2-unit wide box from the visual to z = +0.8. Interact picks the nearest `WorldLink` in range. A `Hover` child (layer 2, `hoverable.gd`) highlights it under the mouse.

## World autoload

- `start_new_game()`, `enter_location(section_id, at_end=false)`, `enter_room(room_id, spawn_at)`, `travel_to(section_id) -> bool`, `use_link(link)`, `current`, `map_nodes()`, `is_safehouse()`, `unlock_door(id)`, `lock_door(id)`, `resume()`.
- `spawn_at`: `""` or `"left"` (left edge), `"right"`, a marker name in the target room, or `"x:<px>"`.
- `current`: `room_id, section, street, building, floor, room, danger, width_px, outdoors, safehouse, name, section_name, light_reduction`.
- Every area change: `Director.attach(level.spawn_root(), player)`, `Director.set_bounds(0, width)`, `Director.begin_area(danger, width_px, outdoors, safehouse, room_id)` (the Director keeps per-room visit times for `repopTime`), DayNight `light_reduction` from the room, ambient sound, `Events.location_entered(room_id)`, `World.room_entered(current)`, and a name banner. Zombies live under the level and go with it.
- Without a run scene (menus, sim tests) World still tracks the room and tells the Director.
- Transitions fade through black (`fade_enabled`; tests turn it off). The level is rebuilt in place, so the player node (health, stamina) survives.
- Stateful: `room_id`, `player_x_px`, `door_locks`, `visited`. `from_dict` rebuilds at once if the run scene is up, else on the next `attach_run_scene` (or `resume()`).
- Signals for other workstreams: `map_requested` (ui map screen; if nothing listens, the area exit travels to the first open neighbour so the game stays playable), `bed_used` (ui sleep dialog), `trigger_entered(id)` (story), `door_refused(door_id, reason)` (HUD message), `room_entered(current)`.

## Locked doors

Per room, `lockedDoors[i]` names a marker; `needsKey[i]` and `lockDiff[i]` go with it. A door starts locked and the state is kept in `World.door_locks` under the original's key `<room id>_<marker>` (also what `questItem.door` holds). Opening it: a held key item whose `door` matches opens it and is used up; else `Locks.try_open(def)` (an autoload or global class named `Locks`, from loot) with `def = {door_id, name, room_id, needs_key, lock_diff}`. It returns true (open), false (refused) or anything else (a minigame that calls `World.unlock_door(door_id)` itself). Without `Locks`: key doors stay shut, lockpick doors open. Only the side listed in the data is locked, as in the original.

## Travel (sec. 12)

`travelTo` calls `sleepWait(null, round(manhattan / 200))`, and each `sleepWait` step is `gameTime += 60`: the unit is **hours**. `World.travel_to` advances `Clock` by that many hours (Clock's minute ticks raise hunger and sleep), then enters the section at its `startLoc`, left edge, like `goto(startLoc, "start")`. Allowed only to sections on the map with art (5, 6, 7, 9, 11-16) and unlocked (`Quests.is_section_unlocked(id)` when it exists, else all). Examples: 16 -> 9 is 2 h, 16 -> 13 is 4 h, 9 -> 5 is 7 h.

- **(verify)** each `sleepWait` hour also restores health (10% of max + (fitness + endurance) / 2) and stamina. Not reproduced: travel just moves the clock.
- **(verify)** the original's map has no markers for sections 1-4 and 10, and section 8 has no `startLoc`; the original cannot travel there either.

## Not built (follow-ups)

Persistent zombies per room (`saveZombies`/`restoreZombies`), human enemies (`enemy`/`enemyX` are in `WorldData.enemies()` but not placed), the endLoc choice in the travel dialog (ui; `enter_location(id, true)` exists), shops, notes, light markers, climbable blocks, `noSpawn` zones, the "deathSame/deathOutside" respawn rules.
