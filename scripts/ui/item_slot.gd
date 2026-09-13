class_name ItemSlot
extends Panel

## One inventory slot: icon plus stack count.
##
## Used by both the hotbar and the bag, since a hotbar slot IS an inventory
## slot — there is no second store to keep in sync.

## Which Inventory slot this widget shows.
var slot_index := 0

@onready var _icon: TextureRect = $Icon
@onready var _count: Label = $Count

var _selected := false


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
		return
	_icon.texture = ItemDB.icon(id)
	# A lone item does not need a "1" cluttering the corner.
	_count.text = str(amount) if amount > 1 else ""
	var item := ItemDB.get_item(id)
	tooltip_text = "%s\n%s" % [ItemDB.display_name(id), item.description] if item != null else id


func set_selected(value: bool) -> void:
	if value == _selected:
		return
	_selected = value
	# Tinting the panel's stylebox avoids carrying a second StyleBox around.
	self_modulate = Color(1.7, 1.6, 1.1) if value else Color.WHITE
