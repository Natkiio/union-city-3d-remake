# Story workstream

Quests, NPC state, triggers, dialogue, cutscenes. Spec: `ORIGINAL_ANALYSIS.md` section 11. Code: `scripts/core/quests.gd` (autoload), `scripts/story/`, `scenes/story/`. Test: `tests/test_story.gd`.

## Model (how the original works, as implemented)

- Quest ids are the `ref` strings ("900", "001", "500"); table keys are `quest<id>`. Four table slots (920, 012-014) are empty `{}` in the original: 35 real quests.
- Quest status: `locked`, `available` (some active NPC's current state has `quest<state>` = this id), `active`, `complete`.
- `start(id)` (setActiveQuest): `changeStateStart`, `unlocksAreaStart`, `triggerOnStart`, first start only: `startCutScene`, `startRewards`; `unlocksDoorStart`.
- `complete(id)`: fetch takes the items (needs all `itemReq` x `itemCount`), kill needs `killCount`; then rewards (items, `cash_N`, `follower`, `partner`), `unlocks` (map sections), XP via `Stats.add_xp(n, "quest")`, `unlocksDoor`, `changeStateComplete`, `triggerOnComplete`. Triggered and talk quests complete when told to.
- Talk quests complete when a dialogue opens with the `talkReq` NPC (`Quests.on_talk`), before the dialogue text is chosen (as the original does).
- Kill quests count `Events.enemy_killed` for enemy refs starting with `killType`, filtered by location/street/building when `World.current` has those keys.
- NPC dialogue state: `state` number picks `content<N>`; `quest<N>` hands out a quest. Text is `content<N>` (offer), `content<N>active`, `content<N>complete`. Buttons: confirm/decline, reqMet or reqNotMet, compResp (advances the state if `content<N+1>` exists). An NPC without a quest shows one OK button; `changeState<N>` moves its state.
- An NPC is **off** when its `state` is the string `"off"` (turnOffNPC sets it, turnOnNPC resets to 1). The separate `off` field in npc.json is never read by the original. `enemy: "true"` NPCs (soldiers, Barry) are flagged hostile-capable only.
- Triggers (`trig.json`): up to 9 `funcN` calls with `funcNvar1..4`, run once unless `multi`. Some start already `triggered: true` and are armed by `turnOnTrigger`.

## Contracts for other workstreams

- World: call `Quests.fire_trigger("trigN")` when the player enters a trigger zone; `Quests.begin_story()` at new game (fires trig1: quest 900 + cutscene 10); instantiate `scenes/story/npc.tscn` and call `setup(npc_id)` for each name in a room's `NPCs`, x from `NPC_x`, facing from `NPCFacing`, pose from `NPCPose`. NPC on/off is handled by the node itself (`Quests.npc_changed`).
- `Quests.story_action(action, args)` carries what the world must do: `startCutScene` (auto-played by CutscenePlayer unless `Quests.auto_play_cutscenes = false`), `speech` (world speech bubble: speaker, text), `showHelp`, `unlockDoor`, `startEndingRush`, `showEnding`, `cash` (loot owns cash later), `companion`, `spawn` (Jeb and Paul ambush), `fixJack`, `animateCharacter`, `setupAnNPCDirect`, `alert`.
- Doors: `Quests.is_door_unlocked(door_id)` (ids like `l5_s1_b1_f1_r403_door1`). Map: `Quests.is_section_unlocked(id)` (accepts 9, "9", "section9"); initial unlocked = section 16 only.
- UI: `Quests.journal()` rows `{id, title, short, description, status, reward, progress, tracked}`; `Quests.track(id)`; signal `Events.quest_changed(id, "active"|"complete")`.
- Save: `Quests` is stateful (`to_dict`/`from_dict`, JSON-safe: ints are re-cast on load).
- Companions are data only: `Quests.companions()` -> `{npc: "follower"|"partner"}`, `has_partner()`.

## Names and text

Quest/NPC templates use placeholders the extractor leaves to the game (`{PartnerName}`, `{Formal}`, ...). `StoryNames.context()` fills all 14 from `Stats.sex` and `Stats.player_name` (partner is "Aoife" for a male player, "Cian" for a female one, Cork "Friendly"/"Older" words). Change the names in `scripts/story/story_names.gd`.

Scripts with a `class_name` here reach autoloads through `get_node` (a `_sys()` helper) because autoload globals are not known when class scripts compile under `-s` tests.

## Data gaps found

- Quest 500's owner **Fred has no NPC record** in the original (dead test data). `scripts/story/story_extras.gd` supplies one (Cork flavour). He needs a place in the level data: section 16, street 2.
- Quest 005 (Kowalski, unlocks `l5_s2_b1_f1_r2_door1`) has no offering NPC and points at a street (s2) that l5 does not have. Dead data; implemented but unreachable.
- Quest 010 has no offering NPC (started by trig14 after 009).
- Reward refs like `XM8_specOps`, `pipe_heavy`, `PPM9_suppressed` are weapon-mod variants that are not in the item tables. `Quests.item_name` turns them into "Base (mod)"; the survival/loot owners should decide how mod variants become real items **(verify)**.
- `trig70` (fixJack) is only reached through scripted flow in the original **(verify)**; it is exposed as an action.

## Cutscenes

`world/cutScene1..13`: `lockControls` plus `actionN {func, var1, var2, timing ms}`. Only four functions occur: `displayWorldSpeech`, `setupAnNPCDirect`, `removePartner`, `animateCharacter`. There are no camera moves in the data. `CutscenePlayer` steps the timeline (`begin(false)`, `step(ms)`), shows speech as a non-pausing caption, skips with Escape (`skip()` drops pending speech, still runs state changes), ends 2.5 s after the last action and emits `Events.trigger_fired("cutscene<N>")`.

## Not done

Companion AI, human enemy AI (Jeb/Paul, `enemy` NPCs), quest log screen, placing NPCs in levels (world), a speech-bubble renderer for `speech` actions outside cutscenes.
