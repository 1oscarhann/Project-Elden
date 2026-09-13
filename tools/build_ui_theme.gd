extends SceneTree

## Builds resources/ui_theme.tres from the pieces cut by build_ui_atlas.gd.
##
## Generated rather than hand-written: a Theme is a flat map of
## (type, kind, name) -> value, and hand-authoring that .tres is a good way to
## silently mis-spell a key and get default styling back with no error.
##
## Nine-slice margins come from the insets build_ui_atlas.gd measures, rounded
## UP past the rounded corners so a stretched panel never smears its own corner.
##
## Run with:  godot --headless --path . --script res://tools/build_ui_theme.gd

const UI := "res://assets/ui/"
const OUT := "res://resources/ui_theme.tres"

## Parchment and ink, sampled from the pack art itself.
const INK := Color(0.30, 0.19, 0.13)          # dark brown, for text on parchment
const INK_DIM := Color(0.45, 0.34, 0.26)
const BUTTON_TEXT := Color(0.11, 0.16, 0.14)  # near-black, for text on green


func _initialize() -> void:
	var theme := Theme.new()

	# --- panels -------------------------------------------------------------
	# 6px margins, not the measured 4: the corner radius is larger than the
	# straight border, and slicing at 4 drags the curve out into a smear.
	theme.set_stylebox("panel", "PanelContainer", _box("panel", 6, 10))
	# Recipe rows sit INSIDE a parchment panel, so they get the tan slot fill
	# rather than a second parchment sheet stacked on the first.
	theme.set_type_variation("RecipeRow", "PanelContainer")
	theme.set_stylebox("panel", "RecipeRow", _box("slot_selected", 4, 4))

	# Inventory and hotbar slots. The pack's slot swatches are flat single
	# colours, so the grid look comes from the gaps between them, not a border.
	theme.set_type_variation("SlotPanel", "Panel")
	theme.set_stylebox("panel", "SlotPanel", _box("slot", 4, 0))

	# --- buttons ------------------------------------------------------------
	theme.set_stylebox("normal", "Button", _box("button_normal", 4, 4, 5))
	theme.set_stylebox("hover", "Button", _box("button_hover", 4, 4, 5))
	theme.set_stylebox("pressed", "Button", _box("button_pressed", 4, 4))
	theme.set_stylebox("disabled", "Button", _box("button_disabled", 4, 4))
	# No focus ring: the pack has no art for one and a default blue rectangle
	# over pixel art looks like a bug.
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	theme.set_color("font_color", "Button", BUTTON_TEXT)
	theme.set_color("font_hover_color", "Button", BUTTON_TEXT)
	theme.set_color("font_pressed_color", "Button", BUTTON_TEXT)
	theme.set_color("font_disabled_color", "Button", Color(0.11, 0.16, 0.14, 0.45))

	# --- warmth bar ---------------------------------------------------------
	theme.set_stylebox("background", "ProgressBar", _box("slot", 4, 0))
	theme.set_stylebox("fill", "ProgressBar", _box("bar_fill", 4, 0))

	# --- text ---------------------------------------------------------------
	# Label is deliberately NOT themed globally: HUD labels sit over the world
	# and must stay light with an outline. Only text on parchment goes dark.
	theme.set_type_variation("PanelText", "Label")
	theme.set_color("font_color", "PanelText", INK)
	theme.set_type_variation("PanelTextDim", "Label")
	theme.set_color("font_color", "PanelTextDim", INK_DIM)

	var err := ResourceSaver.save(theme, OUT)
	print("save=", error_string(err))

	# Prove it round-trips: a Theme that saved but lost a stylebox is
	# indistinguishable from a working one until something renders wrong.
	var back: Theme = ResourceLoader.load(OUT, "", ResourceLoader.CACHE_MODE_IGNORE)
	var missing: Array = []
	for pair in [["panel", "PanelContainer"], ["panel", "RecipeRow"], ["panel", "SlotPanel"],
			["normal", "Button"], ["hover", "Button"], ["pressed", "Button"],
			["disabled", "Button"], ["background", "ProgressBar"], ["fill", "ProgressBar"]]:
		var box: StyleBox = back.get_stylebox(pair[0], pair[1])
		if box == null or not (box is StyleBoxTexture) or (box as StyleBoxTexture).texture == null:
			missing.append("%s/%s" % [pair[1], pair[0]])
	print("reloaded: %d textured styleboxes missing %s" % [missing.size(), missing])
	quit(1 if err != OK or not missing.is_empty() else 0)


## A nine-sliced StyleBoxTexture from assets/ui/<name>.png.
func _box(name: String, margin: int, content: int, bottom := -1) -> StyleBoxTexture:
	var box := StyleBoxTexture.new()
	box.texture = load("%s%s.png" % [UI, name])
	var low: int = margin if bottom < 0 else bottom
	box.texture_margin_left = margin
	box.texture_margin_right = margin
	box.texture_margin_top = margin
	box.texture_margin_bottom = low
	box.content_margin_left = content
	box.content_margin_right = content
	box.content_margin_top = content
	box.content_margin_bottom = content
	return box
