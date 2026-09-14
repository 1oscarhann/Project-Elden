extends Node2D

## Smoke test across every phase built so far.
##
## Exists because a careless edit once silently deleted the whole warmth system
## and the phase's own tests never touched warmth. Run it after any change:
##
##     godot --headless --path . res://tools/regression_check.tscn
##
## Exits 0 when everything passes, or with the number of failures.

## Bumped whenever checks are added. A runtime error aborts the phase it is in
## and every phase after it, and without this the truncated run still reported
## ALL GREEN because nothing had actually *failed*.
const EXPECTED_CHECKS := 131

var f := 0
var fails := 0
var checks := 0
var rooms: RoomManager
var world: World
var props: Node2D
var player: CharacterBody2D
var fire: Campfire
var tree_node: Harvestable
var spawner: AnimalSpawner
## Phase 9 is the one phase that cannot be judged in a single frame: fleeing and
## pathing only exist over time. It runs as a short script of steps instead.
var step := 0
## Seconds, NOT frames: headless runs _process uncapped, so counting frames
## measured a few milliseconds and every timed check failed for no reason.
var wait := 0.0
var quarry: Animal
var quarry_start := Vector2.ZERO
## Seconds spent waiting for the wander check. It polls rather than sleeping a
## fixed span: a deer's rest is up to 6s on top of its initial settle, so any
## single guess is a coin flip and the check went flaky.
var wander_waited := 0.0


func ck(ok: bool, what: String, detail: String = "") -> void:
	checks += 1
	if not ok:
		fails += 1
	print(("  ok   " if ok else " FAIL  "), what, ("   " + detail) if detail else "")


func _ready() -> void:
	add_child((load("res://scenes/main/Main.tscn") as PackedScene).instantiate())


func _process(delta: float) -> void:
	f += 1
	if f > 2:
		_phase9_step(delta)
		return
	if f != 2:
		return
	DayNight.paused = true
	rooms = get_node("Main/Rooms")
	world = rooms.get_node("World")
	props = world.get_node("Props")
	# The room manager reparents the player into whichever room they are in.
	player = props.get_node("Player")
	for c in props.get_children():
		if c is Campfire:
			fire = c
		elif c is Harvestable and tree_node == null and (c as Harvestable).data.hits_required > 1:
			tree_node = c

	_phase1()
	_phase2()
	_phase3()
	_phase4()
	_phase5()
	_phase6()
	_phase7()
	_phase8()
	_phase9()
	print("\n-- Phase 9b: wildlife over time --")


func _finish() -> void:
	ck(checks >= EXPECTED_CHECKS - 1, "the whole suite ran — no phase aborted early",
		"%d of %d" % [checks + 1, EXPECTED_CHECKS])
	print("\n%d checks, %s" % [checks, "ALL GREEN" if fails == 0 else "%d FAILURE(S)" % fails])
	get_tree().quit(fails)


func _phase1() -> void:
	print("\n-- Phase 1: player --")
	var frames: SpriteFrames = player.get_node("Sprite").sprite_frames
	var missing: Array = []
	for state in ["idle", "walk", "run", "chop"]:
		for dir in ["down", "left", "right", "up"]:
			if not frames.has_animation("%s_%s" % [state, dir]):
				missing.append("%s_%s" % [state, dir])
	ck(missing.is_empty(), "all 16 animations present", str(missing))
	ck(not frames.get_animation_loop("chop_down"), "the chop is one-shot, not looping")
	ck(player.motion_mode == CharacterBody2D.MOTION_MODE_FLOATING, "top-down motion mode")


