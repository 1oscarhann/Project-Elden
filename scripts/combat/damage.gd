class_name Damage
extends RefCounted

## THE damage formula (SPEC §6). One function. Do not scatter this.
##
##     base * typeMultiplier * (atk / def) * variance
##
## Everything that wants a damage number calls calculate(). If a mechanic
## needs to change damage, it changes the inputs to this call or it gets a
## named modifier here — it does not do its own arithmetic somewhere else.

const VARIANCE_MIN := 0.95
const VARIANCE_MAX := 1.05

## Multiplier applied to the defender's effective defence while Defending.
const DEFEND_MULTIPLIER := 2.0


class Result extends RefCounted:
	var amount: int
	var multiplier: float
	var hit_weakness: bool
	var was_immune: bool


static func calculate(
	base_power: int,
	attack_type: StringName,
	defend_type: StringName,
	attacker_atk: int,
	defender_def: int,
	is_defending: bool = false,
	rng: RandomNumberGenerator = null,
) -> Result:
	var result := Result.new()
	result.multiplier = TypeChart.multiplier(attack_type, defend_type)
	result.hit_weakness = result.multiplier > TypeChart.NEUTRAL
	result.was_immune = is_zero_approx(result.multiplier)

	if result.was_immune:
		result.amount = 0
		return result

	var effective_def: float = maxf(1.0, float(defender_def))
	if is_defending:
		effective_def *= DEFEND_MULTIPLIER

	var variance := 1.0
	if rng != null:
		variance = rng.randf_range(VARIANCE_MIN, VARIANCE_MAX)

	var raw: float = (
		float(base_power)
		* result.multiplier
		* (float(attacker_atk) / effective_def)
		* variance
	)

	# A connecting hit always does something, so weakness-scouting never reads
	# as a whiff against a high-defence enemy.
	result.amount = maxi(1, int(roundi(raw)))
	return result
