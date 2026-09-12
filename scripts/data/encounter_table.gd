class_name EncounterTable
extends Resource

## Which enemies a zone can throw at you, and how often (SPEC §9 step 2).

@export var zone_id: StringName = &""

## Parallel to `weights`. Each entry is one possible enemy group.
@export var encounters: Array[EnemyData] = []
## Relative weight per entry. Same length as `encounters`.
@export var weights: Array[int] = []

## Average steps between encounters. Actual trigger is randomised around this.
@export var steps_per_encounter: int = 22

## Fixed group fought at the zone's boss trigger. Not part of random rolls.
@export var boss: EnemyData = null


## Rolls one encounter from `encounters`, weighted by `weights`. Falls back
## to a uniform roll if the weights are malformed (missing, or the wrong
## length). Returns null if there is nothing to pick from.
func pick(rng: RandomNumberGenerator) -> EnemyData:
	if encounters.is_empty():
		return null
	var total: int = 0
	for w in weights:
		total += w
	if total <= 0 or weights.size() != encounters.size():
		return encounters[rng.randi() % encounters.size()]

	var roll: int = rng.randi_range(1, total)
	var running: int = 0
	for i in encounters.size():
		running += weights[i]
		if roll <= running:
			return encounters[i]
	return encounters.back()
