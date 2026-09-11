class_name TypeChart
extends RefCounted

## The core hook (SPEC §6). Attack type vs defend type -> damage multiplier.
##
## Kept as plain data so new types are a data edit, not a code change.
## Any pair missing from the table is NEUTRAL.

const IMMUNE := 0.0
const RESIST := 0.5
const NEUTRAL := 1.0
const WEAK := 2.0

## Every type in the game. Add here first, then add the interesting pairs below.
const TYPES: Array[StringName] = [
	&"physical",
	&"fire",
	&"ice",
	&"shock",
	&"wind",
	&"light",
	&"dark",
]

## attacker -> { defender: multiplier }. Only non-neutral pairs are listed.
const CHART: Dictionary = {
	&"fire": {&"ice": WEAK, &"fire": RESIST},
	&"ice": {&"wind": WEAK, &"ice": RESIST, &"fire": RESIST},
	&"shock": {&"wind": WEAK, &"shock": RESIST},
	&"wind": {&"fire": WEAK, &"wind": RESIST},
	&"light": {&"dark": WEAK, &"light": IMMUNE},
	&"dark": {&"light": WEAK, &"dark": IMMUNE},
}


static func multiplier(attack_type: StringName, defend_type: StringName) -> float:
	var row: Variant = CHART.get(attack_type)
	if row == null:
		return NEUTRAL
	return float((row as Dictionary).get(defend_type, NEUTRAL))


static func is_weakness(attack_type: StringName, defend_type: StringName) -> bool:
	return multiplier(attack_type, defend_type) > NEUTRAL
