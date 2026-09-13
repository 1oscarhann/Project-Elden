extends SceneTree

## Cleans a CraftPix icon sheet into a usable item-icon atlas.
##
## The sheets shipped in assets/icons/ are marketing previews, not game-ready:
## they are 3x nearest upscales (verified by an integer-scale error sweep -
## scale 3 scores 0.016 against 0.071 and 0.116 either side), they sit on an
## OPAQUE brown background, and they have category labels baked into the left
## margin. So each sheet is downscaled to native, the background is keyed out,
## the label margin is skipped, and every icon is re-centred into a clean
## transparent cell. Re-centring from the icon's own alpha bounds means a few
## pixels of error in the detected grid origin cannot misalign anything.
##
## Run with:  godot --headless --path . --script res://tools/build_icon_atlas.gd

const SCALE := 3          ## sheets are a 3x upscale of their native size
const PITCH := 36         ## native pixels between icon centres
const OUT_CELL := 32      ## output cell size
const COLS := 10
const ROWS := 10
const BG := Color(0.5686, 0.4941, 0.4118)
const BG_TOLERANCE := 0.06

## source file -> [first content x, first content y] in NATIVE pixels, found by
## scanning for the background gutters between icons.
const SHEETS := {
	"icons_food.png": Vector2i(211, 20),
	"icons_tools_ores.png": Vector2i(208, 23),
}


func _initialize() -> void:
	for name in SHEETS:
		_build(name, SHEETS[name])
	quit()


func _build(name: String, first: Vector2i) -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path("res://assets/icons/" + name))
	if img == null:
		push_error("missing res://assets/icons/" + name)
		return
	img.convert(Image.FORMAT_RGBA8)
	img.resize(img.get_width() / SCALE, img.get_height() / SCALE, Image.INTERPOLATE_NEAREST)

	# The icon is 30px inside a 36px pitch, so back off by the 3px margin.
	var origin := first - Vector2i(3, 3)
	var out := Image.create(COLS * OUT_CELL, ROWS * OUT_CELL, false, Image.FORMAT_RGBA8)
	var kept := 0
	for row in ROWS:
		for col in COLS:
			var src := Rect2i(origin + Vector2i(col, row) * PITCH, Vector2i(PITCH, PITCH))
			if src.end.x > img.get_width() or src.end.y > img.get_height():
				continue
			var cell := img.get_region(src)
			_key_out_background(cell)
			var used := cell.get_used_rect()
			if used.size == Vector2i.ZERO:
				continue
			# Re-centre from the icon's own bounds, so grid drift cannot bite.
			var art := cell.get_region(used)
			if art.get_width() > OUT_CELL or art.get_height() > OUT_CELL:
				continue
			var at := Vector2i(col, row) * OUT_CELL + (Vector2i(OUT_CELL, OUT_CELL) - used.size) / 2
			out.blit_rect(art, Rect2i(Vector2i.ZERO, used.size), at)
			kept += 1

	var dest := "res://assets/icons/items_" + name.replace("icons_", "")
	print("%s -> %s  (%d icons, %dx%d)"
		% [name, dest.get_file(), kept, out.get_width(), out.get_height()])
	var err := out.save_png(dest)
	if err != OK:
		push_error("save failed: " + error_string(err))


## The preview background is opaque; make it transparent so icons can sit on
## any UI colour.
func _key_out_background(cell: Image) -> void:
	for y in cell.get_height():
		for x in cell.get_width():
			var c := cell.get_pixel(x, y)
			if absf(c.r - BG.r) < BG_TOLERANCE and absf(c.g - BG.g) < BG_TOLERANCE \
					and absf(c.b - BG.b) < BG_TOLERANCE:
				cell.set_pixel(x, y, Color(0, 0, 0, 0))
