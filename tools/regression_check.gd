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
const EXPECTED_CHECKS := 270

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
	_phase10()
	_phase11()
	_journal()
	_intro()
	print("\n-- Phase 9b: wildlife over time --")


func _finish() -> void:
	_silence()
	ck(checks >= EXPECTED_CHECKS - 1, "the whole suite ran — no phase aborted early",
		"%d of %d" % [checks + 1, EXPECTED_CHECKS])
	print("\n%d checks, %s" % [checks, "ALL GREEN" if fails == 0 else "%d FAILURE(S)" % fails])
	get_tree().quit(fails)


## Stops every sound before quitting.
##
## Not cosmetic: a playback still running when the tree is torn down keeps its
## stream alive past cleanup, and Godot reports that as leaked instances. Six
## bogus "leaks" in the output is exactly how a real one would go unnoticed.
func _silence() -> void:
	Audio.stop_world_audio()
	_stop_players(get_tree().root)


func _stop_players(node: Node) -> void:
	if node is AudioStreamPlayer or node is AudioStreamPlayer2D:
		node.stop()
	for child in node.get_children():
		_stop_players(child)


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
	# ⚠️ Counted across BOTH of a terrain's sources. The main sheet no longer
	# carries the four straight-edge signatures at all — its own straight edges
	# are dead-flat 2px insets, so they were dropped and the generated wavy
	# sheet supplies those four on its own.
	for pair in [[World.SRC_SAND, "sand", World.SRC_SAND_EDGES],
			[World.SRC_GRASS, "grass", World.SRC_GRASS_EDGES],
			[World.SRC_WOOD, "woodland", World.SRC_WOOD_EDGES]]:
		var cases := {}
		for source_id in [pair[0], pair[2]]:
			_collect_cases(ts, source_id, cases)
		ck(cases.size() == 15, "%s has all 15 corner cases" % pair[1], str(cases.size()))
		ck(int(cases.get(15, 0)) > 4, "%s has interior variety" % pair[1],
			"%d variants" % int(cases.get(15, 0)))


	# The real point of all of it: boundaries must actually use edge tiles, and
	# a share of those must be the GENERATED wavy ones — the pack's own straight
	# edges are a flat 2px inset, so on their own they draw a ruled line.
	var edges := 0
	var wavy := 0
	for c in sand.get_used_cells():
		# Read the cell's OWN source: the wavy variants live in their own
		# atlas, so assuming SRC_SAND here looked up coords in the wrong sheet.
		var source: int = sand.get_cell_source_id(c)
		var atlas := ts.get_source(source) as TileSetAtlasSource
		var data := atlas.get_tile_data(sand.get_cell_atlas_coords(c), 0)
		var full := true
		for n in [TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER, TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER,
				TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER, TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER]:
			if data.get_terrain_peering_bit(n) == -1:
				full = false
		if not full:
			edges += 1
			if source == World.SRC_SAND_EDGES:
				wavy += 1
	ck(edges > 200, "the shoreline is drawn with edge tiles, not squares",
		"%d edge tiles" % edges)
	ck(wavy > 40, "and a real share of them are the generated wavy variants",
		"%d of %d" % [wavy, edges])

	# The sheet's four frames differ by only a few percent, so the sea needs the
	# shimmer shader on top to read as moving at all.
	var mat := water.material as ShaderMaterial
	ck(mat != null and mat.shader != null
		and mat.shader.resource_path.ends_with("water_shimmer.gdshader"),
		"the sea carries the shimmer shader")

	_check_drawable(world.get_node("Sand").tile_set)
	_check_no_sharp_edges()
	_check_detail_is_loose()
	_check_interior_walls()

	# ⚠️ Structural, not cosmetic: sand is a distance from water, so an inland
	# beach is impossible by construction rather than by tuning. This check is
	# what stops anyone quietly turning it back into an elevation band.
	#
	# Stated as CONNECTIVITY, not as a radius. The radius version asserted every
	# sand cell was within beach_width of water, and broke the moment the 2x2
	# opening started pinching one-cell grass necks out into sand — which makes
	# the beach locally three thick and is perfectly coastal. What actually
	# matters is that no patch of sand is marooned inland, and that is exactly
	# "every sand region touches the sea".
	var sand_regions := 0
	var marooned := 0
	var sand_seen := {}
	for y in world.generator.map_size.y:
		for x in world.generator.map_size.x:
			var start := Vector2i(x, y)
			if sand_seen.has(start) or world.terrain_at(start) != IslandGenerator.Terrain.SAND:
				continue
			sand_regions += 1
			var queue: Array[Vector2i] = [start]
			sand_seen[start] = true
			var touches_sea := false
			while not queue.is_empty():
				var c: Vector2i = queue.pop_back()
				for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					var n: Vector2i = c + offset
					var t := world.terrain_at(n)
					if t < IslandGenerator.Terrain.SAND:
						touches_sea = true
						continue
					if t != IslandGenerator.Terrain.SAND or sand_seen.has(n):
						continue
					sand_seen[n] = true
					queue.append(n)
			if not touches_sea:
				marooned += 1
	ck(marooned == 0, "no sand cell sits inland — beaches are coastal by construction",
		"%d sand regions, %d marooned" % [sand_regions, marooned])

	# And woodland must be regions, not speckle: a one-tile grove has no edge
	# for a tile to draw, only corners, which is what reads as a hard square.
	var seen := {}
	var tiny := 0
	var groves := 0
	for y in world.generator.map_size.y:
		for x in world.generator.map_size.x:
			var start := Vector2i(x, y)
			if seen.has(start) or world.terrain_at(start) != IslandGenerator.Terrain.FOREST:
				continue
			var queue: Array[Vector2i] = [start]
			seen[start] = true
			var cells := 0
			while not queue.is_empty():
				var c: Vector2i = queue.pop_back()
				cells += 1
				for o in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					var n: Vector2i = c + o
					if seen.has(n) or world.terrain_at(n) != IslandGenerator.Terrain.FOREST:
						continue
					seen[n] = true
					queue.append(n)
			groves += 1
			if cells < world.generator.min_grove_cells:
				tiny += 1
	ck(tiny == 0, "every woodland grove is a real region, not speckle",
		"%d groves, %d under %d cells" % [groves, tiny, world.generator.min_grove_cells])

	# ⚠️ The signature of a mis-wired bitmask: a FILL tile (all four corners its
	# own terrain) sitting where the layer has a foreign neighbour. In
	# corner-match this should be unselectable — a foreign neighbour shares two
	# of the cell's corners, so those bits cannot be set — but wiring the bits
	# wrong would break exactly that guarantee, silently and everywhere.
	var fills_at_boundary := 0
	var flat_edges := 0
	var wavy_edges := 0
	var straight := {3: true, 5: true, 10: true, 12: true}
	for pair in [["Sand", World.SRC_SAND_EDGES], ["Grass", World.SRC_GRASS_EDGES],
			["Woodland", World.SRC_WOOD_EDGES]]:
		var layer: TileMapLayer = world.get_node(pair[0])
		var occupied := {}
		for c in layer.get_used_cells():
			occupied[c] = true
		for c in layer.get_used_cells():
			var atlas := ts.get_source(layer.get_cell_source_id(c)) as TileSetAtlasSource
			var data := atlas.get_tile_data(layer.get_cell_atlas_coords(c), 0)
			var b := 0
			for i in 4:
				if data.get_terrain_peering_bit([TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER,
						TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER,
						TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER,
						TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER][i]) != -1:
					b |= 1 << i
			if straight.has(b):
				if layer.get_cell_source_id(c) == pair[1]:
					wavy_edges += 1
				else:
					flat_edges += 1
			if b != 15:
				continue
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					if dx == 0 and dy == 0:
						continue
					if not occupied.has(c + Vector2i(dx, dy)):
						fills_at_boundary += 1
						dy = 2
						break
	ck(fills_at_boundary == 0,
		"no fill tile sits at a boundary — every edge resolves to an edge tile",
		str(fills_at_boundary))
	# ⚠️ Not "a minority" any more — ZERO. Every straight edge the pack ships is
	# a dead-flat 2px inset, so one of them anywhere is a ruled line exposed to
	# the player. They are no longer registered at all; every straight run is
	# drawn by a generated wavy variant.
	ck(flat_edges == 0, "no dead-flat straight edge is used anywhere",
		"%d flat of %d straight edges" % [flat_edges, flat_edges + wavy_edges])

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
	# ⚠️ Counted by WALKABILITY, not by "which tile is painted there". The
	# doorway used to be a hole of bare floor tile; it is a proper door piece
	# now, so a check that looked for the floor tile in the bottom row found
	# nothing and failed while the doorway was perfectly fine.
	var wall_src := floor_layer.tile_set.get_source(0) as TileSetAtlasSource
	var doorway: Array = floor_layer.get_used_cells().filter(
		func(c: Vector2i) -> bool: return c.y == inside.room_size.y - 1 \
			and wall_src.get_tile_data(floor_layer.get_cell_atlas_coords(c), 0) \
				.get_collision_polygons_count(0) == 0)
	ck(doorway.size() == 1, "exactly one way through the wall ring", str(doorway.size()))
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
## How many nodes in the props layer came from this scene.
func _count_scene(path: String) -> int:
	var total := 0
	for node in props.get_children():
		if node.scene_file_path == path:
			total += 1
	return total


