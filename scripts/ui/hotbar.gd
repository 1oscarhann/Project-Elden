extends CanvasLayer

## The always-visible row of the first Inventory.HOTBAR_SIZE slots.
##
## Slots are built from the constant rather than placed by hand, so resizing the
## hotbar is a one-line change in Inventory.

@export var slot_scene: PackedScene

@onready var _row: HBoxContainer = $Root/Frame/Row

var _slots: Array[ItemSlot] = []


func _ready() -> void:
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
