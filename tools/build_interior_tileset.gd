extends SceneTree

## Builds assets/tiles/interior_tileset.tres for building interiors.
##
## Sources the Sprout Lands wooden-house wall sheet directly — no compositing
## needed, since it already holds solid 16px cells. NOTE: the phase spec called
## for the dungeon pack's walls and floors, but that pack is restricted to fire,
## doors and chests only, so this uses the house sheet instead and matches the
## rest of the game's art.
##
## Row 0 = floor (cream brick, walkable), row 1 = wall (planks, solid).
##
## Run with:  godot --headless --path . --script res://tools/build_interior_tileset.gd

const TILE := Vector2i(16, 16)
const SHEET := "res://assets/tiles/sprout_lands/Wooden_House_Walls_Tilset.png"
## Cells verified fully opaque by scanning the sheet.
const FLOOR := Vector2i(1, 1)   ## cream brick #e4c79c
const WALL := Vector2i(1, 0)    ## brown planks #a87b61


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

	src.create_tile(FLOOR)
	src.create_tile(WALL)
	var wall := src.get_tile_data(WALL, 0)
	wall.add_collision_polygon(0)
	wall.set_collision_polygon_points(0, 0, PackedVector2Array([
		Vector2(-8, -8), Vector2(8, -8), Vector2(8, 8), Vector2(-8, 8)]))

	print("save=", error_string(ResourceSaver.save(ts, "res://assets/tiles/interior_tileset.tres")))
	var rt: TileSet = ResourceLoader.load("res://assets/tiles/interior_tileset.tres", "",
		ResourceLoader.CACHE_MODE_IGNORE)
	var rs: TileSetAtlasSource = rt.get_source(0)
	var solid := rs.get_tile_data(WALL, 0).get_collision_polygons_count(0)
	var walkable := rs.get_tile_data(FLOOR, 0).get_collision_polygons_count(0)
	print("reloaded: wall polygons=%d (want 1), floor polygons=%d (want 0)" % [solid, walkable])
	quit(0 if solid == 1 and walkable == 0 else 1)
