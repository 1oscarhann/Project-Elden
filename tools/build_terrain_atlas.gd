extends SceneTree

## Generates the two DERIVED terrain sheets. Everything else is referenced
## straight from the Sprout Lands originals by tools/build_tileset.gd — there
## is no composited atlas any more, because compositing threw away the very
## thing we now need: the sheets' corner/edge autotile pieces.
##
## The pack has no dark grass, so woodland is a darkened copy. Nothing else is
## derived. There is deliberately no deep-water sheet: the pack has no art for
## a deep-to-shallow transition, so two flat water tiles met at a hard
## rectangular step — the one genuinely blocky edge left on the island. The sea
## is a single colour now, as in the reference.
##
## Run with:  godot --headless --path . --script res://tools/build_terrain_atlas.gd

const DERIVED := {
	"res://assets/tiles/sprout_lands/Grass.png": ["res://assets/tiles/grass_dark.png", 0.80],
}

## ⚠️ The beach is the GRASS blob in sand colours, not Tilled_Dirt.
##
## Tilled_Dirt is ploughed-field art: its edge pieces are almost square,
## because the edge of a ploughed field is meant to be straight. Used as a
## beach it gave the one genuinely blocky boundary left on the island. The
## grass sheet's blob has big soft fringed curves, so sand borrows its shape.
##
## Both palettes are tiny — 6 colours and 4 — so the swap is a luminance
## remap onto sand's hue, which keeps the blob's shading and therefore its
## readable edge. Sampling sand's own ramp directly does not work: it spans
## only luminance 190-219 against grass's 140-228, and flattening to that
## range erases the dark outline that makes the edge read at all.
const SAND_OUT := "res://assets/tiles/sand_blob.png"
const SAND_SHAPE := "res://assets/tiles/sprout_lands/Grass.png"
## Measured: the most common opaque colour of each sheet.
const GRASS_BASE := Color8(192, 212, 112)
const SAND_BASE := Color8(232, 207, 166)


func _initialize() -> void:
	var failures := 0
	for src in DERIVED:
		var out: String = DERIVED[src][0]
		var factor: float = DERIVED[src][1]
		var tex: Texture2D = load(src)
		if tex == null:
			push_error("Missing %s" % src)
			failures += 1
			continue
		var img := tex.get_image()
		img.convert(Image.FORMAT_RGBA8)
		for y in img.get_height():
			for x in img.get_width():
				var c := img.get_pixel(x, y)
				if c.a <= 0.0:
					continue
				# Alpha is untouched: darkening it would eat the soft edges the
				# whole autotile depends on.
				img.set_pixel(x, y, Color(c.r * factor, c.g * factor, c.b * factor, c.a))
		var err := img.save_png(out)
		print("%s -> %s at %.2f (%s)" % [src.get_file(), out.get_file(), factor, error_string(err)])
		if err != OK:
			failures += 1
	failures += _recolour_sand()
	quit(failures)


## Re-hues the grass blob into sand, pixel by pixel, by luminance ratio.
func _recolour_sand() -> int:
	var tex: Texture2D = load(SAND_SHAPE)
	if tex == null:
		push_error("Missing %s" % SAND_SHAPE)
		return 1
	var img := tex.get_image()
	img.convert(Image.FORMAT_RGBA8)
	var base := _luma(GRASS_BASE)
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a <= 0.0:
				continue
			var ratio := _luma(c) / base
			img.set_pixel(x, y, Color(
				minf(SAND_BASE.r * ratio, 1.0),
				minf(SAND_BASE.g * ratio, 1.0),
				minf(SAND_BASE.b * ratio, 1.0), c.a))
	var err := img.save_png(SAND_OUT)
	print("%s re-hued to sand -> %s (%s)" % [SAND_SHAPE.get_file(), SAND_OUT.get_file(), error_string(err)])
	return 0 if err == OK else 1


func _luma(c: Color) -> float:
	return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
