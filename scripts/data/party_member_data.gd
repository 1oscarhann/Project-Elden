class_name PartyMemberData
extends BattlerData

## A playable character. Growth is linear per level — deliberately dumb, and
## easy to retune once the slice proves the fight is fun (SPEC §6).

@export_group("Growth per level")
@export var hp_growth: int = 6
@export var sp_growth: int = 3
@export var attack_growth: int = 2
@export var defense_growth: int = 2
@export var speed_growth: int = 1

@export_group("Learnset")
## Level -> MoveData. Learned on reaching that level.
@export var learnset: Dictionary = {}
