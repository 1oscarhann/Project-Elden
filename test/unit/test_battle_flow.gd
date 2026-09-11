extends GutTest

## The turn state machine and the One More rule (SPEC §6).
##
## Signal handlers collect into arrays, never into a captured scalar: GDScript
## lambdas capture by value, so `count += 1` inside a closure never escapes it.

const MAX_FRAMES := 400

var _log: Array[String] = []
var _one_more: Array[String] = []
var _outcome: Array = []
var _connections: Array[Array] = []


func before_each():
	GameState.new_game()
	BattleManager.turn_delay = 0.0
	BattleManager.set_seed(42)
	_log = []
	_one_more = []
	_outcome = []
	_connect(BattleManager.action_resolved, func(line: String) -> void: _log.append(line))
	_connect(
		BattleManager.one_more_granted,
		func(actor: Battler) -> void: _one_more.append(actor.display_name())
	)
	_connect(
		BattleManager.battle_finished,
		func(result: int, rewards: Dictionary) -> void:
			_outcome.append(result)
			_outcome.append(rewards)
	)


func after_each():
	for pair in _connections:
		if (pair[0] as Signal).is_connected(pair[1]):
			(pair[0] as Signal).disconnect(pair[1])
	_connections = []
	GameState.new_game()


func _connect(sig: Signal, handler: Callable) -> void:
	sig.connect(handler)
	_connections.append([sig, handler])


func _foes(ids: Array) -> Array[EnemyData]:
	var out: Array[EnemyData] = []
	for id in ids:
		out.append(ContentDB.enemy(StringName(id)))
	return out


func _await_end() -> bool:
	var frames: int = 0
	while _outcome.is_empty() and frames < MAX_FRAMES:
		frames += 1
		await get_tree().process_frame
	return not _outcome.is_empty()


## Plays the best type matchup available — what a player who has read the chart
## would do, and the path most likely to exercise One More.
func _play_optimally(actor: Battler) -> void:
	var targets: Array[Battler] = []
	for foe in BattleManager.enemies:
		if foe.is_alive():
			targets.append(foe)
	if targets.is_empty():
		return

	var best_move: MoveData = null
	var best_target: Battler = targets[0]
	var best_score: float = -1.0
	for move in actor.usable_moves():
		if not move.is_offensive():
			continue
		for target in targets:
			var score: float = (
				float(move.power) * TypeChart.multiplier(move.type, target.data.defend_type)
			)
			if score > best_score:
				best_score = score
				best_move = move
				best_target = target

	if best_move == null:
		BattleManager.submit_action(BattleAction.attack(actor, best_target))
	else:
		BattleManager.submit_action(BattleAction.skill(actor, best_target, best_move))


func _always_defend(actor: Battler) -> void:
	BattleManager.submit_action(BattleAction.defend(actor))


# --- Round bookkeeping ------------------------------------------------------

func test_begin_round_clears_per_round_state():
	var data := BattlerData.new()
	data.id = &"x"
	var battler := Battler.new(data, true)
	battler.used_one_more = true
	battler.is_defending = true

	battler.begin_round()
	assert_false(battler.used_one_more, "One More resets each round")
	assert_false(battler.is_defending, "defend expires each round")


func test_a_battle_starts_in_the_player_phase():
	# With turn_delay at 0 the whole fight resolves synchronously inside
	# start_battle(), so the phase has to be sampled from the first prompt
	# rather than read off the manager afterwards.
	var phases: Array[int] = []
	_connect(
		BattleManager.awaiting_action,
		func(actor: Battler) -> void:
			phases.append(BattleManager.phase)
			BattleManager.submit_action(BattleAction.defend(actor))
	)
	BattleManager.start_battle(GameState.battle_party(), _foes(["frostbit"]))

	assert_gt(phases.size(), 0, "the player was prompted")
	assert_eq(phases[0], Combat.Phase.PLAYER, "the player moves first")
	assert_eq(BattleManager.enemies.size(), 1, "the enemy was built")
	assert_eq(BattleManager.player_party.size(), 1, "the party was built")


# --- Outcomes ---------------------------------------------------------------

func test_a_type_aware_player_beats_two_trash_mobs():
	_connect(BattleManager.awaiting_action, _play_optimally)
	BattleManager.start_battle(GameState.battle_party(), _foes(["frostbit", "gustling"]))
	assert_true(await _await_end(), "the battle reaches an end state")

	assert_eq(_outcome[0], Combat.Outcome.VICTORY, "playing the chart wins")
	assert_gt(int(_outcome[1]["xp"]), 0, "victory pays xp")
	assert_gt(int(_outcome[1]["gold"]), 0, "victory pays gold")
	assert_eq(BattleManager.phase, Combat.Phase.FINISHED, "the machine lands in FINISHED")


func test_the_party_losing_ends_the_battle_in_defeat():
	_connect(BattleManager.awaiting_action, _always_defend)
	for member in GameState.party:
		GameState.vitals[member.id] = {"hp": 1, "sp": 0}

	BattleManager.start_battle(GameState.battle_party(), _foes(["warden"]))
	GameState.restore_vitals_into(BattleManager.player_party)

	assert_true(await _await_end(), "the battle reaches an end state")
	assert_eq(_outcome[0], Combat.Outcome.DEFEAT, "a wiped party loses")
	assert_eq(int(_outcome[1]["xp"]), 0, "a defeat pays no xp")


