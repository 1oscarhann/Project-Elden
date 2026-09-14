class_name IslandGenerator
extends Resource

## Produces the terrain grid for one island.
##
## Deliberately knows nothing about TileMaps, textures or the scene tree: it
## takes parameters and returns a grid of Terrain values. Swapping in a
## different algorithm (hand-authored map, different noise, whatever) means
## replacing this resource and touching nothing in world.gd.

## Row order here must match the row order of assets/tiles/island_terrain.png
## and of tools/build_terrain_atlas.gd.
##
## There is deliberately NO hill or stone terrain. Stone comes from boulders
## scattered on the ground as Harvestable nodes, not from a mined biome — the
## island is sea, beach, grass and woodland, and nothing else.
enum Terrain { DEEP_WATER, SHALLOW_WATER, SAND, GRASS, FOREST }

## Terrain values at or above this are dry land the player can stand on.
const FIRST_WALKABLE := Terrain.SAND

@export_group("Shape")
@export var map_size := Vector2i(96, 96)
## Landmass size as a fraction of the map's short side.
@export_range(0.1, 1.5) var island_radius := 1.15
## How sharply the coast falls away. Higher = rounder, steeper-sided island.
@export_range(0.5, 6.0) var falloff_power := 2.4

@export_group("Seed")
@export var noise_seed := 20240612
## Re-roll every run instead of using noise_seed.
@export var randomize_seed := false

@export_group("Elevation bands")
## Elevation thresholds, low to high. Anything under shallow_level is deep
## water; anything at or above land_level is dry land.
@export_range(0.0, 1.0) var shallow_level := 0.22
@export_range(0.0, 1.0) var land_level := 0.30

@export_group("Beaches")
## ⚠️ Sand is DISTANCE TO WATER, not an elevation band.
##
## As a band between two elevations it appeared wherever the terrain happened
## to sit in that range — which on a flat inland plateau meant broad beige
## patches in the middle of the island, with nothing coastal about them.
## Measuring out from the water instead guarantees beaches ring the coast and
## can never appear inland.
@export_range(1, 8) var beach_width := 2

@export_group("Land cover")
## A second noise field thickens land into woodland in patches, so trees form
## groves rather than scattering evenly.
@export_range(0.0, 1.0) var forest_threshold := 0.52
## ⚠️ Keep this LOW. At 0.09 a grove was about 11 tiles across and speckly,
## and speckle autotiles into hard little rectangles — there is no tile that
## can draw a one-cell-wide region softly. Large, smooth regions are what let
## the edge tiles actually describe a curve.
@export_range(0.005, 0.2) var cover_frequency := 0.026
## Majority-filter passes over the woodland mask. Removes lone cells and
## one-tile spits, which are the shapes that read as blocky.
@export_range(0, 6) var cover_smoothing := 3
## ⚠️ Smoothing alone still leaves a handful of lone cells and pairs, and a
## one-tile grove is exactly the hard little square this was all meant to stop:
## there is no edge for a tile to draw, only corners meeting corners. Any
## woodland region smaller than this is dissolved back into grass.
@export_range(1, 64) var min_grove_cells := 10

## The seed actually used for the most recent generate() call.
var last_seed := 0


