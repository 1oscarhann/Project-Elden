extends GutTest

## Task 3: save/load hardening. test_save_round_trip.gd already covers the
## field-by-field round trip; this file targets specific edge cases and the
## two defects iteration 1 and this iteration found:
##   - slot_summary() returning floats instead of ints
##   - _level_up() firing party_member_leveled once per level during a load

const TEST_SLOT := 9


func before_each():
	GameState.new_game()


func after_each():
	SaveManager.delete_local(TEST_SLOT)


func after_all():
	GameState.new_game()


# --- Regression: slot_summary() type coercion -------------------------------

func test_slot_summary_returns_ints_not_floats():
	GameState.add_gold(931)
	GameState.award_xp(100000)
	SaveManager.save_local(TEST_SLOT)

	var summary: Dictionary = SaveManager.slot_summary(TEST_SLOT)
	assert_typeof(summary.get("gold"), TYPE_INT, "gold is an int, not a float")
	assert_typeof(summary.get("level"), TYPE_INT, "level is an int, not a float")
	assert_typeof(summary.get("zone"), TYPE_STRING, "zone is a String")
	assert_eq(summary.get("gold"), 150 + 931, "the gold value itself is still correct")


func test_slot_summary_of_a_missing_slot_is_empty():
	assert_eq(SaveManager.slot_summary(TEST_SLOT), {}, "a missing slot summarises to nothing")


func test_slot_summary_survives_a_corrupt_party_array():
	# A save with an empty party (e.g. hand-edited, or from a future format
	# change) must not crash the summary reader.
	var blob: Dictionary = GameState.to_dict()
	blob["party"] = []
	var file := FileAccess.open(SaveManager.slot_path(TEST_SLOT), FileAccess.WRITE)
	file.store_string(JSON.stringify(blob))
	file.close()

	var summary: Dictionary = SaveManager.slot_summary(TEST_SLOT)
	assert_eq(summary.get("level"), 1, "an empty party falls back to level 1, not a crash")


# --- Regression: silent level replay on load --------------------------------

func test_loading_a_save_does_not_fire_level_up_signals():
	GameState.award_xp(100000)
	var target_level: int = GameState.party[0].level
	assert_gt(target_level, 1, "sanity: the setup actually leveled the character")
	SaveManager.save_local(TEST_SLOT)

	GameState.new_game()
	var events: Array = []
	var handler := func(member, new_level, learned) -> void:
		events.append(new_level)
	GameState.party_member_leveled.connect(handler)

	SaveManager.load_local(TEST_SLOT)
	GameState.party_member_leveled.disconnect(handler)

	assert_eq(events.size(), 0, "loading a leveled save fires no level-up signals")
	assert_eq(GameState.party[0].level, target_level, "the level itself is still restored")


func test_real_level_ups_still_announce():
	# The fix must not silence award_xp()'s own level-ups, only the replay
	# path inside from_dict().
	var events: Array = []
	var handler := func(member, new_level, learned) -> void:
		events.append(new_level)
	GameState.party_member_leveled.connect(handler)

	GameState.award_xp(GameState.xp_for_level(1))
	GameState.party_member_leveled.disconnect(handler)

	assert_eq(events.size(), 1, "a real level-up during play still announces")


# --- Empty inventory ---------------------------------------------------------

func test_an_empty_inventory_round_trips():
	GameState.consume_item(&"potion", GameState.item_count(&"potion"))
	GameState.consume_item(&"ether", GameState.item_count(&"ether"))
	assert_eq(GameState.inventory.size(), 0, "sanity: the inventory is actually empty")

	var text: String = JSON.stringify(GameState.to_dict())
	assert_true(GameState.from_dict(JSON.parse_string(text)))
	assert_eq(GameState.inventory.size(), 0, "an empty inventory stays empty after a round trip")


func test_an_empty_inventory_does_not_crash_slot_summary():
	GameState.consume_item(&"potion", GameState.item_count(&"potion"))
	GameState.consume_item(&"ether", GameState.item_count(&"ether"))
	SaveManager.save_local(TEST_SLOT)
	var summary: Dictionary = SaveManager.slot_summary(TEST_SLOT)
	assert_eq(summary.get("gold"), GameState.gold, "the summary still reads fine")


# --- Multiple party members / malformed party entries -----------------------

