extends Node

## The player's item storage: a flat array of stacks, the first few of which
## are the hotbar.
##
## Autoload. Replaces the placeholder material dictionary GameState carried
## through Phases 4-5. Stack limits come from ItemDB, so this file never
## learns what any particular item is.

signal inventory_changed
## Fired on a gain, for pickup feedback. Carries what actually landed.
signal item_gained(id: String, count: int)

const SLOT_COUNT := 24
## The first HOTBAR_SIZE slots are the hotbar, so a hotbar slot IS an inventory
## slot — there is no separate store to keep in sync.
const HOTBAR_SIZE := 8

var _slots: Array[Dictionary] = []
var selected_hotbar := 0


func _ready() -> void:
	clear()


func clear() -> void:
	_slots.clear()
	for i in SLOT_COUNT:
		_slots.append({"id": "", "count": 0})
	selected_hotbar = 0
	inventory_changed.emit()


## Slot contents as {"id": String, "count": int}. Empty slots have id == "".
func slot(index: int) -> Dictionary:
	if index < 0 or index >= _slots.size():
		return {"id": "", "count": 0}
	return _slots[index].duplicate()


func is_slot_empty(index: int) -> bool:
	return slot(index)["count"] <= 0


## Adds what it can and returns the LEFTOVER that would not fit, so a caller
## can decide whether to drop it on the ground.
func add_item(id: String, count: int = 1) -> int:
	if id.is_empty() or count <= 0:
		return maxi(count, 0)
	var remaining := count
	var limit := ItemDB.max_stack(id)

	# Top up existing stacks before opening a new slot, or a dozen part-stacks
	# of the same thing would fill the bag.
	for i in _slots.size():
		if remaining <= 0:
			break
		if _slots[i]["id"] != id:
			continue
		var room: int = limit - int(_slots[i]["count"])
		if room <= 0:
			continue
		var moved: int = mini(room, remaining)
		_slots[i]["count"] = int(_slots[i]["count"]) + moved
		remaining -= moved

	for i in _slots.size():
		if remaining <= 0:
			break
		if int(_slots[i]["count"]) > 0:
			continue
		var moved: int = mini(limit, remaining)
		_slots[i] = {"id": id, "count": moved}
		remaining -= moved

	var added := count - remaining
	if added > 0:
		inventory_changed.emit()
		item_gained.emit(id, added)
	return remaining


## All-or-nothing: removes nothing unless the full count is available, so a
## recipe can never half-consume its ingredients.
func remove_item(id: String, count: int = 1) -> bool:
	if id.is_empty() or count <= 0 or not has(id, count):
		return false
	var remaining := count
	# Drain the smallest stacks first so the bag tidies itself up.
	for i in _order_by_smallest_stack(id):
		if remaining <= 0:
			break
		var taken: int = mini(int(_slots[i]["count"]), remaining)
		_slots[i]["count"] = int(_slots[i]["count"]) - taken
		remaining -= taken
		if int(_slots[i]["count"]) <= 0:
			_slots[i] = {"id": "", "count": 0}
	inventory_changed.emit()
	return true


func count(id: String) -> int:
	var total := 0
	for entry in _slots:
		if entry["id"] == id:
			total += int(entry["count"])
	return total


func has(id: String, needed: int = 1) -> bool:
	return count(id) >= needed


## Free room for this id across part-stacks and empty slots.
func room_for(id: String) -> int:
	var limit := ItemDB.max_stack(id)
	var room := 0
	for entry in _slots:
		if entry["id"] == id:
			room += limit - int(entry["count"])
		elif int(entry["count"]) <= 0:
			room += limit
	return room


func is_full() -> bool:
	for entry in _slots:
		if int(entry["count"]) <= 0:
			return false
	return true


## Every held id and its total, for the HUD and for saving later.
func totals() -> Dictionary:
	var out: Dictionary = {}
	for entry in _slots:
		var id: String = entry["id"]
		if id.is_empty():
			continue
		out[id] = int(out.get(id, 0)) + int(entry["count"])
	return out


func select_hotbar(index: int) -> void:
	var clamped := clampi(index, 0, HOTBAR_SIZE - 1)
	if clamped == selected_hotbar:
		return
	selected_hotbar = clamped
	inventory_changed.emit()


func selected_item_id() -> String:
	return slot(selected_hotbar)["id"]


func _order_by_smallest_stack(id: String) -> Array:
	var indices: Array = []
	for i in _slots.size():
		if _slots[i]["id"] == id and int(_slots[i]["count"]) > 0:
			indices.append(i)
	indices.sort_custom(func(a, b): return int(_slots[a]["count"]) < int(_slots[b]["count"]))
	return indices
