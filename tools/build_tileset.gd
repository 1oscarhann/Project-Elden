extends SceneTree

## Builds assets/tiles/island_terrain.tres.
##
## The island is painted as LAYERS, not as one flat grid of terrain rows:
## water underneath everything, then sand, then grass, then woodland, each
## autotiled against emptiness. That is what the Sprout Lands sheets are drawn
## for — their edge pieces are grass-on-transparent, so a grass blob laid over
## sand curves into it instead of meeting it at a hard step.
##
## ⚠️ The corner bits are MEASURED FROM THE ART, not typed out. Each 16px cell
## is probed at its four extreme 2x2 corners: opaque corner = that corner is
## this terrain. Both Grass.png and Tilled_Dirt.png yield a complete 16/16
## corner set that way. A 3px probe does NOT work — the little diamond notches
## that make the inner corners sit exactly on the cell junction, so a wider
## probe straddles them and reports a solid corner.
##
## Every fully-solid cell is registered as its own tile with identical corner
## bits, which is what buys grass texture variety: Godot picks among equally
## good matches, so the interior is drawn from 13 different grass cells rather
## than one repeated tile.
##
## Run with:  godot --headless --path . --script res://tools/build_tileset.gd

const TILE := Vector2i(16, 16)
const WATER_FPS := 0.45

## Terrain indices within the single corner-match terrain set.
const T_SAND := 0
const T_GRASS := 1
const T_WOOD := 2

const SHEETS := {
	"sand": "res://assets/tiles/sand_blob.png",
	"grass": "res://assets/tiles/sprout_lands/Grass.png",
	"wood": "res://assets/tiles/grass_dark.png",
}
## Generated wavy straight-edge variants. They carry the same corner bits as
## the pack's flat edges, so Godot picks between them at random and a run of
## boundary stops being a ruled line. See tools/build_terrain_atlas.gd.
const EDGE_SHEETS := {
	"sand": "res://assets/tiles/sand_edges.png",
	"grass": "res://assets/tiles/grass_edges.png",
	"wood": "res://assets/tiles/wood_edges.png",
}
const WATER := "res://assets/tiles/sprout_lands/Water.png"

const CORNERS := [
	TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER,
	TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER,
	TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER,
	TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER,
]

var _report: Array = []


func _initialize() -> void:
	var ts := TileSet.new()
	ts.tile_size = TILE

	ts.add_physics_layer(0)
	ts.set_physics_layer_collision_layer(0, 1)
	ts.set_physics_layer_collision_mask(0, 1)
	ts.add_navigation_layer(0)

	ts.add_terrain_set(0)
	ts.set_terrain_set_mode(0, TileSet.TERRAIN_MODE_MATCH_CORNERS)
	for i in 3:
		ts.add_terrain(0, i)
	ts.set_terrain_name(0, T_SAND, "sand")
	ts.set_terrain_name(0, T_GRASS, "grass")
	ts.set_terrain_name(0, T_WOOD, "woodland")
	ts.set_terrain_color(0, T_SAND, Color(0.85, 0.74, 0.5))
	ts.set_terrain_color(0, T_GRASS, Color(0.55, 0.74, 0.35))
	ts.set_terrain_color(0, T_WOOD, Color(0.35, 0.52, 0.24))

	# Source 0: the sea. Animated across the sheet's four columns, which ARE
	# four distinct frames — only just (2-4% of pixels differ), which is why the
	# sea reads as static and why the shimmer shader exists on top of them.
	_add_water(ts, 0, WATER, true)
	# Source 1: the same art without collision, painted UNDER the land so the
	# sea is a continuous backdrop without walling the player in on dry ground.
	_add_water(ts, 1, WATER, false)

	var ok := true
	ok = _add_terrain(ts, 2, SHEETS["sand"], T_SAND, true) and ok
	ok = _add_terrain(ts, 3, SHEETS["grass"], T_GRASS, false) and ok
	ok = _add_terrain(ts, 4, SHEETS["wood"], T_WOOD, false) and ok
	# Loose moss patches drawn on transparency. They carry no terrain bits, so
	# they live in their own source and the autotiler can never pick them.
	_add_detail(ts, 5, SHEETS["grass"])
	_add_detail(ts, 6, SHEETS["wood"])
	# Sand is the grass blob re-hued, so it carries the same patches — which is
	# what lets the shoreline be broken up from the sea side too.
	_add_detail(ts, 7, SHEETS["sand"])
	# Only 4 signatures each (the straight edges), so completeness is not
	# required of these — they top up the main sources rather than replace them.
	ok = _add_terrain(ts, 8, EDGE_SHEETS["sand"], T_SAND, true, false) and ok
	ok = _add_terrain(ts, 9, EDGE_SHEETS["grass"], T_GRASS, false, false) and ok
	ok = _add_terrain(ts, 10, EDGE_SHEETS["wood"], T_WOOD, false, false) and ok

	var err := ResourceSaver.save(ts, "res://assets/tiles/island_terrain.tres")
	print("\n".join(_report))
	print("save=", error_string(err))
	quit(0 if ok and err == OK else 1)


