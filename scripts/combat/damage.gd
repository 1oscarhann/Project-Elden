class_name Damage
extends RefCounted

## THE damage formula (SPEC §6). One function. Do not scatter this.
##
##     base * typeMultiplier * (atk / def) * crit * variance
##
## Everything that wants a damage number calls calculate(). If a mechanic needs
## to change damage it changes the inputs, or it gets a named modifier in here.
## It does not do its own arithmetic somewhere else.

const VARIANCE_MIN := 0.95
const VARIANCE_MAX := 1.05

## Multiplier applied to the defender's effective defence while Defending.
const DEFEND_MULTIPLIER := 2.0
const CRIT_MULTIPLIER := 1.5

## The basic Attack action's power when no move is involved.
const BASIC_ATTACK_POWER := 20
const BASIC_ATTACK_TYPE := &"physical"


class Result extends RefCounted:
	var amount: int = 0
	var type_multiplier: float = 1.0
	var hit_weakness: bool = false
	var was_resisted: bool = false
	var was_immune: bool = false
	var was_crit: bool = false

	## The single thing the turn economy keys off (SPEC §6). Weakness or crit
	## earns the attacker another action.
	func grants_one_more() -> bool:
		return hit_weakness or was_crit


static func calculate(
	base_power: int,
	attack_type: StringName,
	attacker: Battler,
	defender: Battler,
	crit_chance: float = 0.0,
	rng: RandomNumberGenerator = null,
) -> Result:
	var result := Result.new()
	result.type_multiplier = TypeChart.multiplier(attack_type, defender.data.defend_type)
	result.hit_weakness = result.type_multiplier > TypeChart.NEUTRAL
	result.was_resisted = (
		result.type_multiplier < TypeChart.NEUTRAL and not is_zero_approx(result.type_multiplier)
	)
	result.was_immune = is_zero_approx(result.type_multiplier)

	if result.was_immune:
		return result

	if rng != null and crit_chance > 0.0:
		result.was_crit = rng.randf() < crit_chance

	var effective_def: float = maxf(1.0, float(defender.data.defense))
	if defender.is_defending:
		effective_def *= DEFEND_MULTIPLIER

	var variance: float = 1.0
	if rng != null:
		variance = rng.randf_range(VARIANCE_MIN, VARIANCE_MAX)

	var raw: float = (
		float(base_power)
		* result.type_multiplier
		* (float(attacker.data.attack) / effective_def)
		* (CRIT_MULTIPLIER if result.was_crit else 1.0)
		* variance
	)

	# A connecting hit always does something, so scouting a weakness never
	# reads as a whiff against a high-defence enemy.
	result.amount = maxi(1, roundi(raw))
	return result


## Convenience wrapper for the basic Attack action, which has no MoveData.
static func basic_attack(
	attacker: Battler, defender: Battler, rng: RandomNumberGenerator = null
) -> Result:
	return calculate(BASIC_ATTACK_POWER, BASIC_ATTACK_TYPE, attacker, defender, 0.05, rng)
