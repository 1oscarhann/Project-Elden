class_name EnemyData
extends BattlerData

## An enemy. Everything a fight needs, in one file (SPEC §5).

@export_group("Rewards")
@export var xp_reward: int = 10
@export var gold_reward: int = 5

@export_group("Presentation")
@export var is_boss: bool = false
## Tint used by the placeholder capsule until real models exist.
@export var placeholder_color: Color = Color(0.8, 0.3, 0.3)

@export_group("AI")
## 0.0 = always picks at random. 1.0 = always picks its best-damage move.
@export_range(0.0, 1.0) var aggression: float = 0.7
