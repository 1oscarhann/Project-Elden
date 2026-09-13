extends SceneTree

## Cleans the CraftPix icon sheets into usable item-icon atlases.
##
## The sheets in assets/icons/ are marketing previews, not game art: they are
## integer upscales sitting on an OPAQUE background, and two of them have
## category labels baked into the left margin. Each is downscaled to native,
## the background is keyed out, the label margin is skipped, and every icon is
## re-centred into a clean transparent cell from its own alpha bounds — so a
## few pixels of error in the detected grid cannot misalign anything.
##
## The two sheet families differ and both are handled:
##   food / tools_ores    3x upscale, brown bg, 10x10 grid, pitch 36, 30px art
##   potions / meat_bones 2x upscale, dark bg,  8x6  grid, pitch 80x72, 70px art
## The 70px art is halved so every atlas lands near a 32-36px cell.
##
## Run with:  godot --headless --path . --script res://tools/build_icon_atlas.gd

const SHEETS := {
	"icons_food.png": {
		"scale": 3, "first": Vector2i(211, 20), "pitch": Vector2i(36, 36),
		"icon": 30, "cols": 10, "rows": 10, "cell": 32, "shrink": 1,
		"bg": [Color(0.5686, 0.4941, 0.4118)],
	},
	"icons_tools_ores.png": {
		"scale": 3, "first": Vector2i(208, 23), "pitch": Vector2i(36, 36),
		"icon": 30, "cols": 10, "rows": 10, "cell": 32, "shrink": 1,
		"bg": [Color(0.5686, 0.4902, 0.4196)],
	},
	"icons_potions_flasks.png": {
		"scale": 2, "first": Vector2i(45, 27), "pitch": Vector2i(80, 72),
		"icon": 70, "cols": 8, "rows": 6, "cell": 36, "shrink": 2,
		"bg": [Color(0.1922, 0.1373, 0.1255), Color(0.275, 0.2, 0.175)],
	},
	"icons_raw_meat_bones.png": {
		"scale": 2, "first": Vector2i(45, 26), "pitch": Vector2i(80, 72),
		"icon": 70, "cols": 8, "rows": 6, "cell": 36, "shrink": 2,
		"bg": [Color(0.1882, 0.1373, 0.1176), Color(0.275, 0.2, 0.175)],
	},
}

const BG_TOLERANCE := 0.07


func _initialize() -> void:
	for name in SHEETS:
		_build(name, SHEETS[name])
	quit()


func _build(name: String, cfg: Dictionary) -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path("res://assets/icons/" + name))
	if img == null:
		push_error("missing res://assets/icons/" + name)
		return
	img.convert(Image.FORMAT_RGBA8)
	var scale: int = cfg["scale"]
	img.resize(img.get_width() / scale, img.get_height() / scale, Image.INTERPOLATE_NEAREST)

	var pitch: Vector2i = cfg["pitch"]
	var icon: int = cfg["icon"]
	var cell: int = cfg["cell"]
	var shrink: int = cfg["shrink"]
	var cols: int = cfg["cols"]
	var rows: int = cfg["rows"]
	# Back off by the margin between the art and its cell.
	var origin: Vector2i = cfg["first"] - (pitch - Vector2i(icon, icon)) / 2

	var out := Image.create(cols * cell, rows * cell, false, Image.FORMAT_RGBA8)
	var kept := 0
	for row in rows:
		for col in cols:
			var src := Rect2i(origin + Vector2i(col * pitch.x, row * pitch.y), pitch)
			if src.position.x < 0 or src.position.y < 0 \
					or src.end.x > img.get_width() or src.end.y > img.get_height():
				continue
			var patch := img.get_region(src)
			_key_out(patch, cfg["bg"])
			var used := patch.get_used_rect()
			if used.size == Vector2i.ZERO:
				continue
			var art := patch.get_region(used)
			if shrink > 1:
				# Lanczos, not nearest: these are detailed illustrations, and
				# dropping every other pixel mangles them.
				art.resize(maxi(1, art.get_width() / shrink), maxi(1, art.get_height() / shrink),
					Image.INTERPOLATE_LANCZOS)
			if art.get_width() > cell or art.get_height() > cell:
				continue
			var size := Vector2i(art.get_width(), art.get_height())
			var at := Vector2i(col, row) * cell + (Vector2i(cell, cell) - size) / 2
			out.blit_rect(art, Rect2i(Vector2i.ZERO, size), at)
			kept += 1

	var dest := "res://assets/icons/items_" + name.replace("icons_", "")
	print("%-28s -> %-26s %3d icons, %dx%d, %dpx cells"
		% [name, dest.get_file(), kept, out.get_width(), out.get_height(), cell])
	var err := out.save_png(dest)
	if err != OK:
		push_error("save failed: " + error_string(err))


## The preview backgrounds are opaque; make them transparent so icons can sit
## on any UI colour. Takes a LIST because the potions and meat sheets have an
## outer border colour and a separate per-icon backing tile — keying only the
## sheet corner leaves every icon sitting on a brown square.
func _key_out(patch: Image, backgrounds: Array) -> void:
	for y in patch.get_height():
		for x in patch.get_width():
			var c := patch.get_pixel(x, y)
			for bg in backgrounds:
				var b: Color = bg
				if absf(c.r - b.r) < BG_TOLERANCE and absf(c.g - b.g) < BG_TOLERANCE \
						and absf(c.b - b.b) < BG_TOLERANCE:
					patch.set_pixel(x, y, Color(0, 0, 0, 0))
					break
