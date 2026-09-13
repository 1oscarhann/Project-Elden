class_name World
extends Room

## Builds the island.
##
## Asks the generator for a terrain grid, paints it into the two TileMapLayers,
## scatters scenery, and reports where the player should stand. Only the *painting*
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

@export_group("Scenery")
## Every kind of harvestable that may appear. Each carries its own terrains and
## spawn chance, so adding a tree or a rock is a new .tres and nothing else.
@export var harvestables: Array[HarvestableData] = []
@export var harvestable_scene: PackedScene
## The one campfire the world seeds near spawn. Phase 8 makes fires placeable;
## for now the night loop just needs somewhere to run to.
@export var campfire_scene: PackedScene
## Box around the spawn that scenery must not cover. A plain radius is not
## enough: a canopy is ~74px tall, so a tree several tiles south still draws
## over the player's head.
@export var spawn_clearing := Vector2(44.0, 48.0)

var _rng := RandomNumberGenerator.new()
## Tiles already taken by scenery or a placed building, so build mode can tell
## a free patch of grass from an occupied one without hunting the scene tree.
var _occupied: Dictionary = {}
var _spawn_cell := Vector2i.ZERO
var _bounds := Rect2()


func _ready() -> void:
	build()


func build() -> void:
	if generator == null:
		push_error("World has no IslandGenerator assigned.")
		return

	var grid: Array = generator.generate()
	_rng.seed = generator.last_seed

	_occupied.clear()
	_paint(grid)
	# Spawn is chosen before scattering so the clearing can be honoured.
	_spawn_cell = _find_spawn_tile(grid)
	var fire_cell := _place_campfire(grid, _spawn_cell)
	_scatter_harvestables(grid, _spawn_cell, fire_cell)

	# Stored rather than pushed at the camera here: this runs before the player
	# exists, so the room manager applies it when it activates this room.
	_bounds = Rect2(Vector2.ZERO, Vector2(generator.map_size * water_layer.tile_set.tile_size))
	island_built.emit(_bounds)


# --- Room interface ---------------------------------------------------------

func sort_layer() -> Node2D:
	return props_layer


func entry_position() -> Vector2:
	return _tile_centre(_spawn_cell)


func camera_bounds() -> Rect2:
	return _bounds


# --- placement --------------------------------------------------------------

## True when every tile of `footprint` at `origin` is dry, unoccupied land.
func can_build(origin: Vector2i, footprint: Vector2i) -> bool:
	for y in maxi(1, footprint.y):
		for x in maxi(1, footprint.x):
			var cell := origin + Vector2i(x, y)
			if _occupied.has(cell):
				return false
			# Land is exactly "painted on the ground layer" — water lives on its
			# own layer, so this rules out the sea and the map edge together.
			if ground_layer.get_cell_source_id(cell) == -1:
				return false
	return true


## Instances a buildable into the y-sorted props layer and marks its tiles.
func build_at(scene: PackedScene, origin: Vector2i, footprint: Vector2i) -> Node2D:
	if scene == null or not can_build(origin, footprint):
		return null
	var node: Node2D = scene.instantiate()
	# Anchor a multi-tile footprint by its bottom-centre, so a 3x3 hut sits on
	# the tiles the ghost showed rather than off to one side.
	node.position = footprint_anchor(origin, footprint)
	props_layer.add_child(node)
	_mark(origin, footprint)
	return node


## World position a building with this footprint should sit at.
func footprint_anchor(origin: Vector2i, footprint: Vector2i) -> Vector2:
	var size := water_layer.tile_set.tile_size
	var span := Vector2i(maxi(1, footprint.x), maxi(1, footprint.y))
	var top_left := Vector2(origin * size)
	return top_left + Vector2(span.x * size.x * 0.5, float(span.y * size.y))


func _mark(origin: Vector2i, footprint: Vector2i) -> void:
	for y in maxi(1, footprint.y):
		for x in maxi(1, footprint.x):
			_occupied[origin + Vector2i(x, y)] = true


func world_to_cell(position: Vector2) -> Vector2i:
	return ground_layer.local_to_map(ground_layer.to_local(position))


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


## Walks every tile once and offers it to each harvestable in turn; the first
## whose terrain matches and whose chance comes up wins the tile.
func _scatter_harvestables(grid: Array, spawn: Vector2i, fire: Vector2i) -> void:
	if harvestables.is_empty() or harvestable_scene == null:
		return
	# Keep the player and the campfire both visible and reachable on load.
	var clear_box := _clear_box(spawn)
	if fire != spawn:
		clear_box = clear_box.merge(_clear_box(fire))
	for y in generator.map_size.y:
		var row: PackedByteArray = grid[y]
		for x in generator.map_size.x:
			var terrain := int(row[x])
			for data in harvestables:
				if data == null or not data.spawn_terrains.has(terrain):
					continue
				if _rng.randf() >= data.spawn_chance:
					continue
				_add_harvestable(data, Vector2i(x, y), clear_box)
				break


func _add_harvestable(data: HarvestableData, cell: Vector2i, clear_box: Rect2) -> void:
	var texture := data.ready_texture()
	if texture == null:
		return
	# Jitter inside the tile so the scatter does not read as a grid.
	var pos := _tile_centre(cell) + Vector2(_rng.randf_range(-4.0, 4.0), _rng.randf_range(-3.0, 3.0))
	# Only scenery that would draw OVER the player can hide him; anything based
	# further north sorts behind and is harmless.
	if pos.y > clear_box.position.y and SpriteAnchor.world_rect(texture, pos, data.sprite_scale).intersects(clear_box):
		return
	var node: Node2D = harvestable_scene.instantiate()
	node.data = data
	node.position = pos
	props_layer.add_child(node)
	_occupied[cell] = true


func _tile_centre(cell: Vector2i) -> Vector2:
	var size := water_layer.tile_set.tile_size
	return Vector2(cell * size) + Vector2(size) * 0.5


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
	_occupied[cell] = true
	return cell


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
