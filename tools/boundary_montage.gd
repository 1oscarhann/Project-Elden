extends Node2D

## Samples boundaries from all over the island at the SAME 6x zoom the owner
## approved, and tiles them into one contact sheet.
##
## The point is not "one spot looks right" — it is whether that quality holds in
## any given area. Every sample is a real boundary cell picked from a different
## part of the map, spread so no two come from the same neighbourhood.
##
##     xvfb-run -a godot --path . --rendering-driver opengl3 \
##         res://tools/boundary_montage.tscn

const MAIN := preload("res://scenes/main/Main.tscn")
const OUT := "user://shots/"
## Each cell of the sheet, cropped from the centre of the 640x360 viewport.
const CROP := Vector2i(320, 180)
const COLS := 4
const ROWS := 3
const ZOOM := 6.0
## Samples must be at least this far apart, in tiles.
const SPREAD := 14

var f := 0
var step := 0
var wait := 0.0
var world: World
var player: Node2D
var cam: Camera2D
var sheet: Image
var points: Array[Vector2] = []
var labels: Array[String] = []
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
		wait = 0.3
		return
	if index >= points.size():
		sheet.save_png(OUT + "boundary_montage.png")
		print("montage: %d samples -> boundary_montage.png" % points.size())
		for i in labels.size():
			print("   %d. %s" % [i + 1, labels[i]])
		Audio.stop_world_audio()
		get_tree().quit(0)
		return
	if wait <= 0.0 and step == 1:
		# Aim, then capture on the NEXT visit so the camera has actually moved.
		player.global_position = points[index]
		get_tree().call_group(PlayerCamera.GROUP, "snap_to_target")
		step = 2
		wait = 0.15
		return
	if step == 2:
		_capture(index)
		index += 1
		step = 1
		wait = 0.05


func _setup() -> void:
	DayNight.paused = true
	DayNight.load_data({"time_of_day": 0.45, "day": 1})
	world = get_node("Main/Rooms/World")
	player = world.get_node("Props/Player")
	cam = player.get_node("Camera2D")
	for n in ["Main/HUD", "Main/Hotbar"]:
		get_node(n).visible = false
	player.visible = false
	cam.zoom = Vector2(ZOOM, ZOOM)
	# Camera limits would stop the view centring on a coastal sample.
	cam.set_world_bounds(Rect2())
	sheet = Image.create_empty(CROP.x * COLS, CROP.y * ROWS, false, Image.FORMAT_RGBA8)
	_pick_points()


## One sample per boundary KIND, spread across the map.
func _pick_points() -> void:
	var T := IslandGenerator.Terrain
	var kinds := [
		[T.GRASS, T.SAND, "grass meets sand"],
		[T.SAND, T.SHALLOW_WATER, "sand meets water"],
		[T.FOREST, T.GRASS, "woodland meets grass"],
		[T.FOREST, T.SAND, "woodland meets sand"],
	]
	var chosen: Array[Vector2i] = []
	var size := world.generator.map_size
	for kind in kinds:
		var found := 0
		# Walk the map on a coarse stride so samples come from everywhere
		# rather than all out of the first region encountered.
		for y in range(2, size.y - 2, 3):
			for x in range(2, size.x - 2, 3):
				if found >= COLS * ROWS / kinds.size():
					break
				var cell := Vector2i(x, y)
				if world.terrain_at(cell) != int(kind[0]):
					continue
				var touches := false
				for dd in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					if world.terrain_at(cell + dd) == int(kind[1]):
						touches = true
				if not touches:
					continue
				var far := true
				for c in chosen:
					if absi(c.x - cell.x) < SPREAD and absi(c.y - cell.y) < SPREAD:
						far = false
						break
				if not far:
					continue
				chosen.append(cell)
				points.append(Vector2(cell * 16) + Vector2(8, 8))
				labels.append("%s  at %s" % [kind[2], cell])
				found += 1
			if found >= COLS * ROWS / kinds.size():
				break


func _capture(slot: int) -> void:
	var frame := get_viewport().get_texture().get_image()
	var src := Rect2i((Vector2i(frame.get_width(), frame.get_height()) - CROP) / 2, CROP)
	var at := Vector2i((slot % COLS) * CROP.x, (slot / COLS) * CROP.y)
	sheet.blit_rect(frame, src, at)
