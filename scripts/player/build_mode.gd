extends Node2D

## Build mode: a grid-snapped ghost of the selected buildable, placed on click.
##
## Lives under the Player. It never touches the world directly — it asks
## whichever Room the player is standing in whether a spot is free and to do the
## placing, so building inside an interior would work the same way if a room
## chose to allow it.
##
## What is buildable is a data question: an item is placeable when its ItemData
## carries a `placed_scene`.

const VALID := Color(0.45, 1.0, 0.5, 0.55)
const BLOCKED := Color(1.0, 0.4, 0.35, 0.5)

## How far from the player a building may be placed, in tiles.
@export var max_distance_tiles := 6.0

var _active := false
var _ghost: Sprite2D
var _item_id := ""
## Set when build mode was opened for a particular item (from the journal),
## rather than for whatever the hotbar has selected. Cleared when it is placed
## or build mode is left, so the hotbar takes over again afterwards.
var _forced_item := ""
var _cell := Vector2i.ZERO
var _valid := false


func _ready() -> void:
	_ghost = Sprite2D.new()
	_ghost.z_index = 50
	_ghost.visible = false
	add_child(_ghost)
	Inventory.inventory_changed.connect(_on_inventory_changed)


func is_active() -> bool:
	return _active


## Start placing a specific item, rather than whatever the hotbar happens to
## have selected. This is how the journal's Build tab reaches build mode — it
## changes how building is REACHED, not how it works.
func begin(item_id: String) -> void:
	var item := ItemDB.get_item(item_id)
	if item == null or not item.is_placeable() or not Inventory.has(item_id, 1):
		return
	_forced_item = item_id
	set_active(true)


func _unhandled_input(event: InputEvent) -> void:
	# ⚠️ `toggle_build` is NOT handled here any more — it opens the journal on
	# its Build tab, which is where you choose what to place. Build mode is
	# entered from there via begin(), and Esc leaves it.
	if not _active:
		return
	if event.is_action_pressed("ui_cancel"):
		set_active(false)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("place_building"):
		if _try_place():
			get_viewport().set_input_as_handled()


func set_active(value: bool) -> void:
	if value == _active:
		return
	_active = value
	_ghost.visible = false
	if _active:
		_rebuild_ghost()
	else:
		_forced_item = ""


func _process(_delta: float) -> void:
	if not _active:
		return
	var room := _room()
	var item := ItemDB.get_item(_item_id)
	if room == null or item == null or not item.is_placeable():
		_ghost.visible = false
		return
	# The ghost follows the mouse, clamped to arm's reach so you cannot build
	# across the island.
	var target := get_global_mouse_position()
	var tile := float(_tile_size())
	var limit := max_distance_tiles * tile
	var offset := target - global_position
	if offset.length() > limit:
		target = global_position + offset.normalized() * limit
	_cell = room.world_to_cell(target)
	# A multi-tile footprint is centred on the cursor horizontally and sits with
	# its base on the cursor row, matching where it will actually land.
	var origin := _cell - Vector2i(int(item.placed_footprint.x) / 2, maxi(1, int(item.placed_footprint.y)) - 1)
	_valid = room.can_build(origin, item.placed_footprint) and Inventory.has(_item_id, 1)
	_ghost.global_position = room.footprint_anchor(origin, item.placed_footprint)
	_ghost.visible = true
	_ghost.modulate = VALID if _valid else BLOCKED


func _try_place() -> bool:
	var room := _room()
	var item := ItemDB.get_item(_item_id)
	if room == null or item == null or not item.is_placeable() or not _valid:
		return false
	var origin := _cell - Vector2i(int(item.placed_footprint.x) / 2, maxi(1, int(item.placed_footprint.y)) - 1)
	# Take the item only once the world has actually accepted the building.
	if room.build_at(item.placed_scene, origin, item.placed_footprint, item.id) == null:
		return false
	Inventory.remove_item(_item_id, 1)
	Audio.play("place")
	return true


func _on_inventory_changed() -> void:
	if _active:
		_rebuild_ghost()


## The ghost wears the placed scene's own sprite, so it always matches what
## will appear — no separate preview art to keep in sync.
func _rebuild_ghost() -> void:
	# A journal pick wins over the hotbar, but only while it is still held.
	if not _forced_item.is_empty() and Inventory.has(_forced_item, 1):
		_item_id = _forced_item
	else:
		_forced_item = ""
		_item_id = Inventory.selected_item_id()
	var item := ItemDB.get_item(_item_id)
	if item == null or not item.is_placeable():
		_ghost.texture = null
		_ghost.visible = false
		return
	var sample: Node = item.placed_scene.instantiate()
	var sprite := sample.get_node_or_null("Sprite") as Sprite2D
	if sprite != null:
		_ghost.texture = sprite.texture
		_ghost.offset = sprite.offset
		_ghost.scale = sprite.scale
	sample.free()


func _room() -> World:
	var rooms := get_tree().get_nodes_in_group(RoomManager.GROUP)
	if rooms.is_empty():
		return null
	return (rooms[0] as RoomManager).current_room() as World


func _tile_size() -> int:
	return 16
