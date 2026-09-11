class_name ItemData
extends Resource

## A consumable. Items are the one action that costs no SP, so they're the
## fallback when a fight goes badly.

enum Effect { HEAL_HP, HEAL_SP, REVIVE, CURE_ALL }

@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var effect: Effect = Effect.HEAL_HP
@export var amount: int = 20
@export var price: int = 50
