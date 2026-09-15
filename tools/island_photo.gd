extends Node2D

## Renders the ENTIRE island as one full-resolution image.
##
## Zooming the camera out to fit 1536x1536 into a 640x360 viewport would throw
## away most of the pixels, so instead the camera pans across the map at 1:1 and
## the frames are stitched. The result is every tile at its real size.
##
##     xvfb-run -a godot --path . --rendering-driver opengl3 \
##         res://tools/island_photo.tscn

const MAIN := preload("res://scenes/main/Main.tscn")
const OUT := "user://shots/"
const FRAME := Vector2i(640, 360)

var f := 0
var step := 0
var wait := 0.0
var world: World
var player: Node2D
var sheet: Image
var span := Vector2i.ZERO
var cols := 0
var rows := 0
var index := 0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	add_child(MAIN.instantiate())


func _process(d: float) -> void:
	f += 1
	if f < 3:
		return
	if wait > 0.0:
		wait -= d
		return
	if step == 0:
		_setup()
		step = 1
		wait = 0.4
		return
	if index >= cols * rows:
		# Trim the overshoot from the right and bottom.
		var final := Image.create_empty(span.x, span.y, false, Image.FORMAT_RGBA8)
		final.blit_rect(sheet, Rect2i(Vector2i.ZERO, span), Vector2i.ZERO)
		final.save_png(OUT + "island_photo.png")
		print("island photo: %dx%d px from %d frames" % [span.x, span.y, cols * rows])
		Audio.stop_world_audio()
		get_tree().quit(0)
		return
	if step == 1:
		var col := index % cols
		var row := index / cols
		# Aim at the centre of this tile of the grid. Whole numbers, so the
		# pixel-snapped camera lands exactly and the seams line up.
		player.global_position = Vector2(col * FRAME.x + FRAME.x / 2,
			row * FRAME.y + FRAME.y / 2)
		get_tree().call_group(PlayerCamera.GROUP, "snap_to_target")
		step = 2
		wait = 0.12
		return
	if step == 2:
		var frame := get_viewport().get_texture().get_image()
		sheet.blit_rect(frame, Rect2i(Vector2i.ZERO, FRAME),
			Vector2i((index % cols) * FRAME.x, (index / cols) * FRAME.y))
		index += 1
		step = 1
		wait = 0.03


func _setup() -> void:
	DayNight.paused = true
	# Mid-morning: full daylight, so the sky tint is not darkening anything.
	DayNight.load_data({"time_of_day": 0.40, "day": 1})
	world = get_node("Main/Rooms/World")
	player = world.get_node("Props/Player")
	for n in ["Main/HUD", "Main/Hotbar"]:
		get_node(n).visible = false
	player.visible = false
	# ⚠️ Freeze the player, or the camera will not land where it is told. The
	# player is a CharacterBody2D and every capture point out at sea sits inside
	# the ocean's collider, so move_and_slide depenetrates it a few pixels and
	# the camera follows — which showed up as a band of the engine's clear
	# colour (#87C2D9 against the sea's #9BD4C3) along the map's top edge.
	player.set_physics_process(false)
	player.velocity = Vector2.ZERO
	# ⚠️ Drop the shimmer for the stitch. It animates on TIME, so each of the
	# frames catches it at a different instant and the sea ends up in visibly
	# different tonal blocks where they meet. A still cannot show shimmer
	# anyway, so the only thing lost is an artefact.
	var water: TileMapLayer = world.get_node("Water")
	water.material = null

	var cam: Camera2D = player.get_node("Camera2D")
	cam.zoom = Vector2.ONE
	# Limits would stop the camera reaching the map's edges.
	cam.set_world_bounds(Rect2())
	span = world.generator.map_size * world.get_node("Water").tile_set.tile_size
	cols = int(ceil(float(span.x) / FRAME.x))
	rows = int(ceil(float(span.y) / FRAME.y))
	sheet = Image.create_empty(cols * FRAME.x, rows * FRAME.y, false, Image.FORMAT_RGBA8)
	print("island is %s px -> %d x %d frames at 1:1" % [span, cols, rows])