func _phase2() -> void:
	print("\n-- Phase 2: world --")
	# The island is layered now: sea under everything, then sand, grass and
	# woodland autotiled on top. Biome is NOT recoverable from the tilemap —
	# the layers encode shape, so terrain questions go to world.terrain_at().
	var water: TileMapLayer = world.get_node("Water")
	var sand: TileMapLayer = world.get_node("Sand")
	var grass: TileMapLayer = world.get_node("Grass")
	var wood: TileMapLayer = world.get_node("Woodland")
	var area: int = world.generator.map_size.x * world.generator.map_size.y
	ck(water.get_used_cells().size() == area, "the sea is painted under every cell",
		str(water.get_used_cells().size()))

	var land := 0
	var wrong_sand := 0
	var wrong_grass := 0
	for y in world.generator.map_size.y:
		for x in world.generator.map_size.x:
			var cell := Vector2i(x, y)
			var is_land: bool = world.terrain_at(cell) >= World.FIRST_LAND
			if is_land:
				land += 1
			if is_land != (sand.get_cell_source_id(cell) != -1):
				wrong_sand += 1
			var is_grass: bool = world.terrain_at(cell) >= IslandGenerator.Terrain.GRASS
			if is_grass != (grass.get_cell_source_id(cell) != -1):
				wrong_grass += 1
	ck(wrong_sand == 0, "sand covers exactly the dry land", "%d wrong of %d" % [wrong_sand, land])
	ck(wrong_grass == 0, "grass covers exactly the grass and woodland", str(wrong_grass))
	ck(wood.get_used_cells().size() < grass.get_used_cells().size(),
		"woodland is a subset of the grass it sits on")

	# Only genuinely open sea is solid. Land sits over a collision-free twin,
	# or the player would be walled in on dry ground.
	var solid: TileSetAtlasSource = water.tile_set.get_source(World.SRC_WATER_SOLID)
	var open: TileSetAtlasSource = water.tile_set.get_source(World.SRC_WATER_OPEN)
	ck(solid.get_tile_animation_frames_count(Vector2i.ZERO) == 4, "the sea animates across 4 frames")
	ck(solid.get_tile_data(Vector2i.ZERO, 0).get_collision_polygons_count(0) > 0,
		"open sea carries collision")
	ck(open.get_tile_data(Vector2i.ZERO, 0).get_collision_polygons_count(0) == 0,
		"and the sea under the land does not")
	var walled := 0
	for c in sand.get_used_cells():
		if water.get_cell_source_id(c) == World.SRC_WATER_SOLID:
			walled += 1
	ck(walled == 0, "no land cell sits on solid water", str(walled))

	# Autotiling: a complete corner set per terrain, and more than one interior
	# tile, which is what stops the grass being one texture repeated.
	var ts: TileSet = sand.tile_set
	ck(ts.get_terrain_sets_count() == 1 and ts.get_terrain_set_mode(0) == TileSet.TERRAIN_MODE_MATCH_CORNERS,
		"one corner-match terrain set")
	for pair in [[World.SRC_SAND, "sand"], [World.SRC_GRASS, "grass"], [World.SRC_WOOD, "woodland"]]:
		var atlas: TileSetAtlasSource = ts.get_source(pair[0])
		var cases := {}
		for i in atlas.get_tiles_count():
			var coord: Vector2i = atlas.get_tile_id(i)
			var data := atlas.get_tile_data(coord, 0)
			var bits := 0
			for b in 4:
				if data.get_terrain_peering_bit([TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER,
						TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER,
						TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER,
						TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER][b]) != -1:
					bits |= 1 << b
			cases[bits] = int(cases.get(bits, 0)) + 1
		ck(cases.size() == 15, "%s has all 15 corner cases" % pair[1], str(cases.size()))
		ck(int(cases.get(15, 0)) > 4, "%s has interior variety" % pair[1],
			"%d variants" % int(cases.get(15, 0)))

	# The real point of all of it: boundaries must actually use edge tiles.
	var edges := 0
	for c in sand.get_used_cells():
		var coord: Vector2i = sand.get_cell_atlas_coords(c)
		var data := (ts.get_source(World.SRC_SAND) as TileSetAtlasSource).get_tile_data(coord, 0)
		var full := true
		for n in [TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER, TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER,
				TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER, TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER]:
			if data.get_terrain_peering_bit(n) == -1:
				full = false
		if not full:
			edges += 1
	ck(edges > 200, "the shoreline is drawn with edge tiles, not squares",
		"%d edge tiles" % edges)

	# The sheet's four frames differ by only a few percent, so the sea needs the
	# shimmer shader on top to read as moving at all.
	var mat := water.material as ShaderMaterial
	ck(mat != null and mat.shader != null
		and mat.shader.resource_path.ends_with("water_shimmer.gdshader"),
		"the sea carries the shimmer shader")

	ck(props.y_sort_enabled, "props layer is y-sorted")