func _phase11() -> void:
	print("\n-- Phase 11: hunger and thirst --")
	# ⚠️ PIN THE ENUM. Every HarvestableData and AnimalData stores its
	# spawn_terrains as RAW INTEGERS, so inserting a value into Terrain
	# silently re-points all of them — adding FRESH_WATER at index 2 turned
	# tree_palm's "sand, grass" into "fresh water, sand" and nothing complained.
	# If this check fails, the .tres files need renumbering to match.
	ck(IslandGenerator.Terrain.DEEP_WATER == 0
		and IslandGenerator.Terrain.SHALLOW_WATER == 1
		and IslandGenerator.Terrain.FRESH_WATER == 2
		and IslandGenerator.Terrain.SAND == 3
		and IslandGenerator.Terrain.GRASS == 4
		and IslandGenerator.Terrain.FOREST == 5,
		"Terrain values match what the .tres files store as raw ints")
	# And the ordering the code relies on: all water sorts below all land.
	ck(IslandGenerator.Terrain.FRESH_WATER < IslandGenerator.FIRST_WALKABLE,
		"fresh water still sorts as water, so every land test keeps working")
	var off_terrain: Array = []
	for data in world.harvestables:
		if data == null:
			continue
		for t in data.spawn_terrains:
			if int(t) < IslandGenerator.FIRST_WALKABLE:
				off_terrain.append("%s on %d" % [data.resource_path.get_file(), t])
	ck(off_terrain.is_empty(), "nothing is scattered onto water", str(off_terrain))
	# --- the stats exist and drain ---
	GameState.set_hunger(GameState.MAX_HUNGER)
	GameState.set_thirst(GameState.MAX_THIRST)
	var before_h := GameState.hunger
	var before_t := GameState.thirst
	GameState._process(2.0)
	ck(GameState.hunger < before_h, "hunger drains over time",
		"%.1f -> %.1f" % [before_h, GameState.hunger])
	ck(GameState.thirst < before_t, "thirst drains over time",
		"%.1f -> %.1f" % [before_t, GameState.thirst])
	# Slow enough to be background pressure, not a treadmill.
	ck(GameState.hunger_drain < 2.0 and GameState.thirst_drain < 2.0,
		"and slowly — this is a cozy game, not a chore",
		"%.2f / %.2f per second" % [GameState.hunger_drain, GameState.thirst_drain])

	# --- NO death, NO damage, ever ---
	GameState.set_hunger(0.0)
	GameState.set_thirst(0.0)
	GameState._process(10.0)
	ck(GameState.hunger == 0.0 and GameState.thirst == 0.0,
		"empty stats sit at zero rather than going negative")
	ck(GameState.speed_factor() > 0.0, "and never stop the player dead",
		"speed factor %.2f" % GameState.speed_factor())
	var lethal: Array = []
	for name in ["health", "damage", "die", "kill"]:
		if GameState.has_method(name) or name in GameState:
			lethal.append(name)
	ck(lethal.is_empty(), "GameState has no health, damage or death at all", str(lethal))

	# --- the penalty is soft, and it IS applied ---
	GameState.set_hunger(GameState.MAX_HUNGER)
	GameState.set_thirst(GameState.MAX_THIRST)
	var fed_speed := GameState.speed_factor()
	var fed_bite := GameState.deprivation_multiplier()
	GameState.set_hunger(0.0)
	GameState.set_thirst(0.0)
	ck(GameState.speed_factor() < fed_speed, "running empty slows the player a little",
		"%.2f vs %.2f" % [GameState.speed_factor(), fed_speed])
	ck(GameState.speed_factor() > 0.4, "but only a little", str(GameState.speed_factor()))
	ck(GameState.deprivation_multiplier() > fed_bite,
		"and makes the cold bite sooner",
		"warmth drain x%.2f vs x%.2f" % [GameState.deprivation_multiplier(), fed_bite])
	ck(GameState.is_deprived(), "which the HUD can ask about directly")

	# --- eating ---
	GameState.set_hunger(10.0)
	Inventory.clear()
	Inventory.add_item("cooked_meat", 1)
	var hungry := GameState.hunger
	ck(GameState.consume("cooked_meat"), "cooked meat can be eaten")
	ck(GameState.hunger > hungry, "and restores hunger",
		"%.0f -> %.0f" % [hungry, GameState.hunger])
	# Cooking has to be worth doing (the Phase 7 incentive).
	var raw := ItemDB.get_item("raw_meat").stat("hunger", 0.0)
	var cooked := ItemDB.get_item("cooked_meat").stat("hunger", 0.0)
	# Raw has to be EDIBLE for the comparison to mean anything — "cooked beats
	# raw" is trivially true if raw is not food at all, which it was.
	ck(raw > 0.0, "raw meat is edible, just poor", "%.0f hunger" % raw)
	ck(cooked >= raw * 2.0, "and cooking at least doubles it, so it pays",
		"%.0f vs %.0f" % [cooked, raw])
	# Juicy things quench a little; meat does not.
	ck(ItemDB.get_item("fruit").stat("thirst", 0.0) > 0.0, "fruit quenches a little too")
	ck(ItemDB.get_item("cooked_meat").stat("thirst", 0.0) == 0.0, "but meat does not")
	ck(not GameState.consume("wood"), "a log is not food")

	# --- drinking, and the sea NOT counting ---
	var fresh: Array[Vector2i] = []
	var sea: Array[Vector2i] = []
	for y in world.generator.map_size.y:
		for x in world.generator.map_size.x:
			var cell := Vector2i(x, y)
			var t := world.terrain_at(cell)
			if t == IslandGenerator.Terrain.FRESH_WATER:
				fresh.append(cell)
			elif t == IslandGenerator.Terrain.SHALLOW_WATER and sea.size() < 400:
				sea.append(cell)
	ck(not fresh.is_empty(), "the island has fresh water on it", "%d cells" % fresh.size())
	ck(world.can_drink_at(Vector2(fresh[0] * 16) + Vector2(8, 8)),
		"which can be drunk from", str(fresh[0]))
	var salty := 0
	for cell in sea:
		if world.can_drink_at(Vector2(cell * 16) + Vector2(8, 8)):
			salty += 1
	ck(salty == 0, "and SEA water never can — it is salt water", "%d of %d sea cells" % [salty, sea.size()])

	GameState.set_thirst(20.0)
	var dry := GameState.thirst
	ck(GameState.drink(30.0), "drinking restores thirst")
	ck(GameState.thirst > dry, "", "%.0f -> %.0f" % [dry, GameState.thirst])
	GameState.set_thirst(GameState.MAX_THIRST)
	ck(not GameState.drink(30.0), "and is refused when already full, so E falls through")

	# --- fresh water is INLAND by construction ---
	# Flood from the border: anything it reaches is ocean, so no cell it reaches
	# may be labelled fresh.
	var reached := {}
	var queue: Array[Vector2i] = []
	var size: Vector2i = world.generator.map_size
	var wet := func(c: Vector2i) -> bool:
		return world.terrain_at(c) < IslandGenerator.Terrain.SAND
	for x in size.x:
		for y in [0, size.y - 1]:
			var c := Vector2i(x, y)
			if wet.call(c) and not reached.has(c):
				reached[c] = true
				queue.append(c)
	while not queue.is_empty():
		var c: Vector2i = queue.pop_back()
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n: Vector2i = c + d
			if n.x < 0 or n.y < 0 or n.x >= size.x or n.y >= size.y:
				continue
			if reached.has(n) or not wet.call(n):
				continue
			reached[n] = true
			queue.append(n)
	var leaked := 0
	for cell in fresh:
		if reached.has(cell):
			leaked += 1
	ck(leaked == 0, "no freshwater cell touches the open sea", "%d leaked" % leaked)

	# --- persistence ---
	GameState.set_hunger(37.0)
	GameState.set_thirst(58.0)
	var snapshot := GameState.save_data()
	GameState.set_hunger(100.0)
	GameState.set_thirst(100.0)
	GameState.load_data(snapshot)
	ck(is_equal_approx(GameState.hunger, 37.0) and is_equal_approx(GameState.thirst, 58.0),
		"both survive a save and load", "%.0f / %.0f" % [GameState.hunger, GameState.thirst])

	# --- HUD ---
	var hud := get_node("Main/HUD")
	ck(hud.get_node_or_null("Frame/Readout/Hunger") != null, "the HUD shows a hunger bar")
	ck(hud.get_node_or_null("Frame/Readout/Thirst") != null, "and a thirst bar")

	GameState.set_hunger(GameState.MAX_HUNGER)
	GameState.set_thirst(GameState.MAX_THIRST)
	Inventory.clear()


