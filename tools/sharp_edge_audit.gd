extends Node2D

## Counts every place the player can see a SHARP edge or a HARD corner.
##
## The rule this enforces: no straight geometric line and no unrounded 90 degree
## corner may ever be exposed at a terrain boundary. Everything the camera can
## see must resolve to a curved or blended piece.
##
## Three violation types, all read from the ARTWORK rather than from the
## tileset's own claims about itself:
##
##   A  flat edge    an exposed boundary tile whose inset depth is the same on
##                   all 16 pixels — a ruled line by construction.
##   B  seam step    two adjacent tiles whose shared boundary profiles disagree,
##                   so the silhouette jumps at the join.
##   C  hard corner  an exposed corner whose opaque region is a perfect right
##                   angle, with no rounding at all.
##
##     godot --headless --path . res://tools/sharp_edge_audit.tscn

const MAIN := preload("res://scenes/main/Main.tscn")
const TILE := 16
const LAYERS := ["Sand", "Grass", "Woodland"]

var f := 0
var world: World
var ts: TileSet
var _img := {}
## (src, coord) -> cached art facts, so the per-cell scan stays cheap.
var _facts := {}


func _ready() -> void:
	add_child(MAIN.instantiate())


func _process(_d: float) -> void:
	f += 1
	if f != 2:
		return
	world = get_node("Main/Rooms/World")
	ts = world.get_node("Sand").tile_set
	audit()
	get_tree().quit(0)


func audit() -> void:
	var flat := 0
	var steps := 0
	var hard := 0
	var boundary := 0
	var per_layer := {}
	for name in LAYERS:
		var r := _scan(name)
		per_layer[name] = r
		boundary += int(r[0])
		flat += int(r[1])
		steps += int(r[2])
		hard += int(r[3])
	print("\n=== SHARP EDGES AND CORNERS EXPOSED TO THE PLAYER ===")
	print("   %-9s %8s %8s %8s %8s %9s" % ["layer", "boundary", "A ruled", "B step", "C corner", "longest"])
	var longest := 0
	for name in LAYERS:
		var r: Array = per_layer[name]
		longest = maxi(longest, int(r[4]))
		print("   %-9s %8d %8d %8d %8d %6d tiles" % [name, r[0], r[1], r[2], r[3], r[4]])
	print("   %-9s %8d %8d %8d %8d %6d tiles" % ["TOTAL", boundary, flat, steps, hard, longest])
	print("\n   VIOLATIONS: %d  (of %d exposed boundary edges)" % [flat + steps + hard, boundary])
	_per_row()