## One water source. `solid` decides whether it carries the collision that
## stops the player walking out to sea.
func _add_water(ts: TileSet, id: int, path: String, solid: bool) -> void:
	var src := TileSetAtlasSource.new()
	src.texture = load(path)
	src.texture_region_size = TILE
	ts.add_source(src, id)
	var coord := Vector2i.ZERO
	src.create_tile(coord)
	src.set_tile_animation_frames_count(coord, 4)
	for frame in 4:
		src.set_tile_animation_frame_duration(coord, frame, WATER_FPS)
	if solid:
		var data := src.get_tile_data(coord, 0)
		data.add_collision_polygon(0)
		data.set_collision_polygon_points(0, 0, PackedVector2Array([
			Vector2(-8, -8), Vector2(8, -8), Vector2(8, 8), Vector2(-8, 8)]))
	_report.append("water src %d %-16s animated=4 solid=%s" % [id, path.get_file(), solid])


## One autotiled land terrain, with its corner bits read off the art.
func _add_terrain(ts: TileSet, id: int, path: String, terrain: int, navigable: bool,
		require_complete := true) -> bool:
	var tex: Texture2D = load(path)
	if tex == null:
		push_error("Missing sheet %s" % path)
		return false
	var img := tex.get_image()
	img.convert(Image.FORMAT_RGBA8)
	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = TILE
	ts.add_source(src, id)

	var found := {}
	var cols := img.get_width() / TILE.x
	var rows := img.get_height() / TILE.y
	for cy in rows:
		for cx in cols:
			var coord := Vector2i(cx, cy)
			var bits := _corner_bits(img, coord)
			# 0000 is a blank cell in the sheet, not a tile.
			if bits == 0:
				continue
			src.create_tile(coord)
			var data := src.get_tile_data(coord, 0)
			data.terrain_set = 0
			data.terrain = terrain
			for i in 4:
				if bits & (1 << i):
					data.set_terrain_peering_bit(CORNERS[i], terrain)
			if navigable:
				var nav := NavigationPolygon.new()
				nav.vertices = PackedVector2Array([
					Vector2(-8, -8), Vector2(8, -8), Vector2(8, 8), Vector2(-8, 8)])
				nav.add_polygon(PackedInt32Array([0, 1, 2, 3]))
				data.set_navigation_polygon(0, nav)
			found[bits] = int(found.get(bits, 0)) + 1

	var missing: Array = []
	for b in range(1, 16):
		if not found.has(b):
			missing.append(b)
	_report.append("terrain src %d %-16s %d tiles, %d/15 corner cases%s"
		% [id, path.get_file(), src.get_tiles_count(), found.size(),
			"" if missing.is_empty() or not require_complete else "  MISSING %s" % str(missing)])
	if require_complete:
		_report.append("    solid-interior variants (texture variety): %d" % int(found.get(15, 0)))
		return missing.is_empty()
	_report.append("    tops up signatures %s" % str(found.keys()))
	return not found.is_empty()


## The loose patch cells: content, but no corner is this terrain. They are the
## sheet's decoration, and they are the only thing in the pack that can break up
## a straight biome edge — the straight-edge TILES do not curve at all (their
## transparent run is a flat 2px on every row), so the boundary is only ever as
## organic as what is scattered along it.
func _add_detail(ts: TileSet, id: int, path: String) -> void:
	var tex: Texture2D = load(path)
	var img := tex.get_image()
	img.convert(Image.FORMAT_RGBA8)
	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = TILE
	ts.add_source(src, id)
	var cols := img.get_width() / TILE.x
	var rows := img.get_height() / TILE.y
	var n := 0
	for cy in rows:
		for cx in cols:
			var coord := Vector2i(cx, cy)
			if _corner_bits(img, coord) != 0:
				continue
			# Skip blank cells; a patch has to actually have ink in it.
			var ink := 0
			for y in TILE.y:
				for x in TILE.x:
					if img.get_pixel(cx * TILE.x + x, cy * TILE.y + y).a > 0.16:
						ink += 1
			if ink < 12:
				continue
			src.create_tile(coord)
			n += 1
	_report.append("detail  src %d %-16s %d loose patches" % [id, path.get_file(), n])


## Probe the four extreme corners of a cell. 2x2 px, right in the corner —
## anything wider straddles the inner-corner notches and misreads them.
func _corner_bits(img: Image, coord: Vector2i) -> int:
	var base := coord * TILE
	var bits := 0
	var offsets := [Vector2i(0, 0), Vector2i(14, 0), Vector2i(0, 14), Vector2i(14, 14)]
	for i in 4:
		var o: Vector2i = base + offsets[i]
		var opaque := 0
		for y in 2:
			for x in 2:
				if img.get_pixel(o.x + x, o.y + y).a > 0.16:
					opaque += 1
		if opaque >= 3:
			bits |= 1 << i
	return bits
