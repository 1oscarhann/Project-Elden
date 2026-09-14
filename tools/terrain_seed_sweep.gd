extends SceneTree
## Generates many islands and checks the 2x2 drawability rule on every layer of
## every one. The regression suite asserts it for the SHIPPED seed; this asserts
## it is a property of the generator rather than a property of one island.
##
##     godot --headless --path . --script res://tools/terrain_seed_sweep.gd

func _initialize() -> void:
	var gen: IslandGenerator = load("res://scenes/main/World.tscn").instantiate().generator
	if gen == null:
		gen = IslandGenerator.new()
	gen.randomize_seed = false
	var total_bad := 0
	for i in 25:
		gen.noise_seed = 1000 + i * 7919
		var grid: Array = gen.generate()
		var bad := 0
		for pair in [["land", 2], ["grass+", 3], ["forest", 4]]:
			bad += _check(gen, grid, int(pair[1]))
		if bad > 0:
			print("  seed %d -> %d UNDRAWABLE" % [gen.noise_seed, bad])
		total_bad += bad
	print("25 seeds, %d undrawable cells total" % total_bad)
	quit(1 if total_bad > 0 else 0)


## Cells of the mask "terrain >= threshold" that sit in no full 2x2 block.
func _check(gen: IslandGenerator, grid: Array, threshold: int) -> int:
	var inside := func(x: int, y: int) -> bool:
		if x < 0 or y < 0 or x >= gen.map_size.x or y >= gen.map_size.y:
			return false
		# The forest layer is an equality, the other two are thresholds.
		if threshold == 4:
			return int(grid[y][x]) == IslandGenerator.Terrain.FOREST
		return int(grid[y][x]) >= threshold
	var bad := 0
	for y in gen.map_size.y:
		for x in gen.map_size.x:
			if not inside.call(x, y):
				continue
			var ok := false
			for oy in [-1, 0]:
				for ox in [-1, 0]:
					if inside.call(x + ox, y + oy) and inside.call(x + ox + 1, y + oy) \
							and inside.call(x + ox, y + oy + 1) and inside.call(x + ox + 1, y + oy + 1):
						ok = true
			if not ok:
				bad += 1
	return bad