func _phase3() -> void:
	print("\n-- Phase 3: day/night and warmth --")
	ck(DayNight.phase_at(0.05) == DayNight.Phase.NIGHT, "phase_at maps night")
	ck(DayNight.phase_at(0.50) == DayNight.Phase.DAY, "phase_at maps day")
	# The player spawns inside the campfire's warmth radius, which correctly
	# beats the clock — step out of it before testing the bare night drain.
	var restore: int = GameState._heat_sources
	GameState._heat_sources = 0
	DayNight.time_of_day = 0.90
	DayNight.advance(0.0)
	ck(GameState.warmth_rate() < 0.0, "warmth drains at night", "%.1f/s" % GameState.warmth_rate())
	DayNight.time_of_day = 0.50
	DayNight.advance(0.0)
	ck(GameState.warmth_rate() > 0.0, "warmth recovers by day", "+%.1f/s" % GameState.warmth_rate())
	GameState.set_warmth(0.0)
	ck(GameState.speed_factor() > 0.0, "speed never reaches zero — no death",
		"x%.2f" % GameState.speed_factor())
	ck(is_equal_approx(GameState.chill(), 1.0), "chill saturates at 1")
	GameState.set_warmth(100.0)
	ck(is_equal_approx(GameState.speed_factor(), 1.0), "full speed when warm")
	ck(is_equal_approx(DayNight.darkness(), 0.0), "darkness is 0 at midday")
	GameState._heat_sources = restore


func _phase4() -> void:
	print("\n-- Phase 4: campfire --")
	ck(fire != null, "a campfire exists in the world")
	if fire == null:
		return
	DayNight.time_of_day = 0.90
	DayNight.advance(0.0)
	fire.set_fuel(50.0)
	var before: float = fire.fuel
	fire._process(2.0)
	ck(is_equal_approx(before - fire.fuel, fire.burn_rate * 2.0), "fuel burn is delta-scaled")
	fire._player_in_warmth = true
	fire._refresh()
	ck(GameState.is_warmed(), "a lit fire warms the player")
	ck(GameState.warmth_rate() > 0.0, "which beats the night drain")
	var heat_before: int = GameState._heat_sources
	fire._refresh()
	fire._refresh()
	ck(GameState._heat_sources == heat_before, "refresh is idempotent — no double counting")
	fire.set_fuel(0.0)
	ck(not GameState.is_warmed(), "a fire dying underfoot stops warming")
	fire._player_in_warmth = false
	fire._refresh()
	Inventory.clear()
	Inventory.add_item("wood", 3)
	fire.set_fuel(10.0)
	ck(fire.add_wood() and Inventory.count("wood") == 2, "adding wood spends exactly one log")


func _phase5() -> void:
	print("\n-- Phase 5: harvestables --")
	var kinds := {}
	for c in props.get_children():
		if c is Harvestable:
			kinds[(c as Harvestable).data.id] = true
	ck(kinds.size() >= 4, "several kinds of harvestable spawned", str(kinds.keys()))
	ck(tree_node != null, "found a multi-hit node to chop")
	if tree_node == null:
		return
	var item: String = tree_node.data.drops[0].item_id
	var before: int = Inventory.count(item)
	for i in tree_node.data.hits_required - 1:
		tree_node.hit()
	ck(tree_node.is_ready(), "survives up to the last hit")
	tree_node.hit()
	ck(not tree_node.is_ready(), "the final hit harvests it")
	ck(Inventory.count(item) > before, "and it dropped %s" % item,
		"+%d" % (Inventory.count(item) - before))
	ck(tree_node._body.collision_layer == 0, "harvested node stops blocking movement")
	ck(not tree_node.hit(), "cannot re-chop a harvested node")
	tree_node._set_stage(tree_node._stages.size() - 1)
	ck(tree_node.is_ready() and tree_node._body.collision_layer == 1, "regrows and blocks again")


func _phase6() -> void:
	print("\n-- Phase 6: items and inventory --")
	ck(ItemDB.count() > 0, "ItemDB loaded items from data", "%d items" % ItemDB.count())
	ck(ItemDB.max_stack("nonsense") == 1, "an unknown id cannot make an infinite stack")
	Inventory.clear()
	ck(Inventory.add_item("wood", 120) == 0, "adding past a stack limit still fits")
	ck(Inventory.count("wood") == 120, "total is right across stacks", str(Inventory.count("wood")))
	ck(Inventory.slot(0)["count"] == ItemDB.max_stack("wood"), "first stack capped at max_stack")
	ck(not Inventory.remove_item("wood", 999), "removal is all-or-nothing")
	ck(Inventory.count("wood") == 120, "and a refused removal takes nothing")
	ck(Inventory.remove_item("wood", 120) and Inventory.count("wood") == 0, "a valid removal clears it")
	Inventory.clear()
	for i in Inventory.SLOT_COUNT:
		Inventory.add_item("fruit", ItemDB.max_stack("fruit"))
	ck(Inventory.is_full() and Inventory.add_item("stone", 5) == 5,
		"a full bag returns the whole amount as leftover")
	Inventory.clear()


