class_name BossGate
extends Area3D

## One-shot boss trigger (SPEC §3: the slice needs a boss). Fires once, then
## records a flag so a cleared gate stays cleared across saves.

signal encounter_triggered(foes: Array)

@export var table: EncounterTable
@export var cleared_flag: StringName = &"zone_01_boss_cleared"


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if not body is PlayerController:
		return
	if table == null or table.boss == null:
		return
	if GameState.get_flag(cleared_flag, false):
		return
	# Set before the fight so a defeat-and-reload doesn't re-trigger on the way
	# back in; clearing the flag is the boss's reward, not its precondition.
	GameState.set_flag(cleared_flag, true)
	encounter_triggered.emit([table.boss] as Array)