func test_a_party_entry_referencing_unknown_content_is_skipped_not_fatal():
	# A save can end up naming a party member id that no longer has matching
	# content (a .tres was renamed or removed after the save was made). That
	# must drop just the bad entry, not fail the whole load.
	var blob: Dictionary = GameState.to_dict()
	blob["party"].append({
		"id": "no_such_hero", "level": 3, "xp": 0, "hp": 10, "sp": 10,
	})

	var real_member_count: int = blob["party"].size() - 1
	assert_true(GameState.from_dict(blob), "a load with one bad entry still succeeds")
	assert_eq(
		GameState.party.size(), real_member_count,
		"the unresolvable entry is dropped, everything else still loads"
	)


func test_known_limitation_duplicate_content_ids_collide_in_vitals():
	# KNOWN LIMITATION (logged in PROGRESS.md, not fixed this iteration):
	# vitals/experience are keyed by BattlerData.id, which is the *content
	# template's* id (e.g. &"hero"), not a per-party-slot instance id. Two
	# party members duplicated from the same .tres template — including the
	# starting hero, which new_game() already adds — therefore share one
	# vitals entry: whichever is added last wins. Fixing this needs a
	# save-schema change (a per-slot key), which is a design decision beyond
	# a hardening pass. This test pins down the current, documented behaviour
	# so a future schema change is a deliberate edit here, not a surprise.
	var starter_id: StringName = GameState.party[0].id
	var twin_a: PartyMemberData = ContentDB.party_member(&"hero")
	var twin_b: PartyMemberData = ContentDB.party_member(&"hero")
	assert_eq(twin_a.id, starter_id, "sanity: a duplicate shares the starter's id too")

	GameState.add_party_member(twin_a)
	GameState.vitals[twin_a.id] = {"hp": 20, "sp": 5}
	GameState.add_party_member(twin_b)
	GameState.vitals[twin_b.id] = {"hp": 40, "sp": 8}

	assert_eq(GameState.party.size(), 3, "starter plus both twins are all in the party array")
	# The last add_party_member's vitals write overwrote the earlier ones —
	# including the original starter's.
	assert_eq(
		GameState.vitals[starter_id]["hp"], 40,
		"documented collision: all three share one vitals entry"
	)


# --- Mid-battle state is not touched by save/load ----------------------------

func test_to_dict_reflects_committed_vitals_not_live_battle_hp():
	# The battle scene only writes back to GameState via store_vitals() at the
	# end of a fight (SPEC: "never run battle inside the overworld"). A save
	# taken while a Battler is mid-fight must reflect the last COMMITTED hp,
	# not whatever the live Battler instance currently holds.
	var member: PartyMemberData = GameState.party[0]
	GameState.vitals[member.id] = {"hp": member.max_hp, "sp": member.max_sp}

	BattleManager.turn_delay = 999999.0  # never auto-advance during this test
	BattleManager.set_seed(1)
	BattleManager.start_battle(GameState.battle_party(), [ContentDB.enemy(&"frostbit")])

	# Simulate mid-fight damage on the live Battler without committing it.
	BattleManager.player_party[0].hp = 1

	var blob: Dictionary = GameState.to_dict()
	assert_eq(
		blob["party"][0]["hp"], member.max_hp,
		"an uncommitted mid-battle hit does not leak into a save"
	)

	# store_vitals() is what commits it — confirm the seam actually works.
	GameState.store_vitals(BattleManager.player_party)
	var after_commit: Dictionary = GameState.to_dict()
	assert_eq(
		after_commit["party"][0]["hp"], 1,
		"store_vitals() is the only path that commits battle hp to a save"
	)


func test_loading_mid_battle_does_not_touch_the_active_battle():
	# from_dict() must not reach into BattleManager at all — save/load and
	# combat are separate systems, and a load mid-fight should not corrupt
	# whatever BattleManager is currently doing.
	BattleManager.turn_delay = 999999.0
	BattleManager.set_seed(2)
	BattleManager.start_battle(GameState.battle_party(), [ContentDB.enemy(&"frostbit")])
	var enemies_before: int = BattleManager.enemies.size()
	var phase_before: int = BattleManager.phase

	GameState.from_dict(GameState.to_dict())

	assert_eq(BattleManager.enemies.size(), enemies_before, "the active battle's enemies are untouched")
	assert_eq(BattleManager.phase, phase_before, "the active battle's phase is untouched")
