class_name EnemyAI
extends RefCounted

## Picks an enemy's action each turn. Pulled out of BattleManager (SPEC §6)
## so the state machine stays about turn order, not target selection —
## and so this logic is testable without spinning up a battle.


## Chooses what `actor` does against the first alive `targets` entry it picks.
## `aggression` (0.0-1.0) is the actor's EnemyData.aggression: the chance it
## reaches for its best move instead of a plain Attack. Below that roll, or
## with no usable moves, it just attacks — playing to win means preferring
## whichever usable move scores highest against the chosen target's type,
## because the One More rule (Combat.ONE_MORE_ENABLED) means ignoring the
## type chart costs the AI a turn too.
static func choose_action(
	actor: Battler, targets: Array[Battler], aggression: float, rng: RandomNumberGenerator
) -> BattleAction:
	if targets.is_empty():
		return BattleAction.defend(actor)

	var target: Battler = targets[rng.randi() % targets.size()]
	var options: Array[MoveData] = actor.usable_moves()

	if options.is_empty() or rng.randf() > aggression:
		return BattleAction.attack(actor, target)

	var best: MoveData = options[0]
	var best_score: float = -1.0
	for move in options:
		if not move.is_offensive():
			continue
		var score: float = (
			float(move.power) * TypeChart.multiplier(move.type, target.data.defend_type)
		)
		if score > best_score:
			best_score = score
			best = move

	if best_score <= 0.0:
		return BattleAction.attack(actor, target)
	return BattleAction.skill(actor, target, best)
