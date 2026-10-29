# NPC models

NPCs are the same Blender-rigged `male_basic` model as the player, dressed from
the original record by `CharacterLook` (`scripts/characters/character_look.gd`).
The flat cutout rig in `scripts/visual/` is not used.

## The rig
One skinned mesh, two surfaces (Clothes, Skin), 19 bones, animations Idle and
Walk. Front is local -Z; `rotation.y = -PI/2` faces +X (player convention).
The first `apply` builds one shared patched copy of the mesh whose vertex colour
stores the rest-pose position. A tiny shader (one material per surface per
character) picks shoe / trousers / top / sleeve colour from it, so no new mesh
data is needed per NPC. Flat boxes on `LookHead` / `LookChest` bone attachments
add hair, hats, glasses, masks, vests and backpacks (about 7 meshes worst case).

## API (static, no autoloads)
- `CharacterLook.apply(model_root, record)`: `model_root` is any `male_basic.tscn` instance
  (player too; `player.gd` untouched). Record keys: sex, skinColour, hairColour, hair,
  clothesTop, clothesBottom, clothesShoe, faceAccessory, torsoAccessory, headAccessory,
  backpack, optional `bodyScale` (float or Vector3). `random` and `$expr` values are
  resolved deterministically per record. Safe to call again. Sets `model_root.scale`
  (female 0.93/0.97/0.93).
- `CharacterLook.random_record(rng)` for crowds; `set_highlight(model_root, on)`;
  `top_y(model_root)`; colour tables `skin_color/hair_color/top_color/bottom_color/shoe_color`
  (keyword tables with defaults for unknown names; add a row to extend).
- Companions/human enemies: instance `male_basic.tscn`, call `apply` with the record, done.

## NPC scene
`NPC (Area3D) > Visual > Model` (male_basic instance, feet on the NPC origin) plus a
Label3D child. Idle loops pingpong with a random start offset; the model turns to
the player within 6 m (`StoryNPC.TURN_RANGE`). `head_top_y()` gives the head top above the
origin (about 1.8-2.0); the name label sits 0.3 above it, a quest marker should go about
0.4 above it. Enemy-flag NPCs get a red name. Hover = emission bump on all rig and
accessory materials plus the label. Z recess and trigger are unchanged.
`WorldData.npcs` facing is not applied by the level builder (NPCs turn to the player instead).

## Capture
`godot --path . -s tests/capture_npcs.gd -- out=/tmp/shots [ids=Williams,Carol,...]` (windowed)
writes `npcs.png` (street line-up with player and zombie) and `npcs_close*.png`.
Not a test. `tests/test_npcmodels.gd` is the headless test.

## Rough spots
Side-on the rig is thin and its arms are single blocks, so short sleeves are just
skin on the forearm; hair and hats are boxes. Hostile NPCs differ from friendly only
by the name tint. Weapons are not drawn.
