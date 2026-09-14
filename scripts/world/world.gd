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
## Terrain at or above this is dry land.
const FIRST_LAND: int = Terrain.SAND

## Tileset source ids, from tools/build_tileset.gd. The "open" water source is
## the same art without collision — it goes UNDER the land so the sea is a
## continuous backdrop instead of stopping at the beach.
##
## There is one sea colour on purpose: the pack has no deep-to-shallow
## transition art, so a separate deep tile met the shallows at a hard
## rectangular step. The generator still classifies depth; nothing draws it.
const SRC_WATER_SOLID := 0
const SRC_WATER_OPEN := 1
const SRC_SAND := 2
const SRC_GRASS := 3
const SRC_WOOD := 4
## Loose moss patches on transparency. These carry no terrain bits and are the
## only thing in the pack that can soften a biome edge — the straight-edge
## TILES do not curve at all (measured: a flat 2px transparent run on every
## row), so a boundary is only as organic as what is scattered along it.
const SRC_DETAIL_GRASS := 5
const SRC_DETAIL_WOOD := 6
## Registered by the tileset builder but deliberately unused: nothing is
## scattered onto water any more. See _scatter_detail.
const SRC_DETAIL_SAND := 7
## Generated wavy straight-edge variants, one sheet per terrain. They carry the
## same corner bits as the pack's flat edges so the autotiler mixes them in.
const SRC_SAND_EDGES := 8
const SRC_GRASS_EDGES := 9
const SRC_WOOD_EDGES := 10
## The one corner-match terrain set, and the terrains inside it.
const TERRAIN_SET := 0
const T_SAND := 0
const T_GRASS := 1
const T_WOOD := 2

@export var generator: IslandGenerator

# These are this scene's own children, so they are looked up directly rather
# than exported: @export'd Node references serialize as NodePath and are not
# reliably resolved by the time _ready() runs.
@onready var water_layer: TileMapLayer = $Water
## Sand covers every land cell, so it is the layer that answers "is this dry
## land" for building and the one that carries the navigation mesh.
@onready var ground_layer: TileMapLayer = $Sand
@onready var grass_layer: TileMapLayer = $Grass
@onready var wood_layer: TileMapLayer = $Woodland
@onready var detail_layer: TileMapLayer = $Detail
@onready var props_layer: Node2D = $Props
@onready var _animals: AnimalSpawner = $Animals

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

@export_group("Ground detail")
## Chance a grass or woodland tile gets a loose moss patch dropped on it. This
## is what stops the interior reading as one flat colour: only 4 of the sheet's
## 13 solid grass cells differ from the plain one by more than 6% of pixels, so
## the autotiler's own variety is nearly invisible on its own.
@export_range(0.0, 1.0) var detail_chance := 0.16
## Chance for a tile on the far side of a boundary: sand that touches grass,
## and shallows that touch sand. Much higher on purpose — these are the patches
## that overhang the edge and break up the straight line, on both sides.
@export_range(0.0, 1.0) var edge_detail_chance := 0.62

var _rng := RandomNumberGenerator.new()
## Tiles already taken by scenery or a placed building, so build mode can tell
## a free patch of grass from an occupied one without hunting the scene tree.
var _occupied: Dictionary = {}
## Buildings the player has put down, as {"item": id, "origin": Vector2i}. The
## seeded campfire is deliberately NOT in here — it comes back with the island.
var _placed: Array[Dictionary] = []
var _spawn_cell := Vector2i.ZERO
var _bounds := Rect2()
## The terrain grid this island was painted from. Kept because terrain is no
## longer recoverable from the tilemap: the layers encode SHAPE, not biome.
var _grid: Array = []


func _ready() -> void:
	build()


