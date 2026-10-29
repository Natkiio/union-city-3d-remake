# combat  —  Done (first pass)
Branch: feat/combat
Done: CombatRules (spread, miss, zones, armor, crit, knockback, melee, shove, perm health, stamina), CombatActions (take_damage compat, zones, kill report), bullets with wall stop/splash, all weapon types fire, shot_fired noise, player vitals + stamina + crouch, death via GameState.reset_run, docs/combat.md
Doing: -
Blocked: (1) hud.gd reads player.MAX_HEALTH (const 55 fallback); should read player.max_health. (2) Input actions for run/crouch (keys read directly: Shift, C). (3) zombie.gd needs take_damage(amount, zone, source, knockback) + enemy_ref/danger_level/xp_value()/armor to get kill XP and zone armor.
Next: wire Stats.add_xp on enemy_killed (progression/lead), melee miss, bullet tunnelling for thin walls
Tests: tests/test_combat.gd  76 pass / 0 fail
