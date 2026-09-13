extends SceneTree

## Builds a SpriteFrames per animal from the CraftPix sheet grids.
##
## Every animal sheet is 32x32 cells, 4 rows = 4 facings, columns = frames
## (verified by measuring every sheet). But the ROW ORDER IS NOT THE SAME FOR
## EVERY ANIMAL: the hare and the deer put left on row 2 and right on row 3,
## while the black grouse has them the other way round. That was found by
## locating the eye pixel within each side row's bounds, not by assuming, so
## each entry below carries its own row order.
##
## Generated rather than hand-edited, like the player's frames: 3 animals x
## 5 states x 4 facings is 60 animations and several hundred atlas regions.
##
## Run with:  godot --headless --path . --script res://tools/build_animal_frames.gd

const CELL := Vector2i(32, 32)
const OUT_DIR := "res://scenes/entities/"
const SHEETS := "res://assets/animals/"

## Frames per second per state. Idle is slow and sleepy; a fleeing animal is not.
const FPS := {"idle": 5.0, "walk": 8.0, "run": 12.0, "hurt": 10.0, "death": 9.0}
## Death must not loop — it holds on the last frame while the node fades.
const LOOPING := {"idle": true, "walk": true, "run": true, "hurt": false, "death": false}

## id -> { prefix, rows (top to bottom), states: state -> sheet suffix }
const ANIMALS := {
	"hare": {
		"prefix": "Hare",
		"rows": ["down", "up", "left", "right"],
		"states": {"idle": "Idle", "walk": "Walk", "run": "Run", "hurt": "Hurt", "death": "Death"},
	},
	"deer": {
		"prefix": "Deer",
		"rows": ["down", "up", "left", "right"],
		"states": {"idle": "Idle", "walk": "Walk", "run": "Run", "hurt": "Hurt", "death": "Death"},
	},
	"grouse": {
		"prefix": "Black_grouse",
		# Side rows are swapped on this sheet. Verified, not assumed.
		"rows": ["down", "up", "right", "left"],
		# The grouse has no Run sheet — it takes off instead, so Flight is its run.
		"states": {"idle": "Idle", "walk": "Walk", "run": "Flight", "hurt": "Hurt", "death": "Death"},
	},
}


func _initialize() -> void:
	var failures := 0
	for id in ANIMALS:
		failures += _build(id, ANIMALS[id])
	quit(failures)


func _build(id: String, spec: Dictionary) -> int:
	var frames := SpriteFrames.new()
	# SpriteFrames ships with a "default" animation that we never use.
	frames.remove_animation("default")
	var regions := 0
	var states: Dictionary = spec["states"]
	var rows: Array = spec["rows"]

	for state in states:
		var path: String = "%s%s_%s.png" % [SHEETS, spec["prefix"], states[state]]
		var sheet: Texture2D = load(path)
		if sheet == null:
			push_error("Missing sheet %s" % path)
			return 1
		var size := sheet.get_size()
		if int(size.y) != CELL.y * rows.size():
			push_error("%s is %s, not %d rows of %dpx" % [path, size, rows.size(), CELL.y])
			return 1
		var columns := int(size.x) / CELL.x

		for row in rows.size():
			var name := "%s_%s" % [state, rows[row]]
			frames.add_animation(name)
			frames.set_animation_speed(name, FPS[state])
			frames.set_animation_loop(name, LOOPING[state])
			for column in columns:
				var atlas := AtlasTexture.new()
				atlas.atlas = sheet
				atlas.region = Rect2(Vector2(column * CELL.x, row * CELL.y), Vector2(CELL))
				frames.add_frame(name, atlas)
				regions += 1

	var out := "%s%s_frames.tres" % [OUT_DIR, id]
	var err := ResourceSaver.save(frames, out)
	print("%s: %d animations, %d regions -> %s (%s)"
		% [id, frames.get_animation_names().size(), regions, out, error_string(err)])

	# Prove it round-trips: a SpriteFrames that saved but lost its regions is
	# indistinguishable from a working one until something tries to draw it.
	var back: SpriteFrames = ResourceLoader.load(out, "", ResourceLoader.CACHE_MODE_IGNORE)
	var expected := states.size() * rows.size()
	var got := back.get_animation_names().size()
	var first := back.get_frame_count("idle_down") if back.has_animation("idle_down") else 0
	if err != OK or got != expected or first == 0:
		push_error("%s round-trip failed: %d/%d animations, idle_down has %d frames"
			% [id, got, expected, first])
		return 1
	return 0
