extends Node2D

## The opening, shot beat by beat, plus the measurement that says whether the
## dimmed background is actually doing anything.
##
##     xvfb-run -a godot --path . --rendering-driver opengl3 \
##         res://tools/intro_shots.tscn
##
## ⚠️ The dim is a screen-reading shader (hint_screen_texture) on the GL
## Compatibility renderer, which is exactly the sort of thing that silently
## draws nothing. So this does not just save pictures: it captures the same
## frame with the effect off and on and prints the saturation and brightness of
## each, the way the fireflies and the smoke were measured. A claim that the
## world "looks darkened" is worth nothing without the numbers.

const OUT := "user://shots/"

var t := 0.0
var step := 0
var game: Node2D
var intro: CanvasLayer
var clean: Image


func _init() -> void:
	# ⚠️ BEFORE the intro pauses the tree, not at the step that needs it.
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	GameState.intro_shown = false
	game = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	add_child(game)
	intro = game.get_node("Intro")


func _frame() -> Image:
	return get_viewport().get_texture().get_image()


func shot(name: String) -> Image:
	var img := _frame()
	img.save_png(OUT + name + ".png")
	print("shot ", name)
	return img


## Mean saturation and mean luma over the frame. Saturation is max-minus-min
## over max, the plain HSV definition — a grey pixel scores 0 whatever its
## brightness, which is the property being claimed.
func _measure(img: Image, label: String) -> Array:
	var sat := 0.0
	var luma := 0.0
	var n := 0
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			var c := img.get_pixel(x, y)
			var hi: float = maxf(c.r, maxf(c.g, c.b))
			var lo: float = minf(c.r, minf(c.g, c.b))
			sat += 0.0 if hi <= 0.0 else (hi - lo) / hi
			luma += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			n += 1
	var s := sat / float(n)
	var l := luma / float(n)
	print("  %-22s saturation %.4f   brightness %.4f" % [label, s, l])
	return [s, l]


func _process(delta: float) -> void:
	t += delta
	match step:
		0:
			if t < 0.4:
				return
			step = 1
			# The effect off, for the diff. amount is tweened 0 -> 1, so 0 is a
			# provable no-op rather than a second render path.
			intro._dim.material.set_shader_parameter("amount", 0.0)
			intro._root.visible = false
		1:
			if t < 0.5:
				return
			step = 2
			clean = shot("intro_00_world_undimmed")
			intro._root.visible = true
			intro._dim.material.set_shader_parameter("amount", 1.0)
		2:
			if t < 0.6:
				return
			step = 3
			var dimmed := shot("intro_01_world_dimmed")
			print("\n-- dimmed background, measured --")
			var a := _measure(clean, "world as played")
			var b := _measure(dimmed, "world under the intro")
			print("  saturation %.1f%% of original, brightness %.1f%%"
				% [100.0 * b[0] / maxf(a[0], 0.0001), 100.0 * b[1] / maxf(a[1], 0.0001)])
			var moved := 0
			var peak := 0
			for y in clean.get_height():
				for x in clean.get_width():
					var d: int = int(abs(clean.get_pixel(x, y).r8 - dimmed.get_pixel(x, y).r8)) \
						+ int(abs(clean.get_pixel(x, y).g8 - dimmed.get_pixel(x, y).g8)) \
						+ int(abs(clean.get_pixel(x, y).b8 - dimmed.get_pixel(x, y).b8))
					if d > 6:
						moved += 1
					peak = maxi(peak, d)
			var total := clean.get_width() * clean.get_height()
			print("  %d of %d px changed (%.1f%%), peak delta %d/765\n"
				% [moved, total, 100.0 * moved / total, peak])
		3:
			# Let the real opening run from the top now the measuring is done.
			if t < 2.9:
				return
			step = 4
			shot("intro_02_line1")
			print("  line: '%s'  arrow: %s" % [intro._line.text, intro._arrow.visible])
		4:
			if t < 3.2:
				return
			step = 5
			intro.advance()
		5:
			if t < 5.6:
				return
			step = 6
			shot("intro_03_line2")
			intro.advance()
		6:
			if t < 9.4:
				return
			step = 7
			shot("intro_04_line3")
			print("  camera zoom mid-shot: ", _camera().zoom)
			intro.advance()
		7:
			if t < 11.2:
				return
			step = 8
			shot("intro_05_after")
			print("  intro_shown: %s   paused: %s   zoom: %s"
				% [GameState.intro_shown, get_tree().paused, _camera().zoom])
		8:
			if t < 11.6:
				return
			_silence()
			get_tree().quit(0)


func _camera() -> Node:
	return get_tree().get_nodes_in_group(PlayerCamera.GROUP)[0]


## A playback still running at teardown keeps its stream alive and is reported
## as a leak. Six bogus leaks is how a real one goes unnoticed.
func _silence() -> void:
	Audio.stop_world_audio()
	_stop(get_tree().root)


func _stop(node: Node) -> void:
	if node is AudioStreamPlayer or node is AudioStreamPlayer2D:
		node.stop()
	for c in node.get_children():
		_stop(c)
