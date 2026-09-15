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


## --- direct slot manipulation ----------------------------------------------
##
## Everything below works on ANY slot, hotbar or not. Before these existed the
## only item you could act on was the selected hotbar item, so anything sitting
## in the bag was dead weight until you shuffled it forward.

## Swaps two slots outright. Used by drag-and-drop when the two cannot merge.
func swap_slots(a: int, b: int) -> void:
	if a == b or not _valid(a) or not _valid(b):
		return
	var keep := _slots[a]
	_slots[a] = _slots[b]
	_slots[b] = keep
	inventory_changed.emit()


## Pours `from` into `to` when they hold the same item, respecting max_stack.
## Returns true if anything moved. A partial pour leaves the remainder behind
## rather than destroying it.
func merge_slots(from: int, to: int) -> bool:
	if from == to or not _valid(from) or not _valid(to):
		return false
	var id: String = _slots[from]["id"]
	if id.is_empty() or _slots[to]["id"] != id:
		return false
	var room: int = ItemDB.max_stack(id) - int(_slots[to]["count"])
	if room <= 0:
		return false
	var moved: int = mini(room, int(_slots[from]["count"]))
	_slots[to]["count"] = int(_slots[to]["count"]) + moved
	_slots[from]["count"] = int(_slots[from]["count"]) - moved
	if int(_slots[from]["count"]) <= 0:
		_slots[from] = {"id": "", "count": 0}
	inventory_changed.emit()
	return true


## What a drag from one slot onto another should do: stack them if they can
## stack, otherwise swap. One call so every drop target behaves the same.
func move_slot(from: int, to: int) -> void:
	if merge_slots(from, to):
		return
	swap_slots(from, to)


## Throws away `count` from one slot. Deliberately destructive and deliberately
## not "drop on the ground" — there is no item entity to drop into the world.
func discard_slot(index: int, count: int = -1) -> bool:
	if not _valid(index) or int(_slots[index]["count"]) <= 0:
		return false
	var taking: int = int(_slots[index]["count"]) if count < 0 else mini(count, int(_slots[index]["count"]))
	_slots[index]["count"] = int(_slots[index]["count"]) - taking
	if int(_slots[index]["count"]) <= 0:
		_slots[index] = {"id": "", "count": 0}
	inventory_changed.emit()
	return true


## Uses the item in ANY slot — the whole point of this block. Consuming is
## GameState's business; this only spends the item if it actually did something.
func use_slot(index: int) -> bool:
	if not _valid(index):
		return false
	var id: String = _slots[index]["id"]
	if id.is_empty() or int(_slots[index]["count"]) <= 0:
		return false
	if not GameState.consume(id):
		return false
	discard_slot(index, 1)
	return true


## True when the item in this slot has a meaningful primary action.
func slot_is_usable(index: int) -> bool:
	var item := ItemDB.get_item(slot(index)["id"])
	if item == null:
		return false
	return item.stat("warmth", 0.0) > 0.0 or item.stat("hunger", 0.0) > 0.0 \
		or item.stat("thirst", 0.0) > 0.0


func slot_is_placeable(index: int) -> bool:
	var item := ItemDB.get_item(slot(index)["id"])
	return item != null and item.is_placeable()


func _valid(index: int) -> bool:
	return index >= 0 and index < _slots.size()


## --- persistence -----------------------------------------------------------

## Saved as the raw slot array rather than totals, because WHERE a thing sits
## is part of the state: the first eight slots are the hotbar.
func save_data() -> Dictionary:
	var slots: Array = []
	for entry in _slots:
		slots.append({"id": entry["id"], "count": int(entry["count"])})
	return {"slots": slots, "selected_hotbar": selected_hotbar}


func load_data(data: Dictionary) -> void:
	clear()
	var slots: Array = data.get("slots", [])
	for i in mini(slots.size(), _slots.size()):
		var entry: Dictionary = slots[i]
		var id := String(entry.get("id", ""))
		var count := int(entry.get("count", 0))
		# Drop anything whose item no longer exists rather than carrying a
		# phantom id the rest of the game cannot resolve.
		if id.is_empty() or count <= 0 or not ItemDB.has_item(id):
			continue
		_slots[i] = {"id": id, "count": mini(count, ItemDB.max_stack(id))}
	selected_hotbar = clampi(int(data.get("selected_hotbar", 0)), 0, HOTBAR_SIZE - 1)
	inventory_changed.emit()


func _order_by_smallest_stack(id: String) -> Array:
	var indices: Array = []
	for i in _slots.size():
		if _slots[i]["id"] == id and int(_slots[i]["count"]) > 0:
			indices.append(i)
	indices.sort_custom(func(a, b): return int(_slots[a]["count"]) < int(_slots[b]["count"]))
	return indices
