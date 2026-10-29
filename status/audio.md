# audio  —  Done
Branch: feat/audio
Done: procedural SfxSynth (all 20 one-shots, 3 groan variants, 3 ambient beds); Sfx autoload with Sfx/Music/Ambient buses, 12+12 player pool, cache, Events hooks (shot, damage, death, kill, level up, item use, search); docs/audio.md
Doing: nothing
Blocked: none (no project.godot change needed, buses are created in code)
Next: rain_loop not built (optional); noise arg of shot_fired unused; human enemy kills need a branch
Tests: tests/test_audio.gd  38 pass / 0 fail (tools/run_tests.sh: test_core 8/0 too)