## The journal hub, and the functional gap it exists to close.
##
## Before it, `Inventory.selected_item_id()` was the only item the game could
## act on, so anything past slot 8 was dead weight until it was shuffled
## forward. These check the thing the owner actually asked to be able to do:
## eat food sitting in the main grid, and drag items around.
func _journal() -> void:
	print("\n-- Journal hub --")
	var main := get_node("Main")
	var journal := main.get_node_or_null("Journal")
	ck(journal != null, "Main has a Journal panel")
	ck(main.get_node_or_null("InventoryPanel") == null
		and main.get_node_or_null("CraftMenu") == null,
		"and the old standalone bag and craft windows are gone")
	var tab_ids: Array = []
	for tab in journal.TABS:
		tab_ids.append(tab["id"])
	ck(tab_ids.has("inventory") and tab_ids.has("crafting") and tab_ids.has("build"),
		"one panel holds the bag, crafting and building", str(tab_ids))
	ck(InputMap.has_action("toggle_journal"), "and opens on a single key")
	journal.set_open(true)
	ck(journal.is_open(), "the journal opens")
	journal._show_tab("crafting")
	ck(journal.current_tab() == "crafting", "and switches tab on a click")
	journal.set_open(false)
	ck(not journal.is_open(), "and closes again")
	# Every tab bar button is wired, or a tab would be unreachable by mouse.
	var wired := 0
	for id in tab_ids:
		if journal._tab_buttons[id].pressed.get_connections().size() > 0:
			wired += 1
	ck(wired == tab_ids.size(), "every tab label is clickable", "%d of %d" % [wired, tab_ids.size()])

	# --- ⚠️ the gap: an item is used WHERE IT SITS ---
	Inventory.clear()
	var stack := ItemDB.max_stack("wood")
	Inventory.add_item("wood", stack * Inventory.HOTBAR_SIZE)
	Inventory.add_item("cooked_meat", 1)
	var meat_slot := -1
	for i in Inventory.SLOT_COUNT:
		if Inventory.slot(i)["id"] == "cooked_meat":
			meat_slot = i
			break
	ck(meat_slot >= Inventory.HOTBAR_SIZE,
		"with a full hotbar, food lands in the bag proper", "slot %d" % meat_slot)
	ck(Inventory.slot_is_usable(meat_slot), "the bag slot reports itself usable")
	GameState.set_hunger(20.0)
	var before_hunger := GameState.hunger
	ck(Inventory.use_slot(meat_slot),
		"and it can be EATEN THERE, with no shuffling to the hotbar first")
	ck(GameState.hunger > before_hunger, "hunger actually goes up",
		"%.0f -> %.0f" % [before_hunger, GameState.hunger])
	ck(Inventory.is_slot_empty(meat_slot), "and the item is spent")
	ck(not Inventory.use_slot(0), "a log in the same bag is still not food")

	# --- drag to rearrange ---
	Inventory.clear()
	Inventory.add_item("wood", 2)
	Inventory.add_item("stone", 3)
	Inventory.move_slot(0, 1)
	ck(Inventory.slot(0)["id"] == "stone" and Inventory.slot(1)["id"] == "wood",
		"dragging one item onto a different one swaps them")
	Inventory.clear()
	Inventory.add_item("wood", stack * 2)
	# Two partial stacks of the same thing cannot arise from add_item, which
	# tops up on purpose — so carve one out to test the pour.
	Inventory.discard_slot(0, stack - 2)
	Inventory.move_slot(1, 0)
	ck(Inventory.slot(0)["count"] == stack,
		"dragging onto a matching stack merges up to max_stack",
		"%d of %d" % [Inventory.slot(0)["count"], stack])
	ck(Inventory.slot(1)["count"] == 2,
		"and the overflow stays behind instead of vanishing",
		"%d left" % Inventory.slot(1)["count"])
	var total := Inventory.count("wood")
	ck(total == stack + 2, "no wood was created or destroyed", "%d" % total)
	# A drag onto an ALREADY FULL stack cannot pour, so it falls through to a
	# swap. Harmless and reversible — what matters is that it does not overflow
	# the cap or invent items, which is what this asserts.
	Inventory.clear()
	Inventory.add_item("wood", stack + 1)
	Inventory.move_slot(1, 0)
	ck(Inventory.slot(0)["count"] <= stack and Inventory.slot(1)["count"] <= stack,
		"a drag onto a full stack never breaches max_stack",
		"%d / %d" % [Inventory.slot(0)["count"], Inventory.slot(1)["count"]])
	ck(Inventory.count("wood") == stack + 1, "and still creates nothing",
		"%d" % Inventory.count("wood"))

	# --- the slot widget can be dragged and clicked at all ---
	var slot_script := load("res://scripts/ui/item_slot.gd") as Script
	var methods: Array = []
	for m in slot_script.get_script_method_list():
		methods.append(m["name"])
	ck(methods.has("_get_drag_data") and methods.has("_can_drop_data")
		and methods.has("_drop_data"),
		"slots implement Godot's drag-and-drop protocol")
	var signals: Array = []
	for sig in slot_script.get_script_signal_list():
		signals.append(sig["name"])
	ck(signals.has("activated"), "and report a click by signal, holding no path to a menu")
	# The hotbar listens too, or clicking a hotbar slot would be dead.
	var bar := main.get_node("Hotbar")
	var bar_slot: ItemSlot = bar._slots[0]
	ck(bar_slot.activated.get_connections().size() > 0, "the hotbar acts on clicks as well")

	Inventory.clear()


