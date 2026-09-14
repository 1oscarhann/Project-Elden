extends Node2D

## Phase 10 walkthrough: title screen, settings, a save round-trip, and each
## piece of the polish pass caught in the act.
##
## Needs a real window for the framebuffer, so run it under a display:
##
##     xvfb-run -a godot --path . --rendering-driver opengl3 \
##         res://tools/phase10_shots.tscn
##
## Shots land in user://shots/.

const OUT := "user://shots/"
## Never slot 0 — that is the autosave the title screen's Continue reads, and a
## screenshot run should not leave a save behind in it.
const SLOT := 2

var f := 0
var step := 0
var wait := 0.0
var menu: Control
var game: Node2D
var rooms: RoomManager
var world: World
var player: CharacterBody2D
var fire: Campfire


func _ready() -> void:
	# ⚠️ Set HERE, not at the step that opens the pause menu. Opening it stops
	# the tree, and a node only told to ignore the pause afterwards never runs
	# again to be told — the run hangs with the last two shots untaken.
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(OUT)
	# ⚠️ Under a CanvasLayer, not straight onto this Node2D. A Control only
	# takes the viewport's rect when it is a root control — a child of the
	# window or of a CanvasLayer. Parented to a Node2D it keeps size (0,0), and
	# the menu renders as a clipped panel jammed into the top-left corner.
	# The engine gives the real main scene the first case; this gives the second.
	var layer := CanvasLayer.new()
	add_child(layer)
	menu = (load("res://scenes/ui/MainMenu.tscn") as PackedScene).instantiate()
	layer.add_child(menu)


func shot(name: String) -> void:
	get_viewport().get_texture().get_image().save_png(OUT + name + ".png")
	print("shot ", name)


func _enter_game() -> void:
	game = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	add_child(game)
	rooms = game.get_node("Rooms")
	world = rooms.get_node("World")
	player = world.get_node("Props/Player")
	for child in world.get_node("Props").get_children():
		if child is Campfire:
			fire = child


## Puts the clock somewhere and lets every listener catch up.
func _set_time(t: float, day: int) -> void:
	DayNight.load_data({"time_of_day": t, "day": day})


func _process(delta: float) -> void:
	f += 1
	if f < 3:
		return
	if wait > 0.0:
		wait -= delta
		return
	match step:
		0:
			# The title screen with a save present, so Continue is live and the
			# slot line has something to say.
			DayNight.paused = true
			_set_time(0.42, 3)
			Inventory.add_item("wood", 12)
			GameState.set_warmth(88.0)
			wait = 0.2
		1:
			shot("p10_title_nosave")
			wait = 0.1
		2:
			menu.get_node("SettingsPanel").open()
			wait = 0.2
		3:
			shot("p10_settings")
			menu.get_node("SettingsPanel").close()
			menu.get_parent().queue_free()
			_enter_game()
			# Long enough for the world to build and the fade-in to finish.
			wait = 1.2
		4:
			DayNight.paused = true
			_set_time(0.45, 3)
			Inventory.add_item("wood", 9)
			Inventory.add_item("stone", 4)
			Inventory.add_item("fibre", 6)
			get_tree().call_group(PlayerCamera.GROUP, "snap_to_target")
			wait = 0.3
		5:
			shot("p10_day")
			# The pickup floater, caught mid-rise rather than at either end.
			Inventory.add_item("berries", 3)
			wait = 0.25
		6:
			shot("p10_pickup_text")
			# Day toast.
			DayNight.day_passed.emit(4)
			wait = 0.6
		7:
			shot("p10_day_toast")
			# Night: fireflies, the fire's light, the crackle you cannot see.
			_set_time(0.88, 4)
			fire.set_fuel(70.0)
			player.global_position = fire.global_position + Vector2(20, 18)
			get_tree().call_group(PlayerCamera.GROUP, "snap_to_target")
			# Fireflies fade in over a couple of seconds by design.
			wait = 3.0
		8:
			shot("p10_night_fireflies")
			# Cold: the blue vignette and the shiver, away from the fire.
			player.global_position = fire.global_position + Vector2(220, 60)
			get_tree().call_group(PlayerCamera.GROUP, "snap_to_target")
			GameState.set_warmth(6.0)
			wait = 0.4
		9:
			shot("p10_cold")
			# Save, then prove the load actually restores it: trash the session
			# first so an unchanged shot would be a failed test, not a pass.
			SaveManager.save_game(SLOT)
			Inventory.clear()
			GameState.set_warmth(100.0)
			_set_time(0.45, 99)
			wait = 0.3
		10:
			shot("p10_before_load")
			SaveManager.apply_data(SaveManager.read_save(SLOT))
			get_tree().call_group(PlayerCamera.GROUP, "snap_to_target")
			wait = 0.4
		11:
			shot("p10_after_load")
			SaveManager.delete_save(SLOT)
			# Pause menu last: it stops the tree, so nothing else can run after.
			_set_time(0.45, 4)
			GameState.set_warmth(72.0)
			game.get_node("PauseMenu").set_open(true)
			wait = 0.3
		12:
			shot("p10_pause")
			game.get_node("PauseMenu/SettingsPanel").open()
			wait = 0.3
		13:
			shot("p10_pause_settings")
			wait = 0.1
		14:
			get_tree().paused = false
			Audio.stop_world_audio()
			print("phase10 shots done")
			get_tree().quit(0)
			return
	step += 1
