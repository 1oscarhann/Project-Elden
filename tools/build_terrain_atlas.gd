extends SceneTree

## Builds assets/tiles/island_terrain.png from the Sprout Lands sheets.
##
## The atlas is 4 columns x 5 rows of 16px tiles, one terrain per row, in the
## order consumed by scripts/world/island_generator.gd. Columns are variants,
## except the two water rows where the four columns are animation frames.
##
## Run with:  godot --headless --path . --script res://tools/build_terrain_atlas.gd

const TILE := 16
const COLS := 4
const SRC := "res://assets/tiles/sprout_lands/"

## row -> [sheet, [cells...], darken]
## Cells are (x, y) in 16px units within that sheet. Chosen by scanning every
## cell for full opacity; see CLAUDE.md for the coordinates and why.
##
## There is no stone row: the island has no rock terrain. Stone comes from
## boulders scattered on the ground as Harvestable nodes.
const LAYOUT := [
	# Deep water: the pack has one water tile, so depth is that tile darkened.
	["Water.png", [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)], 0.62],
	["Water.png", [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)], 1.0],
	# Beaches use the pack's pale tilled earth — it reads as sand at this size.
	["Tilled_Dirt.png", [Vector2i(0, 5), Vector2i(1, 5), Vector2i(2, 5), Vector2i(0, 6)], 1.0],
	["Grass.png", [Vector2i(0, 5), Vector2i(1, 5), Vector2i(2, 6), Vector2i(3, 6)], 1.0],
	# The pack has no dark grass, so forest is its grass darkened. The licence
	# explicitly allows modifying the assets.
	["Grass.png", [Vector2i(0, 5), Vector2i(1, 5), Vector2i(2, 6), Vector2i(3, 6)], 0.80],
]


func _initialize() -> void:
	var out := Image.create(TILE * COLS, TILE * LAYOUT.size(), false, Image.FORMAT_RGBA8)
	var sheets := {}
	for row in LAYOUT.size():
		var entry: Array = LAYOUT[row]
		var name: String = entry[0]
		if not sheets.has(name):
			var path := SRC + name
			if not ResourceLoader.exists(path) and not FileAccess.file_exists(path):
				push_error("Missing %s — extract the Sprout Lands basic pack into %s" % [name, SRC])
				quit(1)
				return
			var img := Image.load_from_file(ProjectSettings.globalize_path(path))
			img.convert(Image.FORMAT_RGBA8)
			sheets[name] = img
		var sheet: Image = sheets[name]
		var cells: Array = entry[1]
		var darken: float = entry[2]
		for col in COLS:
			var cell: Vector2i = cells[col % cells.size()]
			var piece: Image = sheet.get_region(Rect2i(cell * TILE, Vector2i(TILE, TILE)))
			if not is_equal_approx(darken, 1.0):
				_darken(piece, darken)
			out.blit_rect(piece, Rect2i(0, 0, TILE, TILE), Vector2i(col * TILE, row * TILE))
	var err := out.save_png("res://assets/tiles/island_terrain.png")
	print("wrote assets/tiles/island_terrain.png  (%dx%d)  save=%s"
		% [out.get_width(), out.get_height(), error_string(err)])
	quit()


func _darken(img: Image, factor: float) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			img.set_pixel(x, y, Color(c.r * factor, c.g * factor, c.b * factor, c.a))