## The opening, and the flag that keeps it to once.
##
## ⚠️ The behaviour itself cannot be run from here: the intro PAUSES THE TREE,
## and a paused tree stops this suite dead. So this asserts the decision and the
## wiring, and `tools/intro_shots.gd` runs the real thing end to end.
func _intro() -> void:
	print("\n-- Opening --")
	var main := get_node("Main")
	ck(main.get_node_or_null("Intro") == null,
		"the intro removes itself when it has already been seen")
	var scene := load("res://scenes/ui/Intro.tscn") as PackedScene
	ck(scene != null, "and the scene it removes itself from is still there")
	var probe := scene.instantiate()
	ck(probe.lines.size() == 3, "three lines of opening text", "%d" % probe.lines.size())
	ck(probe.lines[0].begins_with("Your plane went down"), "the plane")
	ck(probe.lines[1].begins_with("You swam until"), "the swim")
	ck(probe.lines[2].begins_with("This island"), "and the island")
	ck(probe.chars_per_second > 0.0, "text types out rather than appearing at once",
		"%.0f chars/sec" % probe.chars_per_second)
	ck(probe.get_node("Root/BarTop") != null and probe.get_node("Root/BarBottom") != null,
		"letterbox bars, top and bottom")
	var dim: ColorRect = probe.get_node("Root/Dim")
	ck(dim.material is ShaderMaterial, "the background is dimmed by a shader, not a flat black")
	# ⚠️ Modulate cannot desaturate — it only multiplies — so this HAS to read
	# the screen. If the uniform ever goes, the dim silently becomes a tint.
	ck((dim.material as ShaderMaterial).shader.code.contains("hint_screen_texture"),
		"which reads the screen, so it can drain colour and not just darken it")
	probe.queue_free()

	# --- the flag ---
	ck(GameState.intro_shown, "the flag defaults to already-seen")
	GameState.load_data({})
	ck(GameState.intro_shown,
		"a save with no such key counts as seen, so an old file cannot replay it")
	GameState.load_data({"intro_shown": false})
	ck(not GameState.intro_shown, "and only an explicit false arms it")
	ck(GameState.save_data().has("intro_shown"), "the flag is written to the save")
	GameState.intro_shown = true
	var round_trip := GameState.save_data()
	GameState.intro_shown = false
	GameState.load_data(round_trip)
	ck(GameState.intro_shown, "and survives the round trip, so it plays ONCE")

	# --- the camera shot ---
	var camera := get_tree().get_nodes_in_group(PlayerCamera.GROUP)[0] as PlayerCamera
	var anim := camera.get_node_or_null("IntroAnim") as AnimationPlayer
	ck(anim != null, "the camera carries an AnimationPlayer, not a hardcoded tween")
	ck(anim != null and anim.has_animation("intro"),
		"with the placeholder shot on it", str(anim.get_animation_list()) if anim else "")
	if anim != null and anim.has_animation("intro"):
		var a := anim.get_animation("intro")
		var paths: Array = []
		for i in a.get_track_count():
			paths.append(str(a.track_get_path(i)))
		ck(a.length > 1.0, "that lasts long enough to read under", "%.0fs" % a.length)
		ck(paths.size() >= 1, "and actually animates the camera", str(paths))
		# The file, not an inline SubResource — that is what makes it openable
		# and re-keyframable in the editor without touching any script.
		ck(a.resource_path.begins_with("res://resources/animations/"),
			"kept in its own file so it can be re-keyframed in the editor",
			a.resource_path)
	ck("cinematic" in camera, "the camera can hand control to an animation")
	var held := camera.global_position
	camera.cinematic = true
	camera._process(0.5)
	ck(camera.global_position == held, "and stops following the player while it does")
	camera.cinematic = false
	camera.snap_to_target()


