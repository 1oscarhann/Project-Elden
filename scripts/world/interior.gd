class_name Interior
extends Room

## The inside of a building. Deliberately larger than the footprint outside —
## "bigger on the inside" is the point.
##
## Being indoors is shelter, so it registers as a heat source for as long as the
## player is in here. That reuses the same counted hook the campfire uses, which
## means the warmth system still has no idea what a building is.

## Whether this interior keeps the player warm.
@export var is_sheltered := true

@export_group("Room")
## Interior size in tiles, INCLUDING the wall ring. Deliberately far bigger
## than the building's footprint outside — that is the whole conceit.
@export var room_size := Vector2i(10, 7)
## Atlas cells in assets/tiles/interior_tileset.tres.
@export var floor_tile := Vector2i(1, 1)
@export var wall_tile := Vector2i(1, 0)

@onready var _floor: TileMapLayer = $Floor
@onready var _backdrop: ColorRect = $Backdrop

## Margin of backdrop painted beyond the walls. The room is only a little
## larger than the viewport, so without this the engine's clear colour shows
## past the corners and the room reads as floating in nothing.
const BACKDROP_PAD := 512.0

var _warming := false


## The room is painted rather than hand-authored, so resizing it is one export
## and the exit door cannot drift out of the wall it sits in.
func _ready() -> void:
	_paint_room()
	_place_fixtures()
	_fit_backdrop()


func _paint_room() -> void:
	for y in room_size.y:
		for x in room_size.x:
			var cell := Vector2i(x, y)
			var edge := x == 0 or y == 0 or x == room_size.x - 1 or y == room_size.y - 1
			# The doorway is a gap in the bottom wall, so it reads as a way out.
			if edge and cell == _door_cell():
				_floor.set_cell(cell, 0, floor_tile)
			else:
				_floor.set_cell(cell, 0, wall_tile if edge else floor_tile)


func _door_cell() -> Vector2i:
	return Vector2i(room_size.x / 2, room_size.y - 1)


## Entry and exit are derived from the painted room, not placed by hand.
func _place_fixtures() -> void:
	var tile: int = _floor.tile_set.tile_size.x
	var door_centre := Vector2(_door_cell() * tile) + Vector2(tile, tile) * 0.5
	$ExitDoor.position = door_centre
	# Stand the player a tile inside, so they do not land on the exit and
	# immediately walk back out.
	$Entry.position = door_centre - Vector2(0, tile * 1.5)


func _fit_backdrop() -> void:
	var tile: int = _floor.tile_set.tile_size.x
	_backdrop.position = Vector2(-BACKDROP_PAD, -BACKDROP_PAD)
	_backdrop.size = Vector2(room_size * tile) + Vector2.ONE * (BACKDROP_PAD * 2.0)


func camera_bounds() -> Rect2:
	var tile: int = _floor.tile_set.tile_size.x if _floor != null else 16
	return Rect2(global_position, Vector2(room_size * tile))


func on_entered() -> void:
	if is_sheltered and not _warming:
		_warming = true
		GameState.add_heat_source()


func on_exited() -> void:
	if _warming:
		_warming = false
		GameState.remove_heat_source()


## Hand the heat source back if this interior is freed while occupied.
func _exit_tree() -> void:
	on_exited()
