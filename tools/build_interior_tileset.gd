extends SceneTree

## Builds assets/tiles/interior_tileset.tres for building interiors.
##
## Sources the Sprout Lands wooden-house wall sheet directly — no compositing
## needed, since it already holds solid 16px cells. NOTE: the phase spec called
## for the dungeon pack's walls and floors, but that pack is restricted to fire,
## doors and chests only, so this uses the house sheet instead and matches the
## rest of the game's art.
##
## ⚠️ The sheet is a house FACADE, not an autotile set. Read off the art:
## column 0 is the left frame post (opaque on its RIGHT, transparent left),
## column 2 is the right post (mirrored), column 1 is the plank infill plus the
## cream brick, and (3,2) carries a doorway opening. That orientation drops
## straight into a room — a left wall wants its opaque side facing the interior,
## which is exactly how column 0 is drawn.
##
## Six tiles are registered, not two. The room used to paint ONE horizontal
## plank tile round all four sides, so the side walls ran horizontally, there
## were no corners, and the doorway was a tongue of bare floor.
##
## Run with:  godot --headless --path . --script res://tools/build_interior_tileset.gd

const TILE := Vector2i(16, 16)
const SHEET := "res://assets/tiles/sprout_lands/Wooden_House_Walls_Tilset.png"

## Walkable.
const FLOOR := Vector2i(1, 1)   ## cream brick #e4c79c
## The doorway. Walkable too — it IS the way out, so it must not collide.
const DOOR := Vector2i(3, 2)
## Solid. Top and bottom runs are horizontal planks; the sides are the posts.
const WALL_TOP := Vector2i(1, 0)
const WALL_BOTTOM := Vector2i(1, 2)
const WALL_LEFT := Vector2i(0, 1)
const WALL_RIGHT := Vector2i(2, 1)
const SOLID := [WALL_TOP, WALL_BOTTOM, WALL_LEFT, WALL_RIGHT]
const WALKABLE := [FLOOR, DOOR]


func _initialize() -> void:
	var ts := TileSet.new()
	ts.tile_size = TILE
	ts.add_physics_layer(0)
	ts.set_physics_layer_collision_layer(0, 1)
	ts.set_physics_layer_collision_mask(0, 1)

	var src := TileSetAtlasSource.new()
	src.texture = load(SHEET)
	src.texture_region_size = TILE
	# Added before any tile data is touched, or tiles inherit zero physics
	# layers and every collision polygon silently goes nowhere.
	ts.add_source(src, 0)

	for coord in WALKABLE:
		src.create_tile(coord)
	for coord in SOLID:
		src.create_tile(coord)
		# A side post is mostly transparent, but it is still a wall: the whole
		# cell collides, or the player walks into the gap beside it.
		var data := src.get_tile_data(coord, 0)
		data.add_collision_polygon(0)
		data.set_collision_polygon_points(0, 0, PackedVector2Array([
			Vector2(-8, -8), Vector2(8, -8), Vector2(8, 8), Vector2(-8, 8)]))

	print("save=", error_string(ResourceSaver.save(ts, "res://assets/tiles/interior_tileset.tres")))
	var rt: TileSet = ResourceLoader.load("res://assets/tiles/interior_tileset.tres", "",
		ResourceLoader.CACHE_MODE_IGNORE)
	var rs: TileSetAtlasSource = rt.get_source(0)
	var ok := true
	for coord in SOLID:
		var n := rs.get_tile_data(coord, 0).get_collision_polygons_count(0)
		print("  wall %s polygons=%d (want 1)" % [coord, n])
		ok = ok and n == 1
	for coord in WALKABLE:
		var n := rs.get_tile_data(coord, 0).get_collision_polygons_count(0)
		print("  walkable %s polygons=%d (want 0)" % [coord, n])
		ok = ok and n == 0
	print("%d tiles registered" % rs.get_tiles_count())
	quit(0 if ok else 1)