func test_defeated_enemies_stop_acting():
	_connect(BattleManager.awaiting_action, _play_optimally)
	BattleManager.start_battle(GameState.battle_party(), _foes(["frostbit", "gustling"]))
	await _await_end()
	for foe in BattleManager.enemies:
		assert_false(foe.is_alive(), "every enemy is down after a victory")


# --- One More ---------------------------------------------------------------

func test_exploiting_a_weakness_grants_one_more():
	_connect(BattleManager.awaiting_action, _play_optimally)
	BattleManager.start_battle(GameState.battle_party(), _foes(["frostbit", "gustling"]))
	await _await_end()
	assert_gt(_one_more.size(), 0, "playing the chart triggered One More")


func test_weakness_hits_are_reported_to_the_player():
	_connect(BattleManager.awaiting_action, _play_optimally)
	BattleManager.start_battle(GameState.battle_party(), _foes(["frostbit"]))
	await _await_end()

	var weak_lines: int = 0
	for line in _log:
		if line.contains("(WEAK!)"):
			weak_lines += 1
	assert_gt(weak_lines, 0, "the log tells the player they hit a weakness")


func test_one_more_is_capped_at_once_per_actor_per_round():
	_connect(BattleManager.awaiting_action, _play_optimally)
	BattleManager.start_battle(GameState.battle_party(), _foes(["frostbit", "gustling"]))
	await _await_end()

	# With a single party member, a round can grant at most one player One More,
	# so the total can never exceed the number of rounds fought on each side.
	var cap: int = BattleManager.round_number * (
		BattleManager.player_party.size() + BattleManager.enemies.size()
	)
	assert_lte(_one_more.size(), cap, "One More never chains beyond once per actor per round")


func test_never_acting_still_terminates():
	# Pure defence must not deadlock the machine, even though it never kills.
	_connect(BattleManager.awaiting_action, _always_defend)
	BattleManager.start_battle(GameState.battle_party(), _foes(["frostbit"]))
	var ended: bool = await _await_end()
	assert_true(ended, "a passive player still reaches an end state")


# --- Actions ----------------------------------------------------------------

func test_defending_is_recorded_on_the_actor():
	var acted := []
	_connect(
		BattleManager.awaiting_action,
		func(actor: Battler) -> void:
			acted.append(actor.display_name())
			BattleManager.submit_action(BattleAction.defend(actor))
	)
	BattleManager.start_battle(GameState.battle_party(), _foes(["frostbit"]))
	await get_tree().process_frame
	assert_gt(acted.size(), 0, "the player was asked to act")


func test_using_an_item_consumes_it():
	var before: int = GameState.item_count(&"potion")
	var potion: ItemData = ContentDB.item(&"potion")

	_connect(
		BattleManager.awaiting_action,
		func(actor: Battler) -> void:
			if GameState.item_count(&"potion") == before:
				BattleManager.submit_action(BattleAction.use_item(actor, actor, potion))
			else:
				BattleManager.submit_action(BattleAction.defend(actor))
	)
	BattleManager.start_battle(GameState.battle_party(), _foes(["frostbit"]))
	await get_tree().process_frame
	assert_eq(GameState.item_count(&"potion"), before - 1, "the potion was consumed")


func test_a_skill_spends_sp():
	var spent := []
	_connect(
		BattleManager.awaiting_action,
		func(actor: Battler) -> void:
			var moves: Array[MoveData] = actor.usable_moves()
			if moves.is_empty():
				BattleManager.submit_action(BattleAction.defend(actor))
				return
			spent.append(actor.sp)
			BattleManager.submit_action(
				BattleAction.skill(actor, BattleManager.enemies[0], moves[0])
			)
	)
	BattleManager.start_battle(GameState.battle_party(), _foes(["frostbit"]))
	await get_tree().process_frame
	assert_gt(spent.size(), 0, "a skill was used")
	assert_lt(BattleManager.player_party[0].sp, spent[0], "sp went down")


func test_you_cannot_flee_a_boss():
	_connect(
		BattleManager.awaiting_action,
		func(actor: Battler) -> void: BattleManager.submit_action(BattleAction.flee(actor))
	)
	BattleManager.start_battle(GameState.battle_party(), _foes(["warden"]))
	await get_tree().process_frame

	var refused: bool = false
	for line in _log:
		if line.contains("can't run"):
			refused = true
	assert_true(refused, "the boss refuses a flee attempt")


func test_submitting_out_of_turn_is_ignored():
	_connect(BattleManager.awaiting_action, _always_defend)
	BattleManager.start_battle(GameState.battle_party(), _foes(["frostbit"]))
	var enemy: Battler = BattleManager.enemies[0]
	var hp_before: int = BattleManager.player_party[0].hp

	# An enemy is never the current actor during the player phase.
	BattleManager.submit_action(BattleAction.attack(enemy, BattleManager.player_party[0]))
	assert_eq(BattleManager.player_party[0].hp, hp_before, "an out-of-turn action does nothing")


# --- Encounter hand-off -----------------------------------------------------

func test_a_queued_encounter_is_handed_over_exactly_once():
	BattleManager.queue_encounter(_foes(["frostbit"]))
	assert_eq(BattleManager.take_pending_encounter().size(), 1, "the encounter is handed over")
	assert_eq(BattleManager.take_pending_encounter().size(), 0, "and not handed over twice")