## Free, buildable cells spiralling out from `centre`, nearest first.
func _free_cells_near(centre: Vector2i, radius: int) -> Array:
	var out: Array = []
	for r in range(1, radius + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue  # Only the ring just added.
				out.append(centre + Vector2i(dx, dy))
	return out


## The corner signature a cell REQUIRES: a corner is filled only when all four
## cells meeting at it are in the region. That is the marching-squares semantic
## the blob sheets are drawn for, and it is what makes a one-cell-wide region
## undrawable — no corner qualifies, so the required signature is 0000 and the
## sheet has no such tile.
func _required_bits(cell: Vector2i, region: Dictionary) -> int:
	var bits := 0
	# Order matches build_tileset.gd's CORNERS: TL, TR, BL, BR.
	var quads := [
		[Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)],
		[Vector2i(0, -1), Vector2i(1, -1), Vector2i(0, 0), Vector2i(1, 0)],
		[Vector2i(-1, 0), Vector2i(0, 0), Vector2i(-1, 1), Vector2i(0, 1)],
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)],
	]
	for i in 4:
		var all_in := true
		for d in quads[i]:
			if not region.has(cell + d):
				all_in = false
				break
		if all_in:
			bits |= 1 << i
	return bits


## The signature of the tile Godot actually placed.
func _placed_bits(ts: TileSet, layer: TileMapLayer, cell: Vector2i) -> int:
	var src_id := layer.get_cell_source_id(cell)
	if src_id == -1:
		return -1
	var src := ts.get_source(src_id) as TileSetAtlasSource
	var data := src.get_tile_data(layer.get_cell_atlas_coords(cell), 0)
	var bits := 0
	var corners := [TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER, TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER,
		TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER, TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER]
	for i in 4:
		if data.get_terrain_peering_bit(corners[i]) != -1:
			bits |= 1 << i
	return bits


## ⚠️ THE check for whether corners and edges are right.
##
## "Is there a fill tile at a boundary" was the wrong question and always came
## back clean. The right one is whether the tile Godot placed EXACTLY matches
## the signature the region requires — because when no tile matches, Godot does
## not fail, it silently substitutes the nearest one. That is what a one-wide
## spit or a lone cell hits: required signature 0000, no such tile, so it comes
## out as a disconnected rounded nub.
##
## Measured before the generator opened its masks: 38 wrong on sand, 26 on
## grass, 3 lone cells and 40 one cell wide.
func _check_drawable(ts: TileSet) -> void:
	for layer_name in ["Sand", "Grass", "Woodland"]:
		var layer: TileMapLayer = world.get_node(layer_name)
		var region := {}
		for c in layer.get_used_cells():
			region[c] = true
		var wrong := 0
		var undrawable := 0
		var first := ""
		for cell in layer.get_used_cells():
			var want := _required_bits(cell, region)
			if want == 0:
				undrawable += 1
			if want == _placed_bits(ts, layer, cell):
				continue
			wrong += 1
			if first.is_empty():
				first = " first %s wants %d" % [cell, want]
		ck(wrong == 0, "%s: every tile matches the signature its shape requires" % layer_name,
			"%d cells, %d wrong%s" % [region.size(), wrong, first])
		ck(undrawable == 0, "%s: no cell is outside every 2x2 block of its own terrain" % layer_name,
			"%d such cells" % undrawable)


## The interior room uses the piece drawn for each side, and its doorway is a
## real opening you can walk through.
##
## It used to paint ONE horizontal plank tile round all four sides, so the side
## walls ran horizontally, there were no corners, and the doorway was a tongue
## of bare cream floor. The sheet is a house facade: column 0 is the left frame
## post, column 2 the right, column 1 the plank infill, and (3,2) has a doorway.
func _check_interior_walls() -> void:
	var scene := load("res://scenes/world/interiors/HutInterior.tscn") as PackedScene
	var room := scene.instantiate() as Interior
	add_child(room)
	var layer: TileMapLayer = room.get_node("Floor")
	var ts: TileSet = layer.tile_set
	var src := ts.get_source(0) as TileSetAtlasSource

	var sides := {}
	var size: Vector2i = room.room_size
	sides["top"] = layer.get_cell_atlas_coords(Vector2i(size.x / 2, 0))
	sides["bottom"] = layer.get_cell_atlas_coords(Vector2i(1, size.y - 1))
	sides["left"] = layer.get_cell_atlas_coords(Vector2i(0, size.y / 2))
	sides["right"] = layer.get_cell_atlas_coords(Vector2i(size.x - 1, size.y / 2))
	var distinct := {}
	for k in sides:
		distinct[sides[k]] = true
	ck(distinct.size() == 4, "each wall side uses the piece drawn for it",
		"%d distinct of 4: %s" % [distinct.size(), str(sides)])

	# Every wall cell must stop the player; the doorway must not.
	var leaky := 0
	for cell in layer.get_used_cells():
		var edge: bool = cell.x == 0 or cell.y == 0 \
			or cell.x == size.x - 1 or cell.y == size.y - 1
		var solid := src.get_tile_data(layer.get_cell_atlas_coords(cell), 0) \
			.get_collision_polygons_count(0) > 0
		var door: bool = cell == room.call("_door_cell")
		if edge and not door and not solid:
			leaky += 1
	ck(leaky == 0, "every wall cell is solid, side posts included", "%d leaky" % leaky)

	# ⚠️ Walkable is not the same as PASSABLE. The doorway is one tile wide, so a
	# 16px-wide player centred in it touches both jambs at once and
	# move_and_slide refuses to move — the hut could be entered (its outside
	# door is a free-standing Area2D with no jambs) but never left. The player's
	# body must be narrower than the gap.
	var body := player.get_node("CollisionShape2D") as CollisionShape2D
	var body_width: float = (body.shape as RectangleShape2D).size.x
	var tile: float = float(layer.tile_set.tile_size.x)
	ck(body_width < tile - 1.0, "the player fits THROUGH a one-tile doorway",
		"body %.0fpx wide vs a %.0fpx gap" % [body_width, tile])

	var door_cell: Vector2i = room.call("_door_cell")
	var door_solid := src.get_tile_data(layer.get_cell_atlas_coords(door_cell), 0) \
		.get_collision_polygons_count(0) > 0
	ck(not door_solid, "the doorway is walkable, so the exit works", str(door_cell))
	ck(layer.get_cell_atlas_coords(door_cell) != room.floor_tile,
		"and is drawn as a door, not as bare floor",
		str(layer.get_cell_atlas_coords(door_cell)))

	# Furniture you should bump into, and a rug you should not.
	var solid_props: Array = []
	var loose_props: Array = []
	for prop in room.get_node("Props").get_children():
		if prop.get_node_or_null("Body") != null:
			solid_props.append(prop.name)
		else:
			loose_props.append(prop.name)
	ck(solid_props.size() >= 3, "interior furniture carries collision", str(solid_props))
	ck(loose_props.has("Rug"), "except the rug, which you walk on", str(loose_props))
	room.queue_free()


