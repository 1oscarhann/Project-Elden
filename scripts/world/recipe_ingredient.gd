class_name RecipeIngredient
extends Resource

## One "n of item x" entry in a recipe's ingredient list.

@export var item_id := ""
@export_range(1, 999) var count := 1
