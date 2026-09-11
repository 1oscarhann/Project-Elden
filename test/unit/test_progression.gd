extends GutTest

## XP -> level -> stat growth (SPEC §6).


func before_each():
	GameState.new_game()


func after_all():
	GameState.new_game()


func test_the_xp_curve_climbs_monotonically():
	var previous: int = 0
	for level in range(1, 30):
		var needed: int = GameState.xp_for_level(level)
		assert_gt(needed, previous, "level %d costs more than level %d" % [level, level - 1])
		previous = needed


func test_the_xp_curve_is_defined_at_the_edges():
	assert_gt(GameState.xp_for_level(1), 0, "level 1 has a positive cost")
	assert_gt(GameState.xp_for_level(0), 0, "level 0 is clamped, not zero or negative")
	assert_gt(GameState.xp_for_level(-5), 0, "a negative level is clamped")


func test_a_new_game_starts_at_level_one():
	assert_eq(GameState.party.size(), 1, "a new game has one party member")
	assert_eq(GameState.party[0].level, 1, "starting level is 1")


func test_xp_below_the_threshold_does_not_level():
	var member: PartyMemberData = GameState.party[0]
	GameState.award_xp(GameState.xp_for_level(1) - 1)
	assert_eq(member.level, 1, "one xp short of the threshold does not level")


func test_crossing_the_threshold_levels_exactly_once():
	var member: PartyMemberData = GameState.party[0]
	GameState.award_xp(GameState.xp_for_level(1))
	assert_eq(member.level, 2, "hitting the threshold levels once")


func test_stats_grow_by_the_declared_amounts():
	var member: PartyMemberData = GameState.party[0]
	var before := {
		"hp": member.max_hp, "sp": member.max_sp,
		"atk": member.attack, "def": member.defense, "spd": member.speed,
	}
	var growth := {
		"hp": member.hp_growth, "sp": member.sp_growth,
		"atk": member.attack_growth, "def": member.defense_growth, "spd": member.speed_growth,
	}
	GameState.award_xp(GameState.xp_for_level(1))

	assert_eq(member.max_hp, before["hp"] + growth["hp"], "max hp grows by hp_growth")
	assert_eq(member.max_sp, before["sp"] + growth["sp"], "max sp grows by sp_growth")
	assert_eq(member.attack, before["atk"] + growth["atk"], "attack grows by attack_growth")
	assert_eq(member.defense, before["def"] + growth["def"], "defense grows by defense_growth")
	assert_eq(member.speed, before["spd"] + growth["spd"], "speed grows by speed_growth")


func test_growth_is_linear_across_several_levels():
	var member: PartyMemberData = GameState.party[0]
	var start_hp: int = member.max_hp
	var growth: int = member.hp_growth
	for i in 4:
		GameState.award_xp(GameState.xp_for_level(member.level))
	assert_eq(member.level, 5, "four thresholds means level 5")
	assert_eq(member.max_hp, start_hp + growth * 4, "hp growth compounds linearly")


func test_a_huge_xp_award_does_not_overshoot_or_hang():
	var member: PartyMemberData = GameState.party[0]
	GameState.award_xp(100000)
	assert_gt(member.level, 5, "a big award levels several times")
	assert_lt(
		GameState.experience[member.id], GameState.xp_for_level(member.level),
		"leftover xp is below the next threshold, not banked past it"
	)


func test_levelling_up_restores_the_member():
	var member: PartyMemberData = GameState.party[0]
	GameState.vitals[member.id] = {"hp": 1, "sp": 0}
	GameState.award_xp(GameState.xp_for_level(1))
	assert_eq(GameState.vitals[member.id]["hp"], member.max_hp, "a level up refills hp")
	assert_eq(GameState.vitals[member.id]["sp"], member.max_sp, "a level up refills sp")


func test_the_learnset_grants_moves_at_its_thresholds():
	var member: PartyMemberData = GameState.party[0]
	var starting_moves: int = member.moves.size()
	assert_gt(member.learnset.size(), 0, "the hero has a learnset at all")

	GameState.award_xp(100000)
	assert_gt(member.moves.size(), starting_moves, "levelling teaches new moves")


func test_the_boss_key_move_is_learned_by_levelling():
	# The Warden is only weak to light, so a light move must be reachable
	# through progression rather than through shopping.
	GameState.award_xp(100000)
	var member: PartyMemberData = GameState.party[0]
	var warden: EnemyData = ContentDB.enemy(&"warden")

	var has_answer: bool = false
	for move in member.moves:
		if move.is_offensive() and TypeChart.is_weakness(move.type, warden.defend_type):
			has_answer = true
	assert_true(has_answer, "levelling teaches a move the boss is weak to")


func test_a_move_is_never_learned_twice():
	GameState.award_xp(100000)
	var member: PartyMemberData = GameState.party[0]
	var seen := {}
	for move in member.moves:
		assert_false(seen.has(move.id), "move %s appears once" % move.id)
		seen[move.id] = true


func test_gold_never_goes_negative():
	GameState.add_gold(-999999)
	assert_eq(GameState.gold, 0, "gold is floored at zero")