## ⚠️ A detail patch must be a loose tuft, never a block.
##
## The selection rule used to be "all four extreme corners transparent", and a
## near-solid square with clipped corners passes that: cell (8,4) is 240 of 256
## px opaque and was being scattered across the beach at 62% chance. 21 of the
## 25 registered "patches" were blocks like that, which is where the hard green
## rectangles on the sand came from.
func _check_detail_is_loose() -> void:
	var ts: TileSet = world.get_node("Detail").tile_set
	var blocky: Array = []
	var total := 0
	for source_id in [World.SRC_DETAIL_GRASS, World.SRC_DETAIL_WOOD, World.SRC_DETAIL_SAND]:
		var atlas := ts.get_source(source_id) as TileSetAtlasSource
		if atlas == null:
			continue
		var img := atlas.texture.get_image()
		img.convert(Image.FORMAT_RGBA8)
		for i in atlas.get_tiles_count():
			var coord := atlas.get_tile_id(i)
			total += 1
			var ink := 0
			var widest := 0
			for y in 16:
				var run := 0
				for x in 16:
					if img.get_pixel(coord.x * 16 + x, coord.y * 16 + y).a > 0.16:
						ink += 1
						run += 1
				widest = maxi(widest, run)
			if ink > 96 or widest >= 12:
				blocky.append("src %d %s ink %d widest %d" % [source_id, coord, ink, widest])
	ck(blocky.is_empty(), "every scattered detail patch is a loose tuft, not a block",
		"%d of %d blocky %s" % [blocky.size(), total, str(blocky.slice(0, 2))])

	# And nothing is scattered onto open water, where a hard-outlined lump has
	# nothing to blend into.
	var detail: TileMapLayer = world.get_node("Detail")
	var sand: TileMapLayer = world.get_node("Sand")
	var on_water := 0
	for cell in detail.get_used_cells():
		if sand.get_cell_source_id(cell) == -1:
			on_water += 1
	ck(on_water == 0, "no detail patch sits on open water", "%d on water" % on_water)


## ⚠️ THE RULE: no sharp edge and no hard corner may ever be exposed.
##
## Every boundary the camera can see must resolve to a curved or blended piece.
## Three ways that can fail, all read from the ARTWORK rather than from the
## tileset's claims about itself:
##
##   A ruled line  a straight-edge tile whose inset never varies across its 16px
##   B seam step   adjacent tiles whose shared boundary profiles disagree
##   C hard corner an exposed corner drawn as an unrounded right angle
##
## Measured before the wrong-category and dead-flat tiles were dropped:
## 32 violations (31 ruled + 1 step) across 1676 exposed boundary edges.
func _check_no_sharp_edges() -> void:
	var ts: TileSet = world.get_node("Sand").tile_set
	var images := {}
	var ruled := 0
	var steps := 0
	var exposed := 0
	var dirs := [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]

	for layer_name in ["Sand", "Grass", "Woodland"]:
		var layer: TileMapLayer = world.get_node(layer_name)
		var region := {}
		for c in layer.get_used_cells():
			region[c] = true
		for cell in layer.get_used_cells():
			var facts := _art_of(ts, images, layer.get_cell_source_id(cell),
				layer.get_cell_atlas_coords(cell))
			for side in 4:
				var neighbour: Vector2i = cell + dirs[side]
				if region.has(neighbour):
					# Only test each adjacent pair once, from the bottom/right.
					if side != 1 and side != 3:
						continue
					var theirs := _art_of(ts, images, layer.get_cell_source_id(neighbour),
						layer.get_cell_atlas_coords(neighbour))
					var a: Array = facts["edges"][side]
					var b: Array = theirs["edges"][0 if side == 1 else 2]
					for i in 16:
						if a[i] != b[i]:
							steps += 1
							break
					continue
				var profile: Array = facts["depths"][side]
				var lo := 99
				var hi := -1
				for d in profile:
					if int(d) >= 16:
						continue
					lo = mini(lo, int(d))
					hi = maxi(hi, int(d))
				if hi < 0:
					continue  # nothing opaque on this side, nothing exposed
				exposed += 1
				if hi == lo and _signature(ts, layer.get_cell_source_id(cell),
						layer.get_cell_atlas_coords(cell)) in [3, 5, 10, 12]:
					ruled += 1

	ck(ruled == 0, "no ruled straight line is exposed at any boundary",
		"%d of %d exposed edges" % [ruled, exposed])
	ck(steps == 0, "every adjacent pair joins without a step", "%d steps" % steps)


## Per-tile artwork facts, cached: inset depth per side, and edge silhouettes.
func _art_of(ts: TileSet, cache: Dictionary, src_id: int, coord: Vector2i) -> Dictionary:
	var key := "%d:%d,%d" % [src_id, coord.x, coord.y]
	if cache.has(key):
		return cache[key]
	var atlas := ts.get_source(src_id) as TileSetAtlasSource
	var img: Image = cache.get(src_id, null)
	if img == null:
		img = atlas.texture.get_image()
		img.convert(Image.FORMAT_RGBA8)
		cache[src_id] = img
	var base := coord * 16
	var depths: Array = []
	var edges: Array = []
	for side in 4:
		var profile: Array = []
		var silhouette: Array = []
		for i in 16:
			var d := 16
			for step in 16:
				if img.get_pixel(base.x + _px(side, i, step).x,
						base.y + _px(side, i, step).y).a > 0.16:
					d = step
					break
			profile.append(d)
			silhouette.append(img.get_pixel(base.x + _px(side, i, 0).x,
				base.y + _px(side, i, 0).y).a > 0.16)
		depths.append(profile)
		edges.append(silhouette)
	var facts := {"depths": depths, "edges": edges}
	cache[key] = facts
	return facts


