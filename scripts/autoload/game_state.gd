extends Node

## Autoload. The single source of truth for everything a save file contains
## (SPEC §5): party, inventory, gold, story flags, current zone.
##
## Rule: the overworld scene owns nothing durable. Player position and zone
## state are written here BEFORE swapping to Battle.tscn and read back after,
## because World.tscn is unloaded during combat.

signal gold_changed(new_amount: int)
signal flag_changed(flag: StringName, value: Variant)

var party: Array = []
var inventory: Dictionary = {}
var gold: int = 0
var story_flags: Dictionary = {}
var current_zone: StringName = &""
var player_position: Vector3 = Vector3.ZERO


func to_dict() -> Dictionary:
	# The exact shape that becomes save_slots.data (SPEC §7).
	push_error("GameState.to_dict() not implemented (build order step 5)")
	return {}


func from_dict(_data: Dictionary) -> void:
	push_error("GameState.from_dict() not implemented (build order step 5)")