func _phase7() -> void:
	print("\n-- Phase 7: crafting --")
	ck(Crafting.count() > 0, "recipes loaded from data", "%d recipes" % Crafting.count())
	var plank: RecipeData = Crafting.get_recipe("plank")
	var bench: RecipeData = Crafting.get_recipe("workbench")
	var axe: RecipeData = Crafting.get_recipe("stone_axe")
	ck(plank != null and bench != null and axe != null, "the tree's key recipes exist")
	if plank == null or bench == null or axe == null:
		return
	Inventory.clear()
	Inventory.add_item("wood", 2)
	ck(not Crafting.can_craft(bench), "workbench blocked on raw wood alone — the tree is real")
	Crafting.craft(plank)
	Crafting.craft(plank)
	Inventory.add_item("stone", 2)
	ck(Crafting.can_craft(bench) and Crafting.craft(bench), "and unlocked once planks exist")
	ck(Inventory.count("workbench") == 1, "result landed in the bag")
	Inventory.clear()
	Inventory.add_item("plank", 2)
	Inventory.add_item("rope", 1)
	Inventory.add_item("stone", 3)
	ck(Crafting.has_ingredients(axe) and not Crafting.can_craft(axe),
		"a station recipe is blocked away from its station")
	Crafting.add_station("workbench")
	ck(Crafting.can_craft(axe), "and allowed at it")
	Crafting.remove_station("workbench")
	Crafting.remove_station("workbench")
	ck(not Crafting.has_station("workbench"), "station count cannot go negative")
	Inventory.clear()
	ck(not Crafting.craft(plank), "cannot craft without ingredients")
	GameState.set_warmth(20.0)
	ck(GameState.consume("warmth_tonic") and GameState.warmth > 20.0,
		"a consumable applies its own stats")
	ck(not GameState.consume("stone"), "a plain material does nothing")
	Inventory.clear()
	GameState.set_warmth(100.0)


