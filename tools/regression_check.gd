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
const EXPECTED_CHECKS := 78

var f := 0
var fails := 0
var checks := 0
var rooms: RoomManager
var world: World
var props: Node2D
var player: CharacterBody2D
var fire: Campfire
var tree_node: Harvestable


func ck(ok: bool, what: String, detail: String = "") -> void:
	checks += 1
	if not ok:
		fails += 1
	print(("  ok   " if ok else " FAIL  "), what, ("   " + detail) if detail else "")


func _ready() -> void:
	add_child((load("res://scenes/main/Main.tscn") as PackedScene).instantiate())


func _process(_delta: float) -> void:
	f += 1
	if f != 2:
		if f > 2:
			get_tree().quit(fails)
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
	var water: TileMapLayer = world.get_node("Water")
	var ground: TileMapLayer = world.get_node("Ground")
	var total: int = water.get_used_cells().size() + ground.get_used_cells().size()
	ck(total == world.generator.map_size.x * world.generator.map_size.y,
		"every cell painted exactly once", str(total))
	var overlap := 0
	for c in ground.get_used_cells():
		if water.get_cell_source_id(c) != -1:
			overlap += 1
	ck(overlap == 0, "water and land never overlap", str(overlap))
	var src: TileSetAtlasSource = water.tile_set.get_source(0)
	ck(src.get_tile_animation_frames_count(Vector2i(0, 0)) > 1, "water animates")
	ck(src.get_tile_data(Vector2i(0, 0), 0).get_collision_polygons_count(0) > 0,
		"water carries collision")
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
