# Audio: procedural placeholder sounds

Owner: audio workstream. Code: `scripts/core/sfx.gd` (autoload `Sfx`), `scripts/audio/sfx_synth.gd` (class `SfxSynth`, pure sample builders). Tests: `tests/test_audio.gd`.

No audio files. Every sound is generated in code as mono 16-bit PCM (22050 Hz one-shots, 11025 Hz ambient loops), built on first use and cached.

## Buses

Created in code by `Sfx._ready()` under `Master`: `Sfx`, `Music`, `Ambient`. One-shots play on `Sfx`; the ambient bed plays on `Ambient`. `Music` is created but unused so far.

- `Sfx.set_volume(bus, v)` with `v` in 0..1 (0 is silent). `Sfx.get_volume(bus)` reads it back.
- `Sfx.to_dict()` / `from_dict()` save the bus volumes. `Sfx` is in group `stateful`, and `reset()` stops all sound.

## API

- `Sfx.play(name, position = Vector3.INF, volume_db = 0.0) -> bool`. With a position it uses a 3D player at that point, otherwise a 2D player. Returns false for an unknown name.
- `Sfx.start_ambient(kind, volume_db = -6.0)` and `Sfx.stop_ambient()`. Kinds: `street`, `interior`, `night`. Each is a detuned drone, 8 s long, with every frequency a whole number of cycles per loop so the loop point is seamless.
- Players come from a fixed pool of 12 2D and 12 3D players (`Sfx.pool_stats()`). When all are busy, the next in rotation is stolen.

### Sound names

`pistol_shot`, `shotgun_shot`, `rifle_shot`, `smg_shot`, `dry_click`, `reload`, `punch_hit`, `shove`, `melee_swing`, `blade_hit`, `zombie_groan` (3 random variants), `zombie_bite`, `zombie_death`, `player_hurt`, `player_death`, `pickup`, `door`, `ui_click`, `level_up`, `heartbeat`.

Not built: `rain_loop` (optional in the brief, left for later).

## Events hooks

Connected in `Sfx._ready()` with guards: a missing autoload or signal logs a warning and is skipped. Each hook calls `Sfx.play`.

| Event | Handler | Sound |
|---|---|---|
| `shot_fired(weapon_ref, noise, position)` | `_on_shot_fired` | gunshot chosen by `Sfx.gunshot_for(weapon_ref)`, positional |
| `player_damaged(amount, source)` | `_on_player_damaged` | `player_hurt` |
| `player_died()` | `_on_player_died` | `player_death` |
| `enemy_killed(enemy_ref, danger, xp)` | `_on_enemy_killed` | `zombie_death` (every enemy kill, for now) |
| `level_up(new_level)` | `_on_level_up` | `level_up` |
| `item_used(item_name)` | `_on_item_used` | `pickup` |
| `container_searched(container_id)` | `_on_container_searched` | `pickup` |

`Sfx.gunshot_for` keyword rules, checked in this order:

1. `shotgun`, `pump`, `12ga` → `shotgun_shot`
2. `smg`, `automatic`, `uzi`, `mp5`, `venom` → `smg_shot`
3. `rifle`, `longgun`, `sniper`, `ak47`, `m16`, `fal`, `hellslinger` → `rifle_shot`
4. anything else → `pistol_shot`

Sounds that need a direct call (not on the bus): `dry_click`, `reload`, `punch_hit`, `shove`, `melee_swing`, `blade_hit`, `zombie_bite`, `door`, `ui_click`, `heartbeat`. Combat, UI and world code call `Sfx.play(...)` for these.

## Known limits

- `shot_fired`'s `noise` argument is not used for volume yet.
- `enemy_killed` plays the zombie death sound for any enemy. Human enemies will need a branch on `enemy_ref`.
- Sounds are placeholders: short, synthesised, no mixing or ducking.
- Headless tests report 2 leaked objects at exit (an `AudioStreamWAV` held by the sound cache). This is a shutdown report only; all checks pass.
