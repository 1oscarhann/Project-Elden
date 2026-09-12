class_name MoveData
extends Resource

## A single usable action (SPEC §5). Content is data: a new skill is a new
## .tres, never new code.

enum Target { ONE_ENEMY, ALL_ENEMIES, SELF, ONE_ALLY }
enum Effect { DAMAGE, HEAL, BUFF_ATK, BUFF_DEF }

@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""

## Must be one of TypeChart.TYPES.
@export var type: StringName = &"physical"
@export var effect: Effect = Effect.DAMAGE
@export var target: Target = Target.ONE_ENEMY

## Fed straight into Damage.calculate() as base_power, or used as the heal
## amount / buff percentage depending on `effect`.
@export var power: int = 0
@export var sp_cost: int = 0

## 0.0 - 1.0. Rolled before damage; a crit grants One More just like a
## weakness hit does (see BattleManager).
@export var crit_chance: float = 0.05


## True for a damage-dealing move — the kind BattleAction.skill() needs a
## target for, and the kind EnemyAI scores against the type chart.
func is_offensive() -> bool:
	return effect == Effect.DAMAGE


## True if this move can't currently be afforded.
func costs_more_sp_than(available: int) -> bool:
	return sp_cost > available