func _phase8() -> void:
	print("\n-- Phase 8: building & interiors --")
	ck(rooms != null and rooms.is_in_group(RoomManager.GROUP), "room manager is reachable by group")
	ck(rooms.current_room() == world, "the island is the room we start in")
	ck(player.get_parent() == props, "player lives in the current room's y-sort layer")

	# Placement is a data question — an item is buildable when it carries a scene.
	var kit: ItemData = ItemDB.get_item("hut_kit")
	var wood: ItemData = ItemDB.get_item("wood")
	ck(kit != null and kit.is_placeable(), "hut_kit is placeable from its own data")
	ck(wood != null and not wood.is_placeable(), "a plain material is not")

	# Somewhere genuinely free: search out from spawn rather than assume.
	var spawn: Vector2i = world.world_to_cell(world.entry_position())
	var spot := Vector2i.ZERO
	var found := false
	for r in range(2, 20):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var c := spawn + Vector2i(dx, dy)
				if world.can_build(c, Vector2i(3, 3)):
					spot = c
					found = true
					break
			if found:
				break
		if found:
			break
	ck(found, "the island has room to build on", str(spot))
	if not found:
		return

	var before: int = props.get_child_count()
	var hut: Node2D = world.build_at(kit.placed_scene, spot, Vector2i(3, 3))
	ck(hut != null and props.get_child_count() == before + 1, "a building lands in the props layer")
	ck(not world.can_build(spot, Vector2i(3, 3)), "and its tiles are taken afterwards")
	ck(not world.can_build(spot + Vector2i(2, 2), Vector2i(1, 1)),
		"every tile of the footprint, not just the origin")
	ck(world.build_at(kit.placed_scene, spot, Vector2i(3, 3)) == null, "so nothing can stack on it")
	ck(not world.can_build(Vector2i(-5, -5), Vector2i(1, 1)), "and the sea is not buildable")

	# Bottom-centre anchoring: the 3x3 footprint's base row is where it stands.
	var tile: int = world.water_layer.tile_set.tile_size.x
	var anchor: Vector2 = world.footprint_anchor(spot, Vector2i(3, 3))
	ck(is_equal_approx(anchor.x, float(spot.x * tile) + tile * 1.5)
		and is_equal_approx(anchor.y, float((spot.y + 3) * tile)),
		"footprint anchors on its bottom centre", str(anchor))

	# A placed workbench must actually be a station — that is the point of
	# building one. Driven directly rather than by walking into it, so the
	# check does not depend on a physics frame having settled.
	var bench_item: ItemData = ItemDB.get_item("workbench")
	var pad := Vector2i.ZERO
	for r in range(4, 14):
		if world.can_build(spot + Vector2i(r, 0), Vector2i(1, 1)):
			pad = spot + Vector2i(r, 0)
			break
	var bench: Node2D = world.build_at(bench_item.placed_scene, pad, Vector2i(1, 1))
	ck(bench != null, "found somewhere for a workbench", str(pad))
	if bench == null:
		return
	var station := bench.get_node_or_null("Station") as CraftingStation
	ck(station != null and station.station_id == "workbench", "a placed workbench carries a station")
	if station != null:
		var had: bool = Crafting.has_station("workbench")
		station._on_entered(player)
		ck(Crafting.has_station("workbench"), "standing at it registers the station")
		station._on_exited(player)
		ck(Crafting.has_station("workbench") == had, "and leaving hands it back")
	bench.queue_free()

	# The door in that hut leads somewhere, and that somewhere is a Room.
	var door := hut.get_node_or_null("Door") as Door
	ck(door != null and door.leads_inside(), "the hut carries a door that leads inside")
	if door == null:
		return
	var inside := door.interior_scene.instantiate() as Interior
	add_child(inside)
	ck(inside != null, "the interior is a Room")
	var floor_layer: TileMapLayer = inside.get_node("Floor")
	var painted: int = floor_layer.get_used_cells().size()
	ck(painted == inside.room_size.x * inside.room_size.y,
		"the interior paints its whole room", "%d cells" % painted)
	# Bigger on the inside is the whole point of the phase.
	ck(inside.room_size.x * inside.room_size.y > 3 * 3, "and is bigger inside than out",
		"%dx%d vs 3x3" % [inside.room_size.x, inside.room_size.y])
	var doorway: Array = floor_layer.get_used_cells().filter(
		func(c: Vector2i) -> bool: return c.y == inside.room_size.y - 1 \
			and floor_layer.get_cell_atlas_coords(c) == inside.floor_tile)
	ck(doorway.size() == 1, "exactly one gap in the wall ring", str(doorway.size()))
	ck(inside.get_node("ExitDoor").position.distance_to(inside.get_node("Entry").position) > 0.0,
		"you do not arrive standing on the exit")
	ck(not inside.camera_bounds().has_area() or inside.camera_bounds().size.x < world.camera_bounds().size.x,
		"the interior clamps the camera tighter than the island")

	# Shelter reuses the campfire's counted heat hook — warmth knows nothing of rooms.
	var heat_before: int = GameState.heat_source_count()
	inside.on_entered()
	ck(GameState.heat_source_count() == heat_before + 1, "being indoors registers as shelter")
	inside.on_entered()
	ck(GameState.heat_source_count() == heat_before + 1, "entering twice does not double-count")
	inside.on_exited()
	ck(GameState.heat_source_count() == heat_before, "and leaving hands it back")
	inside.queue_free()
	hut.queue_free()