## Pixel `step` deep from `side` along sample line `i`.
func _px(side: int, i: int, step: int) -> Vector2i:
	match side:
		0: return Vector2i(i, step)
		1: return Vector2i(i, 15 - step)
		2: return Vector2i(step, i)
		_: return Vector2i(15 - step, i)


func _signature(ts: TileSet, src_id: int, coord: Vector2i) -> int:
	var atlas := ts.get_source(src_id) as TileSetAtlasSource
	var data := atlas.get_tile_data(coord, 0)
	var bits := 0
	var corners := [TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER, TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER,
		TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER, TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER]
	for i in 4:
		if data.get_terrain_peering_bit(corners[i]) != -1:
			bits |= 1 << i
	return bits


## Accumulates the corner signatures one source provides into `cases`.
func _collect_cases(ts: TileSet, source_id: int, cases: Dictionary) -> void:
	var atlas := ts.get_source(source_id) as TileSetAtlasSource
	if atlas == null:
		return
	var corners := [TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER, TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER,
		TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER, TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER]
	for i in atlas.get_tiles_count():
		var data := atlas.get_tile_data(atlas.get_tile_id(i), 0)
		var bits := 0
		for b in 4:
			if data.get_terrain_peering_bit(corners[b]) != -1:
				bits |= 1 << b
		cases[bits] = int(cases.get(bits, 0)) + 1


