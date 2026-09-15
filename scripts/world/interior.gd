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
## Atlas cells in assets/tiles/interior_tileset.tres. The sheet is a house
## facade, so each side of the room takes the piece drawn for it: horizontal
## planks along the top and bottom, and the frame posts down the sides. Painting
## one tile round all four sides ran the side walls horizontally and left the
## doorway as a tongue of bare floor.
@export var floor_tile := Vector2i(1, 1)
@export var wall_top := Vector2i(1, 0)
@export var wall_bottom := Vector2i(1, 2)
@export var wall_left := Vector2i(0, 1)
@export var wall_right := Vector2i(2, 1)
## A plank wall with an opening cut in it — walkable, because it is the exit.
@export var door_tile := Vector2i(3, 2)

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
			_floor.set_cell(Vector2i(x, y), 0, _tile_for(Vector2i(x, y)))


## Which piece belongs at a cell. The top and bottom rows run right across,
## corners included, so the room keeps a solid band top and bottom and the posts
## only fill the span between — which is how the facade itself is drawn.
func _tile_for(cell: Vector2i) -> Vector2i:
	if cell == _door_cell():
		return door_tile
	if cell.y == 0:
		return wall_top
	if cell.y == room_size.y - 1:
		return wall_bottom
	if cell.x == 0:
		return wall_left
	if cell.x == room_size.x - 1:
		return wall_right
	return floor_tile


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
