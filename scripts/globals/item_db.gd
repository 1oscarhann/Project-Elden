extends Node

## Loads every ItemData in resources/items/ at boot and hands them out by id.
##
## Autoload. Nothing else in the game holds an ItemData reference directly —
## drops, recipes and UI all pass around string ids and come here to resolve
## them, which is what keeps items addable as pure data.

const ITEM_DIR := "res://resources/items/"

var _items: Dictionary = {}


func _ready() -> void:
	reload()


func reload() -> void:
	_items.clear()
	var dir := DirAccess.open(ITEM_DIR)
	if dir == null:
		push_error("ItemDB: cannot open %s" % ITEM_DIR)
		return
	for file in dir.get_files():
		# Exported builds rewrite .tres to .tres.remap, so strip that first.
		var name := file.trim_suffix(".remap")
		if not name.ends_with(".tres"):
			continue
		var res: Resource = load(ITEM_DIR + name)
		var item := res as ItemData
		if item == null:
			continue
		if item.id.is_empty():
			push_error("ItemDB: %s has no id" % name)
			continue
		if _items.has(item.id):
			push_error("ItemDB: duplicate id '%s' in %s" % [item.id, name])
			continue
		_items[item.id] = item


func has_item(id: String) -> bool:
	return _items.has(id)


func get_item(id: String) -> ItemData:
	return _items.get(id, null)


func display_name(id: String) -> String:
	var item := get_item(id)
	return item.display_name if item != null else id


func icon(id: String) -> Texture2D:
	var item := get_item(id)
	return item.icon if item != null else null


## Falls back to 1 for an unknown id, so a typo cannot silently create an
## infinite stack.
func max_stack(id: String) -> int:
	var item := get_item(id)
	return item.max_stack if item != null else 1


func all_ids() -> Array:
	var ids: Array = _items.keys()
	ids.sort()
	return ids


func count() -> int:
	return _items.size()
