extends Node2D

## Phase 9 walkthrough: finds wildlife, walks the player at it to make it bolt,
## then hunts one, saving a screenshot at each beat.
##
## Needs a real window for the framebuffer, so run it under a display:
##
##     xvfb-run -a godot --path . --rendering-driver opengl3 \
##         res://tools/phase9_shots.tscn
##
## Shots land in user://shots/.

const OUT := "user://shots/"

var f := 0
var step := 0
var wait := 0.0
var rooms: RoomManager
var world: World
var player: CharacterBody2D
var spawner: AnimalSpawner
var quarry: Animal


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	add_child((load("res://scenes/main/Main.tscn") as PackedScene).instantiate())


func shot(name: String) -> void:
	get_viewport().get_texture().get_image().save_png(OUT + name + ".png")
	print("shot ", name)


## Stand the player a short way off and snap the camera onto them.
##
## Teleporting ignores collision, so a naive offset happily parks the player in
## the sea when the animal is near a shore — which looks broken in a shot even
## though it is unreachable in play. Mirror the offset and shorten it until it
## lands on painted ground.
func watch(at: Vector2, offset: Vector2) -> void:
	var chosen := at + offset
	for scale in [1.0, 0.75, 0.5]:
		for flip in [1.0, -1.0]:
			var point: Vector2 = at + Vector2(offset.x * flip, offset.y) * scale
			if world.ground_layer.get_cell_source_id(world.world_to_cell(point)) != -1:
				chosen = point
				scale = -1.0
				break
		if scale < 0.0:
			break
	player.global_position = chosen
	get_tree().call_group(PlayerCamera.GROUP, "snap_to_target")


## Re-aim on the animal's CURRENT position and give the camera one frame to
## land. A wandering animal drifts a long way during a wait, so aiming early
## and shooting late put it outside the frame entirely.
func aim(distance: float) -> void:
	watch(quarry.global_position, Vector2(distance, 6))
	wait = 0.06


## The animal with the most neighbours actually ON SCREEN if we stand there.
## Scored against the viewport box, not a radius: the visible area is 320x180
## world px, so a circle counts animals 120px above that are not in frame.
func _busiest() -> Vector2:
	var best := world.entry_position()
	var most := -1
	var animals: Array = []
	for child in world.get_node("Props").get_children():
		if child is Animal and (child as Animal).is_alive():
			animals.append(child)
	for a in animals:
		var near := 0
		for b in animals:
			var d: Vector2 = (b.global_position - a.global_position).abs()
			if d.x < 140.0 and d.y < 74.0:
				near += 1
		if near > most:
			most = near
			best = a.global_position
	print("busiest spot has ", most, " animals in frame")
	return best


func _process(delta: float) -> void:
	f += 1
	if f < 3:
		return
	if wait > 0.0:
		wait -= delta
		return

	match step:
		0:
			rooms = get_node("Main/Rooms")
			world = rooms.get_node("World")
			player = world.get_node("Props/Player")
			spawner = world.get_node("Animals")
			DayNight.paused = true
			DayNight.time_of_day = 0.45
			Inventory.clear()
			print("alive=", spawner.total_alive())
			wait = 1.0
		1:
			# A deer if there is one — it is the biggest and reads best.
			for child in world.get_node("Props").get_children():
				if child is Animal and (child as Animal).data.id == "deer":
					quarry = child
					break
			if quarry == null:
				for child in world.get_node("Props").get_children():
					if child is Animal:
						quarry = child
						break
			print("quarry=", quarry.data.id)
			# Park the player well clear so it stays calm while it settles.
			watch(quarry.global_position, Vector2(600, 0))
			# Longer than the longest flee_memory, or the "grazing" shot catches
			# an animal still running from the player's arrival.
			wait = 4.5
		2:
			# Just outside its detection radius, so it is still grazing.
			aim(quarry.data.detection_radius + 18.0)
		3:
			print("calm state=", quarry._state, " (0 rest, 1 wander)")
			shot("01_grazing")
			wait = 0.1
		4:
			# Step inside the circle.
			watch(quarry.global_position, Vector2(50, 8))
			wait = 0.3
		5:
			aim(56.0)
		6:
			print("state=", quarry._state, " (2 = FLEE)")
			shot("02_fleeing")
			wait = 0.6
		7:
			# Close in again and take it.
			watch(quarry.global_position, Vector2(20, 10))
			wait = 0.3
		8:
			var hits := 0
			while quarry.is_alive() and hits < 12:
				quarry.hit()
				hits += 1
			print("hunted in ", hits, " swings; bag=", Inventory.totals())
			wait = 0.3
		9:
			# Step aside so the carcass is not hidden behind the player.
			aim(34.0)
		10:
			shot("03_hunted")
			Inventory.select_hotbar(0)
			wait = 0.3
		11:
			shot("04_drops")
			# Look wherever the wildlife actually is. Framing on spawn and
			# hoping is how the first attempt produced an empty field.
			watch(_busiest(), Vector2.ZERO)
			wait = 1.0
		12:
			print("still alive=", spawner.total_alive())
			shot("05_wildlife")
			wait = 0.2
		13:
			get_tree().quit(0)
	step += 1
