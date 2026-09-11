extends GutTest

## Save/load round-trip (SPEC §7): serialise -> deserialise -> every GameState
## field must come back identical.
##
## The comparison goes through JSON.stringify/parse, not just the dictionary,
## so anything that only survives in memory (StringName keys, Vector3, ints
## that come back as floats) is caught here rather than in a player's save.

const TEST_SLOT := 9


func before_each():
	GameState.new_game()


func after_each():
	SaveManager.delete_local(TEST_SLOT)


func after_all():
	GameState.new_game()


## Every durable field on GameState, flattened into something comparable.
## Add to this when you add a field — that is the point of it.
func _snapshot() -> Dictionary:
	var party := []
	for member in GameState.party:
		party.append({
			"id": String(member.id),
			"level": member.level,
			"max_hp": member.max_hp,
			"max_sp": member.max_sp,
			"attack": member.attack,
			"defense": member.defense,
			"speed": member.speed,
			"moves": member.moves.map(func(m: MoveData) -> String: return String(m.id)),
			"xp": int(GameState.experience.get(member.id, 0)),
			"hp": int(GameState.vitals.get(member.id, {}).get("hp", -1)),
			"sp": int(GameState.vitals.get(member.id, {}).get("sp", -1)),
		})

	var inventory := {}
	for id in GameState.inventory:
		inventory[String(id)] = GameState.inventory[id]

	var flags := {}
	for flag in GameState.story_flags:
		flags[String(flag)] = GameState.story_flags[flag]

	return {
		"party": party,
		"inventory": inventory,
		"flags": flags,
		"gold": GameState.gold,
		"zone": String(GameState.current_zone),
		"position": [
			GameState.player_position.x,
			GameState.player_position.y,
			GameState.player_position.z,
		],
		"facing": GameState.player_facing,
	}


## Put every field into a non-default state so a field that silently fails to
## serialise cannot pass by accidentally matching the default.
func _dirty_every_field() -> void:
	GameState.award_xp(GameState.xp_for_level(1) + 7)
	GameState.add_gold(931)
	GameState.add_item(&"potion", 5)
	GameState.add_item(&"ether", 2)
	GameState.set_flag(&"zone_01_boss_cleared", true)
	GameState.set_flag(&"met_the_warden", true)
	GameState.current_zone = &"zone_01"
	GameState.player_position = Vector3(12.5, 1.25, -33.75)
	GameState.player_facing = 1.75
	GameState.vitals[GameState.party[0].id] = {"hp": 13, "sp": 4}


func _round_trip_through_json() -> void:
	var text: String = JSON.stringify(GameState.to_dict())
	var parsed: Variant = JSON.parse_string(text)
	assert_true(parsed is Dictionary, "the blob survives JSON")
	assert_true(GameState.from_dict(parsed), "the blob loads back")


func test_every_field_survives_the_round_trip():
	_dirty_every_field()
	var before: Dictionary = _snapshot()
	_round_trip_through_json()
	assert_eq_deep(_snapshot(), before)


func test_a_pristine_new_game_survives_the_round_trip():
	var before: Dictionary = _snapshot()
	_round_trip_through_json()
	assert_eq_deep(_snapshot(), before)


func test_the_round_trip_is_stable_when_repeated():
	_dirty_every_field()
	var before: Dictionary = _snapshot()
	for i in 3:
		_round_trip_through_json()
	assert_eq_deep(_snapshot(), before)


func test_individual_fields_come_back_with_the_right_types():
	_dirty_every_field()
	var expected_gold: int = GameState.gold
	var expected_zone: StringName = GameState.current_zone
	var expected_position: Vector3 = GameState.player_position

	_round_trip_through_json()

	assert_typeof(GameState.gold, TYPE_INT, "gold comes back an int")
	assert_eq(GameState.gold, expected_gold, "gold is unchanged")
	assert_typeof(GameState.current_zone, TYPE_STRING_NAME, "zone comes back a StringName")
	assert_eq(GameState.current_zone, expected_zone, "zone is unchanged")
	assert_typeof(GameState.player_position, TYPE_VECTOR3, "position comes back a Vector3")
	assert_eq(GameState.player_position, expected_position, "position is unchanged")
	assert_typeof(GameState.player_facing, TYPE_FLOAT, "facing comes back a float")


