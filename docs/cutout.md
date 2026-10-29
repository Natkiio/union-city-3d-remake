# Cutout visuals

Flat 2D cutouts living in the 3D scene: characters are flat polygon parts (head, torso, 2 arms x 2 segments, 2 legs x 2 segments + feet, weapon, backpack) with a dark outline, unshaded, side-on. Everything is generated in code; no imported art. Physics bodies stay 3D, the rig is only their visual child.

## Files

| File | Role |
|---|---|
| `scripts/visual/cut_shapes.gd` (`CutShapes`) | polygon helpers and `make_mesh(items)`: one `ArrayMesh` per part, outline surface behind a fill surface, vertex colours, one shared unshaded material |
| `scripts/visual/cutout_rig.gd` (`CutoutRig`) | the rig (Node3D) |
| `scripts/visual/look.gd` (`Look`) | look dictionaries, palettes, `Look.random(seed)`, `Look.from_npc(record)`, `Look.normalize`, clothes/weapon lookup |
| `scripts/visual/zombie_looks.gd` (`ZombieLooks`) | enemy ref -> look + rig tweaks, `ZombieLooks.apply(rig, ref, seed=0)` |
| `scripts/visual/backdrop.gd` (`Backdrop`) | parallax layers from a parameter dictionary, presets |
| `scripts/visual/props.gd` (`Props`) | street lamp, bin, car, crate, door, window |
| `scenes/chars/cutout_demo.tscn` + `scripts/visual/cutout_demo.gd` | demo: left/right (or 1-7) switch stage |
| `tests/test_cutout.gd` | headless tests |
| `tests/capture_demo.gd` | NOT a test: windowed screenshot tool |

## Rig contract

```gdscript
var rig := CutoutRig.new()            # origin = feet (y=0); faces +X when facing == 1
add_child(rig)
rig.apply_look(Look.from_npc(rec))    # or any dict with npc.json / pre.json keys
rig.play("walk")                      # idle walk run punch shove aim hurt die crawl rise
rig.set_facing(-1.0)                  # mirrors the flip node
rig.set_aim(0.3)                      # radians, + = up; used by "aim" with a firearm
rig.animation_finished.connect(func(a): ...)
```

- Integration: place the rig at the body's feet (the capsule is 1.8 tall, so `position.y = -0.9` under the body). The rig draws in the XY plane with thin Z layers (+-0.1) so it stays on the Z=0 lane.
- `play()` semantics: playing the current looping anim again is a no-op (safe every frame). One-shots (`punch` 0.4 s, `shove` 0.46, `hurt` 0.36, `die` 0.95, `rise` 1.4) emit `animation_finished(anim)` and return to the last looping anim, except `die`, which holds the dead pose (`is_dead()`); a dead rig ignores everything except `rise`. Requesting a loop during a one-shot is remembered and applied afterwards.
- Weapons: `look.weapon` is a `weapon.json` ref. `Look.weapon_class` maps it to `none | pistol | long | melee | shield`. Firearms hold the two-hand pose (idle low, `aim` follows `set_aim`); melee holds the weapon at the ready and `punch` is an overhead swing; unarmed uses a boxer guard. `rig.set_weapon(ref)` swaps it.
- Extras: `joint_position("hand_f"|"head"|"lf_ft"...)` (rig space, for muzzle/blood effects), `mesh_count()`, `anim_speed`, `advance(dt)` (the rig also advances itself in `_process`; call `set_process(false)` + `advance` to drive it manually).
- Animation is procedural: a pose (joint angles) is computed from (anim, time) each frame and eased into the joints; two-bone IK places the hands on weapon grips and the guard; the hips are lowered so the lowest foot touches the ground.
- Cost: about 14 mesh instances per character (limit: 40).

## Looks

Keys (all optional, `Look.normalize` fills them): `sex skinColour hair hairColour facialHair clothesTop clothesBottom clothesShoe faceAccessory torsoAccessory headAccessory backpack weapon`. `"random"` and `$expr` nodes resolve deterministically (seed from the content).

- Hair: none bald shaved cropped short1-3 medium1-2 long1 ponytail1 afro mohawk special1-3 (every value in `npc.json` is covered). Facial hair: shadow fullBeard 1980s soulPatch lincoln goatee.
- Clothes: `Look.top_style(ref)` / `bottom_style(ref)` map the original ref names (`male_armyTop`, `female_jeansBlue`, ...) to colour + sleeve + overlay shapes (apron, pockets, hazard band, badge, stripe, plaid, tie, hood, gown). Unknown refs fall back to a colour guessed from keywords (`Blue`, `Black`, ...).
- Accessories: face (glasses, big glasses, sunglasses, goggles, gas mask, medical mask, bandana, HERC mask), head (cap, army helmet, rebel headband, hazmat hood, HERC helmet, crown, beanie), torso (kevlar vests), backpack.
- Palette: dark and muted, bold outline (`CutShapes.OUTLINE_COL`).

## Zombie looks

`ZombieLooks.apply(rig, "zombieFat")` sets look + tweaks for all 22 refs in `enemy.json`. Tweaks (`rig.apply_tweaks`): `zombie` (grey-green skin, pale eyes, wound patches), `tatter` (ragged hem, drab clothes), `posture` (`stand`, `crawl`, `dog`), `hunch`, `gait` (speed), `limp`, `arms_out`, `width`, `height`, `belly`, `armor[]` (helmet_riot, helmet_army, cap_police, chest, shins, elbows, gloves). `ZombieLooks.move_anim(ref)` gives `walk`, `run` or `crawl` from `enemy.walkAnim`. Silhouettes: fat = wide torso and belly; crawler = on the belly; dog = four legs, long body; riot/army/police = helmet, vest, shin guards; riot shield = shield plate; hatchet/cleaver/hammer = weapon in hand (sprint variants lean harder and use the run gait). Unknown refs get the plain walker.

## Backdrop and props

`Backdrop.build(params)` returns a Node3D with layers `sky` (z -80), `far` (-40), `mid` (-20), `near` (-7); a perspective camera gives the parallax. Parameters: `seed width center_x sky_top sky_bottom orb orb_x far mid features feature_x palette near haze`; presets `cork_day`, `cork_dusk`, `docks_night`. Features: `shandon` (church tower with pepper-pot spire and weathervane), `bridge` (stone arch bridge over water), `cranes` (dock cranes); `mid = terraced` (pastel terraced houses) or `industrial`. `Props.make(name, opts)` for `street_lamp bin car crate door window`; props are origin-at-ground, side-on, and must be placed off the Z=0 lane.

## Seeing it

```
godot --path . -s tests/capture_demo.gd -- /some/dir     # windowed, ~5 s, quits by itself
```

Saves `stage_<name>.png` (1600x900) for every demo stage (anims, weapons, looks, zombies1, zombies2, closeup, closeup_zombies) to the given directory (default `user://`). Run the demo interactively with `godot --path . scenes/chars/cutout_demo.tscn`. The demo camera is level with a shifted frustum, so vertical lines stay vertical.

## Notes and (verify)

- The rig does not react to lighting (unshaded): night needs a tint pass (follow-up: `Clock` lighting preset -> `rig.set_tint`).
- Hair/clothes shapes are interpretations of the ref names, not copies of the original art. **(verify)** the original `faceAccessory`/`headAccessory` names that are not in `npc.json` once more NPCs are used.
- Melee `punch` for firearms is a short forward thrust (rifle butt); a distinct pistol-whip is not drawn.