func _phase9() -> void:
	print("\n-- Phase 9: animals --")
	spawner = world.get_node_or_null("Animals")
	ck(spawner != null, "the world carries an animal spawner")
	if spawner == null:
		return
	ck(spawner.animals.size() >= 2, "more than one species is configured",
		"%d species" % spawner.animals.size())

	# Data-driven: every species must be complete without code knowing its name.
	var incomplete: Array = []
	var wanted := ["idle", "walk", "run", "hurt", "death"]
	for data in spawner.animals:
		if data == null or data.sprite_frames == null:
			incomplete.append("null")
			continue
		for state in wanted:
			for dir in ["down", "left", "right", "up"]:
				if not data.sprite_frames.has_animation("%s_%s" % [state, dir]):
					incomplete.append("%s:%s_%s" % [data.id, state, dir])
	ck(incomplete.is_empty(), "every species has all 20 animations", str(incomplete))
	var unlooped: Array = []
	for data in spawner.animals:
		if data != null and data.sprite_frames.get_animation_loop("death_down"):
			unlooped.append(data.id)
	ck(unlooped.is_empty(), "death does not loop", str(unlooped))
	var slow: Array = []
	for data in spawner.animals:
		if data != null and data.flee_speed <= data.move_speed:
			slow.append(data.id)
	ck(slow.is_empty(), "fleeing is faster than ambling", str(slow))

	# Cozy rule: nothing here may damage the player.
	ck(not (Animal as Object).has_method("attack"), "animals have no attack")

	# Population filled to the caps, and in the y-sorted layer.
	var total := 0
	var capped := true
	for data in spawner.animals:
		if data == null:
			continue
		var live: int = spawner.count_of(data)
		total += live
		if live != data.population:
			capped = false
			print("       %s: %d of %d" % [data.id, live, data.population])
	ck(capped, "every species spawned to its cap", "%d animals" % total)
	var strays := 0
	for child in props.get_children():
		if child is Animal:
			strays += 1
	ck(strays == total, "animals live in the y-sorted props layer", "%d of %d" % [strays, total])

	# Spawn terrain is honoured, so where a species lives is data.
	var wrong: Array = []
	for child in props.get_children():
		if not (child is Animal):
			continue
		var a := child as Animal
		var cell: Vector2i = world.world_to_cell(a.global_position)
		if world.ground_layer.get_cell_source_id(cell) == -1:
			wrong.append("%s in the sea" % a.data.id)
		elif not a.data.spawn_terrains.has(world.terrain_at(cell)):
			wrong.append("%s on terrain %d" % [a.data.id, world.terrain_at(cell)])
	ck(wrong.is_empty(), "every animal stands on terrain its data allows", str(wrong.slice(0, 3)))

	# Navigation: the island's own tiles carry the mesh, the sea does not.
	var ts: TileSet = world.ground_layer.tile_set
	ck(ts.get_navigation_layers_count() > 0, "the tileset has a navigation layer")
	# Navigation rides the sand layer, which covers every land cell exactly.
	var sand_src: TileSetAtlasSource = ts.get_source(World.SRC_SAND)
	var land_nav := 0
	for i in sand_src.get_tiles_count():
		var poly: NavigationPolygon = sand_src.get_tile_data(sand_src.get_tile_id(i), 0).get_navigation_polygon(0)
		if poly != null and poly.get_polygon_count() > 0:
			land_nav += 1
	ck(land_nav == sand_src.get_tiles_count(), "every sand tile is navigable",
		"%d of %d" % [land_nav, sand_src.get_tiles_count()])
	var sea_src: TileSetAtlasSource = ts.get_source(World.SRC_WATER_SOLID)
	var sea_poly: NavigationPolygon = sea_src.get_tile_data(Vector2i.ZERO, 0).get_navigation_polygon(0)
	ck(sea_poly == null or sea_poly.get_polygon_count() == 0,
		"and the sea is not — an animal cannot path into it")
	ck(world.ground_layer.navigation_enabled, "the ground layer bakes that mesh")

	# Drops are data, and rolling one respects its chance.
	var dropless: Array = []
	for data in spawner.animals:
		if data != null and data.drops.is_empty():
			dropless.append(data.id)
	ck(dropless.is_empty(), "every species drops something", str(dropless))
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var never := HarvestDrop.new()
	never.item_id = "bone"
	never.chance = 0.0
	var always := HarvestDrop.new()
	always.item_id = "bone"
	always.min_count = 2
	always.max_count = 2
	ck(never.roll(rng) == 0, "a zero-chance drop yields nothing")
	ck(always.roll(rng) == 2, "and a certain one always yields")

	# The new branch of the tree hangs off the animals.
	for id in ["roast_venison", "roast_poultry", "hunting_knife"]:
		ck(Crafting.get_recipe(id) != null, "recipe %s exists" % id)
	for id in ["venison", "antler", "raw_poultry", "roast_venison", "roast_poultry", "hunting_knife"]:
		ck(ItemDB.get_item(id) != null, "item %s exists" % id)

	# Pick something to chase, and stand the player far away so the wildlife
	# is calm before the flee test starts.
	for child in props.get_children():
		if child is Animal and quarry == null:
			quarry = child
	player.global_position = quarry.global_position + Vector2(600, 0)


