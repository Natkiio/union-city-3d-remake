# Progression (Stats autoload and screens)

Spec: `docs/ORIGINAL_ANALYSIS.md` sections 1-2. Code: `scripts/core/stats.gd`, `scripts/progression/`, `scenes/ui/{character_create,level_up,skills_sheet}.tscn`. Tests: `tests/test_progression.gd`.

## API (autoload `Stats`)

Reads: `level`, `xp`, `attribute_points`, `skill_points`, `attr(n)` (with penalties), `attr_base(n)`, `skill(n)`, `adjusted_skill(n)`, `max_health()`, `carry_weight()`, `xp_to_next()`, `level_xp(L)`, `stamina_max()`, `stamina_regen()`, `stamina_cost(action)`, `health_regen_per_tick()`, `crit_chance(skill)`, `skill_names()`, `background_refs()`, `name_context()`.
Writes: `add_xp(n, reason)`, `spend_attr(n)`, `spend_skill(n)`, `set_background(ref)`, `create_custom(spend, picks)`, `set_identity(name, sex)`, `set_penalty(attr, n)` / `clear_penalties()` (Survival; transient, not saved), `apply_death_penalty()`.
Events emitted: `xp_gained`, `level_up`, `stats_changed`. Listens to `enemy_killed(ref, danger, xp)`: XP is `round(round(danger*5)+5) * enemy.xpBonus`, zero when `level - danger > 4`; a non-zero `xp` argument overrides the amount (anti-farming still applies).

## Decisions and discrepancies

- `adjusted_skill = round(skill + attr*1.6 - 5)` is what the source does (`adjustedSkill`, DoAction.as ~13454). The analysis doc's sentence "an attribute of 5 adds nothing" is wrong: attribute 5 adds +3 (7 -> 10), attribute 10 adds +11 (7 -> 18). We follow the source.
- Max health at endurance 5, level 1 is 55 (20+25+10).
- Backgrounds: attributes from `pre.json`, plus `selectedSkillBonus` (+10) on each of its 4 skills. Free-spend: 10 points over base 5 (each attribute at most `attributeStartMax` = 10 at creation) and up to 4 skills chosen for the +10. **(verify)** that the original gives free-spend characters the +10 picks.
- XP resets to 0 on level-up (overflow discarded); levels cap at 30.
- Regen formulas use `adjusted_skill`; the doc says "survival/5" and "fitness" without saying raw or adjusted **(verify)**.
- Hunger penalty is applied by lowering the attribute (floor 1), so max health, stamina and skills all see it.

## Opening the screens

Each is a Control scene that builds its UI in code and talks only to `Stats`.

```
get_tree().change_scene_to_file("res://scenes/ui/character_create.tscn")   # signal confirmed
add_child(load("res://scenes/ui/level_up.tscn").instantiate())             # signal done
add_child(load("res://scenes/ui/skills_sheet.tscn").instantiate())         # signal closed
```

Character creation calls `Stats.set_background` / `create_custom` and `set_identity` on Confirm. Level-up should be opened by whoever listens to `Events.level_up` (the ui workstream).