func build() -> void:
	if generator == null:
		push_error("World has no IslandGenerator assigned.")
		return

	var grid: Array = generator.generate()
	_grid = grid
	_rng.seed = generator.last_seed

	# Re-runnable on purpose: loading a save made on a different seed rebuilds
	# the island, and scenery would otherwise pile up on top of the old lot.
	for child in props_layer.get_children():
		if child is Player:
			continue  # The room manager owns the player, not us.
		child.queue_free()
		props_layer.remove_child(child)
	_placed.clear()
	_occupied.clear()
	_paint(grid)
	# Spawn is chosen before scattering so the clearing can be honoured.
	_spawn_cell = _find_spawn_tile(grid)
	var fire_cell := _place_campfire(grid, _spawn_cell)
	_scatter_harvestables(grid, _spawn_cell, fire_cell)
	# Wildlife last: the spawner needs the finished terrain grid, and it places
	# into props_layer so animals Y-sort against the trees they walk behind.
	if _animals != null:
		_animals.populate(self, grid)

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
## `item_id` is recorded only so a save can put the building back; the world
## never looks the item up again, so an unrecorded placement still works.
func build_at(scene: PackedScene, origin: Vector2i, footprint: Vector2i, item_id := "") -> Node2D:
	if scene == null or not can_build(origin, footprint):
		return null
	var node: Node2D = scene.instantiate()
	# Anchor a multi-tile footprint by its bottom-centre, so a 3x3 hut sits on
	# the tiles the ghost showed rather than off to one side.
	node.position = footprint_anchor(origin, footprint)
	props_layer.add_child(node)
	_mark(origin, footprint)
	if not item_id.is_empty():
		_placed.append({"item": item_id, "origin": origin})
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


# --- persistence ------------------------------------------------------------

## What a save has to carry about the island.
##
## The terrain itself is NOT saved: it is a pure function of the seed, so the
## seed is all that is needed to get the same island back. Only what the player
## has changed since is written — buildings they placed, trees they chopped,
## fires they fed. That keeps a save a couple of kilobytes instead of a
## megabyte of tile ids.
func save_data() -> Dictionary:
	var placed: Array = []
	for entry in _placed:
		var origin: Vector2i = entry["origin"]
		placed.append({"item": entry["item"], "cell": [origin.x, origin.y]})
	return {
		"seed": generator.last_seed,
		"placed": placed,
		"harvestables": _harvestable_states(),
		"campfires": _campfire_states(),
	}


## Rebuilds the island if the save came from a different seed, then puts back
## everything the player changed. Animals are deliberately not restored — the
## spawner refills the island to its caps anyway, and a save is not improved by
## remembering exactly which hare was standing where.
func load_data(data: Dictionary) -> void:
	var saved_seed := int(data.get("seed", generator.last_seed))
	if saved_seed != generator.last_seed:
		generator.randomize_seed = false
		generator.noise_seed = saved_seed
		build()

	# Buildings first: a harvestable cannot occupy a tile a building is on, and
	# build_at refuses an occupied cell, so ordering here is load-bearing.
	for entry in data.get("placed", []):
		var item := ItemDB.get_item(String(entry.get("item", "")))
		if item == null or not item.is_placeable():
			continue
		var cell: Array = entry.get("cell", [0, 0])
		build_at(item.placed_scene, Vector2i(int(cell[0]), int(cell[1])),
			item.placed_footprint, item.id)

	var trees: Dictionary = data.get("harvestables", {})
	var fires: Dictionary = data.get("campfires", {})
	for node in props_layer.get_children():
		var key := _cell_key(world_to_cell(node.position))
		if node is Harvestable and trees.has(key):
			(node as Harvestable).load_data(trees[key])
		elif node is Campfire and fires.has(key):
			(node as Campfire).load_data(fires[key])


## Only harvestables that differ from their freshly-generated state are written,
## so an untouched island saves an empty dictionary.
func _harvestable_states() -> Dictionary:
	var out: Dictionary = {}
	for node in props_layer.get_children():
		if not (node is Harvestable):
			continue
		var tree := node as Harvestable
		if tree.is_untouched():
			continue
		out[_cell_key(world_to_cell(tree.position))] = tree.save_data()
	return out


func _campfire_states() -> Dictionary:
	var out: Dictionary = {}
	for node in props_layer.get_children():
		if node is Campfire:
			out[_cell_key(world_to_cell(node.position))] = (node as Campfire).save_data()
	return out


## Cells are the key because a node's position is recoverable from it: scenery
## is jittered only within its own tile, so the cell round-trips exactly.
## JSON object keys must be strings, hence the formatting rather than a Vector2i.
func _cell_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]


## Which terrain a cell was generated as. Returns DEEP_WATER off the map.
func terrain_at(cell: Vector2i) -> int:
	if _grid.is_empty() or cell.y < 0 or cell.y >= _grid.size():
		return Terrain.DEEP_WATER
	var row: PackedByteArray = _grid[cell.y]
	if cell.x < 0 or cell.x >= row.size():
		return Terrain.DEEP_WATER
	return int(row[cell.x])