func _phase10() -> void:
	print("\n-- Phase 10: save/load, audio, polish --")
	# Slot 2, never slot 0: slot 0 is what the game autosaves to and what the
	# title screen's Continue reads, and a test run must not leave a save there.
	var slot := 2
	SaveManager.delete_save(slot)

	# Baseline, so phase 9b inherits the world it expected rather than whatever
	# this phase leaves behind.
	var baseline := {
		"day_night": DayNight.save_data(),
		"game_state": GameState.save_data(),
		"inventory": Inventory.save_data(),
		"world": world.save_data(),
	}

	ck(SaveManager.FORMAT_VERSION >= 1, "the save format is versioned",
		"v%d" % SaveManager.FORMAT_VERSION)

	# Chop BEFORE setting the bag up: a boulder drops stone into the inventory,
	# so doing it the other way round means the counts asserted below are not
	# the counts that were put there.
	for i in tree_node.data.hits_required:
		tree_node.hit()

	var bench := ItemDB.get_item("workbench")
	var built: Node2D = null
	var bench_cell := Vector2i.ZERO
	# Searched, not guessed: the cell four tiles diagonally from spawn is as
	# likely as not to hold a tree, and a test that depends on the scatter
	# missing one particular tile is a test that fails on a new seed.
	for cell in _free_cells_near(world.world_to_cell(player.global_position), 12):
		built = world.build_at(bench.placed_scene, cell, bench.placed_footprint, bench.id)
		if built != null:
			bench_cell = cell
			break
	ck(built != null, "a building can be placed for the save to remember", str(bench_cell))

	# Make the session distinctive in every system, then save it.
	Inventory.clear()
	Inventory.add_item("wood", 7)
	Inventory.add_item("stone", 3)
	Inventory.select_hotbar(2)
	GameState.set_warmth(42.0)
	DayNight.load_data({"time_of_day": 0.61, "day": 5})
	fire.set_fuel(63.0)

	ck(SaveManager.save_game(slot), "save_game writes a slot")
	ck(SaveManager.has_save(slot), "and has_save sees it")

	var raw := FileAccess.get_file_as_string(SaveManager.save_path(slot))
	var parsed: Variant = JSON.parse_string(raw)
	ck(parsed is Dictionary, "the save file is valid JSON", "%d bytes" % raw.length())
	var missing: Array = []
	for key in ["version", "day_night", "game_state", "inventory", "world", "player"]:
		if not (parsed as Dictionary).has(key):
			missing.append(key)
	ck(missing.is_empty(), "every system is in the save", str(missing))
	# The whole point of saving deltas rather than the map: a save of a 96x96
	# island should be kilobytes, not megabytes.
	ck(raw.length() < 64000, "the save stays small — the map is not in it",
		"%.1f KB" % (raw.length() / 1024.0))

	ck(SaveManager.slot_summary(slot).begins_with("Day 5"),
		"a slot can be summarised without loading it", SaveManager.slot_summary(slot))

	# Counted BEFORE the load, not assumed to be zero: phase 8 places a workbench
	# of its own, so the question is whether loading ADDS one, not how many
	# exist on the island.
	var benches_before := _count_scene(bench.placed_scene.resource_path)

	# Now trash everything and load it back.
	Inventory.clear()
	Inventory.add_item("fibre", 99)
	GameState.set_warmth(100.0)
	DayNight.load_data({"time_of_day": 0.1, "day": 99})
	fire.set_fuel(0.0)
	var loaded := SaveManager.read_save(slot)
	SaveManager.apply_data(loaded)

	ck(Inventory.count("wood") == 7 and Inventory.count("stone") == 3,
		"the bag comes back exactly", str(Inventory.totals()))
	ck(Inventory.count("fibre") == 0, "and what was not saved does not survive")
	ck(Inventory.selected_hotbar == 2, "including which hotbar slot was selected")
	ck(is_equal_approx(GameState.warmth, 42.0), "warmth comes back", str(GameState.warmth))
	ck(DayNight.day == 5 and is_equal_approx(DayNight.time_of_day, 0.61),
		"the clock comes back", "day %d at %.2f" % [DayNight.day, DayNight.time_of_day])
	ck(is_equal_approx(fire.fuel, 63.0), "the campfire remembers its fuel", str(fire.fuel))
	ck(not tree_node.is_ready(), "a chopped tree stays chopped")

	# Restored by cell, so loading into a world that still holds the building
	# must not stack a second copy on it — and must not lose the original.
	var benches_after := _count_scene(bench.placed_scene.resource_path)
	ck(benches_after == benches_before, "loading does not duplicate a placed building",
		"%d before, %d after" % [benches_before, benches_after])
	ck(world.can_build(bench_cell, bench.placed_footprint) == false,
		"and its tile is still marked occupied")

	# A file claiming a future format is refused rather than half-read.
	var future := loaded.duplicate()
	future["version"] = SaveManager.FORMAT_VERSION + 99
	var file := FileAccess.open(SaveManager.save_path(slot), FileAccess.WRITE)
	file.store_string(JSON.stringify(future))
	file.close()
	ck(SaveManager.read_save(slot).is_empty(), "a save from a newer version is refused")

	ck(SaveManager.delete_save(slot) and not SaveManager.has_save(slot),
		"a slot can be deleted")

	# --- settings ---
	ck(AudioServer.get_bus_index("Music") > 0 and AudioServer.get_bus_index("SFX") > 0,
		"the Music and SFX buses exist")
	var was := Settings.sfx_volume
	Settings.set_value("sfx_volume", 0.25)
	var sfx_db := AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX"))
	ck(is_equal_approx(sfx_db, linear_to_db(0.25)), "a volume setting reaches the bus",
		"%.1f dB" % sfx_db)
	Settings.set_value("sfx_volume", 0.0)
	ck(AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")),
		"and zero genuinely mutes rather than sitting quiet")
	Settings.set_value("sfx_volume", was)
	Settings.set_value("day_length", 420.0)
	ck(is_equal_approx(DayNight.day_length_seconds, 420.0),
		"the day-length setting reaches the clock")
	Settings.set_value("day_length", 600.0)

	# --- audio assets ---
	var bad: Array = []
	var quiet: Array = []
	var clipped: Array = []
	for stem in ["sfx_step", "sfx_chop", "sfx_pickup", "sfx_craft", "sfx_place",
			"sfx_ui", "sfx_eat", "sfx_fire", "amb_day", "amb_night", "music_theme"]:
		var stream := load("res://assets/audio/%s.res" % stem) as AudioStreamWAV
		if stream == null or stream.data.is_empty():
			bad.append(stem)
			continue
		var peak := 0
		var n := stream.data.size() / 2
		for i in n:
			peak = maxi(peak, absi(stream.data.decode_s16(i * 2)))
		# Clipping is what a careless gain change in build_audio.gd produces,
		# and it is inaudible as a handful of samples until it is not.
		if peak >= 32760:
			clipped.append(stem)
		if peak < 3000:
			quiet.append("%s@%d" % [stem, peak])
	ck(bad.is_empty(), "every sound the game asks for exists", str(bad))
	ck(clipped.is_empty(), "and none of them clip", str(clipped))
	ck(quiet.is_empty(), "and none came out silent", str(quiet))

	var unloopable: Array = []
	for stem in ["sfx_fire", "amb_day", "amb_night", "music_theme"]:
		var stream := load("res://assets/audio/%s.res" % stem) as AudioStreamWAV
		if stream.loop_mode == AudioStreamWAV.LOOP_DISABLED:
			unloopable.append(stem)
	ck(unloopable.is_empty(), "the beds and the theme actually loop", str(unloopable))

	var unregistered: Array = []
	for key in Audio.SFX:
		if not ResourceLoader.exists("res://assets/audio/%s.res" % Audio.SFX[key]):
			unregistered.append(key)
	ck(unregistered.is_empty(), "every registered effect key resolves to a file",
		str(unregistered))

	# --- menus and feedback ---
	var scenes: Array = []
	for path in ["res://scenes/ui/MainMenu.tscn", "res://scenes/ui/PauseMenu.tscn",
			"res://scenes/ui/SettingsPanel.tscn"]:
		var node: Node = (load(path) as PackedScene).instantiate()
		if node == null:
			scenes.append(path)
		else:
			node.free()
	ck(scenes.is_empty(), "the menus instantiate", str(scenes))
	ck(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/ui/MainMenu.tscn",
		"the game boots to the title screen")

	# ⚠️ Load-bearing, not cosmetic. _unhandled_input runs in reverse tree order,
	# so a PauseMenu listed last would swallow the Esc that closes the bag.
	var main := get_node("Main")
	ck(main.get_child(0).name == "PauseMenu",
		"the pause menu is the FIRST child, so Esc reaches it last",
		main.get_child(0).name)
	ck(main.get_node_or_null("PickupFeed") != null, "the pickup feed is in the scene")
	ck(main.get_node_or_null("HUD/Toast") != null, "the HUD has a day toast")
	ck(player.get_node_or_null("Dust") != null, "the player kicks up dust")
	ck(player.get_node_or_null("Camera2D/Fireflies") != null, "fireflies follow the camera")
	ck(player.get_node_or_null("Camera2D/Leaves") != null, "leaves drift on the wind")
	ck(fire.get_node_or_null("Crackle") != null, "the campfire crackles")
	ck(fire.get_node_or_null("Smoke") != null, "and smokes")

	# ⚠️ The spec's "no jitter when the camera moves; snap camera to pixels".
	# Measured before the camera was rewritten: the view centre was off a whole
	# pixel on 99.6% of frames, worst remainder 0.5px. With 2d transform
	# snapping on, that makes neighbouring tiles round their screen position
	# different ways on different frames — the shimmer along tile seams.
	var cam := player.get_node("Camera2D") as PlayerCamera
	ck(cam.top_level and not cam.position_smoothing_enabled,
		"the camera follows on its own, not on Godot's smoothing",
		"top_level=%s godot_smoothing=%s" % [cam.top_level, cam.position_smoothing_enabled])
	var worst := Vector2.ZERO
	for i in 30:
		# Nudge the player by a deliberately awkward fraction each step, so the
		# camera is chasing a target that is never on a pixel itself.
		player.global_position += Vector2(1.37, 0.61)
		cam._process(0.016)
		worst = worst.max(cam.pixel_error())
	ck(worst == Vector2.ZERO, "and lands on whole pixels while it moves",
		"worst remainder %.3f px" % maxf(worst.x, worst.y))

	# The flight needs somewhere to fly TO, and the feed asks by group rather
	# than by path, so a renamed hotbar node must not silently break it.
	var bars := get_tree().get_nodes_in_group("hotbar")
	ck(not bars.is_empty(), "the hotbar is reachable by group for the pickup flight")
	if not bars.is_empty():
		Inventory.clear()
		Inventory.add_item("wood", 1)
		ck(bars[0].slot_centre(0) != Vector2.ZERO,
			"and reports where a slot is on screen", str(bars[0].slot_centre(0)))
		Inventory.clear()

	# Put the world back the way phase 9b expects to find it.
	SaveManager.apply_data(baseline)
	if is_instance_valid(built):
		built.queue_free()
	Inventory.clear()


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
