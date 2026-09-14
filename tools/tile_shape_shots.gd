extends Node2D
## Renders controlled shapes so the tileset's one hard limit can be SEEN.
##
## Top row: shapes as the generator used to be able to emit them. Bottom row:
## the same shapes after 2x2 opening, which is what the generator now
## guarantees. A blob survives unchanged; a one-wide strip, a lone cell and a
## corner-touching diagonal are undrawable by a 16-signature corner-match blob
## set and vanish entirely.
##
##     xvfb-run -a godot --path . --rendering-driver opengl3 \
##         res://tools/tile_shape_shots.tscn

const TS := preload("res://assets/tiles/island_terrain.tres")
const T_SAND := 0
const T_GRASS := 1
const OUT := "user://shots/"
var f := 0

const SHAPES := {
	"blob":    ["..##..", ".####.", "######", "######", ".####.", "..##.."],
	"strip":   ["......", "######", "......", "..#...", "..#...", "..#..."],
	"lone":    ["..#...", "......", "#....#", "......", "...#..", "......"],
	"diag":    ["#.....", "##....", ".##...", "..##..", "...##.", "....##"],
}


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var bg := TileMapLayer.new(); bg.tile_set = TS; add_child(bg)
	var raw := TileMapLayer.new(); raw.tile_set = TS; add_child(raw)
	var pad: Array[Vector2i] = []
	for y in range(-2, 18):
		for x in range(-2, 34):
			pad.append(Vector2i(x, y))
	bg.set_cells_terrain_connect(pad, 0, T_SAND, false)

	var ox := 0
	for name in SHAPES:
		var rows: Array = SHAPES[name]
		var cells := _cells(rows, ox, 0)
		raw.set_cells_terrain_connect(cells, 0, T_GRASS, false)
		# Same shape, opened.
		raw.set_cells_terrain_connect(_open(_cells(rows, ox, 9)), 0, T_GRASS, false)
		ox += 8
	# 4 shapes x 8 cols = 32 cells, 18 rows -> 512x288 at 1:1, which fits the
	# 640x360 viewport. The PNG is upscaled afterwards instead of the scene, so
	# nothing is resampled twice.
	position = Vector2(64, 36)


func _cells(rows: Array, ox: int, oy: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			if row[x] == "#":
				out.append(Vector2i(ox + x, oy + y))
	return out


## Drop every cell that is in no full 2x2 block — the generator's rule.
func _open(cells: Array[Vector2i]) -> Array[Vector2i]:
	var region := {}
	for c in cells:
		region[c] = true
	while true:
		var doomed: Array[Vector2i] = []
		for c in region:
			var kept := false
			for oy in [-1, 0]:
				for ox in [-1, 0]:
					var solid := true
					for dy in 2:
						for dx in 2:
							if not region.has(c + Vector2i(ox + dx, oy + dy)):
								solid = false
					if solid:
						kept = true
			if not kept:
				doomed.append(c)
		if doomed.is_empty():
			break
		for c in doomed:
			region.erase(c)
	var out: Array[Vector2i] = []
	for c in region:
		out.append(c)
	return out


func _process(_d: float) -> void:
	f += 1
	if f != 3:
		return
	var img := get_viewport().get_texture().get_image()
	img.resize(img.get_width() * 2, img.get_height() * 2, Image.INTERPOLATE_NEAREST)
	img.save_png(OUT + "tiles_shapes.png")
	print("shot tiles_shapes")
	get_tree().quit(0)
