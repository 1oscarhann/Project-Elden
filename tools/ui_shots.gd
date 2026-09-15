extends Node2D

## Visual check for the UI theme: opens the journal on each of its tabs and
## shoots it, so a theme that loads but renders wrong cannot pass unnoticed.
##
##     xvfb-run -a godot --path . --rendering-driver opengl3 \
##         res://tools/ui_shots.tscn

const OUT := "user://shots/"

var f := 0
var step := 0
var wait := 0.0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	add_child((load("res://scenes/main/Main.tscn") as PackedScene).instantiate())


func shot(name: String) -> void:
	get_viewport().get_texture().get_image().save_png(OUT + name + ".png")
	print("shot ", name)


func act(name: String) -> void:
	var ev := InputEventAction.new()
	ev.action = name
	ev.pressed = true
	Input.parse_input_event(ev)


func _process(delta: float) -> void:
	f += 1
	if f < 3:
		return
	if wait > 0.0:
		wait -= delta
		return
	match step:
		0:
			DayNight.paused = true
			DayNight.time_of_day = 0.45
			Inventory.clear()
			# Deliberately more kinds than the hotbar holds: the last few land
			# past slot 8, which is exactly the case the journal exists for.
			for pair in [["wood", 24], ["stone", 9], ["plank", 12], ["fibre", 7],
					["berries", 5], ["rope", 2], ["venison", 3], ["bone", 4],
					["cooked_meat", 3], ["campfire_kit", 1], ["fruit", 6],
					["raw_meat", 2], ["workbench", 1]]:
				Inventory.add_item(pair[0], pair[1])
			wait = 0.6
		1:
			shot("01_hud_hotbar")
			act("toggle_inventory")
			wait = 0.6
		2:
			shot("02_bag")
			act("toggle_inventory")
			wait = 0.4
		3:
			act("toggle_crafting")
			wait = 0.7
		4:
			shot("03_crafting")
			act("toggle_build")
			wait = 0.7
		5:
			shot("04_build")
			wait = 0.2
		6:
			get_tree().quit(0)
	step += 1