## Tile row by tile row down the whole map, so the claim is not just a total.
func _per_row() -> void:
	print("\n=== ROW BY ROW (every map row that has any exposed boundary) ===")
	var dirs := [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	var rows := {}
	for layer_name in LAYERS:
		var layer: TileMapLayer = world.get_node(layer_name)
		var region := {}
		for c in layer.get_used_cells():
			region[c] = true
		for cell in layer.get_used_cells():
			var facts := _tile_facts(layer.get_cell_source_id(cell),
				layer.get_cell_atlas_coords(cell))
			for side in 4:
				if region.has(cell + dirs[side]):
					continue
				var profile: Array = facts["depths"][side]
				var lo := 99
				var hi := -1
				for d in profile:
					if int(d) >= TILE:
						continue
					lo = mini(lo, int(d))
					hi = maxi(hi, int(d))
				if hi < 0:
					continue
				if not rows.has(cell.y):
					rows[cell.y] = [0, 0]
				rows[cell.y][0] += 1
				if hi == lo and _signature_of(layer.get_cell_source_id(cell),
						layer.get_cell_atlas_coords(cell)) in [3, 5, 10, 12]:
					rows[cell.y][1] += 1
	var keys: Array = rows.keys()
	keys.sort()
	var bad_rows := 0
	var line := ""
	for y in keys:
		var r: Array = rows[y]
		if int(r[1]) > 0:
			bad_rows += 1
		line += "row %d: %d/%d   " % [y, int(r[1]), int(r[0])]
		if line.length() > 96:
			print("   " + line)
			line = ""
	if not line.is_empty():
		print("   " + line)
	print("\n   %d map rows carry an exposed boundary; %d of them contain a sharp edge."
		% [keys.size(), bad_rows])


## Art facts for one tile: per-side exposure depth profile, and corner squareness.
func _tile_facts(src_id: int, coord: Vector2i) -> Dictionary:
	var key := "%d:%d,%d" % [src_id, coord.x, coord.y]
	if _facts.has(key):
		return _facts[key]
	if not _img.has(src_id):
		var src := ts.get_source(src_id) as TileSetAtlasSource
		var im := src.texture.get_image()
		im.convert(Image.FORMAT_RGBA8)
		_img[src_id] = im
	var img: Image = _img[src_id]
	var base := coord * TILE

	# Depth from each side to the first opaque pixel, per sample line.
	var depths := []
	for side in 4:
		var profile: Array = []
		for i in TILE:
			var d := TILE
			for step in TILE:
				var p := Vector2i.ZERO
				match side:
					0: p = Vector2i(i, step)                 # from the top
					1: p = Vector2i(i, TILE - 1 - step)      # from the bottom
					2: p = Vector2i(step, i)                 # from the left
					_: p = Vector2i(TILE - 1 - step, i)      # from the right
				if img.get_pixel(base.x + p.x, base.y + p.y).a > 0.16:
					d = step
					break
			profile.append(d)
		depths.append(profile)

	var facts := {"depths": depths, "img": img, "base": base}
	_facts[key] = facts
	return facts


## The alpha silhouette along one edge of the tile, for the seam test.
func _edge_alpha(facts: Dictionary, side: int) -> Array:
	var img: Image = facts["img"]
	var base: Vector2i = facts["base"]
	var out: Array = []
	for i in TILE:
		var p := Vector2i.ZERO
		match side:
			0: p = Vector2i(i, 0)
			1: p = Vector2i(i, TILE - 1)
			2: p = Vector2i(0, i)
			_: p = Vector2i(TILE - 1, i)
		out.append(img.get_pixel(base.x + p.x, base.y + p.y).a > 0.16)
	return out


func _scan(layer_name: String) -> Array:
	var layer: TileMapLayer = world.get_node(layer_name)
	var region := {}
	for c in layer.get_used_cells():
		region[c] = true

	var boundary := 0
	var flat := 0
	var steps := 0
	var hard := 0
	## side -> set of cells drawn flat, so consecutive ones can be joined into
	## runs. A single flat tile is a 16px straight bit; four in a row is a 64px
	## ruled line, which is what actually reads as geometric.
	var runs := {}

	# Side index matches _tile_facts: 0 top, 1 bottom, 2 left, 3 right.
	var dirs := [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]

	for cell in layer.get_used_cells():
		var src_id := layer.get_cell_source_id(cell)
		var coord := layer.get_cell_atlas_coords(cell)
		var facts := _tile_facts(src_id, coord)
		var depths: Array = facts["depths"]

		for side in 4:
			var neighbour: Vector2i = cell + dirs[side]
			if region.has(neighbour):
				# Not exposed — but the join still has to connect (violation B).
				# Only test each pair once, from the right/bottom side.
				if side != 1 and side != 3:
					continue
				var n_facts := _tile_facts(layer.get_cell_source_id(neighbour),
					layer.get_cell_atlas_coords(neighbour))
				var mine := _edge_alpha(facts, side)
				var theirs := _edge_alpha(n_facts, 0 if side == 1 else 2)
				var diff := 0
				for i in TILE:
					if mine[i] != theirs[i]:
						diff += 1
				if diff > 0:
					steps += 1
				continue

			# Exposed edge. Anything opaque on this side is silhouette the
			# player sees against whatever is underneath.
			var profile: Array = depths[side]
			var lo := TILE
			var hi := 0
			var solid := 0
			for d in profile:
				if d >= TILE:
					continue  # nothing opaque along this sample line
				solid += 1
				lo = mini(lo, int(d))
				hi = maxi(hi, int(d))
			if solid == 0:
				continue  # fully transparent side: nothing is exposed here
			boundary += 1
			# A: a RULED LINE — a straight-edge tile whose inset never varies,
			# so this whole 16px of silhouette is geometrically straight.
			#
			# A corner tile that rounds over and then runs straight for its
			# remaining rows is deliberately NOT counted: that straight part is
			# inherent to drawing a curve inside 16 pixels, and the corner it
			# belongs to is soft. Only tiles whose entire job is a straight run
			# can be a ruled line.
			if hi == lo and _signature_of(src_id, coord) in [3, 5, 10, 12]:
				flat += 1
				_mark_run(runs, cell, side)

		# C: an exposed corner that turns a perfect right angle.
		for corner in 4:
			var dx: int = -1 if corner in [0, 2] else 1
			var dy: int = -1 if corner in [0, 1] else 1
			# Only a corner with BOTH orthogonal neighbours missing is exposed
			# as a corner rather than as part of a run.
			if region.has(cell + Vector2i(dx, 0)) or region.has(cell + Vector2i(0, dy)):
				continue
			if _is_square_corner(facts, corner):
				hard += 1

	return [boundary, flat, steps, hard, _longest_run(runs)]


func _mark_run(runs: Dictionary, cell: Vector2i, side: int) -> void:
	if not runs.has(side):
		runs[side] = {}
	runs[side][cell] = true


## Longest unbroken line of flat tiles along the same side, in tiles.
func _longest_run(runs: Dictionary) -> int:
	var best := 0
	for side in runs:
		var cells: Dictionary = runs[side]
		# Top/bottom edges run horizontally; left/right edges run vertically.
		var step := Vector2i.RIGHT if side in [0, 1] else Vector2i.DOWN
		for cell in cells:
			if cells.has(cell - step):
				continue  # not the start of a run
			var n := 0
			var c: Vector2i = cell
			while cells.has(c):
				n += 1
				c += step
			best = maxi(best, n)
	return best


## The corner signature of a tile, from the tileset.
func _signature_of(src_id: int, coord: Vector2i) -> int:
	var src := ts.get_source(src_id) as TileSetAtlasSource
	var data := src.get_tile_data(coord, 0)
	var bits := 0
	var corners := [TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER, TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER,
		TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER, TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER]
	for i in 4:
		if data.get_terrain_peering_bit(corners[i]) != -1:
			bits |= 1 << i
	return bits


## True when the opaque area meets this corner as an unrounded right angle: the
## two edges running into the corner keep a constant inset right up to it.
func _is_square_corner(facts: Dictionary, corner: int) -> bool:
	var depths: Array = facts["depths"]
	# corner 0 TL -> sides top(0) and left(2); 1 TR -> top(0), right(3);
	# 2 BL -> bottom(1), left(2); 3 BR -> bottom(1), right(3)
	var side_a: int = 0 if corner in [0, 1] else 1
	var side_b: int = 2 if corner in [0, 2] else 3
	for side in [side_a, side_b]:
		var profile: Array = depths[side]
		# Sample the four pixels nearest this corner along that edge.
		var near: Array = []
		for k in 4:
			var i: int = k if corner in [0, 2] else TILE - 1 - k
			if side == 2 or side == 3:
				i = k if corner in [0, 1] else TILE - 1 - k
			near.append(profile[i])
		var lo := TILE
		var hi := 0
		var solid := 0
		for d in near:
			if d >= TILE:
				continue
			solid += 1
			lo = mini(lo, int(d))
			hi = maxi(hi, int(d))
		if solid < 4 or hi != lo:
			return false  # rounded, or the corner is cut away entirely
	return true