## Returns rows of PackedByteArray, indexed grid[y][x], holding Terrain values.
func generate() -> Array:
	last_seed = randi() if randomize_seed else noise_seed

	var elevation := FastNoiseLite.new()
	elevation.seed = last_seed
	elevation.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	elevation.frequency = 0.035
	elevation.fractal_octaves = 4

	var cover := FastNoiseLite.new()
	cover.seed = last_seed + 1
	cover.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	cover.frequency = cover_frequency
	cover.fractal_octaves = 2

	var centre := Vector2(map_size) * 0.5
	var max_radius: float = minf(centre.x, centre.y) * island_radius

	# 1. Water or land, from the shaped elevation field.
	var height: Array = []
	for y in map_size.y:
		var row := PackedFloat32Array()
		row.resize(map_size.x)
		for x in map_size.x:
			row[x] = _elevation_at(elevation, Vector2(x + 0.5, y + 0.5), centre, max_radius)
		height.append(row)

	# 2. The land mask, OPENED so every land cell sits in a full 2x2 block of
	# land. See _open_2x2 — this is the shape the tileset can actually draw,
	# and it has to happen before the beach is measured or the beach ring would
	# be computed against a coastline that is about to change.
	var land: Array = []
	for y in map_size.y:
		var row := PackedByteArray()
		row.resize(map_size.x)
		var heights: PackedFloat32Array = height[y]
		for x in map_size.x:
			row[x] = 1 if heights[x] >= land_level else 0
		land.append(row)
	_open_2x2(land)

	# 3. How far each land cell is from open water, which is what makes a beach.
	var to_water := _distance_to_water(land)

	# 4. Woodland mask. ⚠️ It has to know about the beach BEFORE it is cleaned
	# up: the beach ring cuts through the mask, so a filter run on the raw mask
	# sees two big groves where the finished map has thirteen fragments, and
	# dutifully drops none of the specks the slicing created.
	var forest := _forest_mask(cover, land, to_water)

	# 5. The two inner masks get the same treatment, outermost first. Each is a
	# separate TileMapLayer painted against emptiness, so each has to satisfy
	# the 2x2 rule in its own right — a grass region one cell wide is just as
	# undrawable as a one-cell island.
	var inland: Array = []
	for y in map_size.y:
		var row := PackedByteArray()
		row.resize(map_size.x)
		for x in map_size.x:
			row[x] = 1 if int(land[y][x]) == 1 and int(to_water[y][x]) > beach_width else 0
		inland.append(row)
	_open_2x2(inland)

	# Woodland can only be where grass is, so re-mask it before opening it:
	# opening the inland mask may just have turned some of it into beach.
	for y in map_size.y:
		for x in map_size.x:
			if int(inland[y][x]) == 0:
				forest[y][x] = 0
	_open_2x2(forest)

	var grid: Array = []
	for y in map_size.y:
		var row := PackedByteArray()
		row.resize(map_size.x)
		var heights: PackedFloat32Array = height[y]
		for x in map_size.x:
			if int(land[y][x]) == 0:
				# Depth is still classified, but nothing draws it differently —
				# the pack has no deep-to-shallow transition art.
				row[x] = Terrain.DEEP_WATER if heights[x] < shallow_level \
					else Terrain.SHALLOW_WATER
			elif int(inland[y][x]) == 0:
				row[x] = Terrain.SAND
			elif int(forest[y][x]) == 1:
				row[x] = Terrain.FOREST
			else:
				row[x] = Terrain.GRASS
		grid.append(row)
	return grid


## Morphological opening with a 2x2 structuring element, run to a fixed point.
## Clears any cell of `mask` that does not belong to at least one full 2x2 block
## of set cells, and returns how many it cleared.
##
## ⚠️ This is not cosmetic tidying — it is what makes the mask DRAWABLE.
##
## The tileset is a 16-signature corner-match blob set: a tile shows terrain in
## whichever of its four corners are set, and a corner is set only when all four
## cells meeting at that corner are the same terrain. So a cell that is in no
## 2x2 block has no corner set at all, its required signature is 0000, and there
## is simply no tile for it — bits == 0 is a blank cell in the sheet. Godot then
## substitutes the closest match, which is a single rounded wedge, and a
## one-tile-wide spit renders as a chain of disconnected nubs while a lone cell
## renders as one corner of a blob floating on its own.
##
## Measured on the shipped island before this existed: 38 wrong tiles on sand
## and 26 on grass, of which 3 were lone cells and 40 were one cell wide.
##
## It has to iterate: clearing a cell can leave its neighbour in no 2x2 block
## either, so one pass fixes the strip's middle and leaves new nubs at its ends.
func _open_2x2(mask: Array) -> int:
	var cleared := 0
	while true:
		var doomed: Array[Vector2i] = []
		for y in map_size.y:
			for x in map_size.x:
				if int(mask[y][x]) == 0:
					continue
				if not _in_2x2_block(mask, x, y):
					doomed.append(Vector2i(x, y))
		if doomed.is_empty():
			break
		for c in doomed:
			mask[c.y][c.x] = 0
		cleared += doomed.size()
	return cleared


## True when (x, y) is part of any of the four 2x2 blocks that contain it.
func _in_2x2_block(mask: Array, x: int, y: int) -> bool:
	for oy in [-1, 0]:
		for ox in [-1, 0]:
			var solid := true
			for dy in 2:
				for dx in 2:
					var nx: int = x + ox + dx
					var ny: int = y + oy + dy
					if nx < 0 or ny < 0 or nx >= map_size.x or ny >= map_size.y \
							or int(mask[ny][nx]) == 0:
						solid = false
						break
				if not solid:
					break
			if solid:
				return true
	return false


