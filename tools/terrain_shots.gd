extends Node2D

## Wide looks at the island, for judging terrain transitions. Camera zoom is
## pulled back deliberately: blocky edges are invisible at play zoom and
## obvious from above.
##
##     xvfb-run -a godot --path . --rendering-driver opengl3 \
##         res://tools/terrain_shots.tscn

const OUT := "user://shots/"

var f := 0
var step := 0
var wait := 0.0
var world: World
var player: Node2D
var cam: Camera2D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	add_child((load("res://scenes/main/Main.tscn") as PackedScene).instantiate())


func shot(name: String) -> void:
	get_viewport().get_texture().get_image().save_png(OUT + name + ".png")
	print("shot ", name)


func look(at: Vector2, zoom: float) -> void:
	player.global_position = at
	cam.zoom = Vector2(zoom, zoom)
	cam.reset_smoothing()
	cam.force_update_scroll()


func _process(delta: float) -> void:
	f += 1
	if f < 3:
		return
	if wait > 0.0:
		wait -= delta
		return
	match step:
		0:
			world = get_node("Main/Rooms/World")
			player = world.get_node("Props/Player")
			cam = player.get_node("Camera2D")
			DayNight.paused = true
			DayNight.time_of_day = 0.45
			# Hide the player so the ground is unobstructed.
			player.get_node("Sprite").visible = false
			player.get_node("Shadow").visible = false
			var size: Vector2i = world.generator.map_size
			look(Vector2(size * 16) * 0.5, 0.30)
			wait = 0.5
		1:
			shot("t1_island")
			# A coastline, where sand meets sea.
			look(_find_boundary(IslandGenerator.Terrain.SAND, IslandGenerator.Terrain.SHALLOW_WATER), 1.0)
			wait = 0.4
		2:
			shot("t2_shore")
			look(_find_boundary(IslandGenerator.Terrain.GRASS, IslandGenerator.Terrain.SAND), 1.0)
			wait = 0.4
		3:
			shot("t3_grass_sand")
			look(_find_boundary(IslandGenerator.Terrain.FOREST, IslandGenerator.Terrain.GRASS), 1.0)
			wait = 0.4
		4:
			shot("t4_woodland")
			# Open sea, held still, shot twice — the shimmer has to be provable
			# rather than asserted, and it cannot be seen in one still.
			var size: Vector2i = world.generator.map_size
			look(Vector2(size.x * 16 * 0.5, 6 * 16), 1.0)
			wait = 0.4
		5:
			shot("t5_water_a")
			wait = 1.7
		6:
			shot("t5_water_b")
			wait = 0.2
		7:
			get_tree().quit(0)
	step += 1


## Somewhere the two terrains actually touch, so the shot frames a real edge
## instead of the middle of a field.
func _find_boundary(a: int, b: int) -> Vector2:
	var grid: Array = world.generator.generate()
	var size: Vector2i = world.generator.map_size
	var best := Vector2(size * 16) * 0.5
	var most := -1
	for y in range(6, size.y - 6, 3):
		for x in range(6, size.x - 6, 3):
			var seen_a := 0
			var seen_b := 0
			for dy in range(-5, 6):
				for dx in range(-5, 6):
					var t := int(grid[y + dy][x + dx])
					if t == a: seen_a += 1
					elif t == b: seen_b += 1
			var score: int = mini(seen_a, seen_b)
			if score > most:
				most = score
				best = Vector2(Vector2i(x, y) * 16)
	return best
