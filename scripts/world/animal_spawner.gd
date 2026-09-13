class_name AnimalSpawner
extends Node2D

## Keeps a population of animals on the island and tops it up slowly.
##
## It never places an animal itself — it asks the World for a spawnable tile the
## same way harvestables ask for terrain, so "where does a deer live" is a field
## on AnimalData, not a branch in here.
##
## Respawn is deliberately slow: wildlife you can farm in a minute stops feeling
## like wildlife. The cap is per species, and a fresh animal only appears out of
## sight of the player, so nothing ever pops into existence in front of them.

## Seconds between top-up attempts. One animal per tick at most.
@export var respawn_seconds := 24.0
## A new animal must be at least this far from the player, in pixels.
@export var respawn_clearance := 200.0
## Tries per placement before giving up until the next tick.
@export var placement_attempts := 30

@export var animal_scene: PackedScene
## Every species that lives here. Each carries its own terrains and population,
## so adding wildlife is a new .tres and nothing else.
@export var animals: Array[AnimalData] = []

var _rng := RandomNumberGenerator.new()
var _since_respawn := 0.0
## data.id -> Array of live animals, so a cap is a count, not a scene-tree scan.
var _live: Dictionary = {}
var _land: Dictionary = {}
var _world: World


## Fills the island to its caps in one go. Called by the World once the terrain
## grid exists — the spawner has no opinion about when that is.
func populate(world: World, grid: Array) -> void:
	_world = world
	_rng.seed = world.generator.last_seed ^ 0x5EED
	_index_land(grid)
	for data in animals:
		if data == null:
			continue
		_live[data.id] = []
		for i in data.population:
			_spawn(data, false)


func _process(delta: float) -> void:
	if _world == null or animals.is_empty():
		return
	_since_respawn += delta
	if _since_respawn < respawn_seconds:
		return
	_since_respawn = 0.0
	# One at a time, and only for a species actually below its cap.
	for data in animals:
		if data != null and count_of(data) < data.population:
			_spawn(data, true)
			return


## How many of this species are alive right now.
func count_of(data: AnimalData) -> int:
	_prune(data.id)
	return (_live.get(data.id, []) as Array).size()


func total_alive() -> int:
	var sum := 0
	for data in animals:
		if data != null:
			sum += count_of(data)
	return sum


## Terrain row -> the cells that carry it, so placement is a random pick from a
## list rather than rejection-sampling a 96x96 grid for a rare terrain.
func _index_land(grid: Array) -> void:
	_land.clear()
	for y in _world.generator.map_size.y:
		var row: PackedByteArray = grid[y]
		for x in _world.generator.map_size.x:
			var terrain := int(row[x])
			if not IslandGenerator.is_walkable(terrain):
				continue
			if not _land.has(terrain):
				_land[terrain] = []
			_land[terrain].append(Vector2i(x, y))


func _spawn(data: AnimalData, away_from_player: bool) -> bool:
	if animal_scene == null or data.spawn_terrains.is_empty():
		return false
	for attempt in placement_attempts:
		var terrain: int = data.spawn_terrains[_rng.randi() % data.spawn_terrains.size()]
		var cells: Array = _land.get(terrain, [])
		if cells.is_empty():
			continue
		var cell: Vector2i = cells[_rng.randi() % cells.size()]
		var point := Vector2(cell * 16) + Vector2(8, 8)
		if away_from_player and _too_close_to_player(point):
			continue
		var animal: Animal = animal_scene.instantiate()
		animal.data = data
		animal.position = point
		_world.sort_layer().add_child(animal)
		if not _live.has(data.id):
			_live[data.id] = []
		_live[data.id].append(animal)
		return true
	return false


func _too_close_to_player(point: Vector2) -> bool:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return false
	return point.distance_to((players[0] as Node2D).global_position) < respawn_clearance


## Hunted animals free themselves, so the list is swept rather than signalled —
## one less connection to leak when an animal is freed mid-fade.
##
## A carcass is dropped from the count the moment it dies rather than when the
## node finally frees, so the fade-out does not hold a population slot hostage
## for a second and a half after the kill.
func _prune(id: String) -> void:
	if not _live.has(id):
		return
	var kept: Array = []
	for animal in _live[id]:
		if is_instance_valid(animal) and (animal as Animal).is_alive():
			kept.append(animal)
	_live[id] = kept
