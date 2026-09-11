extends GutTest

## Pillar 2 (SPEC §2): content is data. These assert the loader actually picks
## files up, and that the slice's content is internally consistent.


func before_all():
	ContentDB.reload()


func test_every_content_directory_loads():
	assert_not_null(ContentDB.move(&"ember"), "moves load from data/moves")
	assert_not_null(ContentDB.item(&"potion"), "items load from data/items")
	assert_not_null(ContentDB.enemy(&"frostbit"), "enemies load from data/enemies")
	assert_not_null(ContentDB.party_member(&"hero"), "party loads from data/party")
	assert_not_null(ContentDB.encounter_table(&"zone_01"), "tables load from data/encounters")


func test_an_unknown_id_returns_null_rather_than_crashing():
	assert_null(ContentDB.move(&"no_such_move"), "an unknown move id is null")
	assert_null(ContentDB.enemy(&"no_such_enemy"), "an unknown enemy id is null")
	assert_null(ContentDB.item(&"no_such_item"), "an unknown item id is null")
	assert_null(ContentDB.party_member(&"no_such_member"), "an unknown member id is null")


func test_party_members_are_copied_not_shared():
	# Two loads must not hand back the same mutable object, or levelling one
	# save would level every save.
	var a: PartyMemberData = ContentDB.party_member(&"hero")
	var b: PartyMemberData = ContentDB.party_member(&"hero")
	assert_ne(a, b, "each call returns its own copy")

	a.level = 42
	assert_ne(b.level, 42, "mutating one copy does not touch the other")


func test_the_slice_has_the_content_the_spec_promises():
	assert_gte(ContentDB.all_enemies().size(), 4, "3 trash enemies + 1 boss")
	assert_gte(ContentDB.all_items().size(), 2, "at least two items")


func test_exactly_one_boss_is_defined():
	var bosses := []
	for enemy in ContentDB.all_enemies():
		if enemy.is_boss:
			bosses.append(enemy.id)
	assert_eq(bosses.size(), 1, "the slice has one boss, got %s" % [bosses])


func test_every_enemy_is_internally_valid():
	for enemy in ContentDB.all_enemies():
		assert_ne(enemy.display_name, "", "%s has a display name" % enemy.id)
		assert_gt(enemy.max_hp, 0, "%s has positive hp" % enemy.id)
		assert_gt(enemy.attack, 0, "%s has positive attack" % enemy.id)
		assert_gt(enemy.defense, 0, "%s has positive defense" % enemy.id)
		assert_gte(enemy.xp_reward, 0, "%s pays non-negative xp" % enemy.id)
		assert_gte(enemy.gold_reward, 0, "%s pays non-negative gold" % enemy.id)
		assert_true(
			enemy.defend_type in TypeChart.TYPES,
			"%s defends as a declared type (%s)" % [enemy.id, enemy.defend_type]
		)
		for move in enemy.moves:
			assert_not_null(move, "%s has no null moves" % enemy.id)


func test_every_move_is_internally_valid():
	for id in ["ember", "frost", "gale", "jolt", "radiance", "cleave", "ruin", "crush"]:
		var move: MoveData = ContentDB.move(StringName(id))
		assert_not_null(move, "%s exists" % id)
		if move == null:
			continue
		assert_ne(move.display_name, "", "%s has a display name" % id)
		assert_gt(move.power, 0, "%s has positive power" % id)
		assert_gte(move.sp_cost, 0, "%s has a non-negative sp cost" % id)
		assert_true(move.type in TypeChart.TYPES, "%s uses a declared type" % id)


func test_every_enemy_is_beatable_by_some_declared_type():
	# An enemy immune or resistant to everything would be a soft lock.
	for enemy in ContentDB.all_enemies():
		var best: float = 0.0
		for attack_type in TypeChart.TYPES:
			best = maxf(best, TypeChart.multiplier(attack_type, enemy.defend_type))
		assert_gte(best, TypeChart.NEUTRAL, "%s can be hit at full damage by something" % enemy.id)


func test_the_boss_is_weak_to_something_reachable():
	var warden: EnemyData = ContentDB.enemy(&"warden")
	assert_true(warden.is_boss, "the warden is flagged as a boss")

	var hero: PartyMemberData = ContentDB.party_member(&"hero")
	var answers := []
	for move in hero.learnset.values():
		if move != null and move.is_offensive() \
				and TypeChart.is_weakness(move.type, warden.defend_type):
			answers.append(move.id)
	assert_gt(answers.size(), 0, "the hero's learnset contains an answer to the boss")


func test_the_encounter_table_is_consistent():
	var table: EncounterTable = ContentDB.encounter_table(&"zone_01")
	assert_gt(table.encounters.size(), 0, "the table has entries")
	assert_eq(table.weights.size(), table.encounters.size(), "weights line up with entries")
	assert_gt(table.steps_per_encounter, 0, "the encounter distance is positive")
	assert_not_null(table.boss, "the zone declares a boss")
	for entry in table.encounters:
		assert_false(entry.is_boss, "the boss is not in the random pool")


func test_the_encounter_table_rolls_every_entry_at_a_sane_rate():
	var table: EncounterTable = ContentDB.encounter_table(&"zone_01")
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345

	var counts := {}
	for i in 600:
		var foe: EnemyData = table.pick(rng)
		counts[foe.id] = int(counts.get(foe.id, 0)) + 1

	assert_eq(counts.size(), table.encounters.size(), "every entry can be rolled")
	for id in counts:
		assert_gt(counts[id], 30, "%s is rolled at a sane rate" % id)


func test_an_empty_table_picks_nothing_instead_of_crashing():
	var table := EncounterTable.new()
	assert_null(table.pick(RandomNumberGenerator.new()), "an empty table returns null")