## Woodland mask, thresholded then majority-filtered. The filter is the point:
## raw thresholded noise leaves lone cells and one-tile spits, and there is no
## tile in any autotile set that draws those as anything but a hard rectangle.
func _forest_mask(cover: FastNoiseLite, land: Array, to_water: Array) -> Array:
	# Only cells that can actually END UP woodland: dry land, past the beach.
	var eligible: Array = []
	for y in map_size.y:
		var row := PackedByteArray()
		row.resize(map_size.x)
		for x in map_size.x:
			var ok: bool = int(land[y][x]) == 1 and int(to_water[y][x]) > beach_width
			row[x] = 1 if ok else 0
		eligible.append(row)

	var mask: Array = []
	for y in map_size.y:
		var row := PackedByteArray()
		row.resize(map_size.x)
		for x in map_size.x:
			var on: bool = int(eligible[y][x]) == 1 \
				and _unit(cover.get_noise_2d(x, y)) >= forest_threshold
			row[x] = 1 if on else 0
		mask.append(row)

	for pass_index in cover_smoothing:
		var next: Array = []
		for y in map_size.y:
			var row := PackedByteArray()
			row.resize(map_size.x)
			for x in map_size.x:
				var neighbours := 0
				for dy in [-1, 0, 1]:
					for dx in [-1, 0, 1]:
						if dx == 0 and dy == 0:
							continue
						var nx: int = x + dx
						var ny: int = y + dy
						if nx < 0 or ny < 0 or nx >= map_size.x or ny >= map_size.y:
							continue
						neighbours += int(mask[ny][nx])
				# Five of eight agreeing flips the cell; anything less leaves it.
				if neighbours >= 5:
					row[x] = 1
				elif neighbours <= 3:
					row[x] = 0
				else:
					row[x] = mask[y][x]
				# Smoothing must never push woodland back onto the beach.
				if int(eligible[y][x]) == 0:
					row[x] = 0
			next.append(row)
		mask = next
	return _drop_small_regions(mask)


## Dissolves woodland regions below min_grove_cells back into grass.
func _drop_small_regions(mask: Array) -> Array:
	var seen := {}
	for y in map_size.y:
		for x in map_size.x:
			var start := Vector2i(x, y)
			if seen.has(start) or int(mask[y][x]) == 0:
				continue
			# Flood the region, remembering it, then judge it by size.
			var queue: Array[Vector2i] = [start]
			var region: Array[Vector2i] = []
			seen[start] = true
			while not queue.is_empty():
				var c: Vector2i = queue.pop_back()
				region.append(c)
				for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					var n: Vector2i = c + offset
					if n.x < 0 or n.y < 0 or n.x >= map_size.x or n.y >= map_size.y:
						continue
					if seen.has(n) or int(mask[n.y][n.x]) == 0:
						continue
					seen[n] = true
					queue.append(n)
			if region.size() >= min_grove_cells:
				continue
			for c in region:
				mask[c.y][c.x] = 0
	return mask


## Breadth-first distance from every land cell to the nearest water cell,
## capped — we only care about the first few rings.
func _distance_to_water(land: Array) -> Array:
	var limit: int = beach_width + 1
	var dist: Array = []
	var frontier: Array[Vector2i] = []
	for y in map_size.y:
		var row := PackedByteArray()
		row.resize(map_size.x)
		for x in map_size.x:
			if int(land[y][x]) == 0:
				row[x] = 0
				frontier.append(Vector2i(x, y))
			else:
				row[x] = limit
		dist.append(row)

	var step := 0
	while step < beach_width and not frontier.is_empty():
		step += 1
		var next: Array[Vector2i] = []
		for cell in frontier:
			for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var n: Vector2i = cell + offset
				if n.x < 0 or n.y < 0 or n.x >= map_size.x or n.y >= map_size.y:
					continue
				if int(dist[n.y][n.x]) <= step:
					continue
				dist[n.y][n.x] = step
				next.append(n)
		frontier = next
	return dist


## Noise shaped by a radial falloff, so the landmass is always ringed by water
## no matter what the noise does near the map edge.
func _elevation_at(noise: FastNoiseLite, pos: Vector2, centre: Vector2, max_radius: float) -> float:
	var distance := clampf(pos.distance_to(centre) / max_radius, 0.0, 1.0)
	var falloff := 1.0 - pow(distance, falloff_power)
	return _unit(noise.get_noise_2d(pos.x, pos.y)) * maxf(falloff, 0.0)


## FastNoiseLite returns [-1, 1]; we want [0, 1].
func _unit(n: float) -> float:
	return (n + 1.0) * 0.5


static func is_walkable(terrain: int) -> bool:
	return terrain >= FIRST_WALKABLE
