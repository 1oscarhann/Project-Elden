extends GutTest

## The type chart is the combat's identity (SPEC §6), so every relationship in
## it is asserted explicitly rather than spot-checked.


func test_the_elemental_wheel_turns():
	assert_eq(TypeChart.multiplier(&"fire", &"ice"), TypeChart.WEAK, "fire melts ice")
	assert_eq(TypeChart.multiplier(&"ice", &"wind"), TypeChart.WEAK, "ice grounds wind")
	assert_eq(TypeChart.multiplier(&"wind", &"fire"), TypeChart.WEAK, "wind smothers fire")
	assert_eq(TypeChart.multiplier(&"shock", &"wind"), TypeChart.WEAK, "shock shreds wind")


func test_light_and_dark_are_mutually_weak():
	assert_eq(TypeChart.multiplier(&"light", &"dark"), TypeChart.WEAK, "light burns dark")
	assert_eq(TypeChart.multiplier(&"dark", &"light"), TypeChart.WEAK, "dark swallows light")


func test_immunity():
	assert_eq(TypeChart.multiplier(&"light", &"light"), TypeChart.IMMUNE, "light is null to light")
	assert_eq(TypeChart.multiplier(&"dark", &"dark"), TypeChart.IMMUNE, "dark is null to dark")


func test_resistance():
	assert_eq(TypeChart.multiplier(&"fire", &"fire"), TypeChart.RESIST, "fire resists fire")
	assert_eq(TypeChart.multiplier(&"ice", &"ice"), TypeChart.RESIST, "ice resists ice")
	assert_eq(TypeChart.multiplier(&"ice", &"fire"), TypeChart.RESIST, "ice is weak into fire")
	assert_eq(TypeChart.multiplier(&"wind", &"wind"), TypeChart.RESIST, "wind resists wind")
	assert_eq(TypeChart.multiplier(&"shock", &"shock"), TypeChart.RESIST, "shock resists shock")


func test_unlisted_pairs_are_neutral():
	assert_eq(
		TypeChart.multiplier(&"physical", &"fire"), TypeChart.NEUTRAL,
		"a pair absent from the chart is neutral"
	)
	assert_eq(
		TypeChart.multiplier(&"fire", &"physical"), TypeChart.NEUTRAL,
		"a defender absent from a listed row is neutral"
	)


func test_unknown_types_do_not_crash():
	assert_eq(
		TypeChart.multiplier(&"not_a_type", &"fire"), TypeChart.NEUTRAL,
		"an unknown attacker falls back to neutral"
	)
	assert_eq(
		TypeChart.multiplier(&"fire", &"not_a_type"), TypeChart.NEUTRAL,
		"an unknown defender falls back to neutral"
	)


func test_every_declared_type_resolves_against_every_other():
	for attacker in TypeChart.TYPES:
		for defender in TypeChart.TYPES:
			var value: float = TypeChart.multiplier(attacker, defender)
			assert_true(
				value in [TypeChart.IMMUNE, TypeChart.RESIST, TypeChart.NEUTRAL, TypeChart.WEAK],
				"%s -> %s yields a known multiplier (got %s)" % [attacker, defender, value]
			)


func test_is_weakness_agrees_with_the_chart():
	assert_true(TypeChart.is_weakness(&"fire", &"ice"), "a 2x pair is a weakness")
	assert_false(TypeChart.is_weakness(&"fire", &"fire"), "a resisted pair is not")
	assert_false(TypeChart.is_weakness(&"physical", &"ice"), "a neutral pair is not")
	assert_false(TypeChart.is_weakness(&"dark", &"dark"), "an immune pair is not")