## Frames 3+. Fleeing and pathing only exist over time, so Phase 9's behaviour
## runs as a short script rather than a single-frame assertion.
func _phase9_step(delta: float) -> void:
	if wait > 0.0:
		wait -= delta
		return
	# A freed Node leaves this variable *null*, not merely invalid, so both have
	# to count as gone. Steps 0-6 need a live quarry; step 7 asserts it is gone,
	# so the guard must stop before then or it ends the run instead of checking.
	var gone: bool = quarry == null or not is_instance_valid(quarry)
	if step < 7 and gone:
		ck(false, "the quarry vanished before the run got to step %d" % step)
		_finish()
		return
	match step:
		0:
			wait = 2.0  # Let it settle and take a wander hop or two.
		1:
			ck(quarry.get_node("Agent").get_navigation_map().is_valid(),
				"the agent found a navigation map")
			quarry_start = quarry.global_position
			wander_waited = 0.0
		2:
			# Poll EVERY frame, not on a wait: `wait` short-circuits before this
			# runs, so accumulating there counted one delta per wait window and
			# the 25s deadline took 2000 real seconds to reach.
			#
			# The threshold is a real distance, not a nudge — a resting animal
			# drifts a pixel or two settling, and accepting that passed the
			# check without anything having wandered anywhere.
			var moved: float = quarry.global_position.distance_to(quarry_start)
			wander_waited += delta
			if moved <= 12.0 and wander_waited < 25.0:
				return
			ck(moved > 12.0, "a calm animal wanders on its own",
				"moved %.1fpx after %.1fs" % [moved, wander_waited])
			# Walk up on it.
			quarry_start = quarry.global_position
			player.global_position = quarry.global_position + Vector2(24, 0)
			wait = 0.5
		3:
			ck(quarry._state == Animal.State.FLEE, "it flees when the player closes in",
				"state %d" % quarry._state)
			wait = 1.0
		4:
			var gap: float = quarry.global_position.distance_to(player.global_position)
			ck(gap > 24.0, "and puts distance between them", "%.1fpx away" % gap)
			var cell: Vector2i = world.world_to_cell(quarry.global_position)
			ck(world.ground_layer.get_cell_source_id(cell) != -1,
				"fleeing never takes it into the sea", str(cell))
			wait = 0.1
		5:
			# Hunt it: swing until it drops.
			Inventory.clear()
			var before: int = spawner.count_of(quarry.data)
			var swings := 0
			while quarry.is_alive() and swings < 12:
				quarry.hit()
				swings += 1
			ck(not quarry.is_alive(), "it can be hunted", "%d swings" % swings)
			ck(swings == quarry.data.hits_required, "taking exactly hits_required swings",
				"%d vs %d" % [swings, quarry.data.hits_required])
			var got: Dictionary = Inventory.totals()
			ck(not got.is_empty(), "drops land in the inventory", str(got))
			var expected: Array = []
			for drop in quarry.data.drops:
				expected.append(drop.item_id)
			var unexpected: Array = got.keys().filter(func(k): return not expected.has(k))
			ck(unexpected.is_empty(), "and only what its data lists", str(unexpected))
			ck(spawner.count_of(quarry.data) == before - 1,
				"a carcass stops counting toward the population cap")
			wait = 0.1
		6:
			ck(quarry.collision_layer == 0, "a carcass stops blocking the player")
			ck(not quarry.hit(), "and cannot be hunted twice")
			# It fades and frees itself; the spawner must not be holding it.
			wait = 3.0
		7:
			ck(gone, "the carcass clears itself away")
			# Respawn: the spawner tops the island back up on its own. Sped up
			# here, since the shipped interval is deliberately a slow trickle.
			spawner.respawn_seconds = 0.4
			spawner.respawn_clearance = 0.0
			wait = 2.0
		8:
			var refilled := true
			for data in spawner.animals:
				if data != null and spawner.count_of(data) != data.population:
					refilled = false
					print("       %s: %d of %d" % [data.id, spawner.count_of(data), data.population])
			ck(refilled, "the population refills itself over time",
				"%d animals" % spawner.total_alive())
			# And stops at the cap rather than filling the island forever.
			wait = 2.0
		9:
			var over: Array = []
			for data in spawner.animals:
				if data != null and spawner.count_of(data) > data.population:
					over.append("%s %d>%d" % [data.id, spawner.count_of(data), data.population])
			ck(over.is_empty(), "and never overshoots the cap", str(over))
			Inventory.clear()
			_finish()
			return
	step += 1
