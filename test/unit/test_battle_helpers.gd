extends GutTest

## Task 4 (code cleanup): battle_manager.gd was split into EnemyAI, BattleLog,
## BattlerGroup and Combat.flee_chance so each piece could be tested without
## spinning up a whole battle. This is that coverage — it also pins down that
## the extraction changed nothing observable.


func _battler(id: StringName, attack: int, defense: int, speed: int, is_player: bool) -> Battler:
	var data := BattlerData.new()
	data.id = id
	data.display_name = String(id)
	data.max_hp = 50
	data.max_sp = 20
	data.attack = attack
	data.defense = defense
	data.speed = speed
	return Battler.new(data, is_player)


# --- BattlerGroup ------------------------------------------------------------

func test_alive_filters_out_knocked_out_battlers():
	var a: Battler = _battler(&"a", 10, 10, 10, true)
	var b: Battler = _battler(&"b", 10, 10, 10, true)
	b.take_damage(9999)

	var alive: Array[Battler] = BattlerGroup.alive([a, b])
	assert_eq(alive.size(), 1, "only the living battler remains")
	assert_true(alive.has(a), "the living one is kept")


func test_alive_of_an_empty_group_is_empty():
	assert_eq(BattlerGroup.alive([]).size(), 0, "an empty group stays empty")


func test_random_alive_only_returns_living_members():
	var a: Battler = _battler(&"a", 10, 10, 10, true)
	var b: Battler = _battler(&"b", 10, 10, 10, true)
	b.take_damage(9999)

	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	for i in 20:
		assert_eq(BattlerGroup.random_alive([a, b], rng), a, "the dead one is never picked")


func test_random_alive_of_a_wiped_group_is_null():
	var a: Battler = _battler(&"a", 10, 10, 10, true)
	a.take_damage(9999)
	assert_null(
		BattlerGroup.random_alive([a], RandomNumberGenerator.new()),
		"a fully wiped group returns null, not a crash"
	)


func test_has_boss_finds_a_flagged_enemy():
	var boss_data := EnemyData.new()
	boss_data.id = &"boss"
	boss_data.is_boss = true
	var boss := Battler.new(boss_data, false)

	var trash_data := EnemyData.new()
	trash_data.id = &"trash"
	var trash := Battler.new(trash_data, false)

	assert_true(BattlerGroup.has_boss([trash, boss]), "the boss is found among trash")
	assert_false(BattlerGroup.has_boss([trash]), "no boss present, no boss found")


func test_has_boss_ignores_dead_status():
	# _try_flee checks the whole enemy roster, not just the living ones — a
	# boss you've already half-killed still blocks fleeing.
	var boss_data := EnemyData.new()
	boss_data.id = &"boss"
	boss_data.is_boss = true
	var boss := Battler.new(boss_data, false)
	boss.take_damage(9999)

	assert_true(BattlerGroup.has_boss([boss]), "a defeated boss still counts as present")


# --- Combat.flee_chance ------------------------------------------------------

func test_flee_chance_is_base_when_speeds_match():
	assert_almost_eq(
		Combat.flee_chance(10, 10), Combat.BASE_FLEE_CHANCE, 0.001,
		"equal speed gives the base chance"
	)


func test_flee_chance_improves_with_a_speed_advantage():
	assert_gt(
		Combat.flee_chance(20, 10), Combat.flee_chance(10, 10),
		"being faster than the fastest foe improves the odds"
	)


func test_flee_chance_worsens_with_a_speed_disadvantage():
	assert_lt(
		Combat.flee_chance(5, 10), Combat.flee_chance(10, 10),
		"being slower than the fastest foe worsens the odds"
	)


func test_flee_chance_stays_within_its_declared_bounds():
	assert_eq(
		Combat.flee_chance(-9999, 9999), Combat.FLEE_CHANCE_MIN,
		"an extreme disadvantage clamps to the floor"
	)
	assert_eq(
		Combat.flee_chance(9999, -9999), Combat.FLEE_CHANCE_MAX,
		"an extreme advantage clamps to the ceiling"
	)


# --- EnemyAI ------------------------------------------------------------------

