extends SceneTree

## Cuts the individual UI pieces out of the CraftPix RPG UI pack.
##
## The pack ships whole mocked-up screens, so every usable piece has to be
## located by hand. These rects were found by blob-scanning each sheet and
## checking the crops by eye — in particular the obvious rows of buttons are
## USELESS, because "RESTART" / "RESUME" / "SAVE" are baked into the pixels.
## The blank ones live in the top-left block of Buttons.png.
##
## The four button shades pair up as two colours x (with / without a brown drop
## shadow). Shadow present reads as raised and shadow absent as pushed in, so:
##   normal = mid + shadow · hover = light + shadow · pressed = mid, no shadow.
##
## Only neutral furniture is used. The pack's shop, equipment doll, level
## select and win/lose screens are deliberately not even copied into the repo,
## and item icons stay in assets/icons/ — the pack's own icons are combat gear.
##
## Run with:  godot --headless --path . --script res://tools/build_ui_atlas.gd

const SRC := "res://assets/ui/source/"
const OUT := "res://assets/ui/"

## out name -> [sheet, region]
const PIECES := {
	"panel":            ["Main_tiles", Rect2i(208, 196, 48, 40)],
	"button_normal":    ["Buttons",    Rect2i(9, 130, 30, 14)],
	"button_hover":     ["Buttons",    Rect2i(105, 130, 30, 14)],
	"button_pressed":   ["Buttons",    Rect2i(57, 131, 30, 13)],
	"button_disabled":  ["Buttons",    Rect2i(153, 131, 30, 13)],
	"slot":             ["Inventory",  Rect2i(177, 113, 14, 14)],
	"slot_selected":    ["Inventory",  Rect2i(193, 113, 14, 14)],
	"bar_fill":         ["Settings",   Rect2i(279, 209, 50, 13)],
}


func _initialize() -> void:
	var sheets := {}
	var failures := 0
	for name in PIECES:
		var sheet_name: String = PIECES[name][0]
		var region: Rect2i = PIECES[name][1]
		if not sheets.has(sheet_name):
			var tex: Texture2D = load("%s%s.png" % [SRC, sheet_name])
			if tex == null:
				push_error("Missing source sheet %s" % sheet_name)
				failures += 1
				continue
			sheets[sheet_name] = tex.get_image()
		var src: Image = sheets[sheet_name]
		var img := Image.create_empty(region.size.x, region.size.y, false, src.get_format())
		img.blit_rect(src, region, Vector2i.ZERO)
		var path := "%s%s.png" % [OUT, name]
		var err := img.save_png(path)
		var inset := _inset(img)
		print("%-17s %2dx%-2d from %-11s inset L%d T%d R%d B%d  (%s)"
			% [name, region.size.x, region.size.y, sheet_name,
				inset.x, inset.y, inset.z, inset.w, error_string(err)])
		if err != OK:
			failures += 1
	quit(failures)


## How many pixels in from each edge before the flat interior begins. This is
## what the theme's nine-slice margins are derived from — measured, not guessed,
## so a piece swapped for different art cannot silently stretch its own border.
func _inset(img: Image) -> Vector4i:
	var w := img.get_width()
	var h := img.get_height()
	var fill := img.get_pixel(w / 2, h / 2)
	var left := 0
	var top := 0
	var right := 0
	var bottom := 0
	while left < w and not img.get_pixel(left, h / 2).is_equal_approx(fill):
		left += 1
	while right < w and not img.get_pixel(w - 1 - right, h / 2).is_equal_approx(fill):
		right += 1
	while top < h and not img.get_pixel(w / 2, top).is_equal_approx(fill):
		top += 1
	while bottom < h and not img.get_pixel(w / 2, h - 1 - bottom).is_equal_approx(fill):
		bottom += 1
	return Vector4i(left, top, right, bottom)
