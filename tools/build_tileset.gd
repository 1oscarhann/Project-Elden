extends SceneTree

## Builds assets/tiles/island_terrain.tres from the atlas PNG.
##
## Not hand-written because the config is non-trivial: the two water rows are a
## single ANIMATED tile each (their four columns are frames, not variants) and
## carry the collision that stops the player walking into the sea, while the
## four land rows are four static variants with no collision.
##
## Land tiles also carry a NAVIGATION polygon (Phase 9). TileMapLayer bakes
## those into navigation regions by itself, so the island needs no hand-placed
## NavigationRegion2D — and because only land has one, an animal's
## NavigationAgent2D physically cannot path into the sea.
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
	ts.add_navigation_layer(0)

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
				var land := Vector2i(col, row)
				src.create_tile(land)
				# A full-cell nav polygon. Neighbouring cells merge into one
				# mesh, so this is a walkable island, not 4600 islands.
				# Vertices and the polygon are set directly rather than via
				# make_polygons_from_outlines(), which is deprecated in 4.7 —
				# a square needs no triangulation pass anyway.
				var nav := NavigationPolygon.new()
				nav.vertices = PackedVector2Array([
					Vector2(-8, -8), Vector2(8, -8), Vector2(8, 8), Vector2(-8, 8)])
				nav.add_polygon(PackedInt32Array([0, 1, 2, 3]))
				src.get_tile_data(land, 0).set_navigation_polygon(0, nav)

	print("save=", error_string(ResourceSaver.save(ts, "res://assets/tiles/island_terrain.tres")))

	# Read back and prove the animation and collision actually persisted.
	var rt: TileSet = ResourceLoader.load("res://assets/tiles/island_terrain.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
	var rs: TileSetAtlasSource = rt.get_source(0)
	var animated := 0
	var collide := 0
	var navigable := 0
	var water_navigable := 0
	for row in ROWS:
		var coord := Vector2i(0, row)
		if not rs.has_tile(coord):
			continue
		if rs.get_tile_animation_frames_count(coord) > 1:
			animated += 1
		var data := rs.get_tile_data(coord, 0)
		if data.get_collision_polygons_count(0) > 0:
			collide += 1
		var nav_poly := data.get_navigation_polygon(0)
		# Non-null is not enough — an empty NavigationPolygon serialises fine
		# and silently contributes nothing to the mesh.
		if nav_poly != null and nav_poly.get_polygon_count() > 0:
			if row < LAND_ROW:
				water_navigable += 1
			else:
				navigable += 1
	var land_rows := ROWS - LAND_ROW
	print("reloaded: %d animated water tiles, %d with collision (expected %d each), %d/%d land rows navigable, %d water rows navigable (expected 0)"
		% [animated, collide, LAND_ROW, navigable, land_rows, water_navigable])
	quit(0 if animated == LAND_ROW and collide == LAND_ROW \
		and navigable == land_rows and water_navigable == 0 else 1)
