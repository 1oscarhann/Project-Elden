class_name ItemSlot
extends Panel

## One inventory slot: icon plus stack count, clickable and draggable.
##
## Used by both the hotbar and the journal's bag grid, since a hotbar slot IS an
## inventory slot — there is no second store to keep in sync. That is also why
## dragging between the two works with no special case: they are the same array.
##
## The slot owns no item state. It reads Inventory by index and asks Inventory
## to change things, so two widgets showing the same index can never disagree.

## Emitted when the slot is clicked, so the journal can act without this widget
## needing to know what a journal is.
signal activated(index: int)

## Which Inventory slot this widget shows.
var slot_index := 0

@onready var _icon: TextureRect = $Icon
@onready var _count: Label = $Count

var _selected := false
## Dimmed while its item is being dragged somewhere else.
var _dragging := false
## Lit while a valid drop hovers over it.
var _drop_target := false


func setup(index: int) -> void:
	slot_index = index
	if is_node_ready():
		refresh()


func refresh() -> void:
	var entry := Inventory.slot(slot_index)
	var id: String = entry["id"]
	var amount: int = entry["count"]
	if amount <= 0:
		_icon.texture = null
		_count.text = ""
		tooltip_text = ""
		_apply_tint()
		return
	_icon.texture = ItemDB.icon(id)
	# A lone item does not need a "1" cluttering the corner.
	_count.text = str(amount) if amount > 1 else ""
	var item := ItemDB.get_item(id)
	tooltip_text = "%s\n%s" % [ItemDB.display_name(id), item.description] if item != null else id
	var action := _primary_action()
	if action != "":
		tooltip_text += "\n[click to %s]" % action.to_lower()
	_apply_tint()


## What clicking this slot will do, or "" for an item with no primary action.
## Read from the item's own data — nothing here knows what a berry is.
func _primary_action() -> String:
	if Inventory.is_slot_empty(slot_index):
		return ""
	if Inventory.slot_is_usable(slot_index):
		var item := ItemDB.get_item(Inventory.slot(slot_index)["id"])
		return "Eat" if item.category == ItemData.Category.FOOD else "Use"
	if Inventory.slot_is_placeable(slot_index):
		return "Build"
	return ""


func set_selected(value: bool) -> void:
	if value == _selected:
		return
	_selected = value
	_apply_tint()


## One place decides the slot's tint, or the three states fight each other.
func _apply_tint() -> void:
	if _dragging:
		self_modulate = Color(1, 1, 1, 0.35)
	elif _drop_target:
		self_modulate = Color(1.2, 1.7, 1.2)
	elif _selected:
		self_modulate = Color(1.7, 1.6, 1.1)
	else:
		self_modulate = Color.WHITE
	_icon.modulate.a = 0.35 if _dragging else 1.0


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		activated.emit(slot_index)


# --- drag and drop ----------------------------------------------------------

## The drag payload is just the source index: the receiving slot asks Inventory
## what is there, so nothing about the item is copied and can go stale.
func _get_drag_data(_at: Vector2) -> Variant:
	if Inventory.is_slot_empty(slot_index):
		return null
	var preview := TextureRect.new()
	preview.texture = _icon.texture
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.size = Vector2(28, 28)
	# Centre it under the cursor rather than hanging off the corner.
	var holder := Control.new()
	holder.add_child(preview)
	preview.position = -preview.size * 0.5
	set_drag_preview(holder)
	_set_dragging(true)
	return {"slot": slot_index}


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	var ok: bool = data is Dictionary and data.has("slot") and int(data["slot"]) != slot_index
	_set_drop_target(ok)
	return ok


func _drop_data(_at: Vector2, data: Variant) -> void:
	_set_drop_target(false)
	Inventory.move_slot(int(data["slot"]), slot_index)


func _notification(what: int) -> void:
	# Godot does not tell a slot its drag ended, so every slot clears itself
	# when any drag anywhere finishes. Without this the source stays dimmed
	# after a drag is cancelled.
	if what == NOTIFICATION_DRAG_END:
		_set_dragging(false)
		_set_drop_target(false)
	elif what == NOTIFICATION_MOUSE_EXIT:
		_set_drop_target(false)


func _set_dragging(value: bool) -> void:
	if value == _dragging:
		return
	_dragging = value
	_apply_tint()


func _set_drop_target(value: bool) -> void:
	if value == _drop_target:
		return
	_drop_target = value
	_apply_tint()
