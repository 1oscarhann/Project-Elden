extends Node2D

## Phase 8 walkthrough: drives build mode through its real input path, places a
## hut, steps inside and back out, saving a screenshot at each beat.
##
## Needs a real window for the framebuffer, so run it under a display:
##
##     xvfb-run -a godot --path . --rendering-driver opengl3 \
##         res://tools/phase8_shots.tscn
##
## Shots land in user://shots/.

const OUT := "user://shots/"

var f := 0
var step := 0
var wait := 0
var tries := 0
var rooms: RoomManager
var world: World
var player: CharacterBody2D
var build: Node2D
var hut: Node2D
var target := Vector2i.ZERO


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	add_child((load("res://scenes/main/Main.tscn") as PackedScene).instantiate())


func _act(name: String) -> void:
	var ev := InputEventAction.new()
	ev.action = name
	ev.pressed = true
	Input.parse_input_event(ev)


func shot(name: String) -> void:
	get_viewport().get_texture().get_image().save_png(OUT + name + ".png")
	print("shot ", name)


## Camera smoothing means a one-shot world->screen warp lands off by a few
## pixels, so nudge the cursor until the ghost actually reports the cell we want.
func aim(cell: Vector2i) -> bool:
	var want := Vector2(cell * 16) + Vector2(8, 8)
	var cam := get_viewport().get_camera_2d()
	var here: Vector2i = build._cell
	var screen := (want - cam.get_screen_center_position()) * cam.zoom \
		+ Vector2(get_viewport().get_visible_rect().size) * 0.5
	get_viewport().warp_mouse(screen)
	return here == cell


## First free 3x3 patch within reach of the player.
func free_patch(from: Vector2i) -> Vector2i:
	for r in range(2, 7):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var c := from + Vector2i(dx, dy)
				if world.can_build(c - Vector2i(1, 2), Vector2i(3, 3)):
					return c
	return Vector2i.ZERO


func _process(_delta: float) -> void:
	f += 1
	if f < 3:
		return
	if wait > 0:
		wait -= 1
		return

	match step:
		0:
			rooms = get_node("Main/Rooms")
			world = rooms.get_node("World")
			player = world.get_node("Props/Player")
			build = player.get_node("BuildMode")
			DayNight.paused = true
			DayNight.time_of_day = 0.45
			Inventory.clear()
			Inventory.add_item("hut_kit", 2)
			Inventory.add_item("fence", 8)
			Inventory.select_hotbar(0)
			target = free_patch(world.world_to_cell(player.global_position))
			print("target cell=", target)
			wait = 6
		1:
			_act("toggle_build")
			wait = 4
		2:
			# Hold here until the cursor is locked on the cell we picked.
			# Retry in place — stepping back would re-run the toggle.
			if not aim(target):
				tries += 1
				if tries > 40:
					push_error("could not aim at %s" % target)
					get_tree().quit(1)
				return
			tries = 0
			wait = 2
		3:
			print("ghost valid=", build._valid, " cell=", build._cell, " want=", target)
			shot("01_build_ghost")
			wait = 2
		4:
			_act("place_building")
			wait = 6
		5:
			for c in world.get_node("Props").get_children():
				if c.scene_file_path.ends_with("Hut.tscn"):
					hut = c
			print("hut=", hut, " at ", hut.position if hut else "-",
				" kits left=", Inventory.count("hut_kit"))
			_act("toggle_build")
			wait = 6
		6:
			shot("02_hut_placed")
			wait = 2
		7:
			# Ghost over the hut we just built: the blocked state.
			Inventory.select_hotbar(1)
			_act("toggle_build")
			wait = 4
		8:
			if not aim(target):
				tries += 1
				if tries > 40:
					push_error("could not aim at the hut")
					get_tree().quit(1)
				return
			tries = 0
			wait = 2
		9:
			print("blocked ghost valid=", build._valid, " (want false)")
			shot("03_ghost_blocked")
			_act("toggle_build")
			wait = 4
		10:
			# Walk into the doorway.
			player.global_position = hut.global_position + Vector2(0, -2)
			wait = 40
		11:
			print("room now=", rooms.current_room().name,
				" warmed=", GameState.is_warmed(),
				" heat=", GameState.heat_source_count())
			shot("04_interior")
			# And a look at the room proper, a few tiles in.
			player.global_position += Vector2(0, -32)
			wait = 20
		12:
			shot("05_interior_room")
			wait = 2
		13:
			var exit := rooms.current_room().get_node_or_null("ExitDoor") as Area2D
			player.global_position = exit.global_position
			wait = 10
		14:
			wait = 50
		15:
			print("back in=", rooms.current_room().name, " heat=", GameState.heat_source_count())
			shot("06_back_outside")
			wait = 2
		16:
			get_tree().quit(0)
	step += 1
