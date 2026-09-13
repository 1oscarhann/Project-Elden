class_name RecipeData
extends Resource

## One craftable recipe.
##
## Pure data: a new recipe is a new .tres in resources/recipes/ and nothing
## else. Dependencies between recipes are implicit — a recipe whose ingredient
## is another recipe's result is simply deeper in the tree, and `Crafting` never
## needs to know the shape of that tree.

@export var id := ""
@export var result_item_id := ""
@export_range(1, 99) var result_count := 1
@export var ingredients: Array[RecipeIngredient] = []
## Station required to craft this. Empty means hand-craftable anywhere.
@export var required_station := ""
@export var unlocked_by_default := true
@export var category := "general"


func needs_station() -> bool:
	return not required_station.is_empty()
