extends Node
## Autoload "Events": the game's signal bus. Systems emit and listen here
## instead of calling each other, so a workstream can change without breaking
## the others. Add a signal when a second system needs to react to something;
## keep names past tense. Do not remove or rename a signal without checking
## every listener (grep for "Events.<name>").

# Combat
signal enemy_killed(enemy_ref: String, danger: int, xp: int)
signal player_damaged(amount: float, source: Node)
signal player_died()
signal shot_fired(weapon_ref: String, noise: float, position: Vector3)

# Progression
signal xp_gained(amount: int, reason: String)
signal level_up(new_level: int)
signal stats_changed()

# Items
signal item_used(item_name: String)
signal container_searched(container_id: String)

# World and time
signal location_entered(location_id: String)
signal minute_passed(game_minute: int)
signal hour_changed(hour: int)
signal rush_started()
signal rush_ended()

# Story
signal quest_changed(quest_id: String, state: String)
signal dialogue_started(npc_id: String)
signal dialogue_ended(npc_id: String)
signal trigger_fired(trigger_id: String)

# Run lifecycle
signal run_started()
signal run_reset()
