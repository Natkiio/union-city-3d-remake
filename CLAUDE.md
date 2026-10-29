# Union City 3D remake

A local, not-for-publication 2.5D remake of *The Last Stand: Union City* in Godot 4. The remake is a reimplementation from specs we derive by reverse engineering the original Flash game — not a copy of its code or assets.

## Reference docs

Keep this list current. When the combined size of these gets unwieldy, switch from `@` imports to plain links and branch + PR the change.

- @ROADMAP.md — what's built in Godot, architecture, phased plan
- @docs/PORT_PLAN.md — the Cork City port: architecture, autoloads, workstreams, rules for contributors
- @docs/ORIGINAL_ANALYSIS.md — rules and formulas from the original game (combat, stats, XP, survival, zombie director, searching)

## Reverse-engineering workflow

- The original is an **ActionScript 2** SWF. Decompile with FFDec (in `~/tools`, outside the repo; reproduction commands are in `docs/ORIGINAL_ANALYSIS.md`). `rea` is not needed for this.
- `reference/` holds the SWF and decompiled scripts and is **git-ignored**. Never commit anything from it (original code, art, audio).
- `tools/extract_data.py` turns the decompiled script into JSON under `data/original/` (committed): item/enemy/quest tables, `constants.json`, and `world/` location data. Re-run it rather than hand-editing those files.
- Write new findings into `docs/ORIGINAL_ANALYSIS.md`. Mark anything not confirmed against the running original as **(verify)**.

## Testing

- `tools/run_tests.sh` imports the project (catches parse errors) and runs every `tests/test_*.gd` headless. It must pass before committing.
- A test extends `tests/test_base.gd` and overrides `run()`. Load a scene with `await load_scene("res://...")`; `change_scene_to_file` does not work from a `-s` script. Headless has no mouse, so inject aim by subclassing the player and overriding `_update_aim`.
- Use `godot --headless --path . ...`; without `--path` you get "no main scene defined".

## Git

- The branch is `main`; the port happens on `dev` and `feat/*`. Nothing is pushed or merged to `main` without Robert's go-ahead.
- Parallel work uses `git worktree add <dir> -b feat/<name> dev`, always with an explicit base branch.

## Conventions

- Follow the testing workflow and the "world layout rule" (only zombies share the player's Z=0 lane) in `ROADMAP.md`.
- Never include Claude Code references in commits or PR descriptions: no `Co-Authored-By: Claude` trailers, no "Generated with Claude Code" lines, no mentions of Claude or AI tooling.
