extends CanvasLayer

## The full bag. Toggled with `toggle_inventory` (Tab or I).
##
## Deliberately does NOT pause the game — this is a cozy game, and stopping the
## world to look in your bag is the opposite of relaxed. The grid is built from
## Inventory.SLOT_COUNT rather than placed by hand.

@export var slot_scene: PackedScene
@export var columns := 6
@export var open_seconds := 0.16

@onready var _root: Control = $Root
@onready var _grid: GridContainer = $Root/Window/Layout/Grid

var _slots: Array[ItemSlot] = []
var _open := false
var _tween: Tween


func _ready() -> void:
	_grid.columns = columns
	for i in Inventory.SLOT_COUNT:
		var slot: ItemSlot = slot_scene.instantiate()
		_grid.add_child(slot)
		slot.setup(i)
		_slots.append(slot)
	Inventory.inventory_changed.connect(_refresh)
	_refresh()
	# Start closed without playing the open tween.
	_root.visible = false
	_root.modulate.a = 0.0
	_root.scale = Vector2(0.94, 0.94)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_inventory"):
		toggle()
		get_viewport().set_input_as_handled()
	elif _open and event.is_action_pressed("ui_cancel"):
		set_open(false)
		get_viewport().set_input_as_handled()


func is_open() -> bool:
	return _open


func toggle() -> void:
	set_open(not _open)


func set_open(value: bool) -> void:
	if value == _open:
		return
	_open = value
	if _tween != null and _tween.is_running():
		_tween.kill()
	if _open:
		_refresh()
		_root.visible = true
	# Pivot on the centre so it grows out of the middle rather than a corner.
	_root.pivot_offset = _root.size * 0.5
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_root, "modulate:a", 1.0 if _open else 0.0, open_seconds)
	_tween.tween_property(_root, "scale", Vector2.ONE if _open else Vector2(0.94, 0.94), open_seconds)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT if _open else Tween.EASE_IN)
	if not _open:
		_tween.chain().tween_callback(func(): _root.visible = false)


func _refresh() -> void:
	if not _open:
		return
	for slot in _slots:
		slot.refresh()
		slot.set_selected(slot.slot_index == Inventory.selected_hotbar)
