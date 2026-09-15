extends Node2D

## The cook pot, placed and used.
##
##     xvfb-run -a godot --path . --rendering-driver opengl3 \
##         res://tools/cooking_shots.tscn
##
## Drives the real path rather than the API: the pot is built through
## World.build_at, the station registers because the PLAYER IS STANDING IN IT,
## and the dishes are crafted from the journal's own Craft tab. A menu that
## lists a dish is not the same as a pot that cooks one.

const OUT := "user://shots/"

var t := 0.0
var step := 0
var game: Node2D
var world: World
var player: CharacterBody2D
var journal: CanvasLayer
var pot: Node2D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	GameState.intro_shown = true
	game = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	add_child(game)
	world = game.get_node("Rooms/World")
	player = game.get_node("Rooms/World/Props/Player")
	journal = game.get_node("Journal")
	DayNight.paused = true
	DayNight.time_of_day = 0.42
	Weather.paused = true


func shot(name: String) -> void:
	get_viewport().get_texture().get_image().save_png(OUT + name + ".png")
	print("shot ", name)


func _stock() -> void:
	Inventory.clear()
	for pair in [["venison", 3], ["fruit", 6], ["fibre", 9], ["berries", 8],
			["roast_venison", 2], ["roast_poultry", 2], ["wood", 12]]:
		Inventory.add_item(pair[0], pair[1])


func _process(delta: float) -> void:
	t += delta
	match step:
		0:
			if t < 0.8:
				return
			step = 1
			_stock()
			# Straight onto the player's own tile, so standing still is standing
			# in it — the station registers through body_entered like in play.
			var cell := world.world_to_cell(player.global_position)
			for offset in [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]:
				if world.can_build(cell + offset, Vector2i(1, 1)):
					var item := ItemDB.get_item("cook_pot")
					pot = world.build_at(item.placed_scene, cell + offset,
						item.placed_footprint, item.id)
					break
			print("pot placed: ", pot != null)
		1:
			# Physics has to flush before the Area2D notices the player.
			if t < 1.8:
				return
			step = 2
			if pot != null:
				player.global_position = pot.global_position + Vector2(0, 14)
		2:
			if t < 2.8:
				return
			step = 3
			print("at a pot: ", Crafting.has_station("cookpot"),
				"   stations: ", Crafting.nearby_stations())
			shot("cook_0_pot_placed")
		3:
			if t < 3.2:
				return
			step = 4
			journal._show_tab("crafting")
			journal.set_open(true)
		4:
			if t < 4.0:
				return
			step = 5
			shot("cook_1_menu")
			var made: Array = []
			for recipe in Crafting.all_recipes():
				if recipe.required_station == "cookpot" and Crafting.can_craft(recipe):
					made.append(recipe.result_item_id)
			print("cookable right now: ", made)
		5:
			if t < 4.4:
				return
			step = 6
			for recipe in Crafting.all_recipes():
				if recipe.required_station == "cookpot":
					Crafting.craft(recipe)
			journal._show_tab("inventory")
		6:
			if t < 5.2:
				return
			step = 7
			shot("cook_2_dishes")
			for id in ["fruit_broth", "herb_pottage", "forest_stew", "game_pie"]:
				var item := ItemDB.get_item(id)
				print("  %-14s x%d   hunger %.0f  thirst %.0f  warmth %.0f"
					% [id, Inventory.count(id), item.stat("hunger", 0.0),
						item.stat("thirst", 0.0), item.stat("warmth", 0.0)])
			journal.set_open(false)
		7:
			if t < 5.8:
				return
			# Walk away: the station must UNregister, or the pot would cook
			# from anywhere on the island.
			step = 8
			player.global_position += Vector2(200, 0)
		8:
			if t < 6.6:
				return
			step = 9
			print("walked away, still at a pot: ", Crafting.has_station("cookpot"))
			shot("cook_3_away")
		9:
			if t < 7.0:
				return
			_silence()
			get_tree().quit(0)


func _silence() -> void:
	Audio.stop_world_audio()
	_stop(get_tree().root)


func _stop(node: Node) -> void:
	if node is AudioStreamPlayer or node is AudioStreamPlayer2D:
		node.stop()
	for c in node.get_children():
		_stop(c)
