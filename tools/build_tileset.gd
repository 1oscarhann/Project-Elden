extends SceneTree

## Builds assets/tiles/island_terrain.tres from the atlas PNG.
##
## Not hand-written because the config is non-trivial: the two water rows are a
## single ANIMATED tile each (their four columns are frames, not variants) and
## carry the collision that stops the player walking into the sea, while the
## four land rows are four static variants with no collision.
##
## Run with:  godot --headless --path . --script res://tools/build_tileset.gd

const TILE := Vector2i(16, 16)
const COLS := 4
const ROWS := 5
## Rows below this are water: animated, and solid.
const LAND_ROW := 2
const WATER_FPS := 0.45


func _initialize() -> void:
	var ts := TileSet.new()
	ts.tile_size = TILE
	ts.add_physics_layer(0)
	ts.set_physics_layer_collision_layer(0, 1)
	ts.set_physics_layer_collision_mask(0, 1)

	var src := TileSetAtlasSource.new()
	src.texture = load("res://assets/tiles/island_terrain.png")
	src.texture_region_size = TILE
	# Must be added before any tile data is touched, or tiles inherit zero
	# physics layers and every collision polygon silently goes nowhere.
	ts.add_source(src, 0)

	var solid := 0
	for row in ROWS:
		if row < LAND_ROW:
			# One animated tile whose frames run across the row.
			var coord := Vector2i(0, row)
			src.create_tile(coord)
			src.set_tile_animation_frames_count(coord, COLS)
			for frame in COLS:
				src.set_tile_animation_frame_duration(coord, frame, WATER_FPS)
			var td := src.get_tile_data(coord, 0)
			td.add_collision_polygon(0)
			td.set_collision_polygon_points(0, 0, PackedVector2Array([
				Vector2(-8, -8), Vector2(8, -8), Vector2(8, 8), Vector2(-8, 8)]))
			solid += 1
		else:
			for col in COLS:
				src.create_tile(Vector2i(col, row))

	print("save=", error_string(ResourceSaver.save(ts, "res://assets/tiles/island_terrain.tres")))

	# Read back and prove the animation and collision actually persisted.
	var rt: TileSet = ResourceLoader.load("res://assets/tiles/island_terrain.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
	var rs: TileSetAtlasSource = rt.get_source(0)
	var animated := 0
	var collide := 0
	for row in ROWS:
		var coord := Vector2i(0, row)
		if rs.has_tile(coord):
			if rs.get_tile_animation_frames_count(coord) > 1:
				animated += 1
			if rs.get_tile_data(coord, 0).get_collision_polygons_count(0) > 0:
				collide += 1
	print("reloaded: %d animated water tiles, %d with collision (expected %d each)"
		% [animated, collide, LAND_ROW])
	quit(0 if animated == LAND_ROW and collide == LAND_ROW else 1)