func world_to_cell(position: Vector2) -> Vector2i:
	return ground_layer.local_to_map(ground_layer.to_local(position))


## The island is painted as stacked layers rather than one flat grid: sea
## everywhere, then sand over the land, then grass, then woodland. Each land
## layer is autotiled against emptiness, and because the sheets' edge pieces
## are drawn on transparency, every boundary curves into whatever is beneath
## it instead of meeting it at a hard step.
func _paint(grid: Array) -> void:
	water_layer.clear()
	ground_layer.clear()
	grass_layer.clear()
	wood_layer.clear()

	var land: Array[Vector2i] = []
	var grassy: Array[Vector2i] = []
	var woody: Array[Vector2i] = []
	for y in generator.map_size.y:
		var row: PackedByteArray = grid[y]
		for x in generator.map_size.x:
			var cell := Vector2i(x, y)
			var terrain := int(row[x])
			var is_land := terrain >= FIRST_LAND
			# Sea under everything. Only genuinely open water gets the solid
			# variant, or the player would be walled in on dry land.
			water_layer.set_cell(cell, SRC_WATER_OPEN if is_land else SRC_WATER_SOLID,
				Vector2i.ZERO)
			if is_land:
				land.append(cell)
			if terrain >= Terrain.GRASS:
				grassy.append(cell)
			if terrain == Terrain.FOREST:
				woody.append(cell)

	# Godot picks the corner tile for each cell, and picks at random between
	# equally good matches — which is where the grass texture variety comes
	# from, since every solid interior cell in the sheet is registered.
	ground_layer.set_cells_terrain_connect(land, TERRAIN_SET, T_SAND, false)
	grass_layer.set_cells_terrain_connect(grassy, TERRAIN_SET, T_GRASS, false)
	wood_layer.set_cells_terrain_connect(woody, TERRAIN_SET, T_WOOD, false)
	_scatter_detail()


## Drops loose moss patches over the finished ground: lightly across grass and
## woodland for texture, heavily on the sand that touches grass so the beach
## edge is broken up rather than ruled.
func _scatter_detail() -> void:
	detail_layer.clear()
	var grass_patches := _detail_tiles(SRC_DETAIL_GRASS)
	var wood_patches := _detail_tiles(SRC_DETAIL_WOOD)
	if grass_patches.is_empty():
		return
	for y in generator.map_size.y:
		for x in generator.map_size.x:
			var cell := Vector2i(x, y)
			var terrain := terrain_at(cell)
			var source := SRC_DETAIL_GRASS
			var patches := grass_patches
			var chance := 0.0
			if terrain == Terrain.FOREST:
				chance = detail_chance
				source = SRC_DETAIL_WOOD
				patches = wood_patches
			elif terrain == Terrain.GRASS:
				chance = detail_chance
			elif terrain == Terrain.SAND and _touches(cell, Terrain.GRASS):
				# The whole point: green spilling onto the sand, so the eye
				# reads a ragged shoreline instead of a staircase.
				chance = edge_detail_chance
			# ⚠️ Nothing is scattered onto the WATER any more. "Sandy shoals
			# spilling into the shallows" was the intent; at play zoom it was
			# 270 hard-outlined beige lumps sitting on flat open sea, detached
			# from the beach, reading as litter rather than as shoals. The
			# shoreline gets its softness from the sand blob's own curved alpha
			# edge, which no longer has a single flat tile in it.
			if chance <= 0.0 or _rng.randf() >= chance:
				continue
			detail_layer.set_cell(cell, source, patches[_rng.randi() % patches.size()])


## True when any of the four neighbours is at least `terrain`.
func _touches(cell: Vector2i, terrain: int) -> bool:
	for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if terrain_at(cell + offset) >= terrain:
			return true
	return false


## Every patch coord registered in a detail source, read from the tileset so
## adding art to the sheet needs no change here.
func _detail_tiles(source: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var atlas := detail_layer.tile_set.get_source(source) as TileSetAtlasSource
	if atlas == null:
		return out
	for i in atlas.get_tiles_count():
		out.append(atlas.get_tile_id(i))
	return out


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