func test_choose_action_with_no_targets_defends():
	var actor: Battler = _battler(&"e", 10, 10, 10, false)
	var action: BattleAction = EnemyAI.choose_action(
		actor, [], 1.0, RandomNumberGenerator.new()
	)
	assert_eq(action.kind, BattleAction.Kind.DEFEND, "no living target means defend")


func test_choose_action_at_zero_aggression_always_attacks():
	var actor: Battler = _battler(&"e", 10, 10, 10, false)
	var move := MoveData.new()
	move.id = &"m"
	move.power = 50
	move.sp_cost = 0
	actor.data.moves = [move] as Array[MoveData]
	var target: Battler = _battler(&"p", 10, 10, 10, true)

	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 20:
		var action: BattleAction = EnemyAI.choose_action(actor, [target], 0.0, rng)
		assert_eq(action.kind, BattleAction.Kind.ATTACK, "zero aggression never picks a skill")


func test_choose_action_at_full_aggression_prefers_the_weakness():
	var actor: Battler = _battler(&"e", 10, 10, 10, false)
	var weak_move := MoveData.new()
	weak_move.id = &"fire"
	weak_move.type = &"fire"
	weak_move.power = 20
	weak_move.effect = MoveData.Effect.DAMAGE
	var dud_move := MoveData.new()
	dud_move.id = &"weak_physical"
	dud_move.type = &"physical"
	dud_move.power = 20
	dud_move.effect = MoveData.Effect.DAMAGE
	actor.data.moves = [dud_move, weak_move] as Array[MoveData]

	var target: Battler = _battler(&"p", 10, 10, 10, true)
	target.data.defend_type = &"ice"  # fire is a declared weakness of ice

	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var action: BattleAction = EnemyAI.choose_action(actor, [target], 1.0, rng)
	assert_eq(action.kind, BattleAction.Kind.SKILL, "full aggression reaches for a skill")
	assert_eq(action.move.id, &"fire", "and picks the one that hits the weakness")


func test_choose_action_never_selects_an_unaffordable_move():
	var actor: Battler = _battler(&"e", 10, 10, 10, false)
	var expensive := MoveData.new()
	expensive.id = &"expensive"
	expensive.power = 999
	expensive.sp_cost = 999
	actor.data.moves = [expensive] as Array[MoveData]
	actor.sp = 0

	var target: Battler = _battler(&"p", 10, 10, 10, true)
	var action: BattleAction = EnemyAI.choose_action(
		actor, [target], 1.0, RandomNumberGenerator.new()
	)
	assert_eq(action.kind, BattleAction.Kind.ATTACK, "an unaffordable move falls back to Attack")


# --- BattleLog ----------------------------------------------------------------

func test_describe_attack_reports_weakness_and_amount():
	var attacker: Battler = _battler(&"a", 10, 10, 10, true)
	var target: Battler = _battler(&"t", 10, 10, 10, false)
	var action := BattleAction.attack(attacker, target)

	var result := Damage.Result.new()
	result.amount = 42
	result.hit_weakness = true

	var line: String = BattleLog.describe_attack(action, target, result)
	assert_true(line.contains("42"), "the damage amount is reported")
	assert_true(line.contains("WEAK"), "a weakness hit is called out")


func test_describe_attack_reports_immunity_without_a_damage_number():
	var attacker: Battler = _battler(&"a", 10, 10, 10, true)
	var target: Battler = _battler(&"t", 10, 10, 10, false)
	var action := BattleAction.attack(attacker, target)

	var result := Damage.Result.new()
	result.amount = 0
	result.was_immune = true

	var line: String = BattleLog.describe_attack(action, target, result)
	assert_true(line.contains("unaffected"), "immunity reads as unaffected, not 0 damage")


func test_describe_item_reports_heal_amount():
	var actor: Battler = _battler(&"a", 10, 10, 10, true)
	var item := ItemData.new()
	item.display_name = "Potion"
	item.effect = ItemData.Effect.HEAL_HP
	var action := BattleAction.use_item(actor, actor, item)

	var line: String = BattleLog.describe_item(action, item, actor, 25)
	assert_true(line.contains("25"), "the healed amount is reported")
	assert_true(line.contains("HP"), "hp healing says HP, not SP")
