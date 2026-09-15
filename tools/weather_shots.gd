extends Node2D

## Each weather, shot and MEASURED.
##
##     xvfb-run -a godot --path . --rendering-driver opengl3 \
##         res://tools/weather_shots.tscn
##
## ⚠️ Pictures alone are not the proof. Rain is a particle sheet and fog is a
## flat rect, and both are the sort of thing that silently draws nothing — the
## fireflies did exactly that for two rounds. So this measures each effect's
## own contribution, the way the fireflies, smoke and leaves were signed off.
##
## ⚠️ AND IT MUST BE THE SAME FRAME, effect hidden vs shown, on two CONSECUTIVE
## frames. The first version of this compared frames seconds apart and reported
## 81% of the screen changed for every weather INCLUDING one that should have
## been invisible. That was the water shimmer, which animates on shader TIME
## and moves 54.6% of the sea every frame, plus the wandering animals and the
## fire. Ambient motion swamped the thing being measured.
##
## The sky tint is NOT in that diff — it lives on the world's CanvasModulate,
## not on the WeatherView — so it is read off as a number instead.

const OUT := "user://shots/"

var t := 0.0
var step := 0
var game: Node2D
var view: Node2D
var sky: CanvasModulate
## Frame captured with the WeatherView hidden, waiting for its partner.
var hidden_frame: Image
var pending := ""
var beat_stage := 0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	GameState.intro_shown = true
	game = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	add_child(game)
	var camera: Node = get_tree().get_nodes_in_group(PlayerCamera.GROUP)[0]
	view = camera.get_node("WeatherView")
	sky = game.get_node("Rooms/World/SkyTint")
	# A fixed midday so the day/night gradient is not a second variable.
	DayNight.paused = true
	DayNight.time_of_day = 0.42
	# The state machine must not roll a new weather mid-capture.
	Weather.paused = true


func _frame() -> Image:
	return get_viewport().get_texture().get_image()


func shot(name: String) -> Image:
	var img := get_viewport().get_texture().get_image()
	img.save_png(OUT + name + ".png")
	return img


## Share of pixels the effect itself moved. Comparable to the fireflies (1.03%),
## smoke (0.41%) and leaves (0.65%) numbers, which were measured the same way.
func _diff(a: Image, b: Image, label: String) -> void:
	var moved := 0
	var peak := 0
	for y in a.get_height():
		for x in a.get_width():
			var p := a.get_pixel(x, y)
			var q := b.get_pixel(x, y)
			var d: int = int(abs(p.r8 - q.r8)) + int(abs(p.g8 - q.g8)) + int(abs(p.b8 - q.b8))
			# 12, not 6: one frame of water shimmer is a median delta of 2 per
			# channel, which sums to 6 exactly and would count as "moved".
			if d > 12:
				moved += 1
			peak = maxi(peak, d)
	var total := a.get_width() * a.get_height()
	print("  %-24s %6d of %d px (%5.2f%%), peak delta %d/765"
		% [label, moved, total, 100.0 * moved / total, peak])


## One beat, over THREE frames: hide, capture, show, capture, diff.
##
## ⚠️ The frame gaps are mandatory. get_viewport().get_texture().get_image()
## inside _process returns the PREVIOUS frame — the viewport has not re-rendered
## yet — so hiding the view and capturing in the same call grabs a picture that
## still has it in. The first version of this did exactly that and reported fog,
## a full-screen haze, as moving 0.42% of the screen.
func _beat(label: String, file: String) -> void:
	pending = "%s|%s" % [label, file]
	beat_stage = 0


func _run_beat() -> void:
	match beat_stage:
		0:
			view.visible = false     # takes effect on the NEXT rendered frame
		1:
			hidden_frame = _frame()  # now genuinely without the view
			view.visible = true
		2:
			var parts := pending.split("|")
			pending = ""
			_diff(hidden_frame, shot(parts[1]), parts[0])
	beat_stage += 1


func _process(delta: float) -> void:
	t += delta
	if not pending.is_empty():
		_run_beat()
		return
	match step:
		0:
			if t < 0.8:
				return
			step = 1
			Weather.set_weather("clear", true)
		1:
			if t < 1.6:
				return
			step = 2
			shot("weather_0_clear")
			print("\n-- what each effect actually draws (same frame, hidden vs shown) --")
			Weather.set_weather("rain", true)
		2:
			# Past the view's fade_seconds (2.5) so the sheet is at full alpha.
			if t < 5.4:
				return
			step = 3
			_beat("rain", "weather_1_rain")
		3:
			if t < 6.0:
				return
			step = 4
			Weather.set_weather("fog", true)
		4:
			if t < 10.0:
				return
			step = 5
			_beat("fog", "weather_2_fog")
		5:
			if t < 10.6:
				return
			step = 6
			# Under a roof the sky is a ceiling: same weather, nothing drawn.
			Weather.set_weather("rain", true)
		6:
			if t < 14.4:
				return
			step = 7
			Weather.add_shelter()
		7:
			if t < 18.2:
				return
			step = 8
			_beat("rain, under a roof", "weather_3_rain_sheltered")
		8:
			if t < 18.8:
				return
			step = 9
			print("\n  sheltered: warmth x%.2f, fire x%.2f, logs always catch: %s"
				% [Weather.warmth_multiplier(), Weather.fire_burn_multiplier(),
					Weather.log_catches()])
			Weather.remove_shelter()
			# The sky tint is on the world's CanvasModulate, not on the view,
			# so it is read as a number rather than diffed out of a picture.
			print("\n-- sky tint, read off the CanvasModulate --")
			for id in ["clear", "rain", "fog"]:
				Weather.set_weather(id, true)
				sky._on_weather_changed(Weather.current)
				sky._weather_tint = Weather.current.sky_tint
				sky._on_ticked(DayNight.time_of_day)
				print("  %-6s tint %s -> sky %s"
					% [id, str(Weather.current.sky_tint), str(sky.color)])
		9:
			if t < 19.4:
				return
			_silence()
			get_tree().quit(0)


func _silence() -> void:
	Audio.stop_world_audio()
	_stop(get_tree().root)


func _stop(node: Node) -> void:
	if node is AudioStreamPlayer or node is AudioStreamPlayer2D:
		node.stop()
	for c in node.get_children():
		_stop(c)
