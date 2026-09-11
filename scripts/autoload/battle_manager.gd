extends Node

## Autoload. Owns the combat state machine (SPEC §6):
##
##     RoundStart -> PlayerPhase -> EnemyPhase -> CheckEnd -> loop
##
## Signal-driven. Nothing in here polls from _process().
##
## DECIDED (was an open question in the spec review): hitting a weakness grants
## an extra action. See Combat.ONE_MORE_ENABLED.

signal battle_started(enemies: Array)
signal battle_finished(outcome: Combat.Outcome, rewards: Dictionary)
signal round_started(round_number: int)
signal awaiting_action(actor: Battler)
signal action_resolved(log_line: String)
signal one_more_granted(actor: Battler)
signal battler_died(who: Battler)

## Seconds to pause between resolved actions so the player can read them.
## Set to 0.0 in headless tests to run a whole fight instantly.
var turn_delay: float = 0.45

var phase: Combat.Phase = Combat.Phase.IDLE
var round_number: int = 0
var player_party: Array[Battler] = []
var enemies: Array[Battler] = []

var _rng := RandomNumberGenerator.new()
var _queue: Array[Battler] = []
var _current_actor: Battler = null


func _ready() -> void:
	_rng.randomize()


## Deterministic fights for tests and for reproducible bug reports.
func set_seed(seed_value: int) -> void:
	_rng.seed = seed_value


func start_battle(party: Array[BattlerData], foes: Array[EnemyData]) -> void:
	player_party.clear()
	enemies.clear()

	for member in party:
		player_party.append(Battler.new(member, true))
	for foe in foes:
		var b := Battler.new(foe, false)
		b.died.connect(_on_battler_died.bind(b))
		enemies.append(b)
	for b in player_party:
		b.died.connect(_on_battler_died.bind(b))

	phase = Combat.Phase.ROUND_START
	round_number = 0
	battle_started.emit(enemies)
	_begin_round()


func _begin_round() -> void:
	round_number += 1
	for b in _all_battlers():
		b.begin_round()
	round_started.emit(round_number)
	_begin_player_phase()


func _begin_player_phase() -> void:
	phase = Combat.Phase.PLAYER
	_queue = _alive(player_party)
	_next_in_queue()


func _begin_enemy_phase() -> void:
	phase = Combat.Phase.ENEMY
	_queue = _alive(enemies)
	_next_in_queue()


func _next_in_queue() -> void:
	# Drop anyone who died since the queue was built.
	while not _queue.is_empty() and not _queue[0].is_alive():
		_queue.pop_front()

	if _queue.is_empty():
		_advance_phase()
		return

	_current_actor = _queue[0]
	if phase == Combat.Phase.PLAYER:
		awaiting_action.emit(_current_actor)
	else:
		_resolve(_choose_enemy_action(_current_actor))


func _advance_phase() -> void:
	if _check_end():
		return
	if phase == Combat.Phase.PLAYER:
		_begin_enemy_phase()
	else:
		_begin_round()


## Called by the UI once the player has chosen. Ignored unless we're actually
## waiting on this actor, so a double-click can't queue two actions.
func submit_action(action: BattleAction) -> void:
	if phase != Combat.Phase.PLAYER or action.actor != _current_actor:
		return
	_resolve(action)


func _resolve(action: BattleAction) -> void:
	var grants_one_more: bool = false

	match action.kind:
		BattleAction.Kind.ATTACK, BattleAction.Kind.SKILL:
			grants_one_more = _resolve_offensive(action)
		BattleAction.Kind.ITEM:
			_resolve_item(action)
		BattleAction.Kind.DEFEND:
			action.actor.is_defending = true
			action_resolved.emit("%s defends." % action.actor.display_name())
		BattleAction.Kind.FLEE:
			if _try_flee(action.actor):
				return

	if _check_end():
		return

	await _pause()

	# One More: the actor goes again instead of passing the turn on. Capped at
	# once per round per actor so a lucky streak can't lock the other side out.
	if Combat.ONE_MORE_ENABLED and grants_one_more and not action.actor.used_one_more:
		action.actor.used_one_more = true
		one_more_granted.emit(action.actor)
		action_resolved.emit("%s gets ONE MORE!" % action.actor.display_name())
		if phase == Combat.Phase.PLAYER:
			awaiting_action.emit(action.actor)
		else:
			_resolve(_choose_enemy_action(action.actor))
		return

	_queue.pop_front()
	_next_in_queue()


func _resolve_offensive(action: BattleAction) -> bool:
	var target: Battler = action.target
	if target == null or not target.is_alive():
		target = _random_living_foe(action.actor)
	if target == null:
		return false

	var result: Damage.Result
	if action.kind == BattleAction.Kind.SKILL and action.move != null:
		if not action.actor.spend_sp(action.move.sp_cost):
			action_resolved.emit("%s doesn't have the SP." % action.actor.display_name())
			return false
		result = Damage.calculate(
			action.move.power,
			action.move.type,
			action.actor,
			target,
			action.move.crit_chance,
			_rng
		)
	else:
		result = Damage.basic_attack(action.actor, target, _rng)

	target.take_damage(result.amount)
	action_resolved.emit(_describe(action, target, result))
	return result.grants_one_more()


