extends Node

## Recipe lookup, craftability checks and crafting itself.
##
## Autoload. Loads every RecipeData in resources/recipes/ at boot and leans
## entirely on Inventory for item movement, so it never learns what an item is.
## The recipe "tree" is emergent: a recipe whose ingredient is another recipe's
## result is simply deeper, and nothing here encodes that shape.

signal crafted(recipe: RecipeData)
## Fired when the set of stations the player is standing in changes.
signal stations_changed

const RECIPE_DIR := "res://resources/recipes/"

var _recipes: Dictionary = {}
## station_id -> how many of that station currently contain the player.
var _stations: Dictionary = {}


func _ready() -> void:
	reload()


func reload() -> void:
	_recipes.clear()
	var dir := DirAccess.open(RECIPE_DIR)
	if dir == null:
		push_error("Crafting: cannot open %s" % RECIPE_DIR)
		return
	for file in dir.get_files():
		# Exported builds rewrite .tres to .tres.remap.
		var name := file.trim_suffix(".remap")
		if not name.ends_with(".tres"):
			continue
		var recipe := load(RECIPE_DIR + name) as RecipeData
		if recipe == null or recipe.id.is_empty():
			continue
		if _recipes.has(recipe.id):
			push_error("Crafting: duplicate recipe id '%s'" % recipe.id)
			continue
		_recipes[recipe.id] = recipe


func get_recipe(id: String) -> RecipeData:
	return _recipes.get(id, null)


func count() -> int:
	return _recipes.size()


## Every unlocked recipe, ordered so hand-crafts come before station ones and
## the list is stable for the UI.
func all_recipes() -> Array:
	var list: Array = []
	for id in _recipes:
		var recipe: RecipeData = _recipes[id]
		if recipe.unlocked_by_default:
			list.append(recipe)
	list.sort_custom(func(a, b):
		if a.required_station != b.required_station:
			return a.required_station < b.required_station
		return a.id < b.id)
	return list


# --- stations ---------------------------------------------------------------

func add_station(id: String) -> void:
	if id.is_empty():
		return
	_stations[id] = int(_stations.get(id, 0)) + 1
	stations_changed.emit()


func remove_station(id: String) -> void:
	if not _stations.has(id):
		return
	var left := int(_stations[id]) - 1
	if left <= 0:
		_stations.erase(id)
	else:
		_stations[id] = left
	stations_changed.emit()


func has_station(id: String) -> bool:
	return _stations.has(id)


func nearby_stations() -> Array:
	var ids: Array = _stations.keys()
	ids.sort()
	return ids


# --- craftability -----------------------------------------------------------

func station_ready(recipe: RecipeData) -> bool:
	return not recipe.needs_station() or has_station(recipe.required_station)


## [{item_id, have, need}] for every ingredient, whether satisfied or not —
## the UI wants to show have/need on all of them, not just the missing ones.
func ingredient_status(recipe: RecipeData) -> Array:
	var rows: Array = []
	for ingredient in recipe.ingredients:
		if ingredient == null or ingredient.item_id.is_empty():
			continue
		rows.append({
			"item_id": ingredient.item_id,
			"have": Inventory.count(ingredient.item_id),
			"need": ingredient.count,
		})
	return rows


func has_ingredients(recipe: RecipeData) -> bool:
	for ingredient in recipe.ingredients:
		if ingredient == null or ingredient.item_id.is_empty():
			continue
		if not Inventory.has(ingredient.item_id, ingredient.count):
			return false
	return true


func can_craft(recipe: RecipeData) -> bool:
	return recipe != null and recipe.unlocked_by_default \
		and station_ready(recipe) and has_ingredients(recipe)


## Consumes the ingredients and yields the result.
##
## Transactional: if the result cannot fit once the ingredients are gone, every
## ingredient is put back and nothing is crafted. Crafting is destructive, so
## "half consumed and the output lost" must be impossible.
func craft(recipe: RecipeData) -> bool:
	if not can_craft(recipe):
		return false
	var taken: Array = []
	for ingredient in recipe.ingredients:
		if ingredient == null or ingredient.item_id.is_empty():
			continue
		if not Inventory.remove_item(ingredient.item_id, ingredient.count):
			_refund(taken)
			return false
		taken.append(ingredient)
	var leftover := Inventory.add_item(recipe.result_item_id, recipe.result_count)
	if leftover > 0:
		# No room for the result. Undo, including the part that did fit.
		if leftover < recipe.result_count:
			Inventory.remove_item(recipe.result_item_id, recipe.result_count - leftover)
		_refund(taken)
		return false
	crafted.emit(recipe)
	return true


func _refund(taken: Array) -> void:
	for ingredient in taken:
		Inventory.add_item(ingredient.item_id, ingredient.count)
