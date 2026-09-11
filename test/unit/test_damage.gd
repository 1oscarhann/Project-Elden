extends GutTest

## The damage formula lives in one function (SPEC §6), so this is the only
## place its arithmetic is pinned down.

var _attacker: Battler
var _ice: Battler
var _fire: Battler
var _dark: Battler
var _rng: RandomNumberGenerator


func before_each():
	_attacker = _make(&"attacker", 20, 10, &"physical")
	_ice = _make(&"ice_foe", 10, 10, &"ice")
	_fire = _make(&"fire_foe", 10, 10, &"fire")
	_dark = _make(&"dark_foe", 10, 10, &"dark")
	_rng = RandomNumberGenerator.new()
	_rng.seed = 20260911


func _make(id: StringName, attack: int, defense: int, defend_type: StringName) -> Battler:
	var data := BattlerData.new()
	data.id = id
	data.display_name = String(id)
	data.max_hp = 100
	data.max_sp = 50
	data.attack = attack
	data.defense = defense
	data.defend_type = defend_type
	return Battler.new(data, false)


# --- Type multipliers -------------------------------------------------------

func test_multipliers_order_the_damage():
	var weak: Damage.Result = Damage.calculate(30, &"fire", _attacker, _ice)
	var neutral: Damage.Result = Damage.calculate(30, &"physical", _attacker, _ice)
	var resisted: Damage.Result = Damage.calculate(30, &"fire", _attacker, _fire)

	assert_gt(weak.amount, neutral.amount, "a weakness hits harder than neutral")
	assert_gt(neutral.amount, resisted.amount, "neutral hits harder than a resist")


func test_weakness_is_exactly_double_neutral():
	# Both calls are variance-free (no rng), so the ratio is exact.
	var weak: Damage.Result = Damage.calculate(30, &"fire", _attacker, _ice)
	var neutral: Damage.Result = Damage.calculate(30, &"physical", _attacker, _ice)
	assert_eq(weak.amount, neutral.amount * 2, "WEAK is a clean 2x over neutral")


func test_resist_is_exactly_half_neutral():
	var resisted: Damage.Result = Damage.calculate(30, &"fire", _attacker, _fire)
	var neutral: Damage.Result = Damage.calculate(30, &"physical", _attacker, _fire)
	assert_eq(resisted.amount * 2, neutral.amount, "RESIST is a clean 0.5x of neutral")


func test_immunity_deals_nothing():
	var immune: Damage.Result = Damage.calculate(30, &"dark", _attacker, _dark)
	assert_eq(immune.amount, 0, "an immune hit deals zero")
	assert_true(immune.was_immune, "immunity is flagged")
	assert_false(immune.grants_one_more(), "an immune hit earns no One More")


func test_result_flags_match_the_multiplier():
	assert_true(Damage.calculate(30, &"fire", _attacker, _ice).hit_weakness, "weakness flagged")
	assert_true(Damage.calculate(30, &"fire", _attacker, _fire).was_resisted, "resist flagged")

	var neutral: Damage.Result = Damage.calculate(30, &"physical", _attacker, _ice)
	assert_false(neutral.hit_weakness, "neutral is not a weakness")
	assert_false(neutral.was_resisted, "neutral is not a resist")
	assert_false(neutral.was_immune, "neutral is not immunity")


func test_immunity_is_not_reported_as_a_resist():
	var immune: Damage.Result = Damage.calculate(30, &"dark", _attacker, _dark)
	assert_false(immune.was_resisted, "immunity and resistance are distinct outcomes")


# --- Variance ---------------------------------------------------------------

func test_variance_stays_inside_its_declared_bounds():
	var baseline: int = Damage.calculate(40, &"physical", _attacker, _ice).amount
	var lowest: int = 1 << 30
	var highest: int = 0

	for i in 400:
		var rolled: int = Damage.calculate(40, &"physical", _attacker, _ice, 0.0, _rng).amount
		lowest = mini(lowest, rolled)
		highest = maxi(highest, rolled)

	# +/-1 of slack for the final round() on either end.
	var floor_bound: int = int(floor(float(baseline) * Damage.VARIANCE_MIN)) - 1
	var ceil_bound: int = int(ceil(float(baseline) * Damage.VARIANCE_MAX)) + 1
	assert_between(lowest, floor_bound, baseline, "the low roll respects VARIANCE_MIN")
	assert_between(highest, baseline, ceil_bound, "the high roll respects VARIANCE_MAX")


