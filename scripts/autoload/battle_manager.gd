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


## Starts a fresh fight: builds a Battler for each party member and foe, then
## kicks off round 1. Emits battle_started, then either awaiting_action (the
## player moves first) or battle_finished if the fight somehow starts already
## decided.
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
	_queue = BattlerGroup.alive(player_party)
	_next_in_queue()


func _begin_enemy_phase() -> void:
	phase = Combat.Phase.ENEMY
	_queue = BattlerGroup.alive(enemies)
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
		target = BattlerGroup.random_alive(
			enemies if action.actor.is_player_side else player_party, _rng
		)
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
	action_resolved.emit(BattleLog.describe_attack(action, target, result))
	return result.grants_one_more()


func _resolve_item(action: BattleAction) -> void:
	var item: ItemData = action.item
	if item == null:
		return
	var target: Battler = action.target if action.target != null else action.actor

	var amount: int = 0
	match item.effect:
		ItemData.Effect.HEAL_HP:
			amount = target.heal(item.amount)
		ItemData.Effect.HEAL_SP:
			amount = target.restore_sp(item.amount)

	action_resolved.emit(BattleLog.describe_item(action, item, target, amount))

	if action.actor.is_player_side:
		GameState.consume_item(item.id)


func _try_flee(actor: Battler) -> bool:
	if BattlerGroup.has_boss(enemies):
		action_resolved.emit("You can't run from this.")
		return false

	var foes: Array[Battler] = BattlerGroup.alive(enemies if actor.is_player_side else player_party)
	var fastest: int = 1
	for f in foes:
		fastest = maxi(fastest, f.data.speed)
	var chance: float = Combat.flee_chance(actor.data.speed, fastest)

	if _rng.randf() < chance:
		action_resolved.emit("%s fled." % actor.display_name())
		_finish(Combat.Outcome.FLED)
		return true

	action_resolved.emit("%s couldn't get away." % actor.display_name())
	return false


## Default aggression for a non-enemy Battler (never actually reached in
## play — only EnemyData battlers act during the enemy phase — kept as a
## sane fallback rather than an assumption EnemyAI has to make).
const _DEFAULT_AGGRESSION := 0.7


func _choose_enemy_action(actor: Battler) -> BattleAction:
	var aggression: float = _DEFAULT_AGGRESSION
	if actor.data is EnemyData:
		aggression = (actor.data as EnemyData).aggression
	return EnemyAI.choose_action(actor, BattlerGroup.alive(player_party), aggression, _rng)


func _check_end() -> bool:
	if phase == Combat.Phase.FINISHED:
		return true
	if BattlerGroup.alive(enemies).is_empty():
		_finish(Combat.Outcome.VICTORY)
		return true
	if BattlerGroup.alive(player_party).is_empty():
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


# --- Encounter hand-off (SPEC §9 step 2) ------------------------------------
#
# World.tscn queues the foes, then swaps scenes. Battle.tscn reads them back on
# _ready. This is the only state that crosses the scene boundary, and it's
# deliberately not in GameState because it is never saved.

var pending_encounter: Array[EnemyData] = []


## Called by World.tscn right before it swaps to Battle.tscn.
func queue_encounter(foes: Array[EnemyData]) -> void:
	pending_encounter = foes.duplicate()


## Called by Battle.tscn on _ready(). Clears the queue so a stray re-read
## (or a second Battle.tscn instance) can't fight the same foes twice.
func take_pending_encounter() -> Array[EnemyData]:
	var foes: Array[EnemyData] = pending_encounter.duplicate()
	pending_encounter.clear()
	return foes
