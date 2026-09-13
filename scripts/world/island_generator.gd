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
## Elevation thresholds, low to high. Anything under shallow_level is deep water.
@export_range(0.0, 1.0) var shallow_level := 0.22
@export_range(0.0, 1.0) var sand_level := 0.30
@export_range(0.0, 1.0) var land_level := 0.38

@export_group("Land cover")
## A second noise field thickens land into woodland in patches, so trees form
## groves rather than scattering evenly.
@export_range(0.0, 1.0) var forest_threshold := 0.52

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
	cover.frequency = 0.09
	cover.fractal_octaves = 2

	var centre := Vector2(map_size) * 0.5
	var max_radius: float = minf(centre.x, centre.y) * island_radius

	var grid: Array = []
	for y in map_size.y:
		var row := PackedByteArray()
		row.resize(map_size.x)
		for x in map_size.x:
			row[x] = _classify(
				_elevation_at(elevation, Vector2(x + 0.5, y + 0.5), centre, max_radius),
				_unit(cover.get_noise_2d(x, y)))
		grid.append(row)
	return grid


## Noise shaped by a radial falloff, so the landmass is always ringed by water
## no matter what the noise does near the map edge.
func _elevation_at(noise: FastNoiseLite, pos: Vector2, centre: Vector2, max_radius: float) -> float:
	var distance := clampf(pos.distance_to(centre) / max_radius, 0.0, 1.0)
	var falloff := 1.0 - pow(distance, falloff_power)
	return _unit(noise.get_noise_2d(pos.x, pos.y)) * maxf(falloff, 0.0)


## FastNoiseLite returns [-1, 1]; we want [0, 1].
func _unit(n: float) -> float:
	return (n + 1.0) * 0.5


func _classify(elevation: float, cover: float) -> int:
	if elevation < shallow_level:
		return Terrain.DEEP_WATER
	if elevation < sand_level:
		return Terrain.SHALLOW_WATER
	if elevation < land_level:
		return Terrain.SAND
	if cover >= forest_threshold:
		return Terrain.FOREST
	return Terrain.GRASS


static func is_walkable(terrain: int) -> bool:
	return terrain >= FIRST_WALKABLE
