class_name BattlerData
extends Resource

## Shared stat block for anything that can fight — party members and enemies
## both. Enemies add rewards on top (see EnemyData).

@export var id: StringName = &""
@export var display_name: String = ""
@export var level: int = 1

@export_group("Stats")
@export var max_hp: int = 30
@export var max_sp: int = 10
@export var attack: int = 10
@export var defense: int = 10
@export var speed: int = 10

@export_group("Affinity")
## The type this battler is hit AS. The type chart is read as
## attacker_move_type vs this.
@export var defend_type: StringName = &"physical"

@export_group("Moves")
@export var moves: Array[MoveData] = []
