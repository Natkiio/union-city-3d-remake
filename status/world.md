# world  —  Done
Branch: feat/world (5 commits on dev, not merged)
Done: tools/extract_layout.py (room widths + door/stair/container markers + map positions from the SWF; data/original/world/layout/, map.json); WorldData, LevelBuilder, SetDressing (cutout kit seam), WorldLink, World autoload (contract API, doors/stairs/drops/locks, travel in hours, map_nodes, save/load), run scene scenes/main.tscn, camera limits; old house scenes + door_trigger.gd removed
Doing: -
Blocked: none. Requests: CLAUDE.md should list tools/extract_layout.py next to extract_data.py; ORIGINAL_ANALYSIS sec. 12 travel unit is hours (details in docs/world.md)
Next: follow-ups in docs/world.md (persistent zombies per room, human enemies, shops/notes markers, noSpawn)
Tests: tests/test_world.gd  85 pass / 0 fail (suite 624/0)
