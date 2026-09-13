class_name World
extends Node2D

## Builds the island.
##
## Asks the generator for a terrain grid, paints it into the two TileMapLayers,
## scatters scenery, and drops the player on solid ground. Only the *painting*
## lives here — the algorithm lives in the IslandGenerator resource — so either
## side can be replaced without touching the other.

signal island_built(bounds: Rect2)

const Terrain := IslandGenerator.Terrain
## Terrain rows at or above this are dry land; below it is water, which is the
## layer that carries collision.
const FIRST_LAND: int = Terrain.SAND
## Columns per terrain row in the atlas: variants on land, animation frames on water.
const VARIANTS := 4
const SOURCE_ID := 0

@export var generator: IslandGenerator

# These are this scene's own children, so they are looked up directly rather
# than exported: @export'd Node references serialize as NodePath and are not
# reliably resolved by the time _ready() runs.
@onready var water_layer: TileMapLayer = $Water
@onready var ground_layer: TileMapLayer = $Ground
@onready var props_layer: Node2D = $Props
@onready var player: Node2D = $Props/Player

@export_group("Scenery")
## The one campfire the world seeds near spawn. Phase 8 makes fires placeable;
## for now the night loop just needs somewhere to run to.
@export var campfire_scene: PackedScene
@export var tree_textures: Array[Texture2D] = []
## Chance a forest tile grows a tree.
@export_range(0.0, 1.0) var forest_tree_chance := 0.12
## Chance a plain grass tile grows a tree.
@export_range(0.0, 1.0) var grass_tree_chance := 0.015
## Box around the spawn that scenery must not cover. A plain radius is not
## enough: a canopy is ~74px tall, so a tree several tiles south still draws
## over the player's head.
@export var spawn_clearing := Vector2(44.0, 48.0)

var _rng := RandomNumberGenerator.new()
## Cached per-texture offset that puts a trunk's base on the node origin.
var _trunk_offsets: Dictionary = {}


func _ready() -> void:
	build()


func build() -> void:
	if generator == null:
		push_error("World has no IslandGenerator assigned.")
		return

	var grid: Array = generator.generate()
	_rng.seed = generator.last_seed

	_paint(grid)
	# Spawn is chosen before scattering so the clearing can be honoured.
	var spawn := _find_spawn_tile(grid)
	if player != null:
		player.position = _tile_centre(spawn)
	var fire_cell := _place_campfire(grid, spawn)
	_scatter_trees(grid, spawn, fire_cell)

	var bounds := Rect2(Vector2.ZERO, Vector2(generator.map_size * water_layer.tile_set.tile_size))
	# Group calls rather than direct references, so the camera can live anywhere.
	get_tree().call_group(PlayerCamera.GROUP, "set_world_bounds", bounds)
	get_tree().call_group(PlayerCamera.GROUP, "snap_to_target")
	island_built.emit(bounds)


## Water goes on one layer and land on the other, and the two sets never
## overlap — so the water layer's collision only ever blocks actual water.
func _paint(grid: Array) -> void:
	water_layer.clear()
	ground_layer.clear()
	for y in generator.map_size.y:
		var row: PackedByteArray = grid[y]
		for x in generator.map_size.x:
			var terrain := int(row[x])
			var is_land := terrain >= FIRST_LAND
			# Land rows hold four interchangeable variants; the water rows hold a
			# single animated tile whose columns are frames, not variants.
			var column := _rng.randi_range(0, VARIANTS - 1) if is_land else 0
			var layer: TileMapLayer = ground_layer if is_land else water_layer
			layer.set_cell(Vector2i(x, y), SOURCE_ID, Vector2i(column, terrain))


func _scatter_trees(grid: Array, spawn: Vector2i, fire: Vector2i) -> void:
	if tree_textures.is_empty():
		return
	# Keep the player and the campfire both visible and reachable on load.
	var clear_box := _clear_box(spawn)
	if fire != spawn:
		clear_box = clear_box.merge(_clear_box(fire))
	for y in generator.map_size.y:
		var row: PackedByteArray = grid[y]
		for x in generator.map_size.x:
			var terrain := int(row[x])
			var chance := 0.0
			if terrain == Terrain.FOREST:
				chance = forest_tree_chance
			elif terrain == Terrain.GRASS:
				chance = grass_tree_chance
			if chance <= 0.0 or _rng.randf() >= chance:
				continue
			_add_tree(Vector2i(x, y), clear_box)


