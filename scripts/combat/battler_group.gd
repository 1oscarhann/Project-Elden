class_name BattlerGroup
extends RefCounted

## Pure queries over a side's Battler array (SPEC §6). Pulled out of
## BattleManager because "who's still standing" and "who's the boss" don't
## need the state machine's instance state to answer.


## The subset of `group` that hasn't been knocked out.
static func alive(group: Array[Battler]) -> Array[Battler]:
	var out: Array[Battler] = []
	for b in group:
		if b.is_alive():
			out.append(b)
	return out


## One random living member of `group`, or null if it's wiped.
static func random_alive(group: Array[Battler], rng: RandomNumberGenerator) -> Battler:
	var pool: Array[Battler] = alive(group)
	if pool.is_empty():
		return null
	return pool[rng.randi() % pool.size()]


## True if any living-or-not member of `group` is flagged as a boss. Bosses
## stay "present" for this check even after death mid-round, since the flee
## refusal reads on the group as fought, not the group as currently alive.
static func has_boss(group: Array[Battler]) -> bool:
	for b in group:
		if b.data is EnemyData and (b.data as EnemyData).is_boss:
			return true
	return false
