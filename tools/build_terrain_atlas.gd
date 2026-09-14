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

## --- Generated wavy edge variants -------------------------------------------
##
## ⚠️ Every straight edge the pack ships is a FLAT 2px inset — measured, all
## eight of them, span 0. So a run of grass against sand is a ruled line by
## construction, and no amount of autotile wiring changes that: the shape is
## simply not in the art. These variants add the missing amplitude.
##
## Both ends are pinned at the pack's own depth of 2, which is what lets a
## generated tile abut the originals and the hand-drawn corners without a step.
## Only the middle bulges.
const EDGES_OUT := "res://assets/tiles/grass_edges.png"
const EDGE_VARIANTS := 3
## Sampled from the sheet's own edge tiles: dark outline, mid band, then base.
const EDGE_DARK := Color8(120, 161, 88)
const EDGE_MID := Color8(164, 194, 99)
const EDGE_BASE := Color8(192, 212, 112)
const EDGE_END_DEPTH := 2
const EDGE_MAX_DEPTH := 8


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
	# The edge sheet is kept in memory and handed straight to the two
	# transforms: a PNG written this run is not importable yet, so load() on it
	# returns null until Godot reimports.
	var edges := _make_edges()
	if edges == null:
		failures += 1
	else:
		# Woodland and sand take the same transforms as their main sheets, so
		# the generated edges stay in palette with everything around them.
		failures += _derive(edges, "res://assets/tiles/wood_edges.png", 0.80)
		failures += _rehue(edges, "res://assets/tiles/sand_edges.png")
	quit(failures)


## One bulge profile per variant. w(0) = w(1) = 0 so both ends stay pinned.
func _wave(variant: int, t: float) -> float:
	match variant:
		0:
			return sin(PI * t)
		1:
			return sin(PI * t) * (0.55 + 0.45 * sin(TAU * t + 0.9))
		_:
			return sin(PI * t) * (0.40 + 0.60 * pow(sin(TAU * t + 0.4), 2.0))


## 4 directions x EDGE_VARIANTS, laid out as a grid of 16px cells.
func _make_edges() -> Image:
	var img := Image.create_empty(4 * 16, EDGE_VARIANTS * 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var span := float(EDGE_MAX_DEPTH - EDGE_END_DEPTH)
	for dir in 4:
		for variant in EDGE_VARIANTS:
			var base := Vector2i(dir * 16, variant * 16)
			for i in 16:
				var t := float(i) / 15.0
				var depth: int = EDGE_END_DEPTH + int(round(span * maxf(_wave(variant, t), 0.0)))
				depth = clampi(depth, EDGE_END_DEPTH, EDGE_MAX_DEPTH + 1)
				for n in range(depth, 16):
					var colour := EDGE_BASE
					if n < depth + 2:
						colour = EDGE_DARK
					elif n < depth + 4:
						colour = EDGE_MID
					# dir 0 gap on top, 1 gap on bottom, 2 gap on left, 3 gap on right
					var at := Vector2i(i, n)
					if dir == 1:
						at = Vector2i(i, 15 - n)
					elif dir == 2:
						at = Vector2i(n, i)
					elif dir == 3:
						at = Vector2i(15 - n, i)
					img.set_pixelv(base + at, colour)
	var err := img.save_png(EDGES_OUT)
	print("generated %d wavy edge tiles -> %s (%s)"
		% [4 * EDGE_VARIANTS, EDGES_OUT.get_file(), error_string(err)])
	return img if err == OK else null


func _derive(source: Image, out: String, factor: float) -> int:
	var img := Image.create_from_data(source.get_width(), source.get_height(),
		false, source.get_format(), source.get_data())
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a > 0.0:
				img.set_pixel(x, y, Color(c.r * factor, c.g * factor, c.b * factor, c.a))
	return 0 if img.save_png(out) == OK else 1


func _rehue(source: Image, out: String) -> int:
	var img := Image.create_from_data(source.get_width(), source.get_height(),
		false, source.get_format(), source.get_data())
	var base := _luma(GRASS_BASE)
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a <= 0.0:
				continue
			var ratio := _luma(c) / base
			img.set_pixel(x, y, Color(minf(SAND_BASE.r * ratio, 1.0),
				minf(SAND_BASE.g * ratio, 1.0), minf(SAND_BASE.b * ratio, 1.0), c.a))
	return 0 if img.save_png(out) == OK else 1


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
