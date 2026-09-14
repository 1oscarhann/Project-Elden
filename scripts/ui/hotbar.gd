extends CanvasLayer

## The always-visible row of the first Inventory.HOTBAR_SIZE slots.
##
## Slots are built from the constant rather than placed by hand, so resizing the
## hotbar is a one-line change in Inventory.

## Joined so the pickup feed can ask where a slot is on screen without holding a
## path to this node — it only ever needs an answer, not a reference.
const GROUP := "hotbar"

@export var slot_scene: PackedScene

@onready var _row: HBoxContainer = $Root/Frame/Row

var _slots: Array[ItemSlot] = []


func _ready() -> void:
	add_to_group(GROUP)
	for i in Inventory.HOTBAR_SIZE:
		var slot: ItemSlot = slot_scene.instantiate()
		_row.add_child(slot)
		slot.setup(i)
		_slots.append(slot)
	Inventory.inventory_changed.connect(_refresh)
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	for i in Inventory.HOTBAR_SIZE:
		if event.is_action_pressed("hotbar_%d" % (i + 1)):
			Inventory.select_hotbar(i)
			get_viewport().set_input_as_handled()
			return


func _refresh() -> void:
	for i in _slots.size():
		_slots[i].refresh()
		_slots[i].set_selected(i == Inventory.selected_hotbar)


## Screen-space centre of a hotbar slot, or Vector2.ZERO for an index that is
## not on the hotbar. The pickup flight aims at this.
func slot_centre(index: int) -> Vector2:
	if index < 0 or index >= _slots.size():
		return Vector2.ZERO
	var slot: ItemSlot = _slots[index]
	return slot.global_position + slot.size * 0.5


## Makes the slot the item landed in pop, so the eye is drawn to where it went
## even if the flight itself is missed.
func bump(index: int) -> void:
	if index < 0 or index >= _slots.size():
		return
	var slot: ItemSlot = _slots[index]
	slot.pivot_offset = slot.size * 0.5
	var tween := create_tween()
	tween.tween_property(slot, "scale", Vector2(1.22, 1.22), 0.07)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(slot, "scale", Vector2.ONE, 0.16)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
