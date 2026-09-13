class_name HarvestDrop
extends Resource

## One entry in a harvestable's drop table. Data, so adding a new material to a
## node means editing a .tres, never this file.

@export var item_id := ""
@export var min_count := 1
@export var max_count := 1


func roll(rng: RandomNumberGenerator) -> int:
	return rng.randi_range(mini(min_count, max_count), maxi(min_count, max_count))
