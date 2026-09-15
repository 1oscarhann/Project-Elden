extends SceneTree

## Cuts the cauldron out of the food icon sheet and makes a 16px world sprite.
##
##     godot --headless --path . --script res://tools/build_cookpot_sprite.gd
##
## ⚠️ WHY THIS EXISTS: there is NO pot or cauldron anywhere in the art packs.
## Sprout Lands' furniture sheet is beds, dressers, chairs, clocks and rugs;
## its objects sheet is trees, bushes, rocks and flowers. Checked both.
##
## The precedent for a missing object is to borrow and flag it — the workbench
## is a dresser and the hut is a chicken coop. But `items_food.png` carries an
## actual cauldron at cell (5,8), so the pot is cut from that instead of being
## mimed by unrelated furniture. Same trick `build_icon_atlas.gd` uses, in
## reverse: icon art trimmed and scaled down to sit on the 16px world grid.

const SRC := "res://assets/icons/items_food.png"
const OUT := "res://assets/objects/cook_pot.png"
## The cauldron, in the 10x10 grid of 32px cells.
const CELL := Vector2i(5, 8)
const CELL_SIZE := 32
## A pot is a chunky object, so it gets the full tile rather than being inset.
const TARGET := 16


func _initialize() -> void:
	var sheet := Image.load_from_file(SRC)
	if sheet == null:
		push_error("build_cookpot_sprite: cannot load %s" % SRC)
		quit(1)
		return

	var cut := Image.create(CELL_SIZE, CELL_SIZE, false, sheet.get_format())
	cut.blit_rect(sheet, Rect2i(CELL * CELL_SIZE, Vector2i(CELL_SIZE, CELL_SIZE)),
		Vector2i.ZERO)

	# Trim to the art's own alpha bounds first. The icon is centred inside a
	# padded cell, and scaling the padding down with it would leave the pot
	# noticeably smaller than every other 16px object on the grid.
	var used := cut.get_used_rect()
	if used.size == Vector2i.ZERO:
		push_error("build_cookpot_sprite: cell %s is empty" % CELL)
		quit(1)
		return
	var art := cut.get_region(used)

	# Lanczos, matching build_icon_atlas — nearest on a downscale drops whole
	# rows of the outline and the pot comes out ragged.
	var longest: int = maxi(art.get_width(), art.get_height())
	var scale := float(TARGET) / float(longest)
	art.resize(maxi(1, roundi(art.get_width() * scale)),
		maxi(1, roundi(art.get_height() * scale)), Image.INTERPOLATE_LANCZOS)

	# Re-centre horizontally on a square canvas and sit it on the BOTTOM edge,
	# so the sprite's own base is its base — the point Y-sorting compares.
	var out := Image.create(TARGET, TARGET, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	out.blit_rect(art, Rect2i(Vector2i.ZERO, art.get_size()),
		Vector2i((TARGET - art.get_width()) / 2, TARGET - art.get_height()))

	var err := out.save_png(OUT)
	if err != OK:
		push_error("build_cookpot_sprite: cannot write %s" % OUT)
		quit(1)
		return
	print("build_cookpot_sprite: %s  %dx%d art -> %dx%d"
		% [OUT, used.size.x, used.size.y, art.get_width(), art.get_height()])
	quit(0)