func _add_tree(cell: Vector2i, clear_box: Rect2) -> void:
	var texture: Texture2D = tree_textures[_rng.randi_range(0, tree_textures.size() - 1)]
	var offset := _trunk_offset(texture)
	# Jitter inside the tile so the scatter doesn't read as a grid.
	var pos := _tile_centre(cell) + Vector2(_rng.randf_range(-4.0, 4.0), _rng.randf_range(-3.0, 3.0))
	# Only scenery that would draw OVER the player can hide him; anything with
	# its base further north sorts behind and is harmless.
	if pos.y > clear_box.position.y and _sprite_rect(texture, pos, offset).intersects(clear_box):
		return
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.offset = offset
	sprite.position = pos
	props_layer.add_child(sprite)


## Footprint plus headroom around a tile that scenery must not cover.
func _clear_box(cell: Vector2i) -> Rect2:
	var centre := _tile_centre(cell)
	return Rect2(centre - Vector2(spawn_clearing.x * 0.5, spawn_clearing.y),
		Vector2(spawn_clearing.x, spawn_clearing.y + 8.0))


## Seeds the single campfire a short walk from the spawn, on clear ground.
func _place_campfire(grid: Array, spawn: Vector2i) -> Vector2i:
	if campfire_scene == null:
		return spawn
	var cell := spawn
	for offset in [Vector2i(3, -2), Vector2i(-3, -2), Vector2i(3, 2), Vector2i(-3, 2), Vector2i(0, -3)]:
		if _is_clear(grid, spawn + offset):
			cell = spawn + offset
			break
	var fire: Node2D = campfire_scene.instantiate()
	fire.position = _tile_centre(cell)
	props_layer.add_child(fire)
	return cell


## World-space rect a centred Sprite2D would occupy.
func _sprite_rect(texture: Texture2D, pos: Vector2, offset: Vector2) -> Rect2:
	var size := Vector2(texture.get_size())
	return Rect2(pos + offset - size * 0.5, size)


## Measure where the trunk actually sits instead of hardcoding a number per
## texture, so dropping new tree art into assets/trees/ just works.
func _trunk_offset(texture: Texture2D) -> Vector2:
	if _trunk_offsets.has(texture):
		return _trunk_offsets[texture]
	var image := texture.get_image()
	var used := image.get_used_rect()
	# Sprite2D is centred, so shift it up until the content's bottom edge is on
	# the origin — that origin is what Y-sorting compares.
	var offset := Vector2(0.0, float(image.get_height()) * 0.5 - float(used.end.y))
	_trunk_offsets[texture] = offset
	return offset


func _tile_centre(cell: Vector2i) -> Vector2:
	var size := water_layer.tile_set.tile_size
	return Vector2(cell * size) + Vector2(size) * 0.5


## Spiral out from the middle for a land tile whose neighbours are also land, so
## the player never spawns wedged into the surf.
func _find_spawn_tile(grid: Array) -> Vector2i:
	var centre := generator.map_size / 2
	var limit: int = maxi(generator.map_size.x, generator.map_size.y)
	for radius in range(0, limit):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				# Only test the ring just added, not the filled square.
				if absi(dx) != radius and absi(dy) != radius:
					continue
				var cell := centre + Vector2i(dx, dy)
				if _is_clear(grid, cell):
					return cell
	return centre


func _is_clear(grid: Array, cell: Vector2i) -> bool:
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var c := cell + Vector2i(dx, dy)
			if c.x < 0 or c.y < 0 or c.x >= generator.map_size.x or c.y >= generator.map_size.y:
				return false
			if not IslandGenerator.is_walkable(int(grid[c.y][c.x])):
				return false
	return true