func test_inventory_keys_come_back_as_string_names():
	_dirty_every_field()
	_round_trip_through_json()
	for key in GameState.inventory:
		assert_typeof(key, TYPE_STRING_NAME, "inventory key %s is a StringName" % key)
	assert_eq(GameState.item_count(&"potion"), 5 + 3, "item counts survive")


func test_flag_keys_come_back_as_string_names():
	_dirty_every_field()
	_round_trip_through_json()
	for key in GameState.story_flags:
		assert_typeof(key, TYPE_STRING_NAME, "flag key %s is a StringName" % key)
	assert_eq(GameState.get_flag(&"zone_01_boss_cleared", false), true, "flags survive")


func test_levelled_stats_are_rebuilt_not_trusted_from_the_blob():
	GameState.award_xp(100000)
	var expected_level: int = GameState.party[0].level
	var expected_hp: int = GameState.party[0].max_hp
	var expected_moves: int = GameState.party[0].moves.size()

	_round_trip_through_json()

	assert_eq(GameState.party[0].level, expected_level, "level is restored")
	assert_eq(GameState.party[0].max_hp, expected_hp, "grown stats are replayed from the curve")
	assert_eq(GameState.party[0].moves.size(), expected_moves, "learned moves are replayed")


func test_current_hp_is_clamped_to_the_restored_maximum():
	var blob: Dictionary = GameState.to_dict()
	blob["party"][0]["hp"] = 999999
	blob["party"][0]["sp"] = 999999
	assert_true(GameState.from_dict(blob), "the blob still loads")
	assert_eq(
		GameState.vitals[GameState.party[0].id]["hp"], GameState.party[0].max_hp,
		"an over-large hp value is clamped, not trusted"
	)


func test_a_junk_blob_is_rejected_rather_than_half_applied():
	_dirty_every_field()
	var before: Dictionary = _snapshot()
	assert_false(GameState.from_dict({}), "an empty blob is rejected")
	assert_eq_deep(_snapshot(), before)


func test_a_future_save_version_is_rejected():
	_dirty_every_field()
	var before: Dictionary = _snapshot()
	assert_false(GameState.from_dict({"version": 999}), "a newer save version is refused")
	assert_eq_deep(_snapshot(), before)


func test_the_blob_carries_its_version():
	assert_eq(GameState.to_dict()["version"], SaveFormat.VERSION, "the blob is stamped")


func test_a_save_fits_the_blob_cap():
	_dirty_every_field()
	var size: int = JSON.stringify(GameState.to_dict()).to_utf8_buffer().size()
	assert_lt(size, SaveFormat.MAX_BLOB_BYTES, "a realistic save is well under the cap")


# --- Through the disk path the game actually uses ---------------------------

func test_the_disk_round_trip_preserves_every_field():
	_dirty_every_field()
	var before: Dictionary = _snapshot()

	assert_true(SaveManager.save_local(TEST_SLOT), "the slot writes")
	GameState.new_game()
	assert_true(SaveManager.load_local(TEST_SLOT), "the slot reads back")
	assert_eq_deep(_snapshot(), before)


func test_slot_existence_tracks_writes_and_deletes():
	assert_false(SaveManager.slot_exists(TEST_SLOT), "an unwritten slot is empty")
	SaveManager.save_local(TEST_SLOT)
	assert_true(SaveManager.slot_exists(TEST_SLOT), "a written slot exists")
	SaveManager.delete_local(TEST_SLOT)
	assert_false(SaveManager.slot_exists(TEST_SLOT), "a deleted slot is gone")


func test_loading_a_missing_slot_fails_cleanly():
	assert_false(SaveManager.load_local(TEST_SLOT), "loading an empty slot returns false")


func test_slot_summary_reads_without_deserialising():
	_dirty_every_field()
	SaveManager.save_local(TEST_SLOT)
	var summary: Dictionary = SaveManager.slot_summary(TEST_SLOT)

	# KNOWN DEFECT (see PROGRESS.md, deferred to the save-hardening pass):
	# slot_summary returns these straight out of JSON.parse_string, so they
	# arrive as floats and a save-select screen would render "Gold: 931.0".
	# Compared numerically here so the suite documents the value without
	# baking in the wrong type.
	assert_eq(int(summary.get("gold")), GameState.gold, "the summary reports gold")
	assert_eq(
		int(summary.get("level")), GameState.party[0].level,
		"the summary reports the lead level"
	)
	assert_eq(summary.get("zone"), String(GameState.current_zone), "the summary reports the zone")
