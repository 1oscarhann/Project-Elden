class_name HarvestDrop
extends Resource

## One entry in a drop table — harvestables and animals share it, since "which
## items, how many, how often" is the same question either way. Data, so adding
## a new material to a node means editing a .tres, never this file.

@export var item_id := ""
@export var min_count := 1
@export var max_count := 1
## Probability this entry drops at all. 1.0 keeps every pre-Phase-9 .tres
## behaving exactly as it did before this field existed.
@export_range(0.0, 1.0) var chance := 1.0


## Rolls the chance first, so an uncommon drop (a deer's antlers) yields 0.
func roll(rng: RandomNumberGenerator) -> int:
	if chance < 1.0 and rng.randf() >= chance:
		return 0
	return rng.randi_range(mini(min_count, max_count), maxi(min_count, max_count))