func _resolve_item(action: BattleAction) -> void:
	var item: ItemData = action.item
	if item == null:
		return
	var target: Battler = action.target if action.target != null else action.actor

	match item.effect:
		ItemData.Effect.HEAL_HP:
			var healed: int = target.heal(item.amount)
			action_resolved.emit(
				"%s uses %s. %s recovers %d HP." % [
					action.actor.display_name(), item.display_name,
					target.display_name(), healed,
				]
			)
		ItemData.Effect.HEAL_SP:
			var restored: int = target.restore_sp(item.amount)
			action_resolved.emit(
				"%s uses %s. %s recovers %d SP." % [
					action.actor.display_name(), item.display_name,
					target.display_name(), restored,
				]
			)
		_:
			action_resolved.emit("%s uses %s." % [action.actor.display_name(), item.display_name])

	if action.actor.is_player_side:
		GameState.consume_item(item.id)


func _describe(action: BattleAction, target: Battler, result: Damage.Result) -> String:
	var verb: String = action.move.display_name if action.move != null else "Attack"
	if result.was_immune:
		return "%s uses %s. %s is unaffected." % [
			action.actor.display_name(), verb, target.display_name(),
		]

	var line: String = "%s uses %s. %s takes %d damage" % [
		action.actor.display_name(), verb, target.display_name(), result.amount,
	]
	if result.was_crit:
		line += " (CRITICAL)"
	elif result.hit_weakness:
		line += " (WEAK!)"
	elif result.was_resisted:
		line += " (resisted)"
	return line + "."


func _try_flee(actor: Battler) -> bool:
	var foes: Array[Battler] = _alive(enemies if actor.is_player_side else player_party)
	var fastest: int = 1
	for f in foes:
		fastest = maxi(fastest, f.data.speed)

	var chance: float = clampf(
		Combat.BASE_FLEE_CHANCE + (float(actor.data.speed - fastest) * 0.02), 0.05, 0.95
	)
	if _has_boss():
		action_resolved.emit("You can't run from this.")
		return false

	if _rng.randf() < chance:
		action_resolved.emit("%s fled." % actor.display_name())
		_finish(Combat.Outcome.FLED)
		return true

	action_resolved.emit("%s couldn't get away." % actor.display_name())
	return false


func _choose_enemy_action(actor: Battler) -> BattleAction:
	var targets: Array[Battler] = _alive(player_party)
	if targets.is_empty():
		return BattleAction.defend(actor)

	var target: Battler = targets[_rng.randi() % targets.size()]
	var options: Array[MoveData] = actor.usable_moves()

	var aggression: float = 0.7
	if actor.data is EnemyData:
		aggression = (actor.data as EnemyData).aggression

	if options.is_empty() or _rng.randf() > aggression:
		return BattleAction.attack(actor, target)

	# Play to win: prefer a move that hits this target's weakness, because the
	# One More rule means the AI gets punished for ignoring the type chart too.
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


func _check_end() -> bool:
	if phase == Combat.Phase.FINISHED:
		return true
	if _alive(enemies).is_empty():
		_finish(Combat.Outcome.VICTORY)
		return true
	if _alive(player_party).is_empty():
		_finish(Combat.Outcome.DEFEAT)
		return true
	return false


func _finish(outcome: Combat.Outcome) -> void:
	phase = Combat.Phase.FINISHED
	_queue.clear()
	_current_actor = null

	var rewards: Dictionary = {"xp": 0, "gold": 0}
	if outcome == Combat.Outcome.VICTORY:
		for foe in enemies:
			if foe.data is EnemyData:
				rewards["xp"] += (foe.data as EnemyData).xp_reward
				rewards["gold"] += (foe.data as EnemyData).gold_reward

	battle_finished.emit(outcome, rewards)


func _pause() -> void:
	if turn_delay <= 0.0 or not is_inside_tree():
		return
	await get_tree().create_timer(turn_delay).timeout


func _on_battler_died(who: Battler) -> void:
	battler_died.emit(who)
	action_resolved.emit("%s is down." % who.display_name())


func _all_battlers() -> Array[Battler]:
	var out: Array[Battler] = []
	out.append_array(player_party)
	out.append_array(enemies)
	return out


func _alive(group: Array[Battler]) -> Array[Battler]:
	var out: Array[Battler] = []
	for b in group:
		if b.is_alive():
			out.append(b)
	return out


func _random_living_foe(actor: Battler) -> Battler:
	var pool: Array[Battler] = _alive(enemies if actor.is_player_side else player_party)
	if pool.is_empty():
		return null
	return pool[_rng.randi() % pool.size()]


func _has_boss() -> bool:
	for foe in enemies:
		if foe.data is EnemyData and (foe.data as EnemyData).is_boss:
			return true
	return false


# --- Encounter hand-off (SPEC §9 step 2) ------------------------------------
#
# World.tscn queues the foes, then swaps scenes. Battle.tscn reads them back on
# _ready. This is the only state that crosses the scene boundary, and it's
# deliberately not in GameState because it is never saved.

var pending_encounter: Array[EnemyData] = []


func queue_encounter(foes: Array[EnemyData]) -> void:
	pending_encounter = foes.duplicate()


func take_pending_encounter() -> Array[EnemyData]:
	var foes: Array[EnemyData] = pending_encounter.duplicate()
	pending_encounter.clear()
	return foes