func test_variance_actually_varies():
	var seen := {}
	for i in 200:
		seen[Damage.calculate(40, &"physical", _attacker, _ice, 0.0, _rng).amount] = true
	assert_gt(seen.size(), 1, "rolling with an rng produces more than one value")


func test_no_rng_means_no_variance():
	var first: int = Damage.calculate(40, &"physical", _attacker, _ice).amount
	for i in 20:
		assert_eq(
			Damage.calculate(40, &"physical", _attacker, _ice).amount, first,
			"omitting the rng gives a deterministic number"
		)


func test_immunity_beats_variance():
	for i in 50:
		assert_eq(
			Damage.calculate(40, &"dark", _attacker, _dark, 0.5, _rng).amount, 0,
			"no roll can push an immune hit above zero"
		)


# --- Floors and modifiers ---------------------------------------------------

func test_a_connecting_hit_never_rounds_to_zero():
	var tank := _make(&"tank", 10, 9999, &"physical")
	assert_eq(
		Damage.calculate(1, &"physical", _attacker, tank).amount, 1,
		"a hit against absurd defence still lands 1"
	)
	for i in 100:
		assert_gte(
			Damage.calculate(1, &"physical", _attacker, tank, 0.0, _rng).amount, 1,
			"the floor holds under variance too"
		)


func test_a_resisted_hit_also_respects_the_floor():
	var tank := _make(&"tank", 10, 9999, &"fire")
	assert_gte(
		Damage.calculate(1, &"fire", _attacker, tank).amount, 1,
		"resistance cannot reduce a connecting hit to zero"
	)


func test_defending_halves_the_incoming_hit():
	var open: int = Damage.calculate(40, &"physical", _attacker, _ice).amount
	_ice.is_defending = true
	var guarded: int = Damage.calculate(40, &"physical", _attacker, _ice).amount
	assert_eq(
		guarded * int(Damage.DEFEND_MULTIPLIER), open,
		"defending scales effective defence by DEFEND_MULTIPLIER"
	)


func test_zero_defence_does_not_divide_by_zero():
	var paper := _make(&"paper", 10, 0, &"physical")
	var result: Damage.Result = Damage.calculate(10, &"physical", _attacker, paper)
	assert_gt(result.amount, 0, "zero defence is clamped, not divided by")


func test_a_guaranteed_crit_multiplies_and_grants_one_more():
	var plain: int = Damage.calculate(40, &"physical", _attacker, _ice).amount
	var crit: Damage.Result = Damage.calculate(40, &"physical", _attacker, _ice, 1.0, _rng)
	assert_true(crit.was_crit, "a 1.0 crit chance always crits")
	assert_gt(crit.amount, plain, "a crit hits harder")
	assert_true(crit.grants_one_more(), "a crit earns One More")


func test_a_zero_crit_chance_never_crits():
	for i in 200:
		assert_false(
			Damage.calculate(40, &"physical", _attacker, _ice, 0.0, _rng).was_crit,
			"a 0.0 crit chance never crits"
		)


func test_basic_attack_uses_the_shared_formula():
	var result: Damage.Result = Damage.basic_attack(_attacker, _ice)
	assert_gt(result.amount, 0, "the basic attack deals damage")
	assert_eq(
		result.amount,
		Damage.calculate(Damage.BASIC_ATTACK_POWER, Damage.BASIC_ATTACK_TYPE, _attacker, _ice).amount,
		"basic_attack is the same formula, not a second one"
	)


func test_attack_and_defence_move_damage_the_expected_way():
	var strong := _make(&"strong", 40, 10, &"physical")
	var armoured := _make(&"armoured", 10, 20, &"ice")
	assert_gt(
		Damage.calculate(30, &"physical", strong, _ice).amount,
		Damage.calculate(30, &"physical", _attacker, _ice).amount,
		"more attack means more damage"
	)
	assert_lt(
		Damage.calculate(30, &"physical", _attacker, armoured).amount,
		Damage.calculate(30, &"physical", _attacker, _ice).amount,
		"more defence means less damage"
	)
