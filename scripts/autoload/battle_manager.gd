extends Node

## Autoload. Owns the combat state machine (SPEC §6):
##   PlayerTurn -> EnemyTurn -> CheckWin/Loss -> loop
##
## Signal-driven. Nothing in here polls from _process().
##
## Open design question before this is written: does hitting a weakness grant
## an extra action (Persona press-turn) or only a damage multiplier (Pokemon)?
## See docs/REVIEW.md — it changes the shape of this state machine, so decide
## it before build order step 3.

signal battle_started(encounter_id: StringName)
signal battle_finished(player_won: bool)
signal turn_changed(actor)


func start_battle(_encounter_id: StringName) -> void:
	push_error("BattleManager.start_battle() not implemented (build order step 2)")
