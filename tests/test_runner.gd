extends Node

## Headless test suite.
##
##   godot --headless --path . res://tests/TestRunner.tscn
##
## Run as a SCENE, not with --script: a --script MainLoop never registers the
## autoload globals, so every script that touches GameState or BattleManager
## fails to compile and the suite reports green on nothing.
##
## Exits non-zero on failure so CI can gate on it. Combat is seeded, so a
## failure here reproduces exactly.

var _passed: int = 0
var _failed: int = 0
var _current: String = ""


func _ready() -> void:
	await get_tree().process_frame
	_run("singletons", _test_singletons)

	_run("type chart", _test_type_chart)
	_run("damage formula", _test_damage)
	_run("one more", _test_one_more)
	_run("content loads", _test_content)
	_run("progression", _test_progression)
	_run("save round-trip", _test_save_round_trip)
	_run("encounter weighting", _test_encounter_weighting)
	await _run_async("full battle", _test_full_battle)
	await _run_async("scenes boot", _test_scenes_boot)

	print("\n%d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


# --- Harness ----------------------------------------------------------------

func _run(name: String, fn: Callable) -> void:
	_current = name
	fn.call()


func _run_async(name: String, fn: Callable) -> void:
	_current = name
	await fn.call()


func _check(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		printerr("FAIL [%s] %s" % [_current, message])


func _eq(actual: Variant, expected: Variant, message: String) -> void:
	_check(actual == expected, "%s (got %s, expected %s)" % [message, actual, expected])


# --- Tests ------------------------------------------------------------------

func _test_singletons() -> void:
	# If an autoload's script fails to compile, Godot substitutes a bare Node
	# and every later test quietly tests nothing. Fail here instead.
	var root := get_tree().root
	for name in ["GameState", "BattleManager", "SaveManager", "AudioManager"]:
		var node: Node = root.get_node_or_null(NodePath("/root/%s" % name))
		_check(node != null, "%s autoload exists" % name)
		_check(node != null and node.get_script() != null, "%s kept its script" % name)


func _test_type_chart() -> void:
	_eq(TypeChart.multiplier(&"fire", &"ice"), TypeChart.WEAK, "fire melts ice")
	_eq(TypeChart.multiplier(&"ice", &"wind"), TypeChart.WEAK, "ice grounds wind")
	_eq(TypeChart.multiplier(&"wind", &"fire"), TypeChart.WEAK, "wind smothers fire")
	_eq(TypeChart.multiplier(&"light", &"dark"), TypeChart.WEAK, "light burns dark")
	_eq(TypeChart.multiplier(&"dark", &"dark"), TypeChart.IMMUNE, "dark is null to dark")
	_eq(TypeChart.multiplier(&"physical", &"fire"), TypeChart.NEUTRAL, "unlisted pairs neutral")
	_eq(TypeChart.multiplier(&"nonsense", &"fire"), TypeChart.NEUTRAL, "unknown type neutral")
	_check(TypeChart.is_weakness(&"fire", &"ice"), "is_weakness agrees with the chart")
	_check(not TypeChart.is_weakness(&"fire", &"fire"), "resist is not a weakness")


func _test_damage() -> void:
	var attacker := Battler.new(_stats(&"atk", 20, 10, &"physical"), true)
	var ice := Battler.new(_stats(&"ice_foe", 10, 10, &"ice"), false)
	var fire := Battler.new(_stats(&"fire_foe", 10, 10, &"fire"), false)
	var dark := Battler.new(_stats(&"dark_foe", 10, 10, &"dark"), false)

	var weak := Damage.calculate(30, &"fire", attacker, ice)
	var neutral := Damage.calculate(30, &"physical", attacker, ice)
	var resisted := Damage.calculate(30, &"fire", attacker, fire)
	var immune := Damage.calculate(30, &"dark", attacker, dark)

	_check(weak.amount > neutral.amount, "weakness beats neutral")
	_check(neutral.amount > resisted.amount, "neutral beats resisted")
	_eq(immune.amount, 0, "immune deals nothing")
	_check(weak.hit_weakness, "weakness is flagged")
	_check(resisted.was_resisted, "resist is flagged")
	_check(immune.was_immune, "immunity is flagged")
	_check(weak.grants_one_more(), "a weakness hit earns One More")
	_check(not neutral.grants_one_more(), "a neutral hit does not")
	_check(not immune.grants_one_more(), "an immune hit does not")

	# Defending halves what lands, and a hit never rounds to zero.
	ice.is_defending = true
	var guarded := Damage.calculate(30, &"physical", attacker, ice)
	ice.is_defending = false
	_check(guarded.amount < neutral.amount, "defend reduces damage")

	var tank := Battler.new(_stats(&"tank", 10, 9999, &"physical"), false)
	_check(Damage.calculate(1, &"physical", attacker, tank).amount >= 1, "a hit always lands 1+")


func _test_one_more() -> void:
	var battler := Battler.new(_stats(&"x", 10, 10, &"physical"), true)
	battler.used_one_more = true
	battler.is_defending = true
	battler.begin_round()
	_check(not battler.used_one_more, "One More resets each round")
	_check(not battler.is_defending, "defend expires each round")


func _test_content() -> void:
	ContentDB.reload()
	_check(ContentDB.move(&"ember") != null, "moves load from data/")
	_check(ContentDB.item(&"potion") != null, "items load from data/")
	_check(ContentDB.enemy(&"warden") != null, "enemies load from data/")
	_check(ContentDB.encounter_table(&"zone_01") != null, "encounter tables load from data/")

	var warden := ContentDB.enemy(&"warden")
	_check(warden.is_boss, "the warden is a boss")
	_eq(
		TypeChart.multiplier(&"light", warden.defend_type),
		TypeChart.WEAK,
		"the boss is weak to light"
	)

	# Two calls must not hand back the same mutable object, or levelling one
	# save would level every save.
	var a := ContentDB.party_member(&"hero")
	var b := ContentDB.party_member(&"hero")
	_check(a != b, "party members are copied, not shared")


func _test_progression() -> void:
	var hero := ContentDB.party_member(&"hero")
	_eq(hero.moves.size(), 2, "hero starts with two moves")
	_check(
		GameState.xp_for_level(2) > GameState.xp_for_level(1),
		"the xp curve climbs"
	)

	GameState.new_game()
	var starting_level: int = GameState.party[0].level
	GameState.award_xp(100000)
	var member: PartyMemberData = GameState.party[0]
	_check(member.level > starting_level, "xp levels the party up")
	_check(member.max_hp > hero.max_hp, "levelling grows stats")

	var has_light: bool = false
	for move in member.moves:
		if move.type == &"light" and move.is_offensive():
			has_light = true
	_check(has_light, "the hero learns a light move (the boss key)")


func _test_save_round_trip() -> void:
	GameState.new_game()
	GameState.award_xp(GameState.xp_for_level(1) + 1)
	GameState.add_gold(77)
	GameState.add_item(&"potion", 2)
	GameState.set_flag(&"zone_01_boss_cleared", true)
	GameState.player_position = Vector3(3.0, 1.0, -4.0)
	GameState.current_zone = &"zone_01"

	var blob: Dictionary = GameState.to_dict()
	var text: String = JSON.stringify(blob)
	_check(text.to_utf8_buffer().size() < SaveFormat.MAX_BLOB_BYTES, "a save fits the blob cap")

	var expected_level: int = GameState.party[0].level
	var expected_gold: int = GameState.gold
	var expected_potions: int = GameState.item_count(&"potion")

	# Round-trip through JSON, not just the dictionary, so we catch anything
	# that only survives in memory (StringName keys, Vector3, ints as floats).
	var reparsed: Variant = JSON.parse_string(text)
	_check(reparsed is Dictionary, "the blob survives JSON")
	_check(GameState.from_dict(reparsed), "the blob loads back")

	_eq(GameState.party[0].level, expected_level, "level survives the round-trip")
	_eq(GameState.gold, expected_gold, "gold survives the round-trip")
	_eq(GameState.item_count(&"potion"), expected_potions, "inventory survives")
	_eq(GameState.get_flag(&"zone_01_boss_cleared", false), true, "flags survive")
	_eq(GameState.player_position, Vector3(3.0, 1.0, -4.0), "position survives")

	_check(not GameState.from_dict({}), "a junk blob is rejected, not half-applied")
	_check(not GameState.from_dict({"version": 999}), "a future save version is rejected")

	# And through the disk path the game actually uses.
	GameState.new_game()
	GameState.add_gold(1234)
	_check(SaveManager.save_local(9), "a slot writes to disk")
	GameState.new_game()
	_check(SaveManager.load_local(9), "a slot reads back from disk")
	_eq(GameState.gold, 150 + 1234, "disk round-trip keeps gold")
	SaveManager.delete_local(9)


func _test_encounter_weighting() -> void:
	var table := ContentDB.encounter_table(&"zone_01")
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345

	var counts: Dictionary = {}
	for i in 600:
		var foe: EnemyData = table.pick(rng)
		counts[foe.id] = int(counts.get(foe.id, 0)) + 1

	_eq(counts.size(), table.encounters.size(), "every entry can be rolled")
	for id in counts:
		_check(counts[id] > 30, "%s is rolled at a sane rate" % id)


func _test_full_battle() -> void:
	GameState.new_game()
	BattleManager.turn_delay = 0.0
	BattleManager.set_seed(42)

	# GDScript lambdas capture by value, so a captured int would never escape
	# the closure. Collect into arrays, which are reference types.
	var log_lines: Array[String] = []
	var one_more_hits: Array[String] = []
	BattleManager.action_resolved.connect(func(line: String) -> void: log_lines.append(line))
	BattleManager.one_more_granted.connect(
		func(actor: Battler) -> void: one_more_hits.append(actor.display_name())
	)

	# Always pick the best type matchup, which is what a player who has read
	# the chart would do — and the path most likely to trip the One More rule.
	BattleManager.awaiting_action.connect(_play_optimally)

	var outcome: Array = []
	BattleManager.battle_finished.connect(
		func(result: int, rewards: Dictionary) -> void:
			outcome.append(result)
			outcome.append(rewards)
	)

	var foes: Array[EnemyData] = [
		ContentDB.enemy(&"frostbit"), ContentDB.enemy(&"gustling"),
	] as Array[EnemyData]
	BattleManager.start_battle(GameState.battle_party(), foes)

	var guard: int = 0
	while outcome.is_empty() and guard < 400:
		guard += 1
		await get_tree().process_frame

	_check(not outcome.is_empty(), "the battle reaches an end state")
	if outcome.is_empty():
		return

	_eq(outcome[0], Combat.Outcome.VICTORY, "a type-aware player beats two trash mobs")
	_check(int(outcome[1]["xp"]) > 0, "victory pays xp")
	_check(int(outcome[1]["gold"]) > 0, "victory pays gold")
	_check(not one_more_hits.is_empty(), "exploiting weaknesses triggered One More")
	_check(log_lines.size() > 0, "the fight produced a readable log")

	var weak_lines: int = 0
	for line in log_lines:
		if line.contains("(WEAK!)"):
			weak_lines += 1
	_check(weak_lines > 0, "weakness hits are reported to the player")
	_check(BattleManager.round_number >= 1, "rounds advanced")

	BattleManager.awaiting_action.disconnect(_play_optimally)


func _test_scenes_boot() -> void:
	# The stage and the whole combat UI are built procedurally, so nothing
	# catches a bad node setup except actually instantiating the scene.
	var world_scene: PackedScene = load("res://scenes/World.tscn")
	_check(world_scene != null, "World.tscn loads")
	if world_scene != null:
		var world: Node = world_scene.instantiate()
		get_tree().root.add_child(world)
		await get_tree().process_frame
		var player: Node = world.get_node_or_null(^"Player")
		_check(player is PlayerController, "the world has a player controller")
		_check(
			world.get_node_or_null(^"Player/CameraPivot/SpringArm3D/Camera3D") != null,
			"the chase camera is wired up"
		)
		_check(world.get_node_or_null(^"EncounterField") is EncounterZone, "the field is armed")
		_check(world.get_node_or_null(^"BossGate") is BossGate, "the boss gate exists")
		world.queue_free()
		await get_tree().process_frame

	GameState.new_game()
	BattleManager.turn_delay = 0.0
	BattleManager.queue_encounter([ContentDB.enemy(&"frostbit")] as Array[EnemyData])

	var battle_scene: PackedScene = load("res://scenes/Battle.tscn")
	_check(battle_scene != null, "Battle.tscn loads")
	if battle_scene == null:
		return

	var battle: Node = battle_scene.instantiate()
	get_tree().root.add_child(battle)
	await get_tree().process_frame

	var has_ui: bool = false
	for child in battle.get_children():
		if child is BattleUI:
			has_ui = true
	_check(has_ui, "the battle scene builds its UI")
	_check(BattleManager.phase == Combat.Phase.PLAYER, "the fight opens waiting on the player")
	_check(BattleManager.enemies.size() == 1, "the queued encounter was consumed")

	battle.queue_free()
	await get_tree().process_frame


func _play_optimally(actor: Battler) -> void:
	var targets: Array = []
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


func _stats(id: StringName, attack: int, defense: int, defend_type: StringName) -> BattlerData:
	var data := BattlerData.new()
	data.id = id
	data.display_name = String(id)
	data.max_hp = 100
	data.max_sp = 50
	data.attack = attack
	data.defense = defense
	data.defend_type = defend_type
	return data
